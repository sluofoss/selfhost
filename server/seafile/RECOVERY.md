# Seafile Pro: Disaster Recovery Runbook

## Overview

Seafile stores **all file content** in three B2 buckets (`sluo-seafile-commits`,
`sluo-seafile-fs`, `sluo-seafile-blocks`).  MariaDB stores the **head commit
pointers** that are the entry point into that object graph.

The critical rule:
> **Never run `seafile-gc` after restoring a stale MariaDB backup without first
> verifying the head pointers.** GC traverses from the DB head pointers,
> marks unreachable objects as dead, and permanently deletes them.  All data
> created after the stale backup would be destroyed.

---

## Recovery Option A — Full restore from hourly MariaDB dump (normal case)

Hourly dumps are stored at `B2:sluo-personal-b2/backups/seafile-db/`.

### 1. Stop Seafile

```bash
cd ~/selfhost/server/seafile
docker compose down
```

### 2. Locate the latest good dump

```bash
rclone ls backblaze:sluo-personal-b2/backups/seafile-db/ | sort | tail -20
```

### 3. Download and extract the dump

```bash
mkdir -p /tmp/seafile-restore
rclone copy "backblaze:sluo-personal-b2/backups/seafile-db/<filename>.sql.gz" /tmp/seafile-restore/
gunzip /tmp/seafile-restore/<filename>.sql.gz
```

### 4. Restore MariaDB

```bash
docker compose up -d db
sleep 15  # wait for MariaDB to be ready

docker exec -i seafile_db mysql -u root -p"${INIT_SEAFILE_MYSQL_ROOT_PASSWORD}" \
  < /tmp/seafile-restore/<filename>.sql
```

### 5. Verify head pointers before anything else

```bash
docker exec -i seafile_db mysql -u root -p"${INIT_SEAFILE_MYSQL_ROOT_PASSWORD}" \
  -e "SELECT r.repo_id, r.name, b.commit_id, r.last_modify FROM \
      seafile_db.Repo r JOIN seafile_db.Branch b ON r.repo_id = b.repo_id \
      WHERE b.name='master' ORDER BY r.last_modify DESC LIMIT 20;"
```

The `last_modify` timestamps should match your expectation (within 1 hour).
If they look stale (days old), you have an older dump — search for a more
recent one before proceeding.

### 6. Start Seafile

```bash
docker compose up -d
docker logs seafile -f
```

### 7. Do NOT run GC until Seafile is healthy and fully functional

Only run `seafile-gc` after you have confirmed all libraries look correct and
all expected files are present.

---

## Recovery Option B — S3-only recovery (no usable DB backup)

This is the last-resort path when both the DB and all hourly dumps are lost.
File content survives in B2 but must be reconstructed manually.

### Tools required

```bash
pip install seafobj
pip install boto3
```

Get the Seafile source (for the storage driver code) or use boto3 directly
against the B2 S3-compatible endpoint.

### How Seafile objects are laid out in S3

```
sluo-seafile-commits/<repo-id>/<commit-id>   ← HEAD commit per repo
sluo-seafile-fs/<repo-id>/<dir-or-file-id>   ← directory/file tree nodes
sluo-seafile-blocks/<block-id>               ← raw file content blocks
```

An 11-hex-char prefix (the first 2 chars become the object key prefix in B2
path-style storage).

### Step 1 — Enumerate all repo IDs from the commits bucket

```bash
export AWS_ACCESS_KEY_ID=<seafile_b2_key_id>
export AWS_SECRET_ACCESS_KEY=<seafile_b2_key>

python3 << 'EOF'
import boto3
s3 = boto3.client('s3',
    endpoint_url='https://s3.us-east-005.backblazeb2.com',
    region_name='us-east-005')

paginator = s3.get_paginator('list_objects_v2')
repo_ids = set()
for page in paginator.paginate(Bucket='sluo-seafile-commits', Delimiter='/'):
    for p in page.get('CommonPrefixes', []):
        repo_ids.add(p['Prefix'].rstrip('/'))
for r in sorted(repo_ids):
    print(r)
EOF
```

### Step 2 — Find the latest commit per repo and export files

Use a script that, for each repo ID:
1. Lists commit objects under `<repo-id>/`
2. Parses each commit JSON to find the one with the highest `ctime`
3. Reads the `root_id` (the FS tree root)
4. Recursively walks FS objects (directory and file nodes)
5. For each file node, collects the list of block IDs
6. Downloads blocks in order and concatenates into the original file

A minimal reference implementation:

```python
import boto3, json, struct, zlib

S3_ENDPOINT = 'https://s3.us-east-005.backblazeb2.com'
REGION = 'us-east-005'
s3 = boto3.client('s3', endpoint_url=S3_ENDPOINT, region_name=REGION,
    aws_access_key_id='<key_id>', aws_secret_access_key='<key>')

def get_obj(bucket, repo_id, obj_id):
    try:
        r = s3.get_object(Bucket=bucket,
                          Key=f'{repo_id}/{obj_id[:2]}/{obj_id[2:]}')
        return zlib.decompress(r['Body'].read())
    except Exception:
        # Some versions store without subdirs
        r = s3.get_object(Bucket=bucket, Key=f'{repo_id}/{obj_id}')
        return zlib.decompress(r['Body'].read())

def get_block(block_id):
    r = s3.get_object(Bucket='sluo-seafile-blocks',
                      Key=f'{block_id[:2]}/{block_id[2:]}')
    return r['Body'].read()

def export_dir(repo_id, dir_id, out_path):
    import os
    data = json.loads(get_obj('sluo-seafile-fs', repo_id, dir_id))
    for entry in data.get('dirents', []):
        name = entry['name']
        dest = os.path.join(out_path, name)
        if entry['mode'] == 33188:  # regular file
            os.makedirs(out_path, exist_ok=True)
            fdata = json.loads(
                get_obj('sluo-seafile-fs', repo_id, entry['id']))
            with open(dest, 'wb') as f:
                for blk in fdata['block_ids']:
                    f.write(get_block(blk))
        elif entry['mode'] == 16877:  # directory
            os.makedirs(dest, exist_ok=True)
            export_dir(repo_id, entry['id'], dest)

# Example: export repo <repo-id> using its latest commit's root_id
repo_id = '<repo-id>'
commit_raw = get_obj('sluo-seafile-commits', repo_id, '<latest-commit-id>')
commit = json.loads(commit_raw)
export_dir(repo_id, commit['root_id'], f'/tmp/export/{repo_id}')
```

### Notes

- Object key layout can vary by Seafile version.  If the first pattern fails,
  try without the 2-char subdirectory prefix.
- Block IDs in the FS node are stored as a list in order — concatenate them
  byte-for-byte to reconstruct the file.
- This is a manual recovery procedure.  Budget several hours for a full
  library export.

---

## Preventing future DB loss

The `backup-seafile-db.sh` cron runs at minute 30 of every hour.  Verify it is
active:

```bash
crontab -l | grep seafile
```

To confirm recent backup success:

```bash
ls -lh /data/backups/seafile-db/ | tail -5
rclone ls backblaze:sluo-personal-b2/backups/seafile-db/ | sort | tail -5
```

---

## GC procedure (weekly, safe mode)

Only run GC when:
1. Seafile is fully healthy.
2. The most recent MariaDB backup was taken within the last hour (`crontab` at
   minute 30 ensures this).
3. No restore has been performed in the last 24 hours.

```bash
# Take a fresh DB snapshot first
/path/to/selfhost/server/scripts/backup/backup-seafile-db.sh

# Then run GC inside the container
docker exec seafile /opt/seafile/seafile-server-latest/seaf-gc.sh
```
