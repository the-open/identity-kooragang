module IdentityKooragang
  class Caller < ApplicationRecord
    include ReadOnly
    self.table_name = "callers"
    has_many :calls
    belongs_to :team, optional: true, class_name: 'IdentityKooragang::Team'
  end
end
