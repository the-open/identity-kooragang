require 'rails_helper'

describe IdentityKooragang do
  context '#fetch_new_calls' do
    before(:each) do
      clean_external_database
      $redis.reset

      @subscription = FactoryBot.create(:subscription, name: 'Calling')
      Settings.stub_chain(:kooragang, :opt_out_subscription_id) { @subscription.id }

      @time = Time.now - 120.seconds
      @campaign = IdentityKooragang::Campaign.create(name: 'Test')
      3.times do |n|
        callee = IdentityKooragang::Callee.create!(first_name: "Bob#{n}", phone_number: "6142770040#{n}", campaign: @campaign)
        caller = IdentityKooragang::Caller.create!(first_name: "Jacob#{n}", phone_number: "6142770042#{n}")
        call = IdentityKooragang::Call.create!(created_at: @time, callee: callee, caller: caller, ended_at: @time + 60.seconds, status: 'success')
        call.survey_results << IdentityKooragang::SurveyResult.new(question: 'disposition', answer: 'no answer')
        call.survey_results << IdentityKooragang::SurveyResult.new(question: 'voting_intention', answer: 'labor')
      end
    end

   it 'should fetch the new calls and insert them' do
      IdentityKooragang.fetch_new_calls
      expect(Contact.count).to eq(3)
      member = Member.find_by_phone('61427700401')
      expect(member).to have_attributes(first_name: 'Bob1')
      expect(member.contacts_received.count).to eq(1)
      expect(member.contacts_made.count).to eq(0)
    end

    it 'should record all details' do
      IdentityKooragang.fetch_new_calls
      expect(Contact.first).to have_attributes(duration: 60, system: 'kooragang', contact_type: 'call', status: 'success')
      expect(Contact.first.happened_at.utc.to_s).to eq(@time.utc.to_s)
    end

    it 'should opt out people that need it' do
      member = Member.create!(name: 'BobNo')
      member.update_phone_number('61427700409')
      member.subscribe_to(@subscription)

      callee = IdentityKooragang::Callee.create!(first_name: 'BobNo', phone_number: '61427700409', campaign: @campaign)
      call = IdentityKooragang::Call.create!(created_at: @time, callee: callee, ended_at: @time + 60.seconds, status: 'success')
      call.survey_results << IdentityKooragang::SurveyResult.new(question: 'disposition', answer: 'do not call')

      IdentityKooragang.fetch_new_calls

      member.reload
      expect(member.is_subscribed_to?(@subscription)).to eq(false)
    end

    it 'should assign a campaign' do
      IdentityKooragang.fetch_new_calls
      expect(ContactCampaign.count).to eq(1)
      expect(ContactCampaign.first.contacts.count).to eq(3)
      expect(ContactCampaign.first).to have_attributes(name: @campaign.name, external_id: @campaign.id, system: 'kooragang', contact_type: 'call')
    end

    it 'should match members receiving calls' do
      member = Member.create!(first_name: 'Bob1')
      member.update_phone_number('61427700401')

      IdentityKooragang.fetch_new_calls
      expect(member.contacts_received.count).to eq(1)
      expect(member.contacts_made.count).to eq(0)
    end

    it 'should match members making calls' do
      member = Member.create!(first_name: 'Jacob1')
      member.update_phone_number('61427700421')
      IdentityKooragang.fetch_new_calls
      expect(member.contacts_received.count).to eq(0)
      expect(member.contacts_made.count).to eq(1)
    end

    it 'should upsert calls' do
      member = Member.create!(first_name: 'Janis')
      member.update_phone_number('61427700401')
      call = IdentityKooragang::Call.last
      Contact.create!(contactee: member, external_id: call.id, system: 'kooragang')
      IdentityKooragang.fetch_new_calls
      expect(Contact.count).to eq(3)
      expect(member.contacts_received.count).to eq(1)
    end

    it 'should be idempotent' do
      IdentityKooragang.fetch_new_calls
      contact_hash = Contact.all.select('contactee_id, contactor_id, duration, system, contact_campaign_id').as_json
      IdentityKooragang.fetch_new_calls
      expect(Contact.all.select('contactee_id, contactor_id, duration, system, contact_campaign_id').as_json).to eq(contact_hash)
    end

    it 'should update the last_updated_at' do
      old_updated_at = $redis.with { |r| r.get 'kooragang:calls:last_updated_at' }
      sleep 2
      callee = IdentityKooragang::Callee.create!(first_name: 'BobNo', phone_number: '61427700408', campaign: @campaign)
      call = IdentityKooragang::Call.create!(created_at: @time, callee: callee, ended_at: @time + 60.seconds, status: 'success')
      IdentityKooragang.fetch_new_calls
      new_updated_at = $redis.with { |r| r.get 'kooragang:calls:last_updated_at' }

      expect(new_updated_at).not_to eq(old_updated_at)
    end

    it 'should correctly save Survey Results' do
      IdentityKooragang.fetch_new_calls

      contact_response = ContactCampaign.last.contact_response_keys.find_by(key: 'voting_intention').contact_responses.first
      expect(contact_response.value).to eq('labor')
      expect(Contact.last.contact_responses.count).to eq(2)
    end

    it 'works if there is no caller' do
      callee = IdentityKooragang::Callee.create!(first_name: 'BobNo', phone_number: '61427700409', campaign: @campaign)
      call = IdentityKooragang::Call.create!(created_at: @time, callee: callee, ended_at: @time + 60.seconds, status: 'success')
      IdentityKooragang.fetch_new_calls
      expect(Contact.last.contactor).to be_nil
    end

    it 'works if there is no name' do
      callee = IdentityKooragang::Callee.create!(phone_number: '61427700409', campaign: @campaign)
      call = IdentityKooragang::Call.create!(created_at: @time, callee: callee, ended_at: @time + 60.seconds, status: 'success')
      IdentityKooragang.fetch_new_calls
      expect(Contact.last.contactee.phone).to eq('61427700409')
    end

    it "skips if callee phone can't be matched" do
      callee = IdentityKooragang::Callee.create!(phone_number: '6142709', campaign: @campaign)
      call = IdentityKooragang::Call.create!(created_at: @time, callee: callee, ended_at: @time + 60.seconds, status: 'success')

      expect(Notify).to receive(:warning)

      IdentityKooragang.fetch_new_calls
      expect(Contact.count).to eq(3)
    end

    it "succeeds if caller phone can't be matched" do
      callee = IdentityKooragang::Callee.create!(phone_number: '61427700409', campaign: @campaign)
      caller = IdentityKooragang::Caller.create!(phone_number: '6142409')
      call = IdentityKooragang::Call.create!(created_at: @time, callee: callee, caller: caller, ended_at: @time + 60.seconds, status: 'success')
      IdentityKooragang.fetch_new_calls
      expect(Contact.count).to eq(4)
      expect(Contact.last.contactee.phone).to eq('61427700409')
      expect(Contact.last.contactor).to be_nil
    end

    context('with force=true passed as parameter') do
      before { IdentityKooragang::Call.update_all(updated_at: '1960-01-01 00:00:00') }

      it 'should ignore the last_updated_at and fetch all calls' do
        IdentityKooragang.fetch_new_calls(force: true)
        expect(Contact.count).to eq(3)
      end
    end

    context('with a campaign that has syncing set to false') do
      before do
        @campaign.sync_to_identity = false
        @campaign.save!
      end

      it 'should only find calls from campaigns where syncing is true' do
        c2 = IdentityKooragang::Campaign.create(name: 'Test2')
        callee = IdentityKooragang::Callee.create!(first_name: "Bobby", phone_number: "61427700409", campaign: c2)
        caller = IdentityKooragang::Caller.create!(first_name: "Jacoby", phone_number: "61427700429")
        call = IdentityKooragang::Call.create!(created_at: @time, callee: callee, caller: caller, ended_at: @time + 60.seconds, status: 'success')
        call.survey_results << IdentityKooragang::SurveyResult.new(question: 'disposition', answer: 'no answer')
        call.survey_results << IdentityKooragang::SurveyResult.new(question: 'voting_intention', answer: 'labor')

        IdentityKooragang.fetch_new_calls
        expect(Contact.count).to eq(1)
      end
    end
  end
end
