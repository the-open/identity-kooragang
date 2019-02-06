module IdentityKooragang
  FactoryBot.define do
    factory :kooragang_campaign, class: Campaign do
      name { Faker::Book.title }
      sync_to_identity { true }
      questions { {} }
      factory :kooragang_campaign_with_rsvp_questions do
        questions {
          {
            disposition: { answers: { "2" => { value: "meaningful", next: "rsvp" } } },
            rsvp: { answers: { "2" => { value: "going", rsvp_event_id: 1, rsvp_site_slug: "stagingsite" } } }
          }
        }
      end
    end
  end
end
