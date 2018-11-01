describe IdentityKooragang::KooragangMemberSyncPushSerializer do
  context 'serialize' do
    before(:each) do
      clean_external_database

      @sync_id = 1
      @kooragang_campaign = IdentityKooragang::Campaign.create!(name: 'Test campaign')
      @external_system_params = JSON.generate({'campaign_id' => @kooragang_campaign.id})
      @member = Member.create!(
        name: 'Freddy Kruger',
        email: 'nosleeptill@elmstreet.com',
        phone_numbers: [
          PhoneNumber.new(phone: '447966123456')
        ],
        custom_fields: [
          CustomField.new(
            data: 'me likes',
            custom_field_key: CustomFieldKey.new(name: 'yada')
          )
        ]
      )
      list = List.create(name: 'test list')
      ListMember.create(list: list, member: @member)
      Member.create!(name: 'Miles Davis', email: 'jazz@vibes.com', phone_numbers: [PhoneNumber.new(phone: '61427700400')])
      Member.create!(name: 'Yoko Ono', email: 'yoko@breaktheband.com')
      @batch_members = Member.all.with_phone_numbers.in_batches.first
      @audience = IdentityKooragang::Audience.create!(sync_id: @sync_id, campaign_id: @kooragang_campaign.id)
    end

    it 'returns valid object' do
      rows = ActiveModel::Serializer::CollectionSerializer.new(
        @batch_members,
        serializer: IdentityKooragang::KooragangMemberSyncPushSerializer,
        audience_id: @audience.id,
        campaign_id: @kooragang_campaign.id
      ).as_json
      expect(rows.count).to eq(2)
      expect(rows[0][:external_id]).to eq(ListMember.first.member_id)
      expect(rows[0][:phone_number]).to eq('447966123456')
      expect(rows[0][:campaign_id]).to eq(@kooragang_campaign.id)
      expect(rows[0][:audience_id]).to eq(@audience.id)
      expect(rows[0][:data]).to eq("{\"yada\":\"me likes\"}")
    end

    it "only returns the most recently updated phone number" do
      @member.update_phone_number('61427700500')
      @member.update_phone_number('61427700600')
      @member.update_phone_number('61427700500')
      @batch_members = Member.all.with_phone_numbers.in_batches.first
      rows = ActiveModel::Serializer::CollectionSerializer.new(
        @batch_members,
        serializer: IdentityKooragang::KooragangMemberSyncPushSerializer,
        audience_id: @audience.id,
        campaign_id: @kooragang_campaign.id
      ).as_json
      expect(rows.first[:phone_number]).to eq('61427700500')
    end
  end
end
