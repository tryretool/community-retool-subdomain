# frozen_string_literal: true

module DiscourseRetoolSubdomain
  # Included into ApplicationController. Runs for logged-in users on page loads,
  # never raises, and does nothing when the cookie is absent so that logging
  # out of Retool can't erase a stored value.
  module Capture
    extend ActiveSupport::Concern

    included { before_action :capture_retool_subdomain }

    private

    def capture_retool_subdomain
      return if !SiteSetting.retool_subdomain_enabled
      return if !request.get? || !request.format.html?
      return if current_user.blank?

      host =
        DiscourseRetoolSubdomain::Validator.normalize(
          cookies[DiscourseRetoolSubdomain::COOKIE_NAME],
          SiteSetting.retool_subdomain_main_domain,
        )
      return if host.nil?
      return if session[DiscourseRetoolSubdomain::SESSION_KEY] == host

      # Mark the session only after recording succeeds, so a failed enqueue
      # (e.g. a Redis outage) is retried on the next page load.
      record_retool_subdomain(current_user, host)
      session[DiscourseRetoolSubdomain::SESSION_KEY] = host
    rescue => e
      Rails.logger.warn("[community-retool-subdomain] capture failed: #{e.class}: #{e.message}")
    end

    def record_retool_subdomain(user, host)
      field_id = SiteSetting.retool_subdomain_user_field_id
      previous = nil

      if field_id > 0
        key = "user_field_#{field_id}"
        previous = user.custom_fields[key]
        stored = DiscourseRetoolSubdomain::Policy.resolve(previous, host)
        if stored != previous
          user.custom_fields[key] = stored
          user.save_custom_fields
        end
      end

      if SiteSetting.retool_subdomain_webhook_url.present?
        Jobs.enqueue(
          :discourse_retool_subdomain_notify,
          user_id: user.id,
          subdomain: host,
          previous: previous,
          observed_at: Time.now.utc.iso8601,
        )
      end
    end
  end
end
