module IdentityKooragang
  class SurveyResult < ReadOnly
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

    def call_question_answer_present
      call_question && call_question_answers && call_question_answer
    end

    def call_question_answer_populated_rsvp
      call_question_answer['rsvp_event_id'] && call_question_answer['rsvp_site_slug']
    end

    def is_rsvp?
      call_question_answer_present && call_question_answer_populated_rsvp
    end

    def rsvp_event_id
      is_rsvp? ? call_question_answer['rsvp_event_id'] : nil
    end

    def rsvp_site_slug
      is_rsvp? ? call_question_answer['rsvp_site_slug'] : nil
    end

    def is_opt_out?
      question == 'disposition' && answer == 'do not call'
    end
  end
end
