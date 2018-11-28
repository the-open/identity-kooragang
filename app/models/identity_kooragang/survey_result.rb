module IdentityKooragang
  class SurveyResult < ApplicationRecord
    include ReadOnly
    self.table_name = "survey_results"
    belongs_to :call

    def call_question
      (call.campaign.questions || {})[question]
    end

    def call_question_answers
      (call_question || {})['answers']
    end

    def call_question_answer
      call_question_answers.values.detect { |answer| answer['value'] == self.answer }
    end

    def is_rsvp?
      call_question && call_question_answers && call_question_answer && call_question_answer['rsvp_event_id']
    end

    def rsvp_event_id
      is_rsvp? ? call_question_answer['rsvp_event_id'] : nil
    end

    def is_opt_out?
      question == 'disposition' && answer == 'do not call'
    end
  end
end