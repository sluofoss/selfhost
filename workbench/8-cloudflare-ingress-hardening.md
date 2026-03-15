# TODO 8: Cloudflare-only web ingress via OpenTofu, plus SSH trade-offs

## Current state

The current OCI security list allows direct public access from anywhere to:

- SSH on 22
- HTTP on 80
- HTTPS on 443

Relevant file:

- `infra/main.tf`

That means Cloudflare is currently being used for:

- DNS
- certificates / origin setup

but **not** as a network allowlist in OCI.

## What should change in OpenTofu

The clean approach is:

1. add the Cloudflare provider and use `data.cloudflare_ip_ranges.cloudflare.ipv4_cidr_blocks`
2. replace the single `0.0.0.0/0` rules for ports 80 and 443 with rules for Cloudflare IP ranges only
3. keep SSH separate

That gives you:

- direct web ingress only from Cloudflare
- no direct browser traffic to the origin IP

## Important SSH point

I would **not** try to solve SSH by saying "make SSH come from Cloudflare" in the normal DNS-proxy sense.

Why:

- normal Cloudflare orange-cloud proxying is for web traffic
- raw SSH is a separate problem

So the sane split is:

- Cloudflare-only for 80 / 443
- SSH restricted to your own static IP, VPN, bastion, or Cloudflare Access / Tunnel if you intentionally adopt that later

## Benefits

### 1) Smaller public attack surface

Direct scans and random traffic can no longer hit:

- the web origin on 80 / 443

That is a real hardening step.

### 2) Better alignment with your actual architecture

You already want Cloudflare in front for:

- DNS
- TLS
- DDoS shielding

So letting the origin accept web traffic from anywhere is inconsistent with that goal.

### 3) Very low direct dollar cost

This is mostly a configuration change, not a paid-service change.

## Costs and trade-offs

### 1) OpenTofu must authenticate to Cloudflare when the toggle is enabled

Instead of hardcoding the IPv4 CIDRs, OpenTofu can use:

```hcl
data "cloudflare_ip_ranges" "cloudflare" {}
```

and then feed:

```hcl
data.cloudflare_ip_ranges.cloudflare.ipv4_cidr_blocks
```

into the OCI security rules.

That is more reliable than a hand-maintained list because it tracks Cloudflare's published ranges automatically, but it adds one important dependency:

- this change adds the Cloudflare provider to a stack that previously only declared OCI
- using `cloudflare_ip_ranges` requires authenticating the Cloudflare provider with a token when the toggle is enabled

So the trade-off is:

- **more reliable / lower long-term maintenance** for the IP list itself
- **slightly more operational complexity** because `tofu plan` would now depend on valid Cloudflare provider credentials too
- **a future operational requirement** to notice data-source drift and alert before stale OCI rules become a surprise

### 2) Misconfiguration can break the site

If the IP ranges are stale or incomplete, you can create:

- 521 / 522-style failures

### 3) Direct-origin debugging becomes less convenient

That is usually acceptable, but worth noting.

### 4) SSH still needs a real plan

Today SSH is world-open in OCI.

That is still the biggest obvious remaining network exposure even if 80 / 443 are tightened.

### Future requirement: alert when the published ranges change

Using the provider data source removes manual CIDR edits, but OCI rules still only change after a later `tofu apply`.

So a sensible future follow-up is:

- a cron job, GitHub Action, or similar drift check
- that notices a change in `cloudflare_ip_ranges` / `etag`
- and sends a notification through an agreed channel such as email, SMS, or chat

## My recommended rollout

### Phase 1

Restrict only:

- 80 / 443 to Cloudflare IP ranges

Leave SSH alone temporarily if you want the lowest-risk first step.

### Phase 2

Restrict SSH to one of:

- your home / office static IP
- Tailscale / VPN
- a bastion host
- Cloudflare Access / Tunnel if you deliberately want that model

## A small certificate caveat

The repo still documents Let's Encrypt as an option.

If you rely on:

- Cloudflare Origin Certs only

then web ingress can be Cloudflare-only cleanly.

If you still want direct ACME HTTP challenge behavior at the origin, keep that in mind before changing port-80 rules.

## Cost-benefit view

### Benefit

- meaningful reduction in direct web attack surface
- better consistency with the Cloudflare front-door model
- low implementation cost

### Cost

- Cloudflare provider auth becomes part of the rollout path
- a future drift-alert / re-apply process is still needed
- potential breakage if rules drift
- SSH remains a separate problem until you solve it explicitly

## Bottom line

Yes, this is worth doing.

The strongest simple version is:

- force 80 / 443 to Cloudflare IP ranges
- do **not** leave web ingress world-open
- solve SSH separately with a tighter admin-access path

The repo should use the provider-backed `cloudflare_ip_ranges` data source as the source of truth, but the alerting / notification path is still a future follow-up requirement.
