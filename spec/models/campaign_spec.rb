describe IdentityKooragang::Campaign do
  context '#active' do
    before(:each) do
      clean_external_database
      2.times do
        FactoryBot.create(:kooragang_campaign, status: 'active')
      end
      FactoryBot.create(:kooragang_campaign, status: 'active', sync_to_identity: false)
      FactoryBot.create(:kooragang_campaign, status: 'paused')
      FactoryBot.create(:kooragang_campaign, status: 'inactive')
    end

    it 'returns the active campaigns' do
      expect(IdentityKooragang::Campaign.active.count).to eq(2)
      IdentityKooragang::Campaign.active.each do |campaign|
        expect(campaign).to have_attributes(status: 'active')
      end
    end
  end
end
