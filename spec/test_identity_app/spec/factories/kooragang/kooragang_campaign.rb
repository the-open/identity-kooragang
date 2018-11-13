module IdentityKooragang
  FactoryBot.define do
    factory :kooragang_campaign, class: Campaign do
      name { Faker::Book.title }
    end
  end
end
