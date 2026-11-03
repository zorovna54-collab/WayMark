# Phase 7B-2B — private managed images and server drafts

Date: 2026-10-20. Branch: `auth-jwt-assignment`. No SQL Server changes or Git commit/push.

## Foundation review and changes

Reviewed the 24-path 7B-2A foundation and its report, entities, DTOs, validator,
service, authorization, tests and migration. Room/Place/entrance distinctions,
normalized coordinates, Unknown accessibility and the published graph are intact.
JWT + AdminOnly + active CanEditDrafts membership is still required for every
draft/image operation. Scope comes from Floor → Building → Site in SQL, not headers.

Two gaps required fixes:

1. An upload previously needed only an authorized floor, so image metadata could
   exist without a draft. Upload now requires the floor's existing draft. A new
   FK from image FloorId to the draft's unique FloorId enforces ownership in SQL.
2. The foundation had no durable file reconciliation/quota mechanism. Private
   manifests, staged writes, shared filesystem leases, integrity checks and bounded
   quotas now cover it. Saving/restoring a revision also verifies its image bytes;
   a missing/corrupt image cannot advance the draft.

No critical issue requiring changes to authentication, QR, Dijkstra, production
graph or Flutter was found. Global published-map authorization semantics remain
unchanged; Site isolation here applies to draft resources.

## Provider and codec

`ManagedFileMapImageStorage` implements `IMapImageStorage`. DI selects it; it is
**disabled by default** until MapImages.Enabled and a safe RootPath are configured.
No root is created on API startup. There is no static-file middleware or public URL.

Added exactly two direct packages, both stable **4.153.1**:

- [SkiaSharp](https://www.nuget.org/packages/SkiaSharp/4.153.1), MIT license.
- [SkiaSharp.NativeAssets.Linux.NoDependencies](https://www.nuget.org/packages/SkiaSharp.NativeAssets.Linux.NoDependencies/4.153.1).

Existing .NET/EF/JWT/MailKit/Pkcs versions were not upgraded. Windows native codec
and actual temporary filesystem are exercised by tests. Linux native assets are
included, but Linux execution is not claimed. Keep native codec security updates
under review; an empty NuGet audit is not proof against unknown native CVEs.

`MapImageCodec` checks signature + exact MIME, creates SKCodec, checks declared
encoded dimensions before pixel allocation, then requires **full pixel decode
success** and re-encodes a new PNG/JPEG. It does not accept IncompleteInput as
success ([codec result contract](https://github.com/mono/SkiaSharp-API-docs/blob/main/SkiaSharpAPI/SkiaSharp/SKCodec.xml)).
The normalized file, not the upload's original bytes, determines checksum/size.
Source EXIF/comments/trailing payloads are not copied into the new image.

Limits: 10 MiB input and normalized output; at most 8192 pixels per side and
32,000,000 total pixels; one decoder allocation at a time per application instance.
PNG must end with its complete IEND; JPEG must end with EOI. Animated/multiframe
and non-top-left EXIF orientation are rejected. Normalize/rotate such images in a
trusted editor first; this phase does not silently rotate graph coordinate systems.

## Storage boundary and security

Root must be an explicit absolute local directory, outside the application content
root, wwwroot and any Git checkout (including a checkout with a `.git` file).
Volume roots, relative/UNC paths and symbolic-link/reparse-point components are
rejected. Object keys must be canonical server-generated GUIDs, never client paths.
Root and child paths are rechecked at operations. CreateNew/immutable destination
moves prevent overwrite. Local OS administrators or an attacker with write access
to the storage directory remain outside this application boundary: secure ACLs
are mandatory; portable path checks do not eliminate privileged local TOCTOU races.

```text
<private root>/
  objects/<guid-N>.bin       normalized immutable image
  objects/<guid-N>.json      bounded durable manifest, no original filename/user data
  staging/<guid>.upload     this invocation's incomplete temporary output
  staging/<guid>.manifest   temporary manifest replacement
  leases/floor-<id>.lock     shared per-floor upload/quota lease
  leases/storage.lock       shared storage commit/quota lease
```

Never expose these paths through ASP.NET static files, reverse proxy aliases,
Git, Flutter assets or user-controlled URLs. On Windows grant the API service
account and designated backup operator only the required access. Unix private
child directories use user-only permissions. Do not place multiple unrelated
databases in the same root. Local filesystem locking is the MVP assumption;
network shares/HA/object storage require an adapter with equivalent coordination.

## API contract

Prefix: `/api/admin/floors/{floorId}/map-drafts`.

| Method / suffix | Contract |
| --- | --- |
| POST (base) | Create initial draft, normally without image; returns ID and Version 1. |
| POST /images | Raw body, Content-Type `image/png` or `image/jpeg`. Optional `X-Image-File-Name` must have matching png/jpg/jpeg extension and contain no path. Filename is never stored or used as a key. Returns 201 with metadata. Existing draft required. |
| GET /images?page=1&take=50 | Private bounded metadata list (take 1–100); supports recovery when an upload response was lost/ambiguous. No StorageKey/path disclosed. |
| GET /images/{assetId} | Checks membership, same floor and database + manifest/file checksum, then streams the image. |
| PUT /{draftId} | `{expectedVersion, content:{...,imageAssetId}}`; verifies file integrity and appends a revision. |
| POST /{draftId}/restore | `{expectedVersion,sourceVersion}`; verifies old image and creates a new revision. |

Image response JSON:

```json
{
  "id": "<server-guid>",
  "floorId": 10,
  "mimeType": "image/png",
  "width": 900,
  "height": 598,
  "byteLength": 12345,
  "sha256": "<64-lowercase-hex-characters>"
}
```

Values above illustrate the shape; they are not a claim about a live uploaded map.
Downloads set exact image MIME, `Cache-Control: no-store`,
`X-Content-Type-Options: nosniff` and `Content-Security-Policy: default-src 'none'; sandbox`.
No Base64 image column, physical path, source filename, static link or credentials
are returned. Ordinary users, global Admins without membership and other-Site
Admins are denied. A Site-B caller cannot read a Site-A image by changing FloorId.

Status: 400 malformed image/extension/type/reference; 401 invalid/missing JWT;
403 role/Site denial; 404 missing owned draft/asset; 409 stale revision, quota or
immutable-key conflict; 413 oversized image/document; 503 disabled/misconfigured
storage, I/O error, integrity failure or ambiguous storage outcome. Exceptions and
paths are hidden. A 503 is not a guarantee that SQL did not commit: reload the
authorized metadata list before blindly retrying an upload.

## File / SQL consistency and retention

Filesystem and SQL are **not** a distributed atomic transaction. The protocol is:

1. Authorize Site; require draft; hold a cross-instance floor upload lease.
2. Check floor image count/bytes. Bound stream reads even without Content-Length.
3. Decode/re-encode; compute normalized SHA-256. Check floor remaining budget before
   final file creation. Under the storage lease, enforce root quotas.
4. Write/fsync a unique temporary file. Durably write PendingMetadata manifest
   **before** moving the normalized file to its immutable opaque final name.
5. Insert SQL metadata with the draft ownership FK. If SQL is known to have rolled
   back, mark the manifest NeedsReconciliation. Never physically purge the object.
6. If SQL committed, mark MetadataCommitted. If result/marker confirmation is
   uncertain, keep the bytes and manifest. A later authorized list/download and
   operator reconciliation can establish the outcome after restart.

Repeated stores of the same server key + normalized content and repeated marker
confirmation are idempotent; different content cannot overwrite that key.
Each new HTTP upload still allocates a new asset ID; this is not a claim of HTTP
Idempotency-Key support. Per-floor quotas prevent unlimited retry accumulation.

Only the current invocation's incomplete staging files are removed automatically
on a normal failure. Process-crash leftovers are inventoried, not deleted on startup.
`InspectAsync` lists pending/committed/reconciliation objects, invalid or missing
manifests and leftover temporary files. This is an operator-only source capability,
not a cross-Site HTTP inventory. Its inspection may create coordination directories/
lock files; it does not delete stable asset data or write SQL.

Legacy `DeleteUnreferencedAsync` now **flags** real managed objects; it does not
physically delete them. Images referenced by old revisions survive replacement,
restore and marking. There is no HTTP delete/purge endpoint, retention timer or
automatic revision pruning. Root quota counts retained files and metadata; reaching
capacity deliberately blocks new writes until an approved retention/capacity review.

Default configured limits:

| Setting | Default |
| --- | --- |
| MapImages:MaxStorageBytes | 1 GiB including retained data/metadata and staging |
| MapImages:MaxObjects | 5000 durable manifest entries |
| MapDraftLimits:MaxImagesPerFloor | 100 |
| MapDraftLimits:MaxImageBytesPerFloor | 250 MiB |
| MapDraftLimits:MaxRevisionsPerFloor | 500 |

Revision 501 is rejected with 409; no old revision is removed to make space.
Cross-instance image quota checks require all writers to share this managed root
and its floor lease. A future object-storage adapter must implement equivalent
coordination and bounded/seekable verified reads without changing HTTP contracts.

## Development configuration (instructions only; not applied)

Set per-process environment variables outside Git. Example for the operator's
existing PowerShell terminal; no JWT/connection-string value is included:

```powershell
$env:MapImages__Enabled = 'true'
$env:MapImages__RootPath = Join-Path $env:LOCALAPPDATA 'WayMark\DraftImages\development'
$env:MapImages__MaxStorageBytes = '1073741824'
$env:MapImages__MaxObjects = '5000'
$env:MapDraftLimits__MaxImagesPerFloor = '100'
$env:MapDraftLimits__MaxImageBytesPerFloor = '262144000'
$env:MapDraftLimits__MaxRevisionsPerFloor = '500'
# Only after separate schema/membership approval and setup:
dotnet run --project WayMark.Api/WayMark.Api.csproj
```

Verify the chosen root is private, local, writable by the API account and outside
the repo/application/wwwroot. Do not change an established root casually: changing
it without restoring the objects makes existing metadata unavailable. Keep the
root persistent across backend restarts. Existing User Secrets/JWT/database config
is reused without modification. Default remains disabled when no operator config
is supplied. No actual development root was created outside test fixtures here.

## Controlled Site membership bootstrap (not executed)

1. Approve a maintenance request identifying **Site ID and existing Identity user
   ID**, operator and permitted scope. Do not infer identity from username `admin`.
2. Check the actual target DB/schema and backup before any separately approved write.
   Resolve that exact existing user with trusted UserManager, verify it already has
   the server-managed Admin role, and verify the Site. If not, stop: this task does
   not authorize an Admin grant or account creation.
3. In a separately authorized operator operation, create/update only that approved
   SiteMapMembership with IsActive/CanEditDrafts as approved. Enforce the unique
   (SiteId,UserId), record operator/audit evidence, and never accept role/Site grants
   from a login payload, Flutter, username or arbitrary JWT claim.
4. Obtain a fresh login JWT if necessary. Verify approved Site access, other-Site
   403 and ordinary-user 403 on controlled resources. Revoke membership to verify
   denial on the next request; no token refresh should be required for Site denial.

No bootstrap endpoint, startup seed, privilege grant or production SQL script
executes as part of this source. UserId remains a logical cross-context Identity
reference; trusted maintenance must reject nonexistent/deleted user IDs.

## Migration review — not applied

Preserved `20261020094848_AddMapDraftFoundation` unchanged. New source migration:
**20261020101304_BindMapImagesToDrafts**.

- Up: add `AK_FloorMapDrafts_FloorId` and Restrict FK from image FloorId to draft
  FloorId. No data modification or published/Identity table change.
- Down: remove only that FK and alternate key; not executed.
- Generated with the workspace-local EF 10.0.12 tool via `migrations add
  BindMapImagesToDrafts --context WayMarkDbContext --project WayMark.Api/WayMark.Api.csproj
  --startup-project WayMark.Api/WayMark.Api.csproj --output-dir Data/WayMarkMigrations`.
- Model/snapshot and in-memory SQL generation tests cover both migrations. No SQL
  Server connection, database-update, migration application or seed was run.

Before approval, independently verify real migration histories and backups. If
7B-2A is still pending as reported, review/apply both in order in a separate task.
If it was applied meanwhile and orphan image metadata exists, STOP and reconcile
ownership explicitly; the FK intentionally fails instead of deleting/fixing rows.

## Backup / restore procedure (operator plan, not performed)

1. Schedule a maintenance window; stop draft writers/API so no filesystem leases
   or in-flight SQL/image operations remain. Do not copy only the current revision.
2. Take a verified full SQL Server backup of the correct WayMarkDatabase with its
   graph, draft, image metadata, histories and Identity data. Protect access and
   encryption appropriately; this is not a public artifact.
3. Back up the matching private root `objects` directory including **all .bin and
   .json files**, old-revision images and pending/reconciliation objects. Preserve
   staging for forensic reconciliation if needed; lock files are not data. Record
   the backup pair, migration IDs, counts and checksum inventory in private operator
   records. Do not store backups/images/credentials in this Git repository.
4. Test restoring the pair in an isolated environment with storage initially
   disabled. Restore the DB and objects together; restore ACLs/configured root.
   Compare every SQL asset's ID/size/SHA against its object/manifest and every
   revision image reference. Missing/corrupt files must be restored from backup,
   not silently removed from SQL or replaced by unrelated images.
5. Reconcile pending records by SQL existence and revision references. Keep anything
   referenced, committed or uncertain. Require explicit retention/backup approval
   before a separate physical cleanup operation; none is provided automatically.
6. Enable only after authorized download/history/restore and Site isolation checks
   pass. Document the real restore test; SQL generation/temporary tests here are
   not a claim that a live backup or SQL Server restore was verified.

## Verification actually run

```powershell
dotnet build WayMark.Api/WayMark.Api.csproj --artifacts-path waymark/.dart_tool/phase7b2b/dotnet
dotnet test WayMark.Api.Tests/WayMark.Api.Tests.csproj --artifacts-path waymark/.dart_tool/phase7b2b/dotnet --logger "trx;LogFileName=managed-verified.trx" --results-directory waymark/.dart_tool/phase7b2b/results
dotnet list WayMark.Api/WayMark.Api.csproj package --vulnerable --include-transitive
dotnet list WayMark.Api.Tests/WayMark.Api.Tests.csproj package --vulnerable --include-transitive
git diff --check
git status --short
```

| Check | Actual result |
| --- | --- |
| Backend build | Passed, 0 warnings/errors |
| Backend suite | **212/212 passed**, no skipped tests; prior 175 retained, 37 new cases |
| NuGet API + test project audit | No vulnerable packages reported by current NuGet.org source; no warning suppression |
| SQL Server-provider model tests | Snapshot matches current model; forward SQL for both pending migrations generated in memory only |
| Whitespace / credential literal scan | No findings in this phase's 22 modified/new text paths, including untracked files |
| Git diff check / status | Checked; nothing staged or committed |

**Real codec/filesystem evidence:** `ManagedImageStorageTests` and
`ManagedImageTestStorage` use SkiaSharp to create actual PNG/JPEG image bytes,
full native decoding/re-encoding and real managed .bin/.json files in owned temporary
directories outside the repo. Tests verify dimensions, four-corner pixel content,
normalized SHA-256, MIME, private download, source-comment removal, malformed/
truncated/mismatched/oversized inputs, real filesystem I/O failure, scope denial,
history/restore, version 409, quotas, shared instance leases, immutable retries,
missing/corrupt files/manifests, interrupted metadata status and production route
preservation. The restart test disposes/recreates HTTP host, storage adapter and
SQLite connection using an isolated persistent SQLite file; data is loaded from
disk again. It is not a forced OS crash or power-loss durability test.

**Fake evidence kept separate:** existing `MapDraftImageBoundaryTests` still use
an intentionally fake image provider to inject interface/SQL errors. They are not
evidence of real image decoding. Existing authorization/route tests retain their
isolated in-memory/TestServer setup. No camera/Flutter, production image, live API,
SQL Server migration/backup/restore, Linux host or actual membership bootstrap was
tested or changed in this phase.

## Changed files relative to the uncommitted 7B-2A baseline (22)

New:

1. `WayMark.Api/Services/MapDrafts/ManagedFileMapImageStorage.cs`.
2. `WayMark.Api/Services/MapDrafts/ManagedMapImageOptions.cs`.
3. `WayMark.Api/Services/MapDrafts/ManagedStoragePaths.cs`.
4. `WayMark.Api/Services/MapDrafts/MapImageCodec.cs`.
5. `WayMark.Api/Data/WayMarkMigrations/20261020101304_BindMapImagesToDrafts.cs`.
6. `WayMark.Api/Data/WayMarkMigrations/20261020101304_BindMapImagesToDrafts.Designer.cs`.
7. `WayMark.Api.Tests/ManagedImageTestStorage.cs`.
8. `WayMark.Api.Tests/ManagedImageStorageTests.cs`.
9. This report.

Modified:

10. `WayMark.Api/Services/MapDrafts/MapImageStorage.cs` — coordination/confirmation
    contract and seekable private reads; test adapters remain compatible.
11. `WayMark.Api/Services/MapDrafts/MapDraftService.cs` — ownership, quotas, list,
    integrity and consistency protocol.
12. `WayMark.Api/Services/MapDrafts/MapDraftRegistration.cs` — opt-in managed DI/options.
13. `WayMark.Api/Controllers/MapDraftsController.cs` — optional filename header and
    private metadata list; existing draft contracts retained.
14. `WayMark.Api/Data/MapDraftModel.cs` — draft ownership FK/alternate key only.
15. `WayMark.Api/Data/WayMarkMigrations/WayMarkDbContextModelSnapshot.cs`.
16. `WayMark.Api/Program.cs` — pass configuration to draft registration.
17. `WayMark.Api/WayMark.Api.csproj` — two codec/native package references.
18. `WayMark.Api.Tests/MapDraftTestHost.cs` — optional persistent test SQLite/options.
19. `WayMark.Api.Tests/MapDraftApiTests.cs` — respect required draft ownership.
20. `WayMark.Api.Tests/MapDraftImageBoundaryTests.cs` — fake fixture creates owner draft.
21. `WayMark.Api.Tests/MapDraftModelTests.cs` — new migration SQL assertions.
22. `docs/development/MapPersistence7B2A.md` — historical report follow-up link.

All other initial tracked/untracked file hashes match the phase-start snapshot,
including the original 7B-2A migration/designer, Auth/JWT/configuration, production
routing/graph, Flutter, Gradle, Windows generated files and all 45 Figma references.
All previous uncommitted work is preserved. Logs/build/test artifacts are ignored.

## Decision and prerequisites for 7B-2C

**GO for 7B-2C Flutter integration against the reviewed backend contract in an
isolated or separately approved development environment. NOT production approval.**

Before real SQL-backed use, the operator must explicitly approve and perform:

1. Verify actual SQL instance/database, full backup and migration histories; review
   both pending migrations and confirm there are no orphan assets before the new FK.
2. Apply the reviewed migration chain in a separately authorized task; nothing here
   automatically migrates at startup.
3. Provision approved existing Admin-user Site memberships using controlled
   maintenance, never automatic login/bootstrap grants.
4. Configure and protect a persistent private root and quotas; verify native codec
   availability on the deployment OS; document a paired database+image restore test.
5. Approve retention before any stable-file/revision purge. Until then retained
   unreferenced objects remain inventoried and count against capacity.

7B-2C must preserve local JSON v2, adapt to server draft v1 GUID identities, create
the owning draft before upload, use JWT-protected byte fetches, handle version 409
and uncertain-upload recovery via the scoped image list, and never replace the
published image URL/graph or claim an unreviewed draft is safe for navigation.

No Flutter/UI, JWT secret, connection string, Site/Admin grant, SQL Server data,
publish feature, LM Studio call, commit or push was changed/performed here.
