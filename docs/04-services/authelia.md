# Authelia — Authentication Model

Authelia is the forward-auth SSO/MFA gateway. Traefik calls it on every request before
forwarding traffic. Authelia either approves the request, redirects to its login portal,
or rejects it outright.

The canonical configuration is `server/authelia/config/configuration.yml.tmpl`.

## Per-service auth policy

| Service | Domain | Policy | Reason |
|---|---|---|---|
| Traefik dashboard | `traefik.*` | Two-factor (TOTP) | Admin surface, low-traffic |
| code-server | `vscode.*` | Two-factor (TOTP) | Direct shell access to the server |
| Grafana | `grafana.*` | One-factor (password) | Monitoring, read-mostly |
| Seafile web UI | `files.*` | One-factor (password) | File sync UI |
| Immich | `photos.*` | **Bypassed** | See below |
| immich-public-proxy | `share.*` | **Bypassed** | Intentionally public share links |
| TWS | `tws.*` | Two-factor (TOTP) | Live trading GUI — must not be downgraded |

The Authelia config uses `default_policy: deny`, so any service not explicitly listed is
blocked unless it has a matching rule granting access or bypass.

## Why Immich bypasses Authelia

This is a **deliberate design choice**, not an oversight.

**Immich has its own full authentication layer** — local accounts, OAuth/OIDC, API keys,
and time-limited shared-link tokens. It enforces authentication on every endpoint
independently.

**Mobile apps break with forward-auth.** The Immich iOS and Android apps authenticate
using `Authorization: Bearer <token>` headers. Authelia's forward-auth model works by
redirecting unauthenticated requests to `auth.<DOMAIN>` for interactive login. A Bearer
token request gets a 302 redirect instead of a 401, which crashes the mobile client.
Fixing this requires path-specific bypass rules for every API endpoint — and Immich adds
new API paths regularly, so maintaining that list is fragile.

**The net security gain is zero.** Adding Authelia in front of Immich would give you a
second password prompt on the web UI without any protection gain over what Immich already
provides. Immich already rate-limits logins, supports 2FA internally, and controls its
own session tokens.

**The `share.*` domain is intentionally unauthenticated.** `immich-public-proxy` serves
share links that are meant to be opened by recipients who do not have Immich accounts.
Putting Authelia in front of it would break every link you share.

## What this means in practice

- Navigating to `photos.<DOMAIN>` goes directly to Immich's own login screen.
- The Authelia login portal (`auth.<DOMAIN>`) is not involved.
- Mobile sync apps work without any special configuration.
- Share links work for external recipients without Authelia accounts.

This pattern differs from every other service in the stack. That is expected and correct.
If you are debugging access to Immich and wondering why Authelia is not involved: it is
not involved by design.

## Adding a new service

When adding a new service, decide the auth policy at compose-time, not after deployment.
The options in Authelia are:

- `two_factor` — TOTP or WebAuthn required. Use for: admin surfaces, shell access,
  anything that can modify server state.
- `one_factor` — password only. Use for: monitoring dashboards, read-heavy UIs with low
  blast radius.
- `bypass` — Authelia does nothing. Use only when: the service has its own robust auth
  layer AND forward-auth redirects would break its clients (e.g. mobile apps with Bearer
  tokens), OR the surface is intentionally public (share links).

Add the rule to `configuration.yml.tmpl` and add the Traefik label
`traefik.http.routers.<name>.middlewares=authelia@file` in the service compose file.
Never use `bypass` as a default for convenience — Authelia's `default_policy: deny`
means unlisted services are already inaccessible; bypass actively opts out of protection.
