# frozen_string_literal: true

module DiscourseRetoolSubdomain
  module Policy
    # Decides what the hidden Discourse user field should hold when a user is
    # seen with a (validated) subdomain.
    #
    # existing - the field's current value (String or nil)
    # incoming - the newly observed hostname, already validated
    #
    # Returns the String to store. Returning `existing` unchanged means "no write".
    # The webhook always receives both values, so the Retool DB table keeps full
    # history whichever policy you pick here.
    def self.resolve(existing, incoming)
      # Policy: last observation wins. The field always shows the most recently
      # seen hostname, so it follows a user who switches orgs. The webhook still
      # reports `existing` as `previous`, so Retool DB can keep the history.
      incoming
    end
  end
end
