# community-retool-subdomain

Records which Retool Cloud org a logged-in forum user belongs to, so support can see it next to their threads.

When someone who is logged in to Retool Cloud loads a forum page, the browser already sends Retool's `subdomain` cookie (it is scoped to `.retool.com`, and the forum is a subdomain of that). This plugin reads it on the server, validates it, and reports it to a Retool Workflow with a signed webhook. The Workflow writes it to a Retool DB table, which the support team's tooling reads. Nothing is stored in Discourse.

> **Status: untested inside Discourse.** The plugin was written against Discourse's plugin API from memory and has only been syntax-checked. Install it on a dev or staging forum first. Do not go straight to production.

## What it does and does not do

- Runs only for logged-in users, on full HTML page loads.
- Does nothing when the cookie is missing, so logging out of Retool never erases a stored value.
- Accepts only bare hostnames under `retool.com` (rejects `retool.com` itself, `login.retool.com`, ports, paths, other domains).
- Sends one report per browser session in which it sees a valid hostname. The Retool DB table keeps one row per (username, org) with `last_seen_at`, so the support tooling can show the newest org and the history is kept.
- Never breaks a page: errors are caught and logged as `[community-retool-subdomain] capture failed`.

**The value is a hint, not proof.** Any host under the same site (published apps included) can write that cookie, and users control their own browser. Don't use it for access or identity decisions.

**Coverage is partial.** It only captures users who loaded a forum page while logged in to Retool Cloud in the same browser. Self-hosted Retool users, logged-out users, and other browsers or devices are not captured. The cookie is a session cookie, so it is gone after the browser closes until the next Retool login.

## Requirements

- Self-hosted Discourse (Docker install) and shell access to the server.
- A Retool Workflow that receives the webhook and verifies the signature (described under "Webhook signature" below). Its code is kept outside this repo.
- No Discourse user field is needed. (The plugin can optionally mirror the value into a hidden user field via `retool_subdomain_user_field_id`; the default, `0`, turns that off.)

## Install

1. Put this folder in a Git repo the server can pull from.
2. On the server, edit `/var/discourse/containers/app.yml` and add the repo under the plugin hooks:

   ```yaml
   hooks:
     after_code:
       - exec:
           cd: $home/plugins
           cmd:
             - git clone https://github.com/tryretool/community-retool-subdomain.git
   ```

   Keep any plugin lines that are already there.
3. Rebuild. The forum is offline for several minutes, so schedule it:

   ```
   cd /var/discourse
   ./launcher rebuild app
   ```
4. In Admin, check Plugins: `community-retool-subdomain` should be listed.

## Configure

Admin > Settings, search `retool_subdomain` (or Admin > Plugins > this plugin > Settings).

| Setting | Value |
|---|---|
| `retool_subdomain_main_domain` | `retool.com` (default) |
| `retool_subdomain_user_field_id` | Leave at `0` (default): nothing is stored in Discourse, only the webhook is sent. |
| `retool_subdomain_webhook_url` | The Workflow's webhook URL |
| `retool_subdomain_webhook_secret` | A long random string. Must exactly match the secret in the Workflow's `verify` block. Generate one with `openssl rand -hex 32`. |
| `retool_subdomain_enabled` | Turn on **last**, after the others are set |

With the field ID at `0`, the `previous` value in the webhook payload is always empty. That's fine: the table keeps history through its rows.

(Optional, not used in this setup: setting the ID to a hidden user field's number makes the plugin also write `user_field_<ID>`. It never checks the field exists, so a wrong ID fails silently, and recreating the field changes its ID.)

Do not share the secret in chat, tickets or Git.

## Verify end to end (dev forum)

Use a non-staff test account.

1. Set `retool_subdomain_webhook_url` and `retool_subdomain_webhook_secret`, leave the field ID at `0`, then turn `retool_subdomain_enabled` on.
2. Logged in as the test user, open the browser console on the forum and run:
   `document.cookie = "subdomain=test.retool.com; domain=.retool.com"`
   then reload the page.
3. In the Retool Workflow's run history, confirm an accepted run. Confirm a row for the test user (username lowercased) in the Workflow's table, and that the support tooling shows `test.retool.com` for that user.
4. Set the cookie to `other.retool.com` and reload. A second row should appear, and the support tooling should show the newest value (and flag multiple orgs).
5. Delete the cookie (or log out of the test session) and reload. No new report should arrive.
6. Delete the test rows from the table afterwards.

If nothing appears, check in order: that `retool_subdomain_enabled` is on, that the `subdomain` cookie is listed for `community.retool.com` in browser dev tools, the Workflow run history (a `bad signature` rejection means the secrets don't match; the plugin does not retry 4xx responses, so this fails quietly on the Discourse side), and Admin > Logs for `capture failed`.

## Roll back

- **Immediately:** turn off `retool_subdomain_enabled`. The plugin stops capturing without a rebuild.
- **Fully:** remove the `git clone` line from `app.yml` and rebuild.
- Stored field values and Workflow rows remain; delete them separately if needed.

## Files

| File | Purpose |
|---|---|
| `plugin.rb` | Entry point; attaches the capture hook |
| `lib/discourse_retool_subdomain/capture.rb` | Reads the cookie, stores the value, queues the webhook |
| `lib/discourse_retool_subdomain/validator.rb` | Hostname validation (reserved hosts list needs confirming with the Retool platform team) |
| `lib/discourse_retool_subdomain/policy.rb` | What the optional user field would hold (newest wins). Unused while the field ID is `0`. |
| `app/jobs/regular/discourse_retool_subdomain_notify.rb` | Builds and signs the webhook payload |
| `config/settings.yml`, `config/locales/server.en.yml` | Admin settings and their labels |

## Webhook signature

The job POSTs JSON with `user_id`, `username`, `subdomain`, `previous`, `observed_at`, `timestamp` and `signature`. The signature is HMAC-SHA256 (hex) of these joined by newlines, in this order:

`timestamp`, `user_id`, `username`, `subdomain`, `previous` (empty string if null), `observed_at`

The receiver recomputes it and rejects timestamps older than five minutes. It is a fixed list of fields, not the raw body, because Retool Workflows hand the receiver parsed JSON.

## Known gaps

- Unverified against Discourse 2026.1.4's source: `reloadable_patch`, `user_field_<id>` custom fields, `Jobs::Base`, `Excon`.
- The reserved-hosts list in `validator.rb` is a guess.
- `required_version` in `plugin.rb` may need adjusting.
- Privacy: this links forum accounts to customer orgs. Have the owner of the privacy policy review it before enabling in production.
