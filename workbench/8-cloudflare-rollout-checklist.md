# TODO 8 follow-up: Cloudflare-only web ingress rollout checklist

## What is already done in code

The repo now has a safe toggle for this:

- `restrict_web_to_cloudflare`
- `cloudflare_ip_ranges`
- `ssh_allowed_cidrs`

So the code path exists already.

## New operational assumption

The repo now assumes that when `restrict_web_to_cloudflare = true`, you will supply a valid `CLOUDFLARE_API_TOKEN` so OpenTofu can read:

```hcl
data.cloudflare_ip_ranges.cloudflare.ipv4_cidr_blocks
```

## What still has to happen before a real rollout

### 1) Confirm Cloudflare is actually the front door for every web hostname

Before turning the toggle on, make sure the relevant DNS records are proxied through Cloudflare.

That means:

- `photos`
- `grafana`
- `traefik`
- and any future public admin apps

should all be orange-cloud / proxied if they must keep working after the change.

### 2) Decide the Phase 1 scope

The safest first rollout is:

- restrict only `80/443`
- leave SSH on the current path for now

### 3) Decide the certificate mode

This change is easiest if you rely on:

- Cloudflare Origin Certificates

If you still want direct origin ACME HTTP challenge behavior, think carefully before changing port-80 exposure.

## Exact rollout steps

### Step A

Set the toggle:

```hcl
restrict_web_to_cloudflare = true
```

### Step B

Leave SSH unchanged for Phase 1:

```hcl
ssh_allowed_cidrs = ["0.0.0.0/0"]
```

### Step C

Export Cloudflare auth for the provider:

```bash
export CLOUDFLARE_API_TOKEN=...
```

### Step D

Run:

```bash
cd infra
tofu fmt
tofu validate
tofu plan
```

### Step E

Review that the plan shows:

- `80/443` moving from `0.0.0.0/0`
- to the Cloudflare-provider IPv4 ranges returned by `cloudflare_ip_ranges`

### Step F

Apply the change.

### Step G

Immediately verify:

- `https://photos.<domain>`
- `https://grafana.<domain>`
- `https://traefik.<domain>`
- direct-origin browser access to `https://<reserved-ip>` should stop working

## Rollback plan

If anything breaks:

1. set `restrict_web_to_cloudflare = false`
2. rerun `tofu plan`
3. `tofu apply`

That restores world-open `80/443`.

## Phase 2

After Phase 1 is stable, choose a tighter SSH path:

- static admin IP
- VPN / Tailscale
- bastion
- Cloudflare Access / Tunnel

## Future requirement after rollout

Because OCI only updates on a later `tofu apply`, add a future drift-detection path that:

- notices when the Cloudflare IP data source changes
- alerts through an agreed notification channel
- and either tells you to run `tofu apply` or triggers an automated workflow

## Bottom line

This is ready for a cautious rollout.

The only real remaining decision is:

- whether you want to enable Phase 1 now while leaving SSH alone
- and what notification path should be used later when Cloudflare changes its published IP ranges
