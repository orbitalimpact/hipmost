# hipmost

Migrate HipChat exports to Mattermost. Audit first, import one room at a time, verify each one before moving on.

## Why not migratemost or varna?

| Feature | hipmost | migratemost | varna |
|---|---|---|---|
| Language | Ruby | Python 2 | Python 2 |
| Audit phase | yes — shows what would happen before touching anything | no | no |
| Collision detection | yes — skips exact-timestamp duplicates on merge | no | no |
| Per-room atomic import | yes — generate + import + verify in one command | no | no |
| Mapping review workflow | yes — audit writes YAML you edit and approve | no | no |
| Emoji conversion | yes — HipChat shortcodes to MM shortcodes | partial | no |
| Attachment validation | yes — size check, path resolution, re-import command | no | no |
| Message splitting | yes — splits at word boundary, preserves timestamps | no | silently drops |

Not claiming perfection. If you have a small HipChat export and don't care about any of the above, any tool will work.

## Prerequisites

- Ruby 3.x
- `pg` gem (`gem install pg`)
- PostgreSQL read access to your Mattermost database
- `mmctl` at `/opt/mattermost/bin/mmctl` for the import commands
- `zip` in PATH

## Setup

Create `~/.hipmost-env`:

```sh
export HIPMOST_DB_URL=postgres://mattermost:yourpassword@localhost/mattermost
```

The script also checks `~/.mm-search-env` and the `MATTERMOST_DB_URL` env var as fallbacks.

## Workflow

### 1. Audit the export

```sh
ruby hipmost.rb audit /path/to/hipchat-export
```

This reads the export, queries your Mattermost DB, and writes `hipmost-audit.yaml`. It shows:

- Which HC users matched MM users (by email, then username)
- Which HC rooms matched MM channels (fuzzy name match)
- Suggested action for each: `skip` / `merge` / `new`
- DM inventory per user

Open `hipmost-audit.yaml` and review. The audit output is not your import mapping — it's your research. You'll build a separate `mapping.yaml` from it (see format below).

### 2. Build your mapping

Convert the audit output into a `mapping.yaml`. The audit YAML uses a flat structure; the import commands expect the structured format described in the Mapping Format section. This is intentional — the review step forces you to make deliberate decisions per room rather than bulk-approving.

### 3. Import one room at a time

```sh
ruby hipmost.rb import_one /path/to/hipchat-export --map mapping.yaml --room 'Engineering'
```

This command:
1. Generates JSONL for that one room
2. Packages it as a zip
3. Calls `mmctl import process`
4. Polls the import job until done
5. Verifies post count and samples a few messages
6. Exits nonzero if verification fails

For merge targets (room already exists in MM), it loads existing timestamps first and skips exact duplicates.

### 4. Import DMs

```sh
ruby hipmost.rb import_dm /path/to/hipchat-export --map mapping.yaml --pair 'alice,bob'
```

Same pattern: generate, import, verify. DM channel is created if it doesn't exist.

### 5. Fix attachments (if needed)

```sh
ruby hipmost.rb fix_attachments /path/to/hipchat-export --map mapping.yaml
ruby hipmost.rb fix_attachments /path/to/hipchat-export --map mapping.yaml --room 'Engineering'
```

Re-imports only the attachment-bearing posts. Mattermost matches posts by `channel + create_at` and attaches the files to the existing posts. Run this after `import_one` if attachments were missing.

### 6. Bulk generate + import (alternative)

If you'd rather generate everything at once and import with a single `mmctl` call:

```sh
ruby hipmost.rb generate /path/to/hipchat-export --map mapping.yaml
ruby hipmost.rb generate /path/to/hipchat-export --map mapping.yaml --dry-run  # preview counts
ruby hipmost.rb import hipmost-output.zip
```

The bulk path does less verification than `import_one`. Good for a final full-run after you've tested individual rooms.

## Mapping Format

The import commands (`import_one`, `import_dm`, `fix_attachments`) use a structured mapping, not the raw audit YAML.

```yaml
users:
  - hc: alice           # HipChat mention_name
    hc_id: 12345        # from audit YAML
    mm: alice           # Mattermost username (omit if same as hc)
    email: alice@example.com
    action: map         # map | create | skip

  - hc: bob
    hc_id: 12346
    mm: bob.smith       # different MM username
    email: bob@example.com
    action: map

  - hc: former-employee
    hc_id: 99999
    action: skip        # skip: messages from this user are dropped

rooms_skip:
  - hc_name: Watercooler
    hc_id: 1001
    target: myteam:watercooler   # team:channel-name (MM channel to skip importing into)

rooms_merge:
  - hc_name: Engineering
    hc_id: 2001
    target: myteam:engineering
    display_name: Engineering
    type: O              # O=public, P=private

  - hc_name: Infrastructure
    hc_id: 2002
    target: myteam:infrastructure
    display_name: Infrastructure
    type: P

rooms_new:
  - hc_name: Old Project
    hc_id: 3001
    target: myteam:old-project
    display_name: Old Project
    type: P
    members:             # optional: add these MM users after import
      - alice
      - bob

dms:
  import_dms: yes        # yes | no
```

Field notes:

- `target` format is `team-name:channel-name` where both are the internal names (lowercase, hyphens), not display names
- `action: create` in users means the user doesn't exist in MM yet; hipmost emits a user record and mmctl creates them
- `type` for rooms: `O` is public (open), `P` is private
- `rooms_skip` entries are listed but not imported — useful to document your decisions

## How it works

The audit-first approach exists because HipChat exports are messy. Rooms get renamed, users change usernames, some content was already imported via other paths. Going in blind overwrites things.

The flow:

1. `audit` reads the HC export and queries MM, producing a YAML snapshot of the current state with suggested actions
2. You review and edit that into a `mapping.yaml` — explicit decisions about every room and user
3. `import_one` generates JSONL for exactly one room, imports it, and verifies the result before you proceed to the next

The JSONL format is Mattermost's bulk import format. `mmctl import process` handles the actual write to Mattermost. hipmost doesn't touch the database directly — it only reads.

For merge targets, hipmost loads all existing post timestamps before generating JSONL and skips any HC message whose timestamp exactly matches an existing post. This handles the common case where a partial import was run before.

Messages longer than 16,383 characters (Mattermost's limit) are split at word boundaries. Each chunk gets a `create_at` offset of 1ms to preserve ordering.

Attachments over 50MB are skipped (MM default file size limit). If your MM instance has a different limit, change `MM_MAX_FILE` at the top of the script.

## Limitations

- The fuzzy room matching in `audit` works well for rooms that weren't renamed much. If you renamed rooms significantly between HC and MM, you'll need to set targets manually in your mapping.
- DMs from guest accounts are skipped.
- HipChat `/topic` and `/emoticon` messages are not converted.
- No support for HipChat integrations or bot messages.

## License

AGPL-3.0. See LICENSE.txt.

PRs welcome.
