require 'rails_helper'

describe IdentityKooragang do
  context '#push' do
    before(:each) do
      clean_external_database

      @sync_id = 1
      @kooragang_campaign = IdentityKooragang::Campaign.create!(name: 'Test campaign')
      @external_system_params = JSON.generate({'campaign_id' => @kooragang_campaign.id})

      Member.create!(name: 'Freddy Kruger', email: 'nosleeptill@elmstreet.com', phone_numbers: [PhoneNumber.new(phone: '447966123456')])
      Member.create!(name: 'Miles Davis', email: 'jazz@vibes.com', phone_numbers: [PhoneNumber.new(phone: '61427700400')])
      Member.create!(name: 'Yoko Ono', email: 'yoko@breaktheband.com')
      @members = Member.all
    end

    context 'with valid parameters' do
      it 'has created an attributed Audience in Kooragang' do
        IdentityKooragang.push(@sync_id, @members, @external_system_params) do end
        @kooragang_audience = IdentityKooragang::Audience.find_by_campaign_id(@kooragang_campaign.id)
        expect(@kooragang_audience).to have_attributes(campaign_id: @kooragang_campaign.id, sync_id: 1, status: 'initialising')
      end
      it 'yeilds correct campaign_name' do
        IdentityKooragang.push(@sync_id, @members, @external_system_params) do |members_with_phone_numbers, campaign_name|
          expect(campaign_name).to eq(@kooragang_campaign.name)
        end
      end
      it 'yeilds members_with_phone_numbers' do
        IdentityKooragang.push(@sync_id, @members, @external_system_params) do |members_with_phone_numbers, campaign_name|
          expect(members_with_phone_numbers.count).to eq(2)
        end
      end
    end
  end

  context '#push_in_batches' do
    before(:each) do
      clean_external_database

      @sync_id = 1
      @kooragang_campaign = IdentityKooragang::Campaign.create!(name: 'Test campaign')
      @external_system_params = JSON.generate({'campaign_id' => @kooragang_campaign.id})

      Member.create!(name: 'Freddy Kruger', email: 'nosleeptill@elmstreet.com', phone_numbers: [PhoneNumber.new(phone: '447966123456')])
      Member.create!(name: 'Miles Davis', email: 'jazz@vibes.com', phone_numbers: [PhoneNumber.new(phone: '61427700400')])
      Member.create!(name: 'Yoko Ono', email: 'yoko@breaktheband.com')
      @members = Member.all.with_phone_numbers
      @audience = IdentityKooragang::Audience.create!(sync_id: @sync_id, campaign_id: @kooragang_campaign.id)
    end

    context 'with valid parameters' do
      it 'updates attributed Audience in Kooragang' do
        IdentityKooragang.push_in_batches(1, @members, @external_system_params) do |batch_index, write_result_count|
          @kooragang_audience = IdentityKooragang::Audience.find_by_campaign_id(@kooragang_campaign.id)
          expect(@kooragang_audience).to have_attributes(status: 'active')
        end
      end
      it 'yeilds correct batch_index' do
        IdentityKooragang.push_in_batches(1, @members, @external_system_params) do |batch_index, write_result_count|
          expect(batch_index).to eq(0)
        end
      end
      it 'yeilds write_result_count' do
        IdentityKooragang.push_in_batches(1, @members, @external_system_params) do |batch_index, write_result_count|
          expect(write_result_count).to eq(2)
        end
      end
    end
  end
end
