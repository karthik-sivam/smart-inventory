# Team / Workspace Firestore Contract (iOS)

Canonical field names, paths, and invite-acceptance semantics for Stoqly
workspace collaboration. Android `SCHEMA.md` and this file must stay aligned.
Do **not** deploy `firestore.rules` from an iOS change; rules ship only after
both clients write `inviteId` and accept atomically, and only with explicit
founder approval.

## Paths

```
workspaceInvites/{inviteId}                 // TOP-LEVEL collection
  ownerUID, ownerDisplayName, inviteeEmail (lowercased), role, status, createdAt
  status: pending → accepted | declined

users/{ownerUID}/members/{memberUID}
  uid, displayName, email, role, status, inviteId, joinedAt
```

Roles: `owner` | `manager` | `viewer` (never "editor").
Member status: `active` | `removed`.

## Member document — seven approved fields

Hardened Security Rules (`validAcceptedMembership`) allow **only** these keys
on create/update of a member document by the invitee:

| Field | Accept-path value |
|---|---|
| `uid` | Authenticated UID (must equal `{memberUID}`) |
| `displayName` | Authenticated user's display name |
| `email` | Authenticated Firebase email |
| `role` | Role copied from the pending invitation (`manager` or `viewer`) |
| `status` | `"active"` |
| `inviteId` | Invitation document ID (`workspaceInvites/{inviteId}`) |
| `joinedAt` | `FieldValue.serverTimestamp()` (`request.time` in rules) |

`inviteId` is **additive**. Legacy member documents without it must still decode
on read (`inviteId` optional / default `nil` locally). New accepts always write it.

## Atomic invite acceptance

Invite acceptance and member creation **must** occur in one Firestore
`WriteBatch`, committed once:

1. `workspaceInvites/{inviteId}` → `status: "accepted"` (only `status` changes).
2. `users/{ownerUID}/members/{authenticatedUID}` → the seven fields above,
   using **merge** (`setData(..., merge: true)` / Android `SetOptions.merge()`).

Merge is kept because the existing iOS/Android write contract uses it. Hardened
rules still evaluate `request.resource.data` after the merge and require
`keys().hasOnly` the seven approved fields — extra keys on a pre-existing
member document would fail the candidate rules.

Local side-effects run **only after** the batch commit succeeds:

1. Upsert the local `TeamMember` by `uid` (never insert a duplicate).
2. `safeSave` — check the returned `Bool`; do not swallow a save failure.
3. `joinWorkspace(ownerUID:role:)`.

If the batch fails: do not join, do not persist an active local member, and
surface a retryable error. Decline remains a single status update to
`"declined"` (not batched).

## Local SwiftData

`TeamMember.inviteId` is optional with a `nil` default so existing stores
migrate without a `VersionedSchema`. Newly accepted members store the real
invitation ID.

## Rules deployment

Candidate hardened rules live in the Android repo (`android/firestore.rules`).
They are **not** deployed from this iOS task. Deploy only after iOS and Android
parity is merged and the founder explicitly approves.
