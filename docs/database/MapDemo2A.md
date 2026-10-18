# Map read API and controlled demo seed (phase 2A)

No seed runs at API startup. `SeedDemoMap2A.sql` is a manual, single-batch SQL Server
script, separate from schema migrations. It has not been executed as part of this change.

## API contract

Every endpoint requires the existing JWT bearer authentication. Use
`Authorization: Bearer <accessToken>` from the existing login flow.

| GET path | Response |
| --- | --- |
| `/api/Maps/sites` | `SiteDto[]` with `id`, `name`, `code`, `address` |
| `/api/Maps/sites/{siteId}/buildings` | `BuildingDto[]` with `id`, `siteId`, `name`, `buildingCode` |
| `/api/Maps/buildings/{buildingId}/floors` | `FloorDto[]` with `id`, `buildingId`, `name`, `floorCode`, `sortOrder`, `floorPlanImageUrl` |
| `/api/Maps/floors/{floorId}/graph` | `{floor, nodes, edges}` |
| `/api/WayMarks/code/{code}/map-location` | `{id, name, location, wayMarkCode, node}`; `node` is nullable |

Missing Site/Building/Floor/WayMark returns 404 ProblemDetails. An existing parent
with no children returns 200 with an empty list; an empty floor returns empty
`nodes` and `edges`. Unauthenticated/invalid/expired tokens return 401 via JWT middleware.
Existing WayMark paths and their response shapes are preserved.

Graph nodes contain `id`, `floorId`, `nodeCode`, `name`, `x`, `y`, `nodeType`.
Edges contain `id`, `fromNodeId`, `toNodeId`, `edgeType`, `distanceMeters`,
`isActive`, `isAccessible`. Enum names are strings, for example `Entrance`,
`Elevator`, `Corridor`. Both edge endpoints must belong to the requested floor.
Inactive edges remain visible with `isActive: false`; this API returns map data,
not a traversable route. Reads use DTO projections and `AsNoTracking`.

Illustrative graph response (IDs below are examples, never seed assumptions):

```json
{
  "floor": {
    "id": 100, "buildingId": 10, "name": "Demo Ground Floor",
    "floorCode": "G", "sortOrder": 0, "floorPlanImageUrl": null
  },
  "nodes": [
    { "id": 1, "floorId": 100, "nodeCode": "WM-DEMO-2A-G-ENTRY",
      "name": "Demo entrance", "x": 0.1, "y": 0.8, "nodeType": "Entrance" },
    { "id": 2, "floorId": 100, "nodeCode": "WM-DEMO-2A-G-JUNCTION",
      "name": "Ground corridor", "x": 0.4, "y": 0.8, "nodeType": "Junction" }
  ],
  "edges": [
    { "id": 1, "fromNodeId": 1, "toNodeId": 2, "edgeType": "Corridor",
      "distanceMeters": 10, "isActive": true, "isAccessible": true }
  ]
}
```

Illustrative WayMark response:

```json
{
  "id": 50, "name": "Demo start", "location": "Demo Building / Ground Floor",
  "wayMarkCode": "WM-DEMO-2A-START",
  "node": { "id": 1, "floorId": 100, "nodeCode": "WM-DEMO-2A-G-ENTRY",
    "name": "Demo entrance", "x": 0.1, "y": 0.8, "nodeType": "Entrance" }
}
```

## Manual SQL Server steps

1. Verify the instance and select **WayMarkDatabase** in SSMS. Review the seed
   script and take the backup required by your deployment process before writes.
   Use a session without an open transaction and with `IMPLICIT_TRANSACTIONS OFF`.
   The seed checks `@@TRANCOUNT` first and the implicit-transactions option next,
   before changing session options or entering its transaction/cleanup block.
   It rejects either unsafe state using `RAISERROR` and `RETURN`; it neither
   commits nor rolls back a caller transaction, even with caller `XACT_ABORT ON`.
   It never changes `IMPLICIT_TRANSACTIONS` for you. Do not wrap the seed in
   another transaction or run only a selected portion of the file.
2. Confirm the schema migration is already applied using a read-only query:

   ```sql
   SELECT DB_NAME() AS CurrentDatabase;
   SELECT MigrationId, ProductVersion FROM dbo.__EFMigrationsHistory
   WHERE MigrationId = N'20261018053754_AddNavigationSchema';
   ```

3. Review any existing `WM-DEMO-2A` namespace data. The seed refuses conflicting
   rows instead of changing them. It does not modify existing WayMarks, including
   those with null node links; a conflicting demo WayMark requires manual review.
4. If approved, open `docs/database/SeedDemoMap2A.sql` and execute the **entire
   script** in one SSMS batch. It checks DB_NAME and migration history, uses
   `XACT_ABORT`, its own transaction, an application lock and range locks, and
   rolls back its own active transaction on catchable pre-commit errors.
   `XACT_ABORT` is restored to its previous setting on normal success or caught
   transaction failure. All persistent writes are conditional INSERTs into map/WayMark
   tables; Identity, JWT and migration history are never changed.
5. The success message explicitly says the seed data was **COMMITTED**. Record
   the IDs returned by the read-only reporting queries that follow it.
   Site/Building/Floor/Node IDs are resolved by code, never hard-coded.
   Use those IDs in API URLs. Reporting has a separate TRY/CATCH: a catchable
   reporting error produces an informational warning saying data was already
   committed, with no rollback or rethrow as a seed failure. Such a warning is
   not proof that the inserted data was rolled back.
6. For an approved repeat-run check, run the same seed again and compare counts
   below: they should remain unchanged. Existing mismatched/duplicate demo edges
   cause rollback; the seed does not repair or overwrite them.

Expected demo rows:

| Data | Count |
| --- | ---: |
| Site `WM-DEMO-2A` | 1 |
| Building `WM-DEMO-2A-B` under that Site | 1 |
| Floors `G`, `L1` under that Building | 2 |
| Nodes with `WM-DEMO-2A-` prefix | 7 |
| Directed edges between those nodes | 10 |
| WayMarks `WM-DEMO-2A-START`, `WM-DEMO-2A-DEST` | 2 |

Ground floor has four nodes (including the isolated point) and four directed
in-floor edges. Level 1 has three nodes and four directed in-floor edges.
Two elevator edges connect the floors and are intentionally absent from either
floor graph response. The sample path consists of segments of 10 + 8 + 4 + 12 + 6
meters, each with a reverse edge. All sample edges are active/accessibility-marked
deliberately; this does not implement a wheelchair routing profile. Coordinates
are illustrative, not surveyed. There is no real floor-plan image.

The demo WayMarks are created with their node links. Existing real QR codes are
not reassigned. After seed, call the map-location endpoint for
`WM-DEMO-2A-START` to inspect its link. Floor graphs alone cannot reconstruct
inter-floor routing; that belongs to a later stage.

## Automated checks and limitations

```powershell
dotnet build WayMark.Api/WayMark.Api.csproj
dotnet test WayMark.Api.Tests/WayMark.Api.Tests.csproj
```

Controller/query tests use EF InMemory, and HTTP tests use ASP.NET TestServer
with generated test-only JWT keys. They check hierarchy filtering, empty/missing
resources, both-endpoint floor filtering, DTO serialization, no tracking,
existing WayMark lookup and JWT 401/200/404 behavior.
They do not execute SQL Server SQL, validate SQL Server collation/locking, or
prove seed repeatability against a live database. The seed was reviewed for
conditional insertion/conflict checks but must be verified manually in an
approved development database before broader use.

## Transaction review (static, no SQL executed)

| Situation | Expected control flow |
| --- | --- |
| No open transaction, implicit transactions OFF, correct DB | Starts its own transaction, owns cleanup, commits once on successful seed |
| Caller transaction already open | First guard raises an error and exits before any SET/BEGIN/COMMIT/ROLLBACK in the seed; caller transaction remains caller-owned |
| IMPLICIT_TRANSACTIONS ON without an open transaction | Second guard raises an error and exits without changing the option or starting a transaction |
| Catchable error during seed | Rolls back only if the seed owns a transaction and XACT_STATE is nonzero; restores XACT_ABORT and rethrows the original error |
| SQL Server already auto-rolled back a runtime failure | XACT_STATE is zero; skips redundant rollback and rethrows |
| Catchable error in reporting after successful commit | Separate informational warning explicitly says COMMITTED; no rollback or seed-failure rethrow |
| Repeat run with unchanged matching demo data | Existing conditional INSERTs skip the rows; conflict checks and application lock remain unchanged |

These are static conclusions, not SQL Server execution results. Same-scope
compile errors and statement-recompilation/name-resolution errors may bypass
TRY/CATCH; compile errors are not governed by XACT_ABORT. Connection loss, client
cancellation or fatal errors can also prevent cleanup code or the success
message from running. The script cannot guarantee cleanup/option restoration
for every SQL Server or client failure. After an interrupted/uncertain run,
verify session/transaction state and persisted demo data before retrying; absence
of the success message does not prove COMMIT never happened.
