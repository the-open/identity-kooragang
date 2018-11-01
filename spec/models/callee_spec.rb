describe IdentityKooragang::Callee do
  context '#add_members' do
    before(:each) do
      clean_external_database

      @kooragang_campaign = IdentityKooragang::Campaign.create!(name: 'Test campaign')
      Member.create!(name: 'Freddy Kruger', email: 'nosleeptill@elmstreet.com', phone_numbers: [PhoneNumber.new(phone: '447966123456')])
      Member.create!(name: 'Miles Davis', email: 'jazz@vibes.com', phone_numbers: [PhoneNumber.new(phone: '61427700400')])
      @batch_members = Member.all
      @rows = ActiveModel::Serializer::CollectionSerializer.new(
        @batch_members,
        serializer: IdentityKooragang::KooragangMemberSyncPushSerializer,
        audience_id: 1,
        campaign_id: @kooragang_campaign.id
      ).as_json
    end

    it 'has inserted the correct callees to Kooragang' do
      IdentityKooragang::Callee.add_members(@rows)
      expect(@kooragang_campaign.callees.count).to eq(2)
      expect(@kooragang_campaign.callees.find_by_phone_number('61427700400').first_name).to eq('Miles') # Kooragang allows external IDs to be text
    end

    it "doesn't insert duplicates into Kooragang" do
      2.times do |index|
        IdentityKooragang::Callee.add_members(@rows)
      end
      expect(@kooragang_campaign.callees.count).to eq(2)
      expect(@kooragang_campaign.callees.select('distinct phone_number').count).to eq(2)
    end
  end
end
