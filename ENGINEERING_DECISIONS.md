# Engineering Decisions

## Assumptions (would confirm with a product manager first)
- A **work item** belongs to exactly one team; roles (viewer/member/lead/admin) are **per team**.
- Workflow: `open → in_progress → awaiting_approval → resolved → closed`, plus `in_progress → open`, and Lead-only
  reject (`awaiting_approval → in_progress`) and reopen (`resolved → in_progress`). Closed is terminal.
- Any Member can claim an unassigned item; only a Lead can assign/reassign other people.
- Approval, rejection, closing and reopening need the Lead role **in the item's team**. A Lead may approve their own item (would ask PM whether four-eyes is required).
- "Unassigned urgent" and "Assigned to me" hide resolved/closed items; they are "needs attention" views.

## 1. Concurrency control: conditional updates + optimistic locking
**Context:** two people claiming the same item, stale edits, rapid updates.
**Options:** (a) pessimistic row locks (`SELECT … FOR UPDATE`) held across a request; (b) application-level checks; (c) conditional single-statement updates and a `version` column.
**Choice:** (c). Claim is `UPDATE … WHERE assignee_id IS NULL`; edits use `WHERE version = $n` then `version + 1`; transitions use `WHERE status = $from`. Under READ COMMITTED a concurrent writer waits for the row lock, re-evaluates the `WHERE`, and gets 0 rows → HTTP 409 (with the latest item for edits).
**Trade-off:** clients must handle 409s (the UI shows "this item changed" and reloads). In exchange there are no long-held locks, no deadlocks, and correctness lives in the database rather than in app memory.

## 2. History written in the same transaction as the change
**Context:** history must never disagree with the item.
**Options:** write events after the update; CDC/triggers; same-transaction inserts from the service layer.
**Choice:** every mutation runs inside one `withTx` and inserts `activity_events` rows before commit; the table is **append-only** (a trigger rejects UPDATE/DELETE). Comments are events of kind `comment`.
**Trade-off:** slightly more code in each service function than a trigger-based approach, but event payloads (from/to, actor name) are explicit and testable. A failure rolls back both item and history.

## 3. Authorization: one function, enforced on the server, scoped per team
**Context:** hidden buttons are not security.
**Options:** middleware per route; global roles; a single `can(user, teamId, action)` with a role × action matrix.
**Choice:** `permissions.ts` holds the matrix and the transition map; every service function loads the item and calls `assertCan(user, item.teamId, action)`. Memberships are re-read from the DB on every request, so role changes apply immediately. List queries are scoped with `team_id = ANY(my teams)`. Outsiders get **403** (a viewer can read but not write).
**Trade-off:** one extra query per request for memberships (cheap, indexed by PK). Returning 403 rather than 404 reveals that an item id exists; acceptable for an internal tool and clearer to debug.

## 4. Idempotency inside the transaction + transactional outbox for async work
**Context:** double clicks, client retries, and notifications that must not be lost or duplicated.
**Options:** in-memory dedupe; Redis keys; Postgres key table. For async: fire-and-forget after commit; Redis queue; outbox table.
**Choice:** the `Idempotency-Key` row is inserted in the *same* transaction as the change. A parallel duplicate blocks on the unique index until the first commits, then replays the stored response; if the first fails, the key rolls back so a retry works. Side effects are written as `jobs` rows in the same transaction; a worker claims them with `FOR UPDATE SKIP LOCKED`, retries with exponential backoff, gives up after `max_attempts`, recovers stale `processing` jobs, and the handler is idempotent (`notifications.job_id UNIQUE`).
**Trade-off:** at-least-once delivery (hence idempotent handlers) and Postgres doing double duty as a queue — fine at this scale; a dedicated broker is the 10× answer. Keys are scoped to (user, route+item), so reusing a key for a different request returns 422.

## 5. Search and pagination: server-side, keyset cursor, purpose-built indexes
**Context:** tens of thousands of items and growing history.
**Options:** OFFSET pagination; created_at cursor; monotonically increasing `seq` cursor; external search engine.
**Choice:** keyset pagination on a `bigserial seq` (`WHERE seq < cursor ORDER BY seq DESC LIMIT n+1`), full-text search via a generated `tsvector` column with a GIN index, and indexes on `(team_id, seq)`, `(assignee_id, seq)`, `(status, team_id, seq)` plus a partial index for "unassigned urgent". The activity log is paginated by event id. Seed data creates 3,000 items to exercise this.
**Trade-off:** cursor pages are stable under inserts but cannot jump to page N; ordering is by creation, not by priority/due date (would need composite cursors). Postgres FTS is good enough until relevance ranking or typo tolerance is needed.

## What I chose not to build
Email delivery, attachments, SSO, websockets (30 s polling instead), sign-up flow, per-team workflow configuration, and a separate comments table. Time went to the correctness behaviours the brief prioritises.

## What changes at 10× scale
Read replicas for list/search queries; partition `activity_events` by time; move search to OpenSearch/Typesense; replace the outbox poller with a dedicated queue (or logical replication of the outbox); websockets/SSE for live updates; purge idempotency keys by TTL.
