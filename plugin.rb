# frozen_string_literal: true

# name: community-retool-subdomain
# about: Reports each logged-in user's Retool org hostname to a signed webhook
# url: https://github.com/tryretool/community-retool-subdomain
# version: 0.1.0
# authors: Retool Community Support Engineering
# required_version: 2026.1.0

enabled_site_setting :retool_subdomain_enabled

module ::DiscourseRetoolSubdomain
  PLUGIN_NAME = "community-retool-subdomain"
  COOKIE_NAME = "subdomain"
  SESSION_KEY = "retool_subdomain_seen"
end

after_initialize do
  require_relative "lib/discourse_retool_subdomain/validator"
  require_relative "lib/discourse_retool_subdomain/policy"
  require_relative "lib/discourse_retool_subdomain/capture"
  require_relative "app/jobs/regular/discourse_retool_subdomain_notify"

  reloadable_patch { ApplicationController.include(DiscourseRetoolSubdomain::Capture) }
end
