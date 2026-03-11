# Immich Storage Decision

## Decision

Use the **lean rebuild-first** storage model for Immich.

In practice, that means:

- keep original uploads in Backblaze B2 through the existing rclone mount
- keep PostgreSQL and explicitly bounded caches on the OCI block volume
- keep thumbnail webps local for normal browsing
- treat preview JPEGs as rebuildable and disposable under storage pressure
- keep `encoded-video` in the B2-backed tree unless there is a later, explicit decision to spend more local disk on faster video derivatives

This is the storage posture that best matches the project goals:

- low monthly cost
- easy rebuilds
- minimal surprise growth on the 200 GB OCI block volume

## Why this lives in architecture docs

This is not just an Immich service-tuning note.

It is a cross-cutting design decision that affects:

- B2 usage
- OCI block-volume budgeting
- backup policy
- rebuild time
- expected user experience during regeneration or restore events

That makes `01-architecture/` the right long-term home for it.

## Decision summary

| Area | Decision |
| --- | --- |
| Originals | Stay in B2 |
| PostgreSQL | Keep local on `/data` |
| rclone cache | Keep local on `/data` with an explicit path |
| ML cache | Keep local on `/data` with an explicit path |
| Thumbnail webps | Keep local |
| Preview JPEGs | Rebuildable and disposable under pressure |
| `encoded-video` | Keep B2-backed for now |
| Weekly backups | Do not multiply rebuildable thumbnail data unnecessarily |

## Why this option won

The key planning problem is not raw B2 storage cost.

The real constraint is the combination of:

- a 200 GB local block volume
- local derivative growth
- weekly local backup duplication
- Class C list pressure on the B2-backed originals tree during cold scans and regenerations

The lean rebuild-first model is the only option that stays compatible with those constraints without asking for a larger local volume.

## Key numeric drivers

Measured and modeled during the March 2026 review:

| Driver | Approximate size |
| --- | ---: |
| Thumbnail webps | **~16 GB per 1 TB** of image originals |
| Preview JPEGs at `720 / 50` | **~20.4 GB per 1 TB** of image originals |
| Thumbnail webps + previews | **~36.4 GB per 1 TB** of image originals |

The backup scripts matter too:

- `backup-postgres.sh` keeps 7 local compressed dumps
- `backup-weekly.sh` archives `/data/immich/thumbnails`, `/data/backups/postgres`, and `/var/lib/docker/volumes`
- local weekly retention is 4 weeks

If weekly thumbnail retention is left unchanged, the local-disk picture gets much worse:

| Option | 1 TB image originals | Practical read |
| --- | ---: | --- |
| Lean rebuild-first | **~80 GB** image-derivative subtotal | Still plausible, but wants backup cleanup |
| Balanced local previews | **~182 GB** image-derivative subtotal | Already a bad fit for a 200 GB block volume |

That is why the decision is paired with a backup-policy constraint:

- rebuildable thumbnail data should not be multiplied locally for no real recovery benefit

## B2 cost and performance implications

### Costs

- B2 storage remains cheap relative to local OCI storage pressure
- Uploads are Class A and free
- Class B reads are cheap
- Class C list operations are the real metadata-cost risk
- Occasional full-library reads are often still inside Backblaze's free egress allowance

### Performance

- Keeping thumbnail webps local preserves normal browsing performance
- Treating preview JPEGs as disposable accepts some first-hit latency after cleanup or rebuild
- Keeping `encoded-video` in B2 avoids another unbounded local growth surface
- Cold-tree operations against the originals mount remain the main place where B2 latency and Class C churn show up

## Consequences of this decision

This decision implies the repo should converge toward the following layout:

1. `DB_DATA_LOCATION` should move to an explicit `/data/immich/postgres` path
2. rclone cache placement should be explicit on `/data`
3. the Immich ML cache should be explicit on `/data`
4. thumbnail webps remain local
5. preview JPEGs are documented as rebuildable rather than permanent local assets
6. weekly backup policy should avoid retaining rebuildable thumbnail snapshots by default

## Why the other options were not chosen

### Balanced local previews

This gives a nicer always-hot browsing experience, but it burns through local disk too quickly once the backup multiplier is included.

### Performance-heavy local derivatives

This improves local responsiveness further, but it conflicts with the project's low-cost, easy-rebuild goals and creates the highest risk of silent local growth.

## Related documents

- [Storage Strategy](./storage-strategy.md)
- [Architecture Overview](./overview.md)
- [B2 Bucket Structure](../02-setup/b2-bucket-structure.md)
- [Backup & Restore](../03-operations/backup-restore.md)
