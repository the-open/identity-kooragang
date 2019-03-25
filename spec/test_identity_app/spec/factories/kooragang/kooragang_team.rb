module IdentityKooragang
  FactoryBot.define do
    factory :kooragang_team, class: Team do
      sequence(:name) { |n| "team #{n}" }
    end
  end
end
