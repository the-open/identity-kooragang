module IdentityKooragang
  class Campaign < ApplicationRecord
    include ReadOnly
    self.table_name = "campaigns"
    has_many :callees
    has_many :audiences
  end
end
