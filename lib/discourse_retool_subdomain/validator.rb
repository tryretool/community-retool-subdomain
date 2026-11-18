# frozen_string_literal: true

module DiscourseRetoolSubdomain
  # Mirrors the checks Retool's own app applies to this cookie (see
  # frontend/src/routes/Login/logic/redirects.ts): a bare hostname that is the
  # main domain or a subdomain of it. Any host on the same site can write the
  # cookie, so the value is untrusted input.
  module Validator
    LABEL = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/
    MAX_LENGTH = 253

    # Hosts under the main domain that are not customer orgs.
    # TODO: confirm this list with the Retool platform team.
    NON_ORG_HOSTS = %w[login www docs community api status].freeze

    # Returns the normalised hostname, or nil if the value should be ignored.
    def self.normalize(raw, main_domain)
      return nil if raw.blank? || main_domain.blank?

      host = raw.to_s.strip.downcase
      domain = main_domain.to_s.strip.downcase
      return nil if host.length > MAX_LENGTH
      return nil if host == domain
      return nil if !host.end_with?(".#{domain}")

      labels = host.split(".", -1)
      return nil if !labels.all? { |label| label.match?(LABEL) }
      org_label_count = domain.split(".").length + 1
      return nil if NON_ORG_HOSTS.include?(labels.first) && labels.length == org_label_count

      host
    end
  end
end
