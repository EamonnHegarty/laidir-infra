# DynamoDB access patterns

One table per environment (`laidir-<env>-data`), on-demand billing. Access patterns were designed
first; keys follow from them. Change keys or indexes only after updating this doc.

## Entities

| Entity | Description |
|---|---|
| Profile | One per user: display name, units (kg/lb), preferences |
| Exercise | A user's **custom** exercise. The built-in catalogue is static, versioned JSON shipped with the API and app, not stored here |
| Routine | A workout template: ordered exercises with target sets, reps and weight. Created in the app or via Claude (MCP) |
| Workout | A logged session. Sets are **embedded** in the item (a heavy session is a few KB, far under the 400 KB limit) |

## Keys

| Entity | PK | SK | GSI1PK / GSI1SK | GSI2PK / GSI2SK |
|---|---|---|---|---|
| Profile | `USER#<sub>` | `PROFILE` | – | `USER#<sub>` / `<synced_at>#PROFILE#<sub>` |
| Exercise | `USER#<sub>` | `EXERCISE#<uuid>` | – | `USER#<sub>` / `<synced_at>#EXERCISE#<uuid>` |
| Routine | `USER#<sub>` | `ROUTINE#<uuid>` | – | `USER#<sub>` / `<synced_at>#ROUTINE#<uuid>` |
| Workout | `USER#<sub>` | `WORKOUT#<uuid>` | `USER#<sub>#WORKOUT` / `<started_at>#<uuid>` | `USER#<sub>` / `<synced_at>#WORKOUT#<uuid>` |

`<sub>` is the Cognito user ID, **always taken from the verified JWT, never from the request**.
`<uuid>` is generated on the client. Timestamps are ISO-8601 UTC with milliseconds, so they sort as strings.

## Access patterns

| # | Pattern | Operation |
|---|---|---|
| 1 | Get or update the user's profile | `GetItem/PutItem PK=USER#<sub>, SK=PROFILE` |
| 2 | List the user's custom exercises | `Query PK=USER#<sub>, SK begins_with EXERCISE#` |
| 3 | List the user's routines | `Query PK=USER#<sub>, SK begins_with ROUTINE#` |
| 4 | Get or upsert any item by client UUID | `GetItem/PutItem PK=USER#<sub>, SK=<TYPE>#<uuid>` |
| 5 | Workout history, newest first, paginated | `Query GSI1 PK=USER#<sub>#WORKOUT, ScanIndexForward=false` |
| 6 | Workouts in a date range | `Query GSI1 … SK BETWEEN <from> AND <to>` |
| 7 | **Sync:** everything changed since a cursor, including deletes | `Query GSI2 PK=USER#<sub>, SK > <cursor>` |
| 8 | Delete account (GDPR) | `Query PK=USER#<sub>` + `BatchWriteItem` deletes |

**Why the SK uses the UUID, not the date:** a user editing a workout's date must not change its primary key.
Otherwise the old item is orphaned and offline sync breaks. Date ordering comes from GSI1 instead.

**Why one sync index:** the app stores a cursor (the last GSI2 SK it received) and pulls every change across all
entity types in one paginated query. Pushes are upserts keyed by UUID.

**Why the sync index uses the server's clock (`synced_at`), not the client's (`updated_at`):** `updated_at` is
set by the device that made the change. If that device's clock is behind, its change sorts *before* cursors
other devices already hold, and they never pull it. `synced_at` is stamped by the Lambda on every accepted
write, so the feed is ordered by when the server saw the change. `updated_at` still decides conflicts.
To avoid racing in-flight writes, pull only returns items with `synced_at` a couple of seconds in the past.

## Item attributes common to all entities

| Attribute | Purpose |
|---|---|
| `id` | Client UUID (duplicated from the SK for convenience) |
| `type` | `PROFILE`, `EXERCISE`, `ROUTINE`, `WORKOUT` |
| `schema_version` | Version of the JSON schema (owned by `laidir-api`) the item was written with |
| `created_at`, `updated_at` | ISO-8601 UTC, set by the client. `updated_at` drives conflict resolution |
| `synced_at` | ISO-8601 UTC, set by the **server** on every accepted write. Drives the sync feed (GSI2SK). Not exposed in the API schemas |
| `deleted_at` | Soft delete. `null` while live. Tombstones are synced so other devices delete too |
| `expires_at` | Optional epoch seconds, DynamoDB TTL. Reserved for purging old tombstones (not set yet) |

## Conflict handling

Writes are **conditional on `updated_at`** (last writer wins): `ConditionExpression: attribute_not_exists(PK) OR updated_at < :incoming`.
A stale write is rejected and the client re-pulls. This is enough for a single user on a couple of devices.

## Deliberately not here (yet)

- **Per-exercise history** ("what did I lift last time?"): computed on-device from SQLite. If the server ever needs
  it, add an item per workout-exercise with `GSI3PK = USER#<sub>#EX#<exercise_id>`.
- **Social features or sharing:** would need cross-user keys; out of scope.
- **Scan:** never used by the app, and not granted to the Lambda role.
