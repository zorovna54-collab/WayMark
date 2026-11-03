# Phase 7B-2A — map draft persistence foundation

Date: 2026-10-20. Baseline: `631a76cd196460318429ebff8da394818ccbdd2d`.

Follow-up: [Phase 7B-2B managed image storage](ManagedImageStorage7B2B.md) implements
the private filesystem provider and additional ownership/quotas. This report
retains the historical 7B-2A state and its 175-test result; consult the follow-up
for the current provider, API workflow and verification.

## Audit before implementation

| Concept | Existing evidence | Supported / missing |
| --- | --- | --- |
| Site / hospital scope | `Models/Site.cs`, `Building.cs`, `Floor.cs`; `Data/WayMarkDbContext.cs` | Reuse Site → Building → Floor. No duplicate Hospital entity. |
| Graph node | `Models/NavigationNode.cs`, `NavigationNodeType.cs` | Floor, global unique NodeCode, normalized decimal X/Y, Entrance/Junction/Destination/Elevator/Stairs. A Destination node is not a Room. |
| Directed edge | `Models/NavigationEdge.cs`, `NavigationEdgeType.cs` | Explicit direction, positive decimal meters, active/accessibility booleans. No geometric wall/door/walkability verification. |
| QR landmark | `Models/WayMark.cs`, `Controllers/WayMarksController.cs:GetMapLocation` | Optional unique node link; WayMarkCode and NodeCode have different meanings. Existing records must stay unchanged. |
| Room / Place | No such entity in the current model or snapshot | Missing searchable place, label geometry, one/many entrance associations. A room's center must not become its route destination. |
| Routing | `Services/Routing/RoutePlanner.cs`, `DijkstraRouter.cs` | Resolves two WayMarkCodes to nodes; supports cross-floor directed edges and stored meters. Does not route to a Place or choose among entrances. Wheelchair requests fail closed without verified metadata. |
| Draft | `waymark/lib/features/admin/draft_map.dart` | Local single-floor JSON v2, graph + embedded image; no backend persistence. `sourceNodeId` is only provenance. No Room model. |
| Authorization | `Security/WayMarkSecurity.cs`, `AuthController.cs`, `AuthDbContext.cs` | Trusted server-issued global Admin role. No Site membership. Global Admin alone cannot authorize hospital draft access. |
| Migrations | `20261018022742_CreateWayMarkSchema`, `20261018053754_AddNavigationSchema`, model snapshot; Auth `CreateAuthSchema` | Existing graph schema only; no draft/version/membership tables. Source inspection, not a new inspection of live SQL Server. |

**Decision confirmed by the user:** Site is the hospital authorization boundary
for MVP. Add server-managed UserId–Site membership; do not grant memberships or
Admin roles automatically. Organization owning multiple Sites is deferred.

## Design selected

- Keep the published graph and QR tables untouched. New draft tables hold a
  floor draft head and immutable revision documents, not alternative production
  NavigationNodes/NavigationEdges. No publish path or production fallback.
- A draft belongs to an existing Floor; derive Building/Site by server-side joins.
  CreatedBy/UpdatedBy come from the authenticated Identity user ID, never the body.
- One draft head per Floor. A monotonically increasing concurrency-token Version
  selects an immutable revision. Update requires the expected Version; a stale
  save returns 409. Restoring copies a prior revision into a NEW revision.
- A revision document contains draft-local stable IDs, normalized geometry,
  directed edges, Places and entrance references. A Place has searchable code/name,
  a map label and at least one Entrance node. Many entrances per Place and shared
  entrances are possible. Labels/polygons are display geometry, never route targets.
- A future place-routing request resolves candidate validated entrances, computes
  feasible directed paths, and chooses the lowest valid cost; it never adds a
  straight line from corridor to a room center. Existing `/api/routes` stays intact.
- Local edge endpoints must exist in the revision. Cross-floor transition proposals
  pin a target draft revision and node; validate same Site and matching vertical
  connector types. They do not modify the published multi-floor graph.
- X/Y are normalized image coordinates, origin top-left; pixel position is
  `(x * renderedImageWidth, y * renderedImageHeight)` plus image offset. Meters
  are supplied separately, never inferred from image pixels or normalized deltas.
- Accessibility and passage verification remain **Unknown**. Saving a structurally
  valid draft does not certify doors, walls, walking routes or wheelchair safety.
  An administrator must review the real space before any future publication.
- Store image metadata and an opaque managed-storage key; never Base64 image data
  in SQL. Storage must be private, outside the web root, and accessed only after
  the same Site check. There is no URL fetch, caller-supplied filesystem path or
  static/public draft image endpoint.

## Implementation boundary

Implement draft persistence/contracts/validation and Site checks without changing
existing authentication or routing. New Site membership has no public grant API
and no seed. Until an operator separately provisions an approved membership,
even a global Admin is denied draft access.

Image storage is an abstraction. The default provider is unavailable: image
upload/download returns 503 instead of writing files with an unreviewed decoder
or filesystem policy. A real provider must validate signature/MIME, actual decode,
dimensions, bounded bytes/pixels and SHA-256, strip unneeded metadata, use opaque
server keys, and support private reads/cleanup. Tests of fake storage are not
evidence of production image decoding. Provider configuration and quotas remain a
prerequisite for Flutter Save/Load with images; existing local JSON v2 is unchanged.

No live database access, migration application, membership provisioning, Flutter
Save/Load integration, publish, production place routing or AI call is authorized
by this implementation. Migration source is reviewable independently.

## Persistence and schema

New `Models/MapDrafts.cs`, mapping in `Data/MapDraftModel.cs`, registered by the
existing `WayMarkDbContext`:

| Table | Keys / constraints | Purpose |
| --- | --- | --- |
| SiteMapMemberships | int identity PK; UNIQUE(SiteId, UserId); Site FK Restrict; UserId index | Server-managed active edit permission. Defaults do not grant permission. |
| FloorMapDrafts | GUID PK; UNIQUE(FloorId); Floor FK Restrict; Version concurrency token, >0; Status = Draft | One current draft per floor, server timestamps/actor IDs. |
| FloorMapDraftRevisions | PK(DraftId, Version); draft + optional image FK Restrict | Immutable bounded JSON graph/place snapshot; append on update/restore. |
| FloorMapImageAssets | GUID PK; UNIQUE(StorageKey); Floor FK Restrict; byte/pixel/MIME checks | Private opaque file reference + SHA-256 and decoded metadata; no image Base64/blob column. |

The membership PK is intentionally a narrow integer. `(int SiteId, nvarchar(450)
UserId)` would have a maximum 904-byte key; SQL Server has a 900-byte primary-key
limit. The separate unique nonclustered index fits the 1700-byte index limit.
See [SQL Server limits](https://learn.microsoft.com/en-us/sql/sql-server/maximum-capacity-specifications-for-sql-server?view=sql-server-ver16).

UserId/CreatedBy/UpdatedBy are logical references to AuthDbContext's Identity user
IDs, not duplicate Identity entities in this context. They have no cross-context
SQL FK to AspNetUsers. Operator provisioning must validate an existing user ID;
future Identity deletion/provisioning must clean up/revoke memberships and never
reuse a deleted ID. No membership grant/revoke API, script or seed is provided.

Places/entrance associations currently live **inside immutable draft revisions**;
they are not yet a published Places table. Draft IDs are GUIDs, separate from int
production NavigationNode IDs; optional SourceNodeId/ExistingWayMarkCode are
validated provenance only. Draft NodeCode is unique within a revision using
ordinal case-insensitive comparison, not a relaxation of the existing globally
unique published NodeCode. Future publication must check the production database
collation/global uniqueness and remap stable local IDs deliberately.

An eventual compatible published extension would add `Places` (FloorId, code/name,
label/optional geometry) and `PlaceEntrances` (PlaceId, NavigationNodeId), preserving
all current WayMarks and graph IDs. Require UNIQUE(FloorId, PlaceCode) and
UNIQUE(PlaceId, NavigationNodeId), restrict deletion and validate same floor/Site.
Do not introduce it or change legacy route requests in this phase. A future
destination-place API chooses among eligible entrance nodes via actual graph
costs; absent a feasible entrance it returns no route rather than crossing walls.

Floor drafts support pinned directed cross-floor transition proposals. They do
not imply a whole-site revision manifest, bidirectional travel, actual elevator
availability or published multi-floor topology. Coherent version selection and
verification of physical vertical connectors are future publication requirements.

## API contract implemented

All paths below start with `/api/admin/floors/{floorId}/map-drafts`.
All reads and writes require **JWT + AdminOnly + active CanEditDrafts Site membership**.
Site is resolved from Floor → Building → Site. Reads return `Cache-Control: no-store`.
No body/header/site claim grants scope; unknown ownership fields are rejected.

| Method | Suffix | Result |
| --- | --- | --- |
| GET | (none) | Current metadata or 404 within an authorized floor. |
| POST | (none) | Create initial content; 201 with server GUID/Version 1. Conflict if a floor draft already exists. |
| PUT | /{draftId} | `{expectedVersion, content}`; append revision and advance head atomically. |
| GET | /{draftId}/graph?version=... | Exact immutable version, or current head when omitted. |
| GET | /{draftId}/versions?beforeVersion=...&take=50 | Descending versions, bounded 1–100 records, exclusive pagination cursor. |
| GET | /{draftId}/places?query=...&version=... | Case-insensitive search over draft place code/name; label and entrance IDs returned. Not production Flutter Search. |
| POST | /validate | Content → errors/warnings, 200 or 400; ReadyForProduction is always false. No database write. |
| POST | /{draftId}/restore | `{expectedVersion, sourceVersion}` → NEW current revision; old revisions preserved. |
| POST | /images | Raw PNG/JPEG body, max 10 MiB; currently 503 because real validated storage is not configured. |
| GET | /images/{assetId} | Private same-floor image reference; unavailable provider returns 503 for an existing asset; never a static URL. |

Codes: 400 invalid structure/references, 401 absent/invalid/expired JWT, 403 missing
role/subject or Site permission, 404 unavailable draft/version/image **inside an
authorized floor**, 409 stale version/concurrent winner/duplicate floor draft,
413 oversized document/image, 503 storage/schema/provider unavailable. Missing
and out-of-scope floors both return 403, deliberately preventing floor enumeration.
Database exceptions, SQL text, storage paths and stack traces are not returned.

Example content (illustrative draft IDs/geometry, not seed or a production map):

```json
{
  "schemaVersion": 1,
  "imageAssetId": null,
  "nodes": [
    {"id":"11111111-1111-1111-1111-111111111111","nodeCode":"DRAFT-DOOR-A","name":"Cửa A","x":0.1,"y":0.2,"nodeType":"Entrance"},
    {"id":"22222222-2222-2222-2222-222222222222","nodeCode":"DRAFT-DOOR-B","name":"Cửa B","x":0.8,"y":0.2,"nodeType":"Entrance"}
  ],
  "edges": [
    {"id":"33333333-3333-3333-3333-333333333333","fromNodeId":"11111111-1111-1111-1111-111111111111","toNodeId":"22222222-2222-2222-2222-222222222222","edgeType":"Corridor","distanceMeters":null,"isActive":true,"accessibility":"Unknown","passageVerification":"Unknown"}
  ],
  "places": [
    {"id":"44444444-4444-4444-4444-444444444444","placeCode":"EXAM","name":"Phòng khám","label":{"x":0.5,"y":0.7},"entranceNodeIds":["11111111-1111-1111-1111-111111111111","22222222-2222-2222-2222-222222222222"],"accessibility":"Unknown"}
  ],
  "transitions": []
}
```

Null meters mean unmeasured draft distance and produce a warning; they cannot
become a routing weight. Supplied meters must be positive, max 999999999.999,
at most 3 decimal places. Missing node coordinates/type are rejected, never
inferred as an Entrance at (0,0). Non-Unknown safety claims are rejected because
this phase has no trusted physical accessibility/walkability review workflow.

The new server contract is **not** a direct importer of Flutter local JSON v2.
Phase 7B-2B needs an explicit adapter: preserve local IDs/geometry, upload an image
through the validated private provider, reference its server asset ID, and keep
local export/import working. No v2 dataBase64 is written to SQL by this API.

## Atomicity and authorization evidence

Head + revision use one relational SaveChanges, not separate commits. The Version
is an application-managed EF concurrency token and the revision PK is a second
race guard. A provider can insert a revision before checking the head's token:
after EF rollback the service checks a fresh untracked head and maps a real
concurrent winner to 409. It never retries stale content or overwrites a winner.
Restore revalidates references, then appends; no revision UPDATE/DELETE endpoint.
See [EF concurrency](https://learn.microsoft.com/en-us/ef/core/saving/concurrency)
and [atomic SaveChanges](https://learn.microsoft.com/en-us/ef/core/saving/transactions).

Site membership is checked from the database on every operation, including graph,
history, search, validation and image reads. A signed global Admin without the
membership is denied. Site revocation is effective on the next request without a
new login. Global Admin roles remain subject to existing JWT expiry/revocation
limitations; authentication itself was not changed. This implements a resource
check in addition to the role policy, as described in
[resource authorization](https://learn.microsoft.com/en-us/aspnet/core/security/authorization/resource-based).

## Migration source — NOT APPLIED

`20261020094848_AddMapDraftFoundation`, generated with the workspace-local EF
10.0.12 tool (not a global install):

```powershell
waymark/.dart_tool/phase7b2a/tools/dotnet-ef.exe migrations add AddMapDraftFoundation --context WayMarkDbContext --project WayMark.Api/WayMark.Api.csproj --startup-project WayMark.Api/WayMark.Api.csproj --output-dir Data/WayMarkMigrations
```

The new, unapplied membership mapping/migration/designer/snapshot were refined
together to use the narrow int PK described above. A SQL Server-provider test
checks no pending model changes and generates the exact forward SQL **in memory**.

- Up: CREATE the four tables, their PK/FK/check constraints and indexes only.
  No existing graph/QR/Identity table alteration, data INSERT/UPDATE/DELETE or seed.
- Down: DROP only those four NEW tables, dependent revisions first. Executing Down
  would delete draft data/memberships; it has not been executed or authorized.
- SQL generation includes the normal INSERT into `__EFMigrationsHistory`; this is
  not a business-data insert and the generated SQL was not executed.
- WayMarkDbContext history remains `__EFMigrationsHistory`; Auth remains
  `__AuthMigrationsHistory`. No Auth model/migration/config/secret changes.

## Verification (actual commands, isolated data)

```powershell
dotnet build WayMark.Api/WayMark.Api.csproj --artifacts-path waymark/.dart_tool/phase7b2a/dotnet
dotnet test WayMark.Api.Tests/WayMark.Api.Tests.csproj --artifacts-path waymark/.dart_tool/phase7b2a/dotnet --logger "trx;LogFileName=foundation-accepted.trx" --results-directory waymark/.dart_tool/phase7b2a/results
dotnet list WayMark.Api/WayMark.Api.csproj package --vulnerable --include-transitive
dotnet list WayMark.Api.Tests/WayMark.Api.Tests.csproj package --vulnerable --include-transitive
git diff --check
git status --short
```

Output/logs/tool installation are ignored under `.dart_tool/phase7b2a/`.
The only added package is **Microsoft.EntityFrameworkCore.Sqlite 10.0.12 in the test
project**, matching existing EF Core. It provides a private `Data Source=:memory:`
relational fixture to test rollback, FKs, unique keys and concurrency. No SQL
Server connection string, User Secrets or live server is loaded in these tests.

- Backend build: passed, 0 warnings/errors.
- Final backend suite: **175/175 passed**, 0 skipped; original 108-test baseline
  retained and 67 new cases. First run exposed provider-dependent ordering of
  revision insertion vs concurrency checking; fixed and rerun successfully.
- SQL Server-provider metadata tests: snapshot has no pending model changes;
  forward SQL generation is additive only, no production/Identity changes. This
  is not a test of SQL execution on SQL Server 2022.
- API tests: real shared JWT validation/policy with TestServer; missing, expired,
  wrong-signature/tampered token, ordinary user, global Admin without membership,
  inactive/no-edit membership, wrong Site/floor, immediate membership revocation,
  stale version, restore/history/search, invalid references and ownership injection.
- Relational rollback: injected failure on the second write preserves head version
  and history; racing writers preserve the winner and return 409. Production graph,
  QR and the stored-distance test route remain unchanged after draft save/restore.
- Image boundary tests: fake provider round trip/private headers, wrong MIME,
  width/height/pixel/byte limits, cross-floor asset rejection, path traversal blocked
  before provider read, unknown-length stream byte limit, SQL failure cleanup.
  A failure injected **after** a SQL commit retains referenced bytes and reports
  failure; an uncertain follow-up read likewise leaves reconciliation to an operator.
  These tests do not claim real PNG/JPEG decoding, disk/object storage or browser UI.
- API + test-project NuGet audit: no vulnerable packages reported by the current
  `https://api.nuget.org/v3/index.json` source; no security warnings suppressed.
- Diff whitespace check passed; new/untracked task text files also scanned because
  ordinary `git diff --check` alone does not include untracked files.
- Tracked-file SHA-256 comparison against the start-of-task snapshot changed only
  the five intended existing backend/test files listed below. Gradle, the three
  protected Windows files and all 45 Figma-reference files retain prior audit hashes.
- No Flutter files changed; Flutter analyze/tests/build were not rerun. No live API,
  camera, production SQL or operator membership test is claimed.

## Files (24 task paths)

Existing files modified:

1. `WayMark.Api/Program.cs` — DI registration only.
2. `WayMark.Api/Data/WayMarkDbContext.cs` — new DbSets/mapping registration.
3. `WayMark.Api/Data/WayMarkMigrations/WayMarkDbContextModelSnapshot.cs` — additive model.
4. `WayMark.Api.Tests/WayMark.Api.Tests.csproj` — isolated relational test provider.
5. `WayMark.Api.Tests/AdminAuthorizationTests.cs` — policy guard expects 9 protected
   actions (original 4 plus 5 draft actions), preserving all existing security tests.

New files:

6. `WayMark.Api/Models/MapDrafts.cs`.
7. `WayMark.Api/Data/MapDraftModel.cs`.
8. `WayMark.Api/Contracts/MapDraftDtos.cs`.
9. `WayMark.Api/Controllers/MapDraftsController.cs`.
10. `WayMark.Api/Services/MapDrafts/DraftAccess.cs`.
11. `WayMark.Api/Services/MapDrafts/MapDraftValidator.cs`.
12. `WayMark.Api/Services/MapDrafts/MapDraftService.cs`.
13. `WayMark.Api/Services/MapDrafts/MapImageStorage.cs`.
14. `WayMark.Api/Services/MapDrafts/BoundedImageStream.cs`.
15. `WayMark.Api/Services/MapDrafts/MapDraftExceptionFilter.cs`.
16. `WayMark.Api/Services/MapDrafts/MapDraftRegistration.cs`.
17. `WayMark.Api/Data/WayMarkMigrations/20261020094848_AddMapDraftFoundation.cs`.
18. `WayMark.Api/Data/WayMarkMigrations/20261020094848_AddMapDraftFoundation.Designer.cs`.
19. `WayMark.Api.Tests/MapDraftValidationTests.cs`.
20. `WayMark.Api.Tests/MapDraftApiTests.cs`.
21. `WayMark.Api.Tests/MapDraftImageBoundaryTests.cs`.
22. `WayMark.Api.Tests/MapDraftModelTests.cs`.
23. `WayMark.Api.Tests/MapDraftTestHost.cs`.
24. This report.

## GO / NO-GO and operator decisions

**GO for review of the backend draft foundation and preparation of the 7B-2B
adapter. NO-GO for live deployment / end-to-end server image Save/Load yet.**

Before using it against the actual database, obtain explicit approval to:

1. Review backup/live schema and the additive migration SQL, then schedule a
   separately authorized migration application. No database-update command or
   automatic startup migration was run here.
2. Provision the exact approved existing Identity user IDs with Site membership
   through trusted operator maintenance; grant no automatic Admin or membership.
   Global Admin alone remains insufficient. Test scope denial with controlled data.
3. Choose and implement a private managed/object storage provider and maintained
   image decoder with appropriate licensing, actual decoding, byte/pixel quotas,
   metadata removal, private reads, backup/retention and orphan reconciliation.
   Both application bytes and storage output must be bounded. The unavailable
   default cannot be replaced by the fake test provider in a real environment.
4. Approve the Flutter local-v2-to-server-v1 adapter, optimistic-conflict UI, and
   draft-only image preview. Do not replace published FloorPlanImageUrl or graph.

Remaining limits:

- New **draft** endpoints enforce Site isolation. Existing published map reads,
  WayMark Admin CRUD and routing retain their existing global authorization
  semantics; this is not a claim of whole-backend multi-tenant isolation. A broader
  hospital authorization audit is required before a multi-hospital deployment.
- There is no production Place search/destination API or publish workflow yet.
  Room labels and proposed corridors cannot prove real-space safety. All physical
  accessibility/walkability is Unknown; no wheelchair route is certified.
- Revision JSON is bounded (2 MiB, 2000 nodes/places, 10000 edges, 1000 transition
  proposals); search is in-memory within an authorized revision, not SQL full-text.
  History is paged but not automatically pruned; storage/site quotas, audit events,
  sustained-load/rate-limit testing and retention remain deployment work.
- Pinned cross-floor references need a coherent site manifest and fresh provenance
  validation during any future publication. No graph is promoted automatically.
- EF/provider tests are not live SQL Server execution or proof of physical routes.

No staging, commit, push, account grant, production SQL write, Publish or AI call
was performed in this phase. Existing Gradle/Figma changes remain in the workspace.
