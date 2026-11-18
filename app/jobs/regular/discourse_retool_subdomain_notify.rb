# frozen_string_literal: true

module Jobs
  # Sends one signed report per observed (user, subdomain) change. The receiver
  # should recompute signature = HMAC-SHA256(secret, [timestamp, user_id, username,
  # subdomain, previous || "", observed_at].join("\n")) and reject stale timestamps.
  class DiscourseRetoolSubdomainNotify < ::Jobs::Base
    sidekiq_options retry: 3

    def execute(args)
      url = SiteSetting.retool_subdomain_webhook_url
      secret = SiteSetting.retool_subdomain_webhook_secret
      return if url.blank? || secret.blank?

      user = User.find_by(id: args[:user_id])
      return if user.nil?

      timestamp = Time.now.to_i.to_s
      fields = {
        user_id: user.id,
        username: user.username,
        subdomain: args[:subdomain],
        previous: args[:previous],
        observed_at: args[:observed_at],
      }

      # Sign a fixed list of fields, not the raw body: Retool Workflows hand the
      # receiver parsed JSON, so the original bytes can't be reproduced there.
      signed_string = [
        timestamp,
        fields[:user_id],
        fields[:username],
        fields[:subdomain],
        fields[:previous].to_s,
        fields[:observed_at],
      ].join("\n")
      signature = OpenSSL::HMAC.hexdigest("SHA256", secret, signed_string)

      response =
        Excon.post(
          url,
          body: fields.merge(timestamp: timestamp, signature: signature).to_json,
          headers: {
            "Content-Type" => "application/json",
          },
          connect_timeout: 5,
          read_timeout: 10,
          write_timeout: 10,
        )

      # Raise on server errors so Sidekiq retries. A 4xx means the receiver rejected
      # the payload, so retrying won't help.
      raise "webhook returned #{response.status}" if response.status >= 500
    end
  end
end
