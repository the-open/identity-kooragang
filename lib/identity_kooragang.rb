require "identity_kooragang/engine"

module IdentityKooragang
  SYSTEM_NAME = 'kooragang'
  SYNCING = 'campaign'
  CONTACT_TYPE = 'call'
  ACTIVE_STATUS = 'active'
  FINALISED_STATUS = 'finalised'
  FAILED_STATUS = 'failed'
  PULL_JOBS = [[:fetch_new_calls, 5.minutes], [:fetch_active_campaigns, 10.minutes]]
  MEMBER_RECORD_DATA_TYPE='object'

  def self.push(sync_id, member_ids, external_system_params)
    begin
      campaign_id = JSON.parse(external_system_params)['campaign_id'].to_i
      phone_type = JSON.parse(external_system_params)['phone_type'].to_s
      priority = ApplicationHelper.integer_or_nil(JSON.parse(external_system_params)['priority']) || 1
      campaign_name = Campaign.find(campaign_id).name
      audience = Audience.create!(sync_id: sync_id, campaign_id: campaign_id, priority: priority)
      members = Member.where(id: member_ids).with_phone_type(phone_type)
      yield members, campaign_name, external_system_params
    rescue => e
      audience.update_attributes!(status: FAILED_STATUS) if audience
      raise e
    end
  end

  def self.push_in_batches(sync_id, members, external_system_params)
    begin
      audience = Audience.find_by_sync_id(sync_id)
      audience.update_attributes!(status: ACTIVE_STATUS)
      params = JSON.parse(external_system_params)
      campaign_id = params['campaign_id'].to_i
      phone_type = params['phone_type'].to_s
      include_rsvped_events = !!params['include_rsvped_events']
      members.in_batches(of: Settings.kooragang.push_batch_amount).each_with_index do |batch_members, batch_index|
        rows = ActiveModel::Serializer::CollectionSerializer.new(
          batch_members,
          serializer: KooragangMemberSyncPushSerializer,
          audience_id: audience.id,
          campaign_id: campaign_id,
          phone_type: phone_type,
          include_rsvped_events: include_rsvped_events
        ).as_json
        write_result_count = Callee.add_members(rows)

        yield batch_index, write_result_count
      end
      audience.update_attributes!(status: FINALISED_STATUS)
    rescue => e
      audience.update_attributes!(status: FAILED_STATUS)
      raise e
    end
  end

  def self.description(sync_type, external_system_params, contact_campaign_name)
    external_system_params_hash = JSON.parse(external_system_params)
    if sync_type === 'push'
      "#{SYSTEM_NAME.titleize} - #{SYNCING.titleize}: #{contact_campaign_name} ##{external_system_params_hash['campaign_id']} (#{CONTACT_TYPE})"
    else
      "#{SYSTEM_NAME.titleize}: #{external_system_params_hash['pull_job']}"
    end
  end

  def self.base_campaign_url(campaign_id)
    Settings.kooragang.base_campaign_url ? sprintf(Settings.kooragang.base_campaign_url, campaign_id.to_s) : nil
  end

  def self.worker_currenly_running?(method_name)
    workers = Sidekiq::Workers.new
    workers.each do |_process_id, _thread_id, work|
      matched_process = work["payload"]["args"] = [SYSTEM_NAME, method_name]
      if matched_process
        puts ">>> #{SYSTEM_NAME.titleize} #{method_name} skipping as worker already running ..."
        return true
      end
    end
    puts ">>> #{SYSTEM_NAME.titleize} #{method_name} running ..."
    return false
  end

  def self.get_pull_jobs
    defined?(PULL_JOBS) && PULL_JOBS.is_a?(Array) ? PULL_JOBS : []
  end

  def self.get_push_jobs
    defined?(PUSH_JOBS) && PUSH_JOBS.is_a?(Array) ? PUSH_JOBS : []
  end

  def self.pull(sync_id, external_system_params)
    begin
      pull_job = JSON.parse(external_system_params)['pull_job'].to_s
      self.send(pull_job, sync_id) do |records_for_import_count, records_for_import, records_for_import_scope, pull_deferred|
        yield records_for_import_count, records_for_import, records_for_import_scope, pull_deferred
      end
    rescue => e
      raise e
    end
  end

  def self.fetch_new_calls(sync_id, force: false)
    ## Do not run method if another worker is currently processing this method
    yield 0, {}, {}, true if self.worker_currenly_running?(__method__.to_s)

    started_at = DateTime.now
    last_updated_at = Time.parse($redis.with { |r| r.get 'kooragang:calls:last_updated_at' } || '1970-01-01 00:00:00')
    updated_calls = Call.updated_calls(force ? DateTime.new() : last_updated_at)
    updated_calls_all = Call.updated_calls_all(force ? DateTime.new() : last_updated_at)
    iteration_method = force ? :find_each : :each

    updated_calls.send(iteration_method) do |call|
      self.delay(retry: false, queue: 'low').handle_new_call(sync_id, call.id)
    end

    unless updated_calls.empty?
      $redis.with { |r| r.set 'kooragang:calls:last_updated_at', updated_calls.last.updated_at }
    end

    execution_time_seconds = ((DateTime.now - started_at) * 24 * 60 * 60).to_i
    yield(
      updated_calls.size,
      updated_calls.pluck(:id),
      {
        scope: 'kooragang:calls:last_updated_at',
        scope_limit: Settings.kooragang.pull_batch_amount,
        from: last_updated_at,
        to: updated_calls.empty? ? nil : updated_calls.last.updated_at,
        started_at: started_at,
        completed_at: DateTime.now,
        execution_time_seconds: execution_time_seconds,
        remaining_behind: updated_calls_all.count
      },
      false
    )
  end

  def self.handle_new_call(sync_id, call_id)
    call = Call.find(call_id)
    contact = Contact.find_or_initialize_by(external_id: call.id.to_s, system: SYSTEM_NAME)

    # Callee upsert phone against member_id
    contactee = UpsertMember.call(
      {phones: [{ phone: call.callee.phone_number }], firstname: call.callee.first_name, member_id: call.callee.external_id},
      entry_point: "#{SYSTEM_NAME}:#{__method__.to_s}",
      ignore_name_change: false
    )

    unless contactee
      Notify.warning "Kooragang: Contactee Insert Failed", "Contactee #{call.inspect} could not be inserted because the contactee could not be created"
      return
    end

    # Caller conditional upsert phone against phone_number
    if call.caller
      contactor = UpsertMember.call(
        {phones: [{ phone: call.caller.phone_number }]},
        entry_point: "#{SYSTEM_NAME}:#{__method__.to_s}",
        ignore_name_change: false
      )
      team = Team.find_by_id(call.caller.team_id)
    else
      contactor = nil
      team = nil
    end

    contact_campaign = ContactCampaign.find_or_initialize_by(external_id: call.callee.campaign.id, system: SYSTEM_NAME)
    contact_campaign.update!(name: call.callee.campaign.name, contact_type: CONTACT_TYPE)

    additional_data = {}
    additional_data[:team] = team.name if team

    contact.update!(contactee: contactee,
                    contactor: contactor,
                    contact_campaign: contact_campaign,
                    duration: call.ended_at - call.created_at,
                    contact_type: CONTACT_TYPE,
                    happened_at: call.created_at,
                    status: call.status,
                    data: additional_data )

    call.survey_results.each do |sr|
      contact_response_key = ContactResponseKey.find_or_initialize_by(key: sr.question, contact_campaign: contact_campaign)
      contact_response_key.save! if contact_response_key.new_record?
      contact_response = ContactResponse.find_or_initialize_by(contact: contact, value: sr.answer, contact_response_key: contact_response_key)
      contact_response.save! if contact_response.new_record?

      # Process optouts
      if Settings.kooragang.subscription_id && sr.is_opt_out?
        subscription = Subscription.find(Settings.kooragang.subscription_id)
        contactee.unsubscribe_from(subscription, reason: 'kooragang:disposition', event_time: DateTime.now)
      end

      ## RSVP contactee to nation builder
      if defined?(IdentityNationBuilder) && sr.is_rsvp?
        rows = ActiveModel::Serializer::CollectionSerializer.new(
          [contactee],
          serializer: IdentityNationBuilder::NationBuilderMemberSyncPushSerializer
        ).as_json
        IdentityNationBuilder::API.rsvp(sr.rsvp_site_slug, rows, sr.rsvp_event_id.to_i)
      end
    end
  end

  def self.fetch_active_campaigns(sync_id, force: false)
    ## Do not run method if another worker is currently processing this method
    yield 0, {}, {}, true if self.worker_currenly_running?(__method__.to_s)

    active_campaigns = IdentityKooragang::Campaign.active

    iteration_method = force ? :find_each : :each

    active_campaigns.send(iteration_method) do |campaign|
      self.delay(retry: false, queue: 'low').handle_campaign(sync_id, campaign.id)
    end

    yield(
      active_campaigns.size,
      active_campaigns.pluck(:id),
      {},
      false
    )
  end

  def self.handle_campaign(sync_id, campaign_id)

    campaign = IdentityKooragang::Campaign.find(campaign_id)
    contact_campaign = ContactCampaign.find_or_initialize_by(external_id: campaign.id, system: SYSTEM_NAME)
    contact_campaign.update!(name: campaign.name, contact_type: CONTACT_TYPE) if contact_campaign.new_record?

    campaign.questions.each do |k,v|
      contact_response_key = ContactResponseKey.find_or_initialize_by(key: k, contact_campaign: contact_campaign)
      contact_response_key.save! if contact_response_key.new_record?
    end
  end
end
