module IdentityKooragang
  class Campaign < ApplicationRecord
    include ReadOnly
    self.table_name = "campaigns"
    has_many :callees
    has_many :audiences

    ACTIVE_STATUS='active'

    scope :active, -> {
      where('sync_to_identity')
      .where('status = ?', ACTIVE_STATUS)
      .order('created_at')
    }
  end
end
