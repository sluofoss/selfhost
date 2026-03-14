# Authentication Guide

All browser-accessible services are gated by **Authelia** (`auth.sluofoss.com`) as the first layer.
After an Authelia session is established, most services have their own second login screen.

---

## How Authelia works

When you visit a protected service without a session:
1. Traefik intercepts the request and asks Authelia to verify
2. Authelia redirects you to `auth.sluofoss.com`
3. You enter your Authelia username + password + TOTP code
4. Authelia sets a session cookie for the `sluofoss.com` domain
5. You are forwarded back to the service you originally requested

The Authelia session lasts 12 hours (inactivity timeout: 1 hour). Logging out at
`auth.sluofoss.com` ends the session for all protected services simultaneously.

---

## Service-by-service breakdown

### Authelia portal — `auth.sluofoss.com`
| Field | Detail |
|---|---|
| Purpose | Central session manager; not a service itself |
| Login | Username + password + TOTP (one-time code from authenticator app) |
| Authelia policy | bypass (portal cannot gate itself) |
| Accounts | 1 per person — in `server/authelia/config/users_database.yml` |
| Multi-user | Add a new entry to `users_database.yml`, assign `groups`; Authelia hot-reloads the file |

### Traefik dashboard — `traefik.sluofoss.com`
| Field | Detail |
|---|---|
| Login | Authelia only (two-factor) — no separate Traefik credential after migration |
| Authelia policy | `two_factor`, `user:sean` only |
| Accounts | 1 total (Authelia `sean`) |
| Multi-user | Not designed for multiple operators; change `user:sean` to `group:admins` in `configuration.yml` to open it |

### VSCode / code-server — `vscode.sluofoss.com`
| Field | Detail |
|---|---|
| Login | Layer 1: Authelia two-factor; Layer 2: code-server `PASSWORD` env var (prompted each session) |
| Authelia policy | `two_factor`, `user:sean` only |
| Accounts | 1 Authelia account + 1 shared code-server password (not per-user) |
| Multi-user | Not designed for multiple users; a single workspace with root-level file access |

### Grafana — `grafana.sluofoss.com`
| Field | Detail |
|---|---|
| Login | Layer 1: Authelia one-factor; Layer 2: Grafana's own login |
| Authelia policy | `one_factor`, `group:admins` |
| Accounts | 1 Authelia account + 1 Grafana account per person |
| Multi-user | Add Authelia account to `admins` group + create matching Grafana user |
| Future | Grafana supports OIDC — can be configured to use Authelia as provider, eliminating the second login |

### Seafile — `files.sluofoss.com`
| Field | Detail |
|---|---|
| Login (browser) | Layer 1: Authelia one-factor; Layer 2: Seafile's own login |
| Login (desktop/mobile app) | Seafile app login only — Authelia bypassed for `/api2/`, `/seafhttp/`, `/seafdav/` paths |
| Authelia policy | `one_factor` for web UI; `bypass` for sync/API paths |
| Accounts | 1 Authelia account + 1 Seafile account per person |
| Multi-user | Seafile has full multi-user support (admin panel, org groups, shared libraries). Each user needs both an Authelia account and a Seafile account. Seafile admin can manage users independently of Authelia after they pass the first gate. |
| Future | Seafile Pro supports OAuth2/OIDC — configuring Authelia as OIDC provider gives single-sign-on (one login for both) |

### Immich — `photos.sluofoss.com`
| Field | Detail |
|---|---|
| Login | Immich's own login only (email + password) |
| Authelia policy | `bypass` — Authelia does not gate Immich |
| Why bypassed | Immich mobile apps use `Authorization: Bearer` token auth; Authelia's redirect-on-401 would break them |
| Accounts | 1 Immich account per person — managed entirely within Immich admin panel |
| Multi-user | Full native multi-user: admin creates accounts, sets roles (admin/viewer), controls library sharing |
| Public shares | Share links work via `share.sluofoss.com` (see below) — no login required for viewers |

### Immich public share proxy — `share.sluofoss.com`
| Field | Detail |
|---|---|
| Login | None — intentionally public |
| Authelia policy | `bypass` |
| Purpose | Serves Immich share links to people without accounts; proxy fetches content server-side using an Immich API key |
| Accounts | No account needed to view shared content |
| Multi-user | Works for any valid Immich share link regardless of who created it |

### CouchDB / Obsidian LiveSync — `obsidian.sluofoss.com`
| Field | Detail |
|---|---|
| Login | CouchDB HTTP Basic Auth embedded in the Obsidian LiveSync plugin settings |
| Authelia policy | `bypass` — LiveSync sends credentials directly; forward-auth redirects would break it |
| Accounts | CouchDB credentials set in LiveSync plugin config on each device |
| Multi-user | Each user/device gets a separate CouchDB database + credentials; no sharing between instances |

---

## Adding a new user to the stack

1. **Authelia account** — add an entry to `server/authelia/config/users_database.yml`:
   ```yaml
   alice:
     displayname: "Alice"
     password: "<argon2id hash>"   # generate: docker run --rm authelia/authelia:4 authelia crypto hash generate argon2 --password 'pass'
     email: alice@example.com
     groups:
       - users   # or admins for full access
   ```
   Authelia hot-reloads this file; no restart needed.
   On first login, the user will be prompted to register a TOTP device.

2. **Per-service accounts** — create accounts as needed:
   - **Immich**: Admin panel → Users → invite or create
   - **Seafile**: Admin panel → Users → add user
   - **Grafana**: Admin panel → Users → invite (or OIDC once configured)

3. **Access control** — by default the Authelia `access_control` rules allow any authenticated
   user (`one_factor`) to reach Seafile, Grafana (admins group only), and Navidrome web UI.
   Traefik dashboard and code-server remain restricted to `user:sean`; update
   `server/authelia/config/configuration.yml` to grant others if needed.

---

## Account count summary

| Person | Authelia | Immich | Seafile | Grafana | CouchDB | code-server |
|---|---|---|---|---|---|---|
| Admin (sean) | ✓ (TOTP) | ✓ | ✓ | ✓ | ✓ (if using LiveSync) | shared PASSWORD |
| Regular user | ✓ (TOTP) | ✓ | ✓ | optional | own credentials | no access |
| Share link viewer | none | none (share link only) | none | none | none | none |

---

## Notification delivery

Authelia uses a **filesystem notifier** — email is not sent over SMTP. Identity verification
codes (e.g. for TOTP registration) are written to:

```
server/authelia/config/notification.txt   (local repo copy)
/home/ubuntu/selfhost/server/authelia/config/notification.txt   (live server)
```

To retrieve a one-time code: `sudo cat ~/selfhost/server/authelia/config/notification.txt`
on the server, or via SSH.
