module IdentityKooragang
  class Team < ApplicationRecord
    include ReadOnly
    self.table_name = "teams"
  end
end
