module IdentityKooragang
  class SurveyResult < ApplicationRecord
    include ReadOnly
    self.table_name = "survey_results"
    belongs_to :call

    def is_rsvp
      call_question = (call.campaign.questions || {})[question]
      if call_question && (answers = call_question['answers'])
        answer = answers.values.detect { |answer| answer['value'] == sr.answer }
        return answer && answer['rsvp_event_id']
      end
      false
    end

    def rsvp_event_id
      call_question = (call.campaign.questions || {})[question]
      if call_question && (answers = call_question['answers'])
        answer = answers.values.detect { |answer| answer['value'] == self.answer }
        return answer['rsvp_event_id']
      end
      nil
    end

    def is_opt_out?
      question == 'disposition' && answer == 'do not call'
    end
  end
end