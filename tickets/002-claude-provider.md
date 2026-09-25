# 002 — Claude usage provider

Blocked by: 001 (needs `UsageProvider`, `UsageSnapshot`, `UsageWindow`). Base: `001-scaffold`.

## Goal

A `ClaudeUsageProvider` in `AIBarCore` that reads the Claude Code OAuth token from the macOS Keychain and fetches the account's rate-limit usage from Anthropic's OAuth usage endpoint, returning a `UsageSnapshot` with the 5-hour, weekly, and per-model weekly windows.

## Why

Claude is the first and, in v1, the only provider. Reusing the Claude Code session means the user never has to log in twice. The endpoint below has been verified on this machine and returns HTTP 200.

## Data source (verified 2026-09-25)

1. **Credentials.** Claude Code stores a JSON blob in the login Keychain as a generic password with service `Claude Code-credentials`. The blob contains `claudeAiOauth.accessToken` (string) and `claudeAiOauth.expiresAt` (epoch millis). Read it by running `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w` through `Process` and parsing stdout as JSON. Rationale: the Keychain item's ACL is bound to Claude Code's binary, and the `security` CLI is what other menu-bar tools in this space use to avoid per-app Keychain access prompts. Do not log or persist the token.
2. **Request.** `GET https://api.anthropic.com/api/oauth/usage` with headers `Authorization: Bearer <accessToken>`, `anthropic-beta: oauth-2025-04-20`, `Accept: application/json`.
3. **Response.** Use the `limits` array as the source of truth; it is the structured form. Each entry: `kind` (`"session"` | `"weekly_all"` | `"weekly_scoped"` | others), `group`, `percent` (number), `severity`, `resets_at` (ISO-8601 with fractional seconds and offset, or null), `scope` (null or `{ "model": { "id": null, "display_name": "Fable" }, "surface": null }`), `is_active`.
   - `session` → `UsageWindow` kind `.fiveHour`, title `5-hour`, id `session`.
   - `weekly_all` → kind `.weekly`, title `Weekly`, id `weekly_all`.
   - `weekly_scoped` with `scope.model.display_name` → kind `.weeklyModel(name)`, title `Weekly · <name>`, id `weekly_scoped:<name>`.
   - Unknown kinds → `.other`, title = kind, keep them (do not drop data the API adds later).
   - If `limits` is missing or empty, fall back to the legacy top-level objects `five_hour` and `seven_day` (`{ "utilization": Double, "resets_at": String? }`).
   - Decode tolerantly: every field the app does not need must be ignorable, and null must not fail decoding.

Sanitized real response fixture (put it in the test target as a resource or a string constant):

```json
{"five_hour":{"utilization":0.0,"resets_at":"2026-09-26T02:00:00.000000+00:00","limit_dollars":null,"used_dollars":null,"remaining_dollars":null,"locked_reason":null},"seven_day":{"utilization":12.0,"resets_at":"2026-10-01T23:59:59.686471+00:00","limit_dollars":null,"used_dollars":null,"remaining_dollars":null,"locked_reason":null},"seven_day_oauth_apps":null,"seven_day_opus":null,"seven_day_sonnet":null,"nimbus_quill":{"utilization":0.0,"resets_at":null,"limit_dollars":null,"used_dollars":null,"remaining_dollars":null,"locked_reason":null},"extra_usage":{"is_enabled":false,"monthly_limit":null,"used_credits":null,"utilization":null,"currency":null,"decimal_places":null,"disabled_reason":null,"user_disabled":false,"spend_limit_reached":false,"credits_ever_enabled":false,"daily":null,"weekly":null},"limits":[{"kind":"session","group":"session","percent":0,"severity":"normal","resets_at":"2026-09-26T02:00:00.000000+00:00","scope":null,"is_active":false},{"kind":"weekly_all","group":"weekly","percent":12,"severity":"normal","resets_at":"2026-10-01T23:59:59.686471+00:00","scope":null,"is_active":false},{"kind":"weekly_scoped","group":"weekly","percent":22,"severity":"normal","resets_at":"2026-10-01T23:59:59.686471+00:00","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":true}],"spend":{"used":{"amount_minor":0,"currency":"USD","exponent":2},"limit":null,"percent":0,"severity":"normal","enabled":false,"disabled_reason":null,"cap":null,"balance":null,"auto_reload":null,"disclaimer":"...","can_purchase_credits":false,"can_toggle":false},"member_dashboard_available":false,"seven_day_breakdown":{"as_of":"2026-09-25T21:59:50.719629+00:00","window_started_at":"2026-09-24T23:59:59.686471+00:00","rows":[{"key":"claude_code","display_name":"Claude Code","percent":100},{"key":"chat","display_name":"Chats","percent":0}]}}
```

## Requirements

- `ClaudeUsageProvider: UsageProvider` with `id = ProviderID("claude")`, `displayName = "Claude"`.
- Inject two seams so tests need neither the Keychain nor the network:
  - `protocol CredentialSource { func accessToken() async throws -> String }` with `KeychainCredentialSource` (the `security` CLI approach above) as the production implementation.
  - `protocol HTTPTransport { func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) }` with a `URLSession`-backed production implementation.
- `enum ClaudeUsageError: Error` covering at least: `.notLoggedIn` (no Keychain item or unparsable blob), `.tokenExpired` (HTTP 401), `.http(status: Int)`, `.decoding(underlying)`. Give each a user-facing `errorDescription` (`LocalizedError`), e.g. "Sign in to Claude Code to see usage".
- Window order in the snapshot: 5-hour first, then weekly, then per-model weekly, then others.
- Dates: parse `resets_at` with `ISO8601DateFormatter` using `.withInternetDateTime` and `.withFractionalSeconds`; fall back to without fractional seconds.

## Verification

Unit tests, using fakes for both seams:
- Fixture above decodes to exactly three windows in the required order, with percents 0/12/22, `weeklyModel(name: "Fable")`, and parsed reset dates.
- Missing `limits` falls back to `five_hour`/`seven_day`.
- 401 → `.tokenExpired`; 500 → `.http(500)`; credential source throwing → `.notLoggedIn`.
- Unknown `kind` is kept as `.other`.

Also do one manual run against the real endpoint (a tiny `swift run` or test marked as integration and skipped by default) and note the result in the report. Do not print the token.

## Out of scope

Token refresh (Claude Code refreshes it while in use; if it expires, surface `.tokenExpired`). UI. Persistence.
