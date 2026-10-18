# Routing MVP (phase 3A)

`POST /api/routes` requires the existing JWT bearer token. The request body has
only `startWayMarkCode` and `destinationWayMarkCode`: required non-whitespace
strings, maximum 100 characters each. Leading/trailing whitespace is trimmed.
Codes are resolved using SQL Server's configured collation, not client-side
case conversion. No IDs are assumed from the demo data.

```json
{
  "startWayMarkCode": "WM-DEMO-2A-START",
  "destinationWayMarkCode": "WM-DEMO-2A-DEST"
}
```

## Algorithm and data loading

- `RoutePlanner` uses EF Core `AsNoTracking` to read WayMarks, nodes with floor
  metadata, and active edges. It loads the graph across all floors, including
  explicitly configured inter-floor/inter-building connections.
- `DijkstraRouter` has no EF, coordinate or floor dependency. It consumes node
  IDs and directed weighted edges, using `decimal` distances and a priority queue.
  It never creates a reverse edge. Inactive edges are excluded defensively too.
- Distances come only from stored `DistanceMeters`; X/Y are not physical meters.
  Invalid eligible weights/endpoints and arithmetic overflow produce an invalid
  graph result instead of a fabricated path. Positive weights, settled nodes,
  stale-entry checks and bounded reconstruction prevent cyclic traversal.
- Node/edge IDs give deterministic tie handling; any equal-distance shortest
  route is valid. Parallel edges retain their actual selected edge IDs.
- Same existing node returns one node, no edges and distance zero. Missing
  endpoints are checked first; a nonexistent node is never accepted as a zero path.

`accessibleOnly` is an optional **query** flag, default `false`, keeping the MVP
body at two fields. `POST /api/routes?accessibleOnly=true` accepts only active
edges with `IsAccessible = true`. Without this explicit request, accessibility
does not affect the shortest-distance objective. The flag is a map author's
explicit accessibility marking, not a complete wheelchair assessment: it has
no width/slope/lift availability/user-specific suitability guarantees. The
server does not automatically exclude stairs or infer accessibility from type.

## Response

The ordered `nodes` array includes node identity, name/type and `FloorDto`
(including BuildingId). The ordered `edges` array includes a 1-based sequence,
edge identity/type/distance/accessibility, FromNodeId/ToNodeId and both floor IDs.
`Movement` is `SameFloor` or `ChangeFloor`: direction is explicitly the ordered
from-to pair. It is not a compass bearing, left/right turn, or an up/down claim
derived from Floor.SortOrder. No GPS, live progress or travel time is inferred.

Illustrative demo response below: **IDs are examples**, not expected database
IDs. With the unchanged seed, the expected path distance is 40 meters.

```json
{
  "start": { "id": 501, "name": "Demo start", "location": "Demo Building / Ground Floor", "wayMarkCode": "WM-DEMO-2A-START" },
  "destination": { "id": 502, "name": "Demo destination", "location": "Demo Building / Level 1", "wayMarkCode": "WM-DEMO-2A-DEST" },
  "totalDistanceMeters": 40,
  "accessibleOnly": false,
  "nodes": [
    { "id": 101, "nodeCode": "WM-DEMO-2A-G-ENTRY", "name": "Demo entrance", "nodeType": "Entrance", "floor": { "id": 10, "buildingId": 1, "name": "Demo Ground Floor", "floorCode": "G", "sortOrder": 0, "floorPlanImageUrl": null } },
    { "id": 102, "nodeCode": "WM-DEMO-2A-G-JUNCTION", "name": "Ground corridor", "nodeType": "Junction", "floor": { "id": 10, "buildingId": 1, "name": "Demo Ground Floor", "floorCode": "G", "sortOrder": 0, "floorPlanImageUrl": null } },
    { "id": 103, "nodeCode": "WM-DEMO-2A-G-LIFT", "name": "Ground elevator", "nodeType": "Elevator", "floor": { "id": 10, "buildingId": 1, "name": "Demo Ground Floor", "floorCode": "G", "sortOrder": 0, "floorPlanImageUrl": null } },
    { "id": 104, "nodeCode": "WM-DEMO-2A-L1-LIFT", "name": "Level 1 elevator", "nodeType": "Elevator", "floor": { "id": 20, "buildingId": 1, "name": "Demo Level 1", "floorCode": "L1", "sortOrder": 1, "floorPlanImageUrl": null } },
    { "id": 105, "nodeCode": "WM-DEMO-2A-L1-JUNCTION", "name": "Level 1 corridor", "nodeType": "Junction", "floor": { "id": 20, "buildingId": 1, "name": "Demo Level 1", "floorCode": "L1", "sortOrder": 1, "floorPlanImageUrl": null } },
    { "id": 106, "nodeCode": "WM-DEMO-2A-L1-DEST", "name": "Demo destination", "nodeType": "Destination", "floor": { "id": 20, "buildingId": 1, "name": "Demo Level 1", "floorCode": "L1", "sortOrder": 1, "floorPlanImageUrl": null } }
  ],
  "edges": [
    { "sequence": 1, "id": 1, "fromNodeId": 101, "toNodeId": 102, "fromFloorId": 10, "toFloorId": 10, "edgeType": "Corridor", "distanceMeters": 10, "isAccessible": true, "movement": "SameFloor" },
    { "sequence": 2, "id": 2, "fromNodeId": 102, "toNodeId": 103, "fromFloorId": 10, "toFloorId": 10, "edgeType": "Corridor", "distanceMeters": 8, "isAccessible": true, "movement": "SameFloor" },
    { "sequence": 3, "id": 3, "fromNodeId": 103, "toNodeId": 104, "fromFloorId": 10, "toFloorId": 20, "edgeType": "Elevator", "distanceMeters": 4, "isAccessible": true, "movement": "ChangeFloor" },
    { "sequence": 4, "id": 4, "fromNodeId": 104, "toNodeId": 105, "fromFloorId": 20, "toFloorId": 20, "edgeType": "Corridor", "distanceMeters": 12, "isAccessible": true, "movement": "SameFloor" },
    { "sequence": 5, "id": 5, "fromNodeId": 105, "toNodeId": 106, "fromFloorId": 20, "toFloorId": 20, "edgeType": "Corridor", "distanceMeters": 6, "isAccessible": true, "movement": "SameFloor" }
  ]
}
```

## Status codes

| HTTP | Meaning / ProblemDetails `code` |
| --- | --- |
| 200 | Route found, including the zero-distance case |
| 400 | Invalid JSON/body, missing/whitespace/overlength codes or invalid query flag; ValidationProblemDetails |
| 401 | Missing/invalid/expired JWT |
| 404 | `start_waymark_not_found` or `destination_waymark_not_found` |
| 409 | `start_not_mapped`, `destination_not_mapped`, `start_node_not_found`, `destination_node_not_found` (missing linked node/floor) |
| 422 | `no_route`: no directed path under the selected filter |
| 500 | `invalid_graph` or `route_calculation_failed` |
| 503 | `route_data_unavailable` for database-provider exceptions |

Failure responses never include exception messages, SQL/connection details or
stack traces. Server-side logs retain diagnostic exceptions. Request cancellation
is propagated instead of being converted into a synthetic no-route result.

## Swagger verification (manual)

1. Restart/rebuild the API with the new source when you control its running
   terminal. An already-running process will not acquire the new endpoint merely
   because a separate validation build passed.
2. Open Swagger at the API's actual listening URL, log in through the existing
   Auth endpoint and authorize with the returned JWT (HTTP bearer scheme).
3. Execute `POST /api/routes` with the two demo codes above. Keep accessibleOnly
   false initially. Expect 200, distance 40, six ordered nodes and five edges,
   including one Elevator/ChangeFloor edge, if seed data is unchanged.
4. Repeat with accessibleOnly true. The unchanged demo edges are all marked
   accessible, so the expected demo path remains 40. This is a filter test, not a
   real-world accessibility guarantee.
5. Set destinationWayMarkCode equal to startWayMarkCode: expect 200/zero distance.
   Try an unknown code for 404; remove JWT for 401. No data writes are needed.

The isolated demo node has no WayMark in the existing seed; do not insert/reassign
one just to test this endpoint. No-path/isolation behavior is covered in isolated
tests. A live request using the isolated node would require an explicitly approved
WayMark mapping in a future task. No seed changes are part of this stage.

## Validation and limitations

Unit tests cover direction, differing route weights/edge counts, floor transitions,
inactive edges, isolated/missing nodes, empty graphs, same node, decimal sums,
parallel edges, cycles/stale priorities, accessibility, invalid weights and overflow.
HTTP integration tests use ASP.NET TestServer + EF InMemory with temporary JWT
keys and test-only data. They exercise validation, auth, status codes, floor-aware
response ordering and sanitized errors. Existing map tests remain part of the suite.
They do not verify production Program startup, SQL Server execution/collation,
or a live Swagger/SQL Server route request. No production database is contacted.

The MVP reloads the full graph per request without caching or pagination. Its
separate read queries do not provide a versioned snapshot during concurrent map
editing; use stable map data for now. Data publication/versioning and performance
work remain for a later stage. Only explicit edges permit inter-floor/site travel.
There are no opening hours, temporary elevator availability, turn-by-turn text,
user-specific accessibility profiles, GPS tracking or Flutter Navigation integration.

Example validation commands with isolated output, if a running API locks its EXE:

```powershell
dotnet build WayMark.Api/WayMark.Api.csproj --no-restore --output WayMark.Api/obj/Route3A-Validation -p:UseAppHost=false
dotnet test WayMark.Api.Tests/WayMark.Api.Tests.csproj --no-restore --output WayMark.Api/obj/Route3A-Validation -p:UseAppHost=false
```
