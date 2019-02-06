require "identity_kooragang/engine"

module IdentityKooragang
  SYSTEM_NAME = 'kooragang'
  PULL_BATCH_AMOUNT = 1000
  PUSH_BATCH_AMOUNT = 1000
  SYNCING = 'campaign'
  CONTACT_TYPE = 'call'
  ACTIVE_STATUS = 'active'
  FINALISED_STATUS = 'finalised'
  FAILED_STATUS = 'failed'
  PULL_JOBS = [[:fetch_new_calls, 5.minutes], [:fetch_active_campaigns, 10.minutes]]

  def self.push(sync_id, members, external_system_params)
    begin
      campaign_id = JSON.parse(external_system_params)['campaign_id'].to_i
      phone_type = JSON.parse(external_system_params)['phone_type'].to_s
      priority = ApplicationHelper.integer_or_nil(JSON.parse(external_system_params)['priority']) || 1
      campaign_name = Campaign.find(campaign_id).name
      audience = Audience.create!(sync_id: sync_id, campaign_id: campaign_id, priority: priority)
      yield members.with_phone_type(phone_type), campaign_name
    rescue => e
      audience.update_attributes!(status: FAILED_STATUS) if audience
      raise e
    end
  end

  def self.push_in_batches(sync_id, members, external_system_params)
    begin
      audience = Audience.find_by_sync_id(sync_id)
      audience.update_attributes!(status: ACTIVE_STATUS)
      campaign_id = JSON.parse(external_system_params)['campaign_id'].to_i
      phone_type = JSON.parse(external_system_params)['phone_type'].to_s
      members.in_batches(of: get_push_batch_amount).each_with_index do |batch_members, batch_index|
        rows = ActiveModel::Serializer::CollectionSerializer.new(
          batch_members,
          serializer: KooragangMemberSyncPushSerializer,
          audience_id: audience.id,
          campaign_id: campaign_id,
          phone_type: phone_type
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

  def self.description(external_system_params, contact_campaign_name)
    "#{SYSTEM_NAME.titleize} - #{SYNCING.titleize}: #{contact_campaign_name} ##{JSON.parse(external_system_params)['campaign_id']} (#{CONTACT_TYPE})"
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

  def self.get_pull_batch_amount
    Settings.kooragang.pull_batch_amount || PULL_BATCH_AMOUNT
  end

  def self.get_push_batch_amount
    Settings.kooragang.push_batch_amount || PUSH_BATCH_AMOUNT
  end

  def self.get_pull_jobs
    defined?(PULL_JOBS) && PULL_JOBS.is_a?(Array) ? PULL_JOBS : []
  end

  def self.fetch_new_calls(force: false)
    ## Do not run method if another worker is currently processing this method
    return if self.worker_currenly_running?(__method__.to_s)

    last_updated_at = Time.parse($redis.with { |r| r.get 'kooragang:calls:last_updated_at' } || '1970-01-01 00:00:00')
    updated_calls = Call.updated_calls(force ? DateTime.new() : last_updated_at)

    iteration_method = force ? :find_each : :each

    updated_calls.send(iteration_method) do |call|
      self.delay(retry: false, queue: 'low').handle_new_call(call.id)
    end

    unless updated_calls.empty?
      $redis.with { |r| r.set 'kooragang:calls:last_updated_at', updated_calls.last.updated_at }
    end

    updated_calls.size
  end

  def self.handle_new_call(call_id)
    call = Call.find(call_id)
    contact = Contact.find_or_initialize_by(external_id: call.id.to_s, system: SYSTEM_NAME)
    contactee = Member.upsert_member(
      {phones: [{ phone: call.callee.phone_number }], firstname: call.callee.first_name},
      "#{SYSTEM_NAME}:#{__method__.to_s}"
    )

    unless contactee
      Notify.warning "Kooragang: Contactee Insert Failed", "Contactee #{call.inspect} could not be inserted because the contactee could not be created"
      return
    end

    # Caller conditional upsert phone
    if call.caller
      contactor = Member.upsert_member(
        {phones: [{ phone: call.caller.phone_number }]},
        "#{SYSTEM_NAME}:#{__method__.to_s}"
      )
    else
      contactor = nil
    end

    contact_campaign = ContactCampaign.find_or_initialize_by(external_id: call.callee.campaign.id, system: SYSTEM_NAME)
    contact_campaign.update_attributes!(name: call.callee.campaign.name, contact_type: CONTACT_TYPE)

    contact.update_attributes!(contactee: contactee,
                              contactor: contactor,
                              contact_campaign: contact_campaign,
                              duration: call.ended_at - call.created_at,
                              contact_type: CONTACT_TYPE,
                              happened_at: call.created_at,
                              status: call.status)

    call.survey_results.each do |sr|
      contact_response_key = ContactResponseKey.find_or_create_by!(key: sr.question, contact_campaign: contact_campaign)
      contact_response_key.contact_responses << ContactResponse.new(contact: contact, value: sr.answer)

      # Process optouts
      if Settings.kooragang.subscription_id && sr.is_opt_out?
        subscription = Subscription.find(Settings.kooragang.subscription_id)
        contactee.unsubscribe_from(subscription, 'kooragang:disposition')
      end

      ## RSVP contactee to nation builder
      if not defined?(IdentityNationBuilder).nil? && sr.is_rsvp?
        rows = ActiveModel::Serializer::CollectionSerializer.new(
          [contactee],
          serializer: IdentityNationBuilder::NationBuilderMemberSyncPushSerializer
        ).as_json
        IdentityNationBuilder::API.rsvp(sr.rsvp_site_slug, rows, sr.rsvp_event_id.to_i)
      end
    end
  end

  def self.fetch_active_campaigns(force: false)
    ## Do not run method if another worker is currently processing this method
    return if self.worker_currenly_running?(__method__.to_s)

    active_campaigns = IdentityKooragang::Campaign.active

    iteration_method = force ? :find_each : :each

    active_campaigns.send(iteration_method) do |campaign|
      self.delay(retry: false, queue: 'low').handle_campaign(campaign.id)
    end

    active_campaigns.size
  end

  def self.handle_campaign(campaign_id)
    campaign = IdentityKooragang::Campaign.find(campaign_id)
    contact_campaign = ContactCampaign.find_or_initialize_by(external_id: campaign.id, system: SYSTEM_NAME)
    contact_campaign.update_attributes!(name: campaign.name, contact_type: CONTACT_TYPE)

    campaign.questions.each do |k,v|
      contact_response_key = ContactResponseKey.find_or_create_by!(key: k, contact_campaign: contact_campaign)
    end
  end
end
