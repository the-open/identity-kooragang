module IdentityKooragang
  class Call < ApplicationRecord
    include ReadOnly
    self.table_name = "calls"
    belongs_to :callee
    belongs_to :caller, optional: true
    has_many :survey_results
    delegate :campaign, to: :callee, allow_nil: true

    BATCH_AMOUNT=1000

    scope :updated_calls, -> (last_updated_at) {
      includes(:caller, { callee: [:campaign] }, :survey_results)
      .references(:campaign)
      .where('campaigns.sync_to_identity')
      .where('calls.ended_at is not null AND calls.callee_id is not null')
      .where('calls.updated_at >= ?', last_updated_at)
      .order('calls.updated_at')
      .limit(BATCH_AMOUNT)
    }
  end
end
