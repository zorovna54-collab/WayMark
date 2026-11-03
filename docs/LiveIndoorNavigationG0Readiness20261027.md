# WayMark Live Indoor Navigation — G0 Readiness Audit

Ngày audit: **27/10/2026 — Asia/Saigon**  
Workspace: D:/project/WayMark  
Phạm vi: **read-only source/environment audit**, ngoại lệ duy nhất là báo cáo Markdown này. Không triển khai Sprint 1.

Quy ước: **CONFIRMED** = thấy trực tiếp trong source/cấu hình/kết quả lệnh; **INFERRED** = đánh giá hoặc thiết kế đề xuất từ bằng chứng; **NOT VERIFIED** = chưa chạy/đo trong phiên này. CONFIRMED về source không đồng nghĩa chức năng đã chạy thành công trên thiết bị thật.

## A. Executive Summary

**Quyết định: CONDITIONAL GO cho Sprint 1 — Android Sensor Infrastructure. Chưa đủ bằng chứng để GO cho live indoor navigation hoặc công bố độ chính xác định vị.**

| Hạng mục | Kết luận | Nhãn |
|---|---|---|
| QR công khai → snapshot → chọn điểm đến → preview → navigation | Có luồng hoàn chỉnh trong source, dùng snapshot riêng và GUID node/tầng | CONFIRMED |
| Graph có hướng, khoảng cách mét, nhiều tầng | Có; mét nhập độc lập tọa độ ảnh; kết nối liên tầng là cạnh tường minh | CONFIRMED |
| Navigation hiện tại | Checklist theo node: nút xác nhận hoặc QR; không phải tracking vật lý | CONFIRMED |
| QR trong lúc navigation | Đã có capture → resolve lại → kiểm tra map/version → đối chiếu node/tầng; reroute cần xác nhận | CONFIRMED |
| Vị trí giữa cạnh, PDR, fusion, bước chân, heading sensor, blue dot live | Chưa có trong các module đã kiểm tra | CONFIRMED |
| Android native bridge | Có FlutterActivity/embedding v2 và hai MethodChannel; chưa có sensor channel | CONFIRMED |
| Thiết bị Android | adb devices -l trả danh sách rỗng | CONFIRMED |
| Khả năng đo bước/heading trên điện thoại | **NOT VERIFIED ON PHYSICAL DEVICE** | NOT VERIFIED |
| Baseline kiểm thử | Log có sẵn ghi 357 pass / 4 skip, analyze sạch, Android/Web build thành công; không chạy lại G0 | CONFIRMED về log cũ |
| Tài liệu Live Plan tùy chọn | docs/WayMark_Live_Indoor_Navigation_Plan.md không tồn tại; không tạo thay thế | CONFIRMED |

**Những việc đủ căn cứ làm ngay:** provider contract thuần Dart, capability probe native, runtime permission, luồng event có timestamp gốc, fake provider, quản lý start/stop/pause/resume và debug probe tách khỏi sản phẩm.

**Blocker trước Sprint 2/live tracking:**

1. Danh tính cạnh GUID bị mất khi chuyển sang graph/route dùng cho UI; cần adapter từ snapshot, không dùng RouteEdge.id phiên-local làm khóa lâu dài.
2. Chỉ có geometry hai đầu cạnh, không có đường đi cong/polyline hay ràng buộc tường. Route đúng về topology vẫn có thể vẽ đường xuyên phòng.
3. Không thấy north/map bearing hoặc phép hiệu chuẩn heading theo ảnh. “Cạnh có hướng” hiện tại là from→to, không phải azimuth đo được.
4. Chưa có chính sách xác định travel direction khi người dùng xoay điện thoại, đi lùi, cầm lệch hoặc bỏ túi. QR chỉ neo vị trí/tầng.
5. Chưa đo capability, latency, sai số bước, drift, pin trên Android thật. Không lấy kết quả emulator hay log build làm bằng chứng thay thế.

Các blocker 1–4 không chặn xây dựng hạ tầng cảm biến độc lập ở Sprint 1. Thiết bị thật là verification gate để nghiệm thu phần native, không phải điều kiện bắt buộc để bắt đầu viết contract/fake.

## B. Source Architecture Map

### B1. Cấu trúc và state thực tế

Flutter được tổ chức theo feature dưới waymark/lib/features: admin/Builder, scanner, search, route, navigation, home/history, auth/profile, ai. Model route nằm ở lib/models; HTTP, auth session, AI, draft/publication/history nằm ở lib/services; theme nằm ở lib/core.

State chính là StatefulWidget + setState; route stack dùng Navigator/MaterialPageRoute. Không thấy Provider/Riverpod/BLoC trong dependency hay các luồng khảo sát. AuthSession.changes và NavigationHistorySession.message dùng ValueNotifier. main.dart:14–17 khởi tạo MaterialApp → LoginPage; Visitor có PublicMapEntryPage và scanner công khai, không cần JWT cho public endpoints.

Backend có **hai họ graph khác nhau**, không được trộn ID:

- Legacy: NavigationNodes/NavigationEdges, ID SQL int, WayMarkCode → NavigationNodeId; routing qua API có xác thực.
- Draft/Published project: GUID project/floor/node/edge, JSON content, snapshot khóa bởi (MapId, Version), QR opaque token; Visitor tải snapshot và tính route trên điện thoại.
- WayMarkDbContext.cs:10–24,151–153 đăng ký cả hai họ và NavigationHistory; không phải một graph duy nhất đã tự đồng bộ.

| Thành phần, vị trí source | Trách nhiệm, input → output | Tái sử dụng / adapter | Rủi ro khi thêm tracking |
|---|---|---|---|
| lib/features/admin/draft_map.dart:11,71,94,411 | DraftNode/DraftEdge/DraftMap; thao tác node/cạnh → JSON và DraftRoute ngắn nhất theo mét | Dùng model snapshot làm dữ liệu nguồn; không dùng đối tượng Builder đang sửa cho tracking | Mutable; nodeCode/ID local không đồng nhất SQL |
| lib/features/admin/draft_map_editor.dart:58,1356,1680,2315 | _DraftMapEditorState, _edgeDialog, DraftMapPainter; normalized pointer → cập nhật draft; vẽ ảnh/graph | Tái dùng quy tắc tọa độ/canvas; không đưa tracking vào Builder | Một thao tác hai chiều tạo hai cạnh; không suy ngược hướng vật lý từ UI |
| lib/features/admin/local_map_project.dart:7,36,56,98,181 | LocalMapProject/LocalFloorLink; JSON v3 bọc các floor v2 + links → project đã check references | Tái dùng snapshot đầu vào, link GUID | Không có metric frame chung giữa tầng |
| lib/features/admin/draft_server_session.dart:12,236,295 | DraftServerMapper / DraftServerSession; draft ↔ server DTO, save/load revision | Tái dùng parser GUID/node/edge; giữ nguyên JSON | Không gọi mapper sinh ID để “sửa” snapshot trong phiên tracking |
| lib/features/admin/draft_files_native.dart:4,6,26 và draft_recovery.dart:9 | SAF pick/save + recovery app-private qua channel; bytes ↔ file | Dùng cho draft/recovery; không coi là cache positioning | Export/recovery là thao tác ghi; không chạy G0 |
| lib/services/published_map_api_service.dart:17,35,295,357,365 | publicQrToken, PublishedMapSession, project, resolve/loadQr; payload → map/version, ảnh, snapshot, startKey | Tái dùng làm QrLocalization adapter | Resolve cần mạng; không có offline revocation assurance |
| lib/features/navigation/local_map_navigation.dart:150,246,260,346,362 | LocalMapNavigation; project copy → graph/session IDs; chuyển stable identity ↔ route identity | Tái dùng routing/QR mapping; thêm read-only tracking graph adapter ở Sprint sau | Cạnh GUID bị bỏ khỏi _graphs; RouteEdge.id được gán lại theo index |
| lib/features/search/local_map_search_page.dart:61,139,205,249,286 | QR startKey + query → Room hoặc Node destination → RoutePreviewPage | Tái dùng nguyên luồng; start khóa khi initialStart có giá trị | Không thay start/destination bởi event sensor từng frame |
| lib/features/route/route_preview_page.dart:107,134 | _loadRoute/_startNavigation; target + start → WayMarkRoute → NavigationPage | Tái dùng route và callback reroute | Route replacement phải đổi revision tracking, không khởi động lại provider tùy tiện |
| lib/features/navigation/manual_navigation.dart:32,63,99,141,162 | ManualNavigation; route + manual/QR confirmation → nodeIndex/currentEdge/completed | Giữ làm fallback; cần lớp điều phối tracking riêng | Không gọi confirmNext sau mỗi bước chân; một edge không tương đương một bước |
| lib/features/navigation/navigation_page.dart:40,111,124,185,390,583 | Chủ phiên UI, history, scan lại, reroute, render node đang chọn | Vị trí phù hợp để sở hữu controller và hủy subscription ở Sprint sau | Chưa có app/route lifecycle sensor; dispose hiện chưa có tài nguyên sensor để dọn |
| lib/features/route/floor_route_map.dart:41,47,77,271,381 | FloorRouteMap/FloorRoutePainter; route + graph + indices → đường/markers theo tầng | Tái dùng nền route; cần hook overlay độc lập | Cache invalid khi route/api/localMap đổi; không tạo route mới cho từng event |
| lib/features/route/floor_route_geometry.dart:6,74 | normalizedMapPoint/FloorRouteGeometry.build; normalized nodes + route → stops/segments/transitions | Tái dùng phép chiếu; thêm edge interpolation adapter | Không chứa collision detection hoặc geometry corridor |
| lib/features/route/floor_plan_canvas.dart:36,135,152,228 | FloorPlanCanvas; ảnh + painter → scene contain + transform pan/zoom | BlueDotOverlay phải ở cùng scene bên trong InteractiveViewer | Sai padding/contain/transform nếu overlay đặt ở màn hình ngoài |
| lib/features/route/map_paint_scale.dart:5 | beginScreenSizedMapPaint; bù scale để nét/marker giữ cỡ màn hình | Tái dùng cho dot/halo | Không nhân zoom hai lần |
| lib/services/waymark_api_service.dart:176,197,222 | Legacy location, floor graph, route HTTP → typed models | Giữ legacy/fallback riêng | Không mang ID legacy vào snapshot Published |
| lib/services/navigation_history_service.dart:65,79,94 | Published lifecycle scan/select/start/finish → history cho tài khoản hợp lệ | Tái dùng history theo phiên, không theo từng bước | Guest không ghi history; sensor events không được tự phát HTTP history |

Các đường dẫn lib/... trong bảng có tiền tố **waymark/**.

### B2. Data flow Navigation thực tế

Luồng ưu tiên cho Live Navigation là Published, vì có snapshot và GUID:

~~~text
ScannerPage._handlePayload / PublicMapEntryPage._open
  → PublishedMapApiService.loadQr
  → GET /api/public/qr/{token}
  → mapId + version + floorKey + nodeId
  → GET /api/public/maps/{mapId}/versions/{version} + ảnh đúng version
  → project() → DraftServerMapper → LocalMapProject.decode
  → LocalMapNavigation.fromProject (encode/decode thành bản copy)
  → stableStartKey(floorKey, nodeId)
  → LocalMapSearchPage(initialStart khóa)
  → Room entrance hoặc searchable Node
  → RoutePreviewPage._loadRoute → routeToRoom / routeToNode
  → DraftMap.shortestRoute (directed, measured, active)
  → WayMarkRoute
  → NavigationPage / ManualNavigation
  → xác nhận manual hoặc QR → completed → Finish/history
~~~

Legacy là nhánh riêng: normalizeWayMarkQrCode → getMapLocation → GET WayMarks/code/.../map-location → SearchPage → POST /api/routes → RoutePlanner/DijkstraRouter → NavigationPage. RoutesController, MapsController, WayMarksController đều có Authorize. Không gọi nhánh này là public anonymous.

| Câu hỏi audit Navigation | Trả lời theo source |
|---|---|
| 1. Start node từ đâu? | Published: QR resolver trả stable GUID + floorKey, sau đó stableStartKey ánh xạ vào snapshot. Local thử nghiệm: có thể chọn start từ danh sách. Legacy: WayMark.NavigationNodeId qua map-location. |
| 2. Route biểu diễn ra sao? | WayMarkRoute: start/destination, nodes có thứ tự, edges có sequence, totalDistanceMeters/options. RouteNode không chứa x/y; lấy tọa độ từ FloorMapData. |
| 3. Có hướng và mét không? | Có fromNodeId→toNodeId, distanceMeters, floor IDs, Movement SameFloor/ChangeFloor. Không có heading/azimuth; hướng vẽ là vector giữa hai tọa độ. |
| 4. Có current Node/Edge không? | ManualNavigation._nodeIndex/currentNode/currentEdge; confirmations manual/qr và lastVerifiedNodeIndex. Không có progressMeters, pose, timestamp, confidence hoặc edge occupation liên tục. |
| 5. Biết đã đến node tiếp theo bằng gì? | confirmNext() khi bấm “Đã đến điểm tiếp theo”, hoặc acceptQr() sau kiểm tra; chưa có phép đo cảm biến/proximity. Arrival là checklist completion, không chứng nhận vị trí liên tục. |
| 6. Đi sai/reroute hiện tại? | Không tự phát hiện sai tuyến. Chỉ QR offRoute mới đề nghị tính lại; Published dùng rerouteFromLocation trên snapshot cũ; legacy gọi rerouteNavigation/API. Hủy/lỗi giữ tuyến và tiến độ. |
| 7. Chuyển tầng? | Cạnh fromFloor!=toFloor có Movement=ChangeFloor; UI chuyển active floor theo nodeIndex, có lựa chọn xem tầng. Không có barometer/floor detection. |
| 8. Normalized → màn hình? | normalizedMapPoint(x,y,scene)=Offset(x*W,y*H); ảnh và graph chung scene BoxFit.contain, Center; InteractiveViewer áp transform sau đó. Gốc trên-trái, y tăng xuống. |
| 9. Nhận stream mà không rebuild toàn màn hình? | Chưa có interface. Có thể thêm Listenable/CustomPainter(repaint:) riêng cho dot trong scene, giữ route/graph/image stable. Đây là INFERRED, cần adapter nhỏ ở canvas; không chỉ truyền stream vào constructor hiện tại là đủ. |
| 10. Version pin trong phiên? | Published: có, closure resolvePublishedQr giữ id/version và từ chối mismatch; map là copy tách khỏi editor. publication là field mutable nên pin là quy ước được loader đảm bảo, chưa là type bất biến tuyệt đối. Legacy: không có map version; floor graph tải lazy/cache theo int nên không có bảo đảm snapshot đồng bộ với route. |

**Integration point đề xuất, không triển khai G0:**

- NavigationPage sở hữu IndoorTrackingController theo phiên map/version; inject provider để test. ManualNavigation giữ độc lập làm fallback, không đổi semantics các xác nhận hiện tại.
- BlueDotOverlay nằm trong Stack của FloorPlanCanvas tại scene-size, sau layer route, trước/độc lập với control ngoài viewport. API canvas hiện chỉ có painter/painterBuilder, cần thêm hook layer tối thiểu ở Sprint sau.
- Controller không điều khiển camera. Khi mở scanner thì dừng tích phân PDR, vào relocalizing; sau resolve hợp lệ mới reset baseline. Route bị phủ bởi scanner không nhất thiết khiến app chuyển background: phải quản lý route visibility riêng.
- Giữ graph/ảnh/route object ổn định, repaint overlay theo position; chỉ cập nhật instruction node/floor khi có thay đổi ngữ nghĩa. Không gọi Dijkstra sau mỗi bước.

### B3. Graph, identity, coordinate — ưu tiên cao

| Thuộc tính | Bằng chứng và hệ quả |
|---|---|
| Tọa độ node | Normalized [0..1], không phải pixel/mét. Backend NavigationNode.cs:19–23; DbContext.cs:105–120; LocalMapValidation:61–67. Pixel ảnh chỉ dùng để xác định aspect ratio scene. |
| Stable node | DraftMap.nodeIds map code→GUID; server DraftNodeDto.Id GUID. LocalMapNavigation gán lại int node ID tuần tự chỉ trong session; stableIdentity/routeIdentity bridge GUID. |
| Stable edge | DraftMap.edgeIds map cặp from + NUL + to→GUID; DraftEdgeDto.Id và LocalFloorLink.id là GUID. updateEdge giữ GUID nếu đổi endpoint; không suy “cùng GUID” nghĩa geometry không đổi qua version. Legacy có SQL int ID. |
| Mất edge identity ở UI | MapGraphEdge không có trường id. LocalMapNavigation._graphs tạo cạnh chỉ endpoints/meters/type/active; _routeToTarget gán id=_routing.edges.indexOf(e)+1. GUID link cũng không đi vào RouteEdge. Cần tracking graph adapter giữ GUID gốc và version. |
| Một/hai chiều | Mỗi edge là một hướng from→to. Builder twoWay thêm cạnh đảo chiều, có GUID riêng. Dijkstra local/backend chỉ duyệt outgoing; không có implicit reverse. Directed pair trùng bị chặn trong DraftMap. |
| Khoảng cách | DraftEdge.meters + isMeasured; chưa đo serialize distanceMeters=null. Publish yêu cầu tất cả cạnh có mét. Backend legacy decimal(12,3). Không tính mét từ khoảng cách normalized/pixel; tên “measured” không chứng minh đã khảo sát hiện trường. |
| Nhiều tầng | JSON local v3 = các floor v2 + links. GUID floorKey khác SQL FloorId và khác int floor ID theo index trong session. Không dùng floorCode/name làm identity. |
| Cầu thang/thang máy | LocalFloorLink/ProjectLinkDto fromFloor/fromNode→toFloor/toNode, type Stairs/Elevator, mét >0, active. Validate backend yêu cầu hai node đúng loại; không tự nối node chỉ vì tên giống nhau. Link cũng có hướng. |
| Geometry | DraftEdge/NavigationEdge/RouteEdge chỉ endpoints, không polyline. Place.Polygon là polygon Room để vẽ/label, không geometry cạnh hay mô hình tường walkable. |
| Vị trí giữa cạnh | Chưa có type hoặc hàm edgeId+progressMeters→x/y. Renderer chỉ vẽ đoạn thẳng nối node. |
| Hành lang cong/gấp khúc | Nếu chỉ có hai đầu, dot nội suy sẽ cắt góc và có thể xuyên phòng dù shortest path hợp topology. Source không có kiểm tra giao tường. Không có bằng chứng mọi map hiện tại đều gặp lỗi này. |
| Hướng theo ảnh/bắc | Không thấy map north/bearing calibration trong các schema liên quan. atan2 trong painter chỉ vẽ mũi tên; không phải sensor heading hay travel heading. |

**Khả năng dùng IndoorPosition = mapVersionId + floorId + edgeId + progressMeters: CONDITIONAL cho Sprint 2.**

Định nghĩa mapVersionId là **(server mapId, published version)**, floorId là **stable floorKey GUID**, edgeId là **stable directed edge GUID**, progressMeters tính từ fromNode. Không dùng riêng version số nguyên, LocalMapProject.id hoặc ID int phiên để thay mapId server. Tuple đủ xác định vị trí *đã gắn vào cạnh cùng tầng*, nhưng không bao phủ thời điểm neo đúng node/chưa chọn nhánh và chuyển tầng.

Tối thiểu cần union vị trí NodeAnchor / OnEdge / FloorTransition, kèm timestampNs, source, confidence/uncertainty, sessionGeneration. QR đứng tại node không bắt buộc chọn edge giả. FloorTransition phải giữ from/to floor; không nội suy giữa hai ảnh tầng như một mặt phẳng.

**Phương án hành lang thẳng, không đổi schema:**

1. Đọc snapshot đã pin, xây tracking graph bất biến trong bộ nhớ từ floors[].content.edges và node GUID; tạo ánh xạ GUID↔int renderer.
2. Với cạnh cùng tầng có L>0, endpoints A/B khác nhau và geometry đã kiểm chứng là hành lang thẳng: t=s/L; x=(1-t)Ax+tBx; y=(1-t)Ay+tBy.
3. Chỉ vẽ khi s hợp lệ trong [0,L]. Có thể clamp để hiển thị ở biên nhưng phần quãng dư phải được giữ thành event/uncertainty; không tự chuyển sang nhánh được route gợi ý.
4. Bước chân chưa đủ bằng chứng cho chiều tiến/lùi thì không cộng “tiến về đích” mặc định. Directed route là ràng buộc dẫn đường; người thật vẫn có thể đi ngược hoặc rời tuyến.
5. Điểm cong dùng các node/cạnh thẳng trung gian đã author/đo bằng công cụ hiện có ở công việc bản đồ riêng; không thêm node vào snapshot đã publish trong G0.

**Mở rộng polyline sau này:** versioned geometry với các điểm normalized theo cạnh, cumulative metric length theo đoạn, validation continuity/endpoints và mapping theo chiều cạnh. Nếu chỉ có tổng mét thì phân bổ theo chiều dài pixel là xấp xỉ, cần khai báo/kiểm chứng; không dùng Euclidean normalized làm chuẩn mét khi aspect ratio khác nhau. Cần thiết kế migration/compatibility riêng vì DTO backend Disallow unknown fields. Không thêm field hoặc đổi JSON trong G0/Sprint 1.

### B4. QR localization audit

**Format và mapping CONFIRMED:**

- Public payload: WMQR1: + token hex chữ thường 64 ký tự. Flutter cũng chấp nhận URL http/https có path /q/{token}, chỉ trích token và gọi API base URL đã cấu hình; không đi theo host QR.
- Token là opaque locator; **GUID node không nằm trực tiếp trong payload**, được server map trong MapNodeQr(MapId, FloorKey, NodeId, DraftVersion, PublishedVersion).
- MapProjectService tạo token random 32 byte, khóa QR theo draft version. Public map lookup theo (MapId,Version); MapPublication.ContentJson là bản copy. Publish bản mới không làm QR cũ tự đổi phiên bản.
- GET resolve kiểm IsActive trước: inactive → HTTP 410 qr_revoked; chưa published → 409 map_not_published; node không còn trong snapshot đã pin → 410 qr_node_missing; không có/malformed token → 404.
- PublicMapsController AllowAnonymous. PublishedMapApiService chỉ gắn Authorization khi private=true, không theo redirects.
- Scanner có camera permission/retry/error UI, chống lookup trùng, stop khi inactive/paused/hidden/detached, resume có điều kiện, dispose observer/controller. Đó là lifecycle camera, chưa phải lifecycle sensor.
- Legacy payload chỉ là mã trim 1–100 ký tự không control; resolve map-location bằng int ID, không có public token/version/revoke contract tương đương.

| Câu hỏi | Kết luận |
|---|---|
| Neo đầu hành trình? | Có thể tái dùng Node QR Published. Resolver + membership của node/tầng trong snapshot cung cấp anchor xác minh bằng server tại lúc resolve; không chứng minh người đang đứng đúng vị trí vật lý của biển QR. |
| Quét QR thứ hai trong Navigation? | Đã hỗ trợ trong source: _scanLocation dùng ScannerPage.capture rồi map.resolvePublishedQr. Hiện cập nhật checklist hoặc reroute, chưa reset PDR vì chưa có PDR. |
| Flutter tối thiểu cần thêm gì ở Sprint sau? | QrLocalization adapter trả VerifiedAnchor có map/version/floor/node/normalized coordinate/time; controller pause/discard event cũ khi scan; correction transaction atomically reset estimator và baseline sau validate, giữ UI Visitor hiện có. |
| QR khác version/map? | Giữ nguyên pin, từ chối correction. Nếu muốn chuyển map/version phải tạo phiên mới rõ ràng sau tải/validate; không gộp ID hay tự đổi version giữa chừng. |
| QR revoke? | 410 không cập nhật vị trí; giữ last estimate nhưng báo mất khả năng xác minh/uncertain tùy độ cũ. Không tái sử dụng kết quả resolve cũ làm một xác nhận mới khi offline. |
| Cần PositioningAnchor entity v1? | Chưa cần bảng/backend entity riêng. Dùng Node QR và value object VerifiedAnchor trong Flutter. Có thể trừu tượng hóa anchor source để mở rộng BLE/RTT/UWB sau. |
| QR xác nhận heading? | Không. Payload/resolve chỉ vị trí, map/version, floor/node. Không có marker pose/orientation hay map-north. QR scan không giải được phone heading→travel direction. |
| Không phá Visitor? | Có thể: bọc existing resolver, thêm controller tùy chọn/fallback. Giữ capture/legacy/public branches và existing tests. Chưa được chứng minh bằng runtime integration mới. |

Revocation chỉ được kiểm lúc resolve: một phiên đã tải map không tự nhận push revoke, và PublicAsync đọc snapshot không kiểm QR còn active. Không khẳng định cơ chế hiện tại hủy mọi phiên đã mở khi thu hồi QR. Đây là hạn chế cần chính sách freshness về sau, không yêu cầu sửa backend ở G0/Sprint 1.

## C. Android Sensor Readiness

### C1. Cấu hình và môi trường

| Mục | Giá trị và nguồn |
|---|---|
| Flutter/Dart cục bộ | Flutter 3.47.7 stable, Dart 3.13.5 từ C:/src/flutter/bin/cache/flutter.version.json, đọc file trực tiếp; không chạy flutter doctor/version |
| Dart constraint | pubspec.yaml:21–22 = ^3.13.3 |
| AGP/Kotlin | settings.gradle.kts:22–23 = AGP 9.1.0, Kotlin 2.4.0 |
| Gradle wrapper | gradle-wrapper.properties:5 = 9.3.1-all |
| Compile/target/min | app/build.gradle.kts:9,22–23 delegate FlutterExtension; SDK source cục bộ: compile=36, target=36, min=24 tại FlutterExtension.kt:23,26,34 |
| Artifact cũ | merged_manifests/debug/processDebugManifest/AndroidManifest.xml:8–9 cũng ghi min24/target36; là artifact cũ, không phải một build mới trong audit |
| Java/Kotlin target | JavaVersion.VERSION_17 và JvmTarget.JVM_17; không xác nhận runtime JDK process đang build vì G0 không build |
| Kotlin configuration | android.newDsl=false, android.builtInKotlin=false, kotlin.incremental=false; không suy cần nâng cấp hay đổi cờ |
| Flutter embedding | MainActivity : FlutterActivity, configureFlutterEngine gọi super; Manifest flutterEmbedding=2 |
| Channel hiện có | waymark/ai_preferences, waymark/draft_files; file worker và onActivityResult phục vụ SAF; onDestroy dọn pending/worker |
| Manifest source | INTERNET, CAMERA; không ACTIVITY_RECOGNITION, không sensor feature requirement/service/permission cho background tracking |
| Dependencies | http 1.6.0, mobile_scanner 7.4.2, qr_flutter 4.1.0, web; không sensors_plus/pedometer/compass plugin trong pubspec/lock |
| App lifecycle | Scanner là WidgetsBindingObserver; NavigationPage không có sensor/app observer, route observer cho tracking chưa có |
| API runtime | Không thấy listener cổng mặc định 5121 lúc kiểm tra; không khởi động API. Không kết luận mọi instance API/port khác đều dừng; HTTP/SQL runtime NOT VERIFIED. |
| ADB | adb.exe có trong Android SDK; adb process/server đã hiện diện; adb devices -l không có serial nào, kể cả emulator ở lúc kiểm tra |

**NOT VERIFIED ON PHYSICAL DEVICE.** Không cài APK, không grant quyền, không gọi dumpsys sensorservice vì không có thiết bị. Không dùng UI/UX emulator acceptance trước đây để kết luận sensor readiness điện thoại.

**INFERRED:** min24 đã vượt API giới thiệu cả sáu sensor được hỏi; native SensorManager tương thích về API surface. Khả năng compile/regression vẫn cần gate Sprint 1; cấu hình SDK không chứng minh sensor có trên máy.

### C2. Sensor inventory

| Sensor Android / API có từ | App đang dùng? | Thiết bị thật có? | Vai trò và giới hạn đề xuất |
|---|---|---|---|
| TYPE_STEP_DETECTOR / 19 | Chưa | NOT VERIFIED | Event một bước; ưu tiên cho thử nghiệm từng bước; cần ACTIVITY_RECOGNITION từ Android 10/API29. Không bảo đảm nhận đúng mọi bước. |
| TYPE_STEP_COUNTER / 19 | Chưa | NOT VERIFIED | Số tích lũy từ reboot khi sensor active; dùng kiểm đối chiếu, baseline riêng mỗi session; không thay mỗi delta thành các event bước có timestamp giả. |
| TYPE_ROTATION_VECTOR / 9 | Chưa | NOT VERIFIED | Orientation quaternion theo hệ tham chiếu Android; phụ thuộc chất lượng fusion/từ trường. Phone attitude không phải travel heading. |
| TYPE_GAME_ROTATION_VECTOR / 18 | Chưa | NOT VERIFIED | Relative rotation không neo bắc từ; drift yaw; useful để quan sát quay tương đối, không thay cho heading tuyệt đối. |
| Accelerometer / 3 | Chưa | NOT VERIFIED | Gia tốc m/s² có gravity, trục thiết bị; raw signal/diagnostic. Không viết thuật toán phát hiện bước từ raw trong Sprint 1. |
| Gyroscope / 3 | Chưa | NOT VERIFIED | Vận tốc góc rad/s theo trục thiết bị; tích phân sẽ drift. Không tự suy quãng đường từ gyro. |

Các mô tả API dựa trên [Sensor API](https://developer.android.com/reference/android/hardware/Sensor), [Motion sensors](https://developer.android.com/develop/sensors-and-location/sensors/sensors_motion), [Position sensors](https://developer.android.com/develop/sensors-and-location/sensors/sensors_position). Capability thực tế phải lấy getDefaultSensor/getSensorList và kết quả registerListener; không suy từ Android version.

SensorEvent.timestamp là ns theo elapsedRealtimeNanos, monotonic **cho từng sensor**; giữ nguyên timestamp gốc, thêm sequence/generation và native receive time để quan sát trễ. Không thay bằng DateTime.now hoặc so trực tiếp với Stopwatch Dart khác mốc. Event các sensor/batch có thể tới lệch thứ tự; tương lai phải đồng bộ theo thời điểm đo. [SensorEvent](https://developer.android.com/reference/android/hardware/SensorEvent).

Chỉ thu khi foreground trong v1, unregister lúc pause/stop/cancel/dispose; sampling 20–50Hz là điểm khởi đầu **đề xuất để đo**, không bảo đảm tần số phần cứng hay latency. Không cần HIGH_SAMPLING_RATE_SENSORS cho dải này. Background restrictions và rate limits cần tuân thủ [Sensors Overview](https://developer.android.com/develop/sensors-and-location/sensors/sensors_overview).

### C3. So sánh phương án tích hợp

Phương án plugin được so sánh cụ thể với API công khai của [sensors_plus](https://pub.dev/packages/sensors_plus) và [pedometer](https://pub.dev/packages/pedometer), không suy rằng mọi plugin đều thiếu mọi khả năng. sensors_plus công bố raw motion/magnetic/barometer; không cung cấp toàn bộ Step Detector + rotation vector theo contract audit cần. pedometer có step count/pedestrian status và DateTime timestamp; tài liệu đó chưa chứng minh giữ native event ns hoặc một event/từng bước để PDR.

| Tiêu chí | A. Flutter plugin có sẵn | B. Kotlin SensorManager + channels |
|---|---|---|
| Step Detector | Phải kiểm plugin/native implementation; sensors_plus đơn lẻ không đủ; pedometer count không tự tương đương detector | Yêu cầu trực tiếp TYPE_STEP_DETECTOR, report absent/registration failure |
| Heading | Cần plugin khác hoặc tự fusion raw; kiểm reference frame | Expose rotation/game quaternion + accuracy/reference frame; chưa giải travel direction |
| Timestamp | API/schema phụ thuộc plugin; không mặc định DateTime là timestamp sensor | Giữ native timestampNs và native receive clock nhất quán |
| Latency | Chịu HAL và cách plugin batch; phải đo | Chọn sampling/report latency và đo native→Dart; vẫn không bảo đảm real-time cứng |
| Pause/resume | Wrapper subscription + xác minh native unregister | Chủ động lifecycle/session generation, onCancel/unregister; thêm code cần bảo trì |
| Activity permission | Vẫn phải khai báo/runtime request; một số plugin không xử lý toàn flow | MethodChannel request ở activity foreground, callback có quản lý |
| Nhiều thiết bị | Plugin giảm công việc chung nhưng không thêm sensor cho máy thiếu | Capability rõ từng sensor/vendor/API; fallback rõ |
| Testability | Mock API Dart thuận lợi; native vẫn cần thiết bị | Fake provider + channel mocks + physical native gate; dễ giữ contract đúng yêu cầu |
| Bảo trì | Thêm package, plugin release/Gradle constraints; có cộng đồng | Không thêm package cảm biến; team sở hữu bridge, schema, lifecycle/tests |
| Compatibility repo | Chưa có dependency này; cần đánh giá lock và AGP9/Kotlin2.4 thực tế | Có sẵn Kotlin/embedding/channels để nối; chưa build code mới nên compatibility mới là INFERRED |

Tại ngày tra cứu, sensors_plus 7.1.1 ghi Java17, Kotlin2.2.0, AGP>=8.12.1, Gradle>=8.13; các con số hiện tại của repo không thấp hơn các mức công bố, nhưng điều này **không xác nhận** kết hợp AGP9/Kotlin2.4 đã được plugin kiểm thử. Không thêm/nâng package để audit.

**Khuyến nghị Sprint 1: B**, với class Kotlin riêng đăng ký tại MainActivity, không nhét toàn bộ xử lý sensor vào activity đã chứa SAF/preferences. EventChannel cho samples/status stream; MethodChannel cho capabilities, permission, start/stop và clock sample. Android-first, cần detector và timestamp đồng bộ, repo đã có channel native nên phương án này kiểm soát được contract với thay đổi hẹp. Chưa cần FlutterPlugin đa nền tảng đóng gói riêng.

## D. Positioning Architecture Proposal

Tất cả interface dưới đây là **đề xuất**, không phải API đang có trong source.

### D1. Ranh giới module

| Module | Vai trò, input → output / interface đề xuất | Liên hệ source và dependency | Unit testing | Sprint |
|---|---|---|---|---|
| SensorProvider | capabilities, permission, control; native sample → Stream<SensorSample>; probe(), requestPermission(), start(config), stop(), dispose() | MainActivity + channel mới; không phụ thuộc route/HTTP | Codec malformed/units/order/generation; fake streams; channel mock | **1** |
| PdrEngine | StepSample + orientation đã time-align + stride model + calibration → MotionEstimate có deltaMeters/uncertainty; ingest(sample), reset(anchor, calibration) | Hạ tầng mới, không dùng ManualNavigation làm integrator | Replay thật/fake, stride drift, no-step/no-motion, phone rotation | 2+ |
| QrLocalization | payload + pinned map context → VerifiedAnchor hoặc typed failure; resolve(payload, expectedVersion) | Bọc PublishedMapApiService.resolve + stableIdentity/stableLocation; không gọi history như một side effect mỗi correction | Same map/version, wrong floor/node, 410/offline, stale reply | 2+ |
| MapMatchingEngine | MotionEstimate + last pose + immutable full graph → candidate positions/confidence; match(motion, state) | Adapter từ Published project giữ edge GUID; route chỉ là prior | Directed/reverse, ambiguity, straight interpolation, disconnected edges | 2 cho straight corridor, branch/polyline sau |
| PositionFusion | candidate + anchor + sensor quality → IndoorPosition/uncertainty; applyMotion(), applyAnchor() | On-device, không phụ thuộc backend; chưa cần EKF framework | Atomic correction, stale event, version/session rejection | 2+, ban đầu gộp logic tối thiểu trong controller |
| IndoorTrackingController | Điều phối trạng thái, subscription, correction, session/version → ValueListenable<TrackingState>/position stream | NavigationPage sở hữu; dùng Provider/PDR/Matching/QR, không sửa route liên tục | Fake clock/provider/QR, close/route replacement/pause/race | 2+; Sprint1 chỉ SensorSessionController nhỏ |
| BlueDotOverlay | IndoorPosition + graph adapter + scene metrics → dot/halo trạng thái và repaint | FloorPlanCanvas scene Stack, FloorRouteMap cache, normalizedMapPoint, map_paint_scale | Zoom/pan/contain/floor isolation, no image reload/rebuild root | 2+ |

Không cần tạo bảy service lớn trong Sprint 1. Sprint 2 có thể dùng một controller với các pure functions cho stride/interpolation/candidate scoring; chỉ tách PositionFusion thành class khi có nhiều nguồn đo hoặc logic đáng kể. Giữ ranh giới input/output để BLE/Wi-Fi RTT/UWB bổ sung Measurement/Anchor adapters về sau; không đưa các permission/backend đó vào Sprint 1.

~~~text
Android Sensors
  → SensorProvider (timestamp/units/capability)
  → PDR (motion estimate, chưa snap ép vào route)
  → MapMatching (candidates + ambiguity)
  → PositionFusion / IndoorTrackingController
  → IndoorPosition + confidence
  → navigation instruction adapter + BlueDotOverlay

QR capture
  → existing server resolver + pinned snapshot validation
  → VerifiedAnchor (node/floor/version/time; không có heading)
  → atomic correction + reset integration baseline
~~~

Điểm quan trọng: intended route không phải bằng chứng vị trí. Không tự chọn nhánh đang nằm trên route để che việc người dùng đã đi sai; nếu hai nhánh không phân biệt được thì uncertain, yêu cầu QR khi phù hợp. Không tạo timer chạy blue dot theo tổng khoảng cách tuyến.

### D2. Contract SensorProvider tối thiểu cho Sprint 1

~~~dart
// Phác thảo contract; không tạo class thật trong G0.
abstract interface class SensorProvider {
  Stream<SensorSample> get samples;
  Stream<SensorProviderStatus> get statuses;
  Future<SensorCapabilities> probe();
  Future<MotionPermission> requestPermission();
  Future<SensorStartResult> start(SensorConfig config);
  Future<void> stop();
  Future<void> dispose();
}
~~~

SensorSessionController.pause/resume gọi stop/start có await và generation mới; không chỉ pause subscription Dart rồi để native tiếp tục thu. Khả năng provider/status/error phải tách nhau:

- SensorCapabilities: available sensors theo loại, native identity/vendor/version nếu có, min delay/range/resolution, supported sampling metadata; permission trạng thái riêng; probe không tự xin quyền.
- SensorSample: schemaVersion, sessionGeneration, sequence, kind, sensorTimestampNs (int64), nativeReceiveTimestampNs, values sao chép, accuracy; units theo kind, quaternion x/y/z/w và reference frame rõ. Không gọi orientation mẫu là “travelHeading”.
- StepDetector.values=[1.0] là step event; Counter là cumulativeSteps, không double count với detector. Reboot/reset/giảm counter phải tạo discontinuity/baseline mới.
- Probe có sensor không bảo đảm register thành công; start trả tập đã đăng ký/thất bại và degraded mode, không bool “supported” duy nhất.
- Codec kiểm kiểu, chiều dài, finite, sensor type, schema/version, timestamp và generation; giữ thứ tự theo sensor. Không giả định global timestamp luôn tăng giữa hai loại khác nhau.
- MethodChannel đề xuất waymark/sensors/control; EventChannel waymark/sensors/events. Control nhận start/stop/probe/requestPermission; clock sample giúp debug latency trong cùng native clock.
- Một session, một native subscription owner; start/stop idempotent, serialize control; EventChannel onCancel và native onPause/onDestroy đều có unregister an toàn. Stream chỉ phát khi native registration thành công và quyền hợp lệ.
- Kết thúc phiên bỏ late event cùng generation cũ; resume không hồi chiếu số bước tích lũy trong thời gian app không quan sát như chuyển động live đã biết.
- UnsupportedSensorProvider cho web/desktop trả unavailable rõ, không phát dữ liệu giả. FakeProvider chỉ inject test/debug.

### D3. Tracking state machine và fallback

Nên tách **tracking state** với **ManualNavigation state/history terminal state**, tránh đổi nghĩa “Completed” thành sensor đã xác minh arrival. Có thể giữ enum đầy đủ đề xuất nhưng lưu reason/capability/lastPose riêng, giảm số tổ hợp enum.

| State | Điều kiện vào/ra tối thiểu |
|---|---|
| uninitialized | Chưa probe/provider chưa khởi tạo → needsAnchor hoặc sensorUnavailable/permissionDenied |
| needsAnchor | Chưa có neo hợp lệ của pinned map → anchored khi QR verified |
| anchored | Có vị trí node/floor; chưa đủ travel-heading/calibration → tracking khi đủ, không tự chuyển chỉ vì có rotation sample |
| tracking | Dữ liệu mới, chất lượng đủ, một candidate hợp lý; chỉ bước chân thật mới tiến quãng đường |
| uncertain | Heading stale/drift, orientation thay đổi, ambiguity, geometry không đủ, bước/motion mâu thuẫn → giữ/hạn chế estimate, xin mốc khi cần |
| relocalizing | Mở scan/resolve; suspend integration; accepted anchor reset atomic, cancel giữ last verified pose nhưng đánh giá lại freshness |
| paused | App/route không active hoặc user pause; native unregister; resume re-probe quyền/capability, tạo generation mới, quay needsAnchor/uncertain nếu mất chuyển động |
| sensorUnavailable | Thiếu sensor cần thiết hoặc registration fail; dùng Navigation tĩnh/QR-only |
| permissionDenied | Người dùng từ chối/revoke quyền; không lặp prompt tự động, có hành động thử lại/Settings rõ ràng |
| finished | Explicit finish/cancel theo chính sách phiên; stop/unsubscribe, không nhận event cũ |
| failed | Lỗi không thể phục hồi session/contract; cleanup rồi cho fallback; không crash Visitor |

Sprite/dot không được tự tiến khi xoay điện thoại tại chỗ. Không mặc định rotation của phone bằng travel direction; thử nghiệm v1 về sau cần điều kiện cầm máy/hiệu chuẩn nêu rõ, và giảm confidence nếu điều kiện bị phá. QR không reset heading về from→to một cách ngầm định.

Sprint 1 chỉ triển khai các trạng thái hạ tầng idle/starting/running/paused/permissionDenied/unavailable/error/disposed để quan sát sensors; không triển khai state machine định vị/anchor ở bảng trên.

## E. Risks & Unknowns

P0 = phải chặn hành vi vị trí sai trước khi bật live; P1 = phải kiểm soát trước nghiệm thu tính năng liên quan; P2 = tối ưu/mở rộng. P0 ở đây là **rủi ro thiết kế nếu thêm tracking**, không tự khẳng định đang có lỗi production do feature chưa tồn tại.

| Mức | Rủi ro / bằng chứng | Biện pháp tối thiểu v1 và gate |
|---|---|---|
| P0 | Phone orientation khác travel direction; schema không có map heading | Calibration có điều kiện, separate phone attitude/travel direction, uncertain khi không đủ bằng chứng; turn-in-place không đổi vị trí |
| P0 | Snap vào route sai nhánh gây vị trí xuyên tường | Match full graph/candidate confidence, không ép intended route; dừng suy diễn khi ambiguity và QR re-anchor |
| P0 | Geometry hai endpoints không theo hành lang cong | Chỉ bật straight verified edges; split authoring hoặc polyline thiết kế riêng; thiếu geometry thì static fallback |
| P0 | Lẫn map/version/GUID với int session | Pinned immutable tracking context, GUID adapters, reject khác version/map và event generation cũ |
| P0 | Late event sau QR/pause/reset làm dịch vị trí mới | Atomic reset, generation tokens, per-sensor time validation; không replay bước trước anchor |
| P1 | Sai stride length theo người/tốc độ | Calibrate bằng quãng đo thật, lưu uncertainty; báo bias theo lượt, không công bố độ chính xác chưa đo |
| P1 | Heading drift/từ trường nhiễu; game rotation không có bắc | Report accuracy/reference frame, stale checks; QR chỉ sửa position, heading phải có cách hiệu chuẩn riêng |
| P1 | Dữ liệu mét nhập sai/không được khảo sát | Fixture kiểm soát và corridor đo thật; “isMeasured” chỉ là flag nhập dữ liệu |
| P1 | Zoom/pan/contain/padding làm lệch dot | Vẽ dot cùng scene/transform, dùng geometry helper; test aspect ratio/resize/floor/fit |
| P1 | Người đi sai/đi ngược nhưng route vẫn hướng tới đích | Ước lượng motion độc lập route; không tăng progress chỉ vì có step; offRoute/uncertain trước reroute tự động |
| P1 | Thiếu Step Detector | Report absent; counter-only diagnostics, static/QR fallback; không giả lập detector bằng timer |
| P1 | Permission denied/revoked | Request just-in-time API29+, recheck resume; không block Search/Preview/manual |
| P1 | Lifecycle leak/đếm trùng khi resume/scanner | Native+Dart cleanup, one owner, start/stop await, route visibility, cancellation race tests |
| P1 | Chuyển tầng suy từ quãng chân không đủ | Explicit floor transition state + QR/manual confirmation; không tự đổi tầng từ step count |
| P1 | QR revoke/offline/freshness | Resolve lại lúc correction, 410 fail closed; giữ uncertainty, không công bố revoke realtime cho phiên offline |
| P1 | Privacy vị trí trong nhà/QR | On-device processing, không gửi mỗi step; debug opt-in, buffer bounded, không log token/QR/location người thật mặc định |
| P1 | Event rate làm rebuild, pin và main-thread load | Stream nhẹ; PDR theo samples, overlay repaint riêng, UI debug throttle; không reroute mỗi bước |
| P2 | Battery | Start/stop foreground, sampling thấp đủ dùng, raw acc/gyro chỉ khi cần debug; đo session duration/event rate và battery riêng |
| P2 | Package/native maintenance | Native bridge hẹp, versioned schema, fake tests; không nâng toolchain vô cớ |
| P2 | Curved corridors, BLE/RTT/UWB | Geometry/source abstraction giữ mở; ngoài Sprint 1 |

**Unknowns phải ghi rõ:** model/OEM/API điện thoại; sensor vendor và default/wakeup variant; registerListener thực tế; permission behavior theo OS; bước bỏ sót/false positives; sensor-to-Dart latency; magnetic environment; map north/calibration; độ đúng của geometry/mét hiện trường; battery drain; live backend/SQL availability. Không unknown nào được đổi thành claim PASS chỉ bằng source review.

Không thấy cơ sở để chứng nhận phòng/cửa/accessibility an toàn. Các DTO giữ Unknown và snapshot verifiedForPatientUse=false; tracking không được nâng các trạng thái đó.

## F. Sprint 1 Proposal — Android Sensor Infrastructure

### F1. Scope nhỏ, độc lập

**Chỉ** capability + permission + native sample stream + lifecycle + fake/test/debug. Thu StepDetector ưu tiên, StepCounter để đối chiếu, RotationVector (GameRotation fallback với frame relative), optional accelerometer/gyro diagnostics. Không làm PDR, stride estimator production, blue dot, QR correction, map matching, branch matching, floor inference hoặc rerouting mới.

Không sửa schema Node/Edge/JSON, backend, SQL, JWT, dependency hay Gradle trừ khi một lỗi compile có bằng chứng bắt buộc phải được xử lý trong công việc riêng. Không yêu cầu API/SQL chạy để nghiệm thu sensor infrastructure.

### F2. File dự kiến

| Loại | File đề xuất | Nội dung |
|---|---|---|
| Tạo | waymark/lib/features/indoor_tracking/sensors/sensor_models.dart | Sample/capability/config/permission/status, schema và codec |
| Tạo | waymark/lib/features/indoor_tracking/sensors/sensor_provider.dart | Interface, factory platform và unavailable provider đơn giản |
| Tạo | waymark/lib/features/indoor_tracking/sensors/android_sensor_provider.dart | Method/EventChannel adapter, không Android imports ở Dart |
| Tạo | waymark/lib/features/indoor_tracking/sensors/sensor_session_controller.dart | Start/stop/pause/resume/generation, observable hạ tầng |
| Tạo | waymark/lib/features/indoor_tracking/debug/sensor_probe_page.dart | Debug-only observer, capability/permission/count/timestamps/quality/error; không map/dot |
| Tạo | waymark/tool/sensor_probe_main.dart | Alternate debug entrypoint, không đổi route/menu sản phẩm |
| Tạo | waymark/android/app/src/main/kotlin/com/example/waymark/sensors/AndroidSensorBridge.kt | SensorManager, channels, capability, permission result, registration/cleanup |
| Tạo | waymark/test/support/fake_sensor_provider.dart | Deterministic provider/clock, absent/denied/error modes |
| Tạo | waymark/test/sensor_models_test.dart | Codec, units/schema/timestamp, counter baseline/discontinuity representation |
| Tạo | waymark/test/android_sensor_provider_test.dart | Channel control/events/error/generation, unsupported platform |
| Tạo | waymark/test/sensor_session_controller_test.dart | State/permission/lifecycle/races/idempotence |
| Tạo | waymark/test/sensor_probe_page_test.dart | Widget controls, status/fallback, unmount cleanup |
| Sửa | waymark/android/app/src/main/AndroidManifest.xml | ACTIVITY_RECOGNITION; sensor uses-feature nếu khai báo phải required=false |
| Sửa | waymark/android/app/src/main/kotlin/com/example/waymark/MainActivity.kt | Tạo/wire bridge, permission callback tách request code, native pause/destroy cleanup; giữ hai channel cũ và SAF callback |
| Không dự kiến sửa | pubspec.*, Gradle, main.dart, Navigation/Builder/scanner, backend/database | Giữ Sprint 1 độc lập; debug entrypoint riêng |

Đây là danh sách dự kiến cho Sprint 1; **không file nào trong bảng được tạo/sửa tại G0**.

### F3. Tasks và acceptance criteria

1. **Contract + fake:** thống nhất sensor kind, units, frame, schema, ns timestamp, generation. Fake không phát trước start và không tiếp tục sau stop/dispose. Test mọi kind/malformed event.
2. **Capability:** probe không tự mở permission dialog; report sáu loại có/không. start report registration failures/degraded mode riêng permission.
3. **Permission:** request ACTIVITY_RECOGNITION chỉ khi người dùng nhấn start step observation; API<29 không xin runtime này. Không xin location/BLE/camera cho sensor probe. Deny/revoke không crash, không auto prompt vòng lặp, cho phép quan sát orientation khi phù hợp.
4. **Native bridge:** dùng SensorManager.registerListener cho detector/counter, callback chuyển bản copy values. Không dùng requestTriggerSensor thay cho step detector. Nêu source/frame/rate thực; không phát step giả nếu thiếu sensor.
5. **Lifecycle:** unregister khi native pause/destroy, EventChannel cancel, Dart pause/stop/dispose; resume recheck permission và tạo session generation. Có gate route visibility trong debug harness; không chạy foreground service/background v1.
6. **Debug quan sát:** build kDebugMode/alternate entrypoint riêng, start/stop rõ; hiển thị count và sampled orientation/latency thưa để không rebuild theo mỗi raw event; buffer bounded. Không persist sensor/QR/token mặc định, không network.
7. **Tests:** provider/channel/controller/widget tests pass; regression QR/Builder/rendering phù hợp. Sau implementation mới chạy analyze/build có kiểm soát, không chạy SQL E2E để kiểm sensors.
8. **Physical gate:** ít nhất một Android thật, ghi model/OS/API, sensor list/probe, permission grant/deny/revoke, đi/dừng/quay tại chỗ, pause/resume 10 vòng, stop/cancel/dispose, absence path bằng fake. Không nghiệm thu native chỉ với emulator.

**Nghiệm thu Sprint 1 khi:**

- Có evidence samples thật StepDetector và rotation vector trên ít nhất một máy có sensor; timestamp giữ ns và quality/frame minh bạch.
- Không leak/duplicate listener qua 10 vòng lifecycle; event generation cũ không vào session mới; unsupported/permission denied có trạng thái đúng.
- Không thay đổi tiến độ Navigation, không phát HTTP từ provider, không thêm position animation.
- Android build/debug probe và test Dart pass; existing SAF/preferences channels vẫn hoạt động qua smoke check.
- Nếu máy thật thiếu StepDetector: capability/fallback có thể đạt; mục “real detector validation” còn NOT VERIFIED, cần máy khác trước khi đóng gate hỗ trợ live từng bước.

### F4. Chiến lược kiểm thử các Sprint sau

| Nhóm | Case / cách kiểm | Khi triển khai |
|---|---|---|
| Unit — event parsing | Type/length/finite/schema unknown, units/quaternion optional fields, accuracy unavailable | 1 |
| Unit — event time/order | Per-sensor monotonic, cross-sensor reorder hợp lệ, duplicate/stale/late, generation reset, sample clock latency | 1; time-alignment PDR ở 2 |
| Unit — lifecycle | Start/start, stop/stop, start fail giữa các sensor, denied/revoked, absent, resume after dispose, cancel race, bounded stream | 1 |
| Unit — stride | Distance per real step, calibration bias, no displacement on zero steps/phone rotation; counter không double count | 2+ |
| Unit — edge/coordinates | Progress [0,L], reverse direction, overshoot/ambiguous junction, zero-length geometry, aspect ratio, same floor interpolation | 2+ |
| Unit — QR/version | Same/different map/version, floor/node absent, revoked/offline, stale resolve after new session, correction atomic và counter baseline | 2+ |
| Integration — sensors→controller | Channel mock/fake stream controls session, no network, cleanup stream on unmount | 1 |
| Integration — QR→start / position→Navigation | Existing Published path + future position adapter; manual fallback giữ semantics | 2+ |
| Integration — cleanup/regression | Dispose, scanner overlay/return, route replacement, auth/account change; Builder/QR/Published/zoom không regress | Một phần 1, đầy đủ 2+ |
| Native thực | Sensor probe/permission/lifecycle/latency trên Android thật | 1; PDR accuracy sau |

Các test hiện có cần giữ: published_map_test.dart, qr_publish_hotfix_test.dart, local_map_navigation_test.dart, multifloor_navigation_test.dart, navigation_qr_match_test.dart/navigation_qr_flow_test.dart, scanner_camera_test.dart, sprint10_zoom_test.dart, map_zoom_smoke_test.dart và ai_timeout_preferences_test.dart (channel AI cũ). Đọc source tests không đồng nghĩa G0 chạy lại tests.

### F5. Phép thử hành lang và báo cáo số liệu

Chuẩn bị hành lang thẳng **10–20m đo bằng thước**, ghi khoảng cách ground truth, ảnh/map version/cạnh có geometry đúng; QR node tại đầu, cuối nếu có. Không lấy mét nhập trong fixture làm số đo thật.

- Đề xuất ban đầu **2 điện thoại thật, 2 người**, mỗi cặp người–máy **5 lượt đi mỗi chiều**: tổng 40 lượt chuẩn. Nếu chỉ có một máy, báo rõ phạm vi pilot 20 lượt/2 người, không suy rộng đa thiết bị.
- Mỗi cặp thêm **3 lượt đi–dừng–đi mỗi chiều**; ghi thời gian đứng yên 10 giây. Thêm **3 lần quay máy tại chỗ 30 giây**, có người quan sát đếm false steps; **3 lượt đi ngược hướng tham chiếu** để kiểm không ép progress về đích.
- Đổi cách cầm chủ động trong ca riêng (cầm thẳng/lệch/đổi tay/bỏ túi nếu được hỗ trợ), không gộp mọi ca vào một mean. QR cuối dùng xác minh endpoint, không xóa sai số trước khi ghi nhận.
- Ground truth steps do người đếm/clicker, đồng hồ các lần start/stop; ghi detector count, counter delta, missed/extra steps, native timestamp gaps, rate/accuracy, pause/discontinuities.
- Sprint 1 chỉ báo detection/count/lifecycle/latency. Sprint 2 mới báo estimatedDistance, endpoint error dọc cạnh, signed bias, relative error và QR correction delta. Không tạo thuật toán distance tạm chỉ để có số ở Sprint 1.
- Báo theo từng lượt và tổng hợp từng model/người/case: n, mean/median, min/max, p95 khi n đủ (n nhỏ ghi rõ giới hạn), tỷ lệ failed/incomplete; lưu cả lượt lỗi. Accuracy steps=(detected−truth)/truth và absolute error, không chỉ correlation. Ground truth=0 thì dùng false step count, không chia cho 0.
- Battery là thử riêng tối thiểu 3 phiên hoạt động cố định thời lượng so với baseline tương đương, cùng màn hình/rate; nêu giới hạn coarse battery % nếu không có đo chuyên dụng.

**Chưa có phép đo Android thật trong G0; không có claim độ chính xác theo mét.**

## G. GO / CONDITIONAL GO / NO-GO Decision

| Quyết định | Phạm vi |
|---|---|
| **CONDITIONAL GO** | Có thể giao Codex triển khai Sprint 1 ngay theo scope F, dùng native bridge B, fake và debug entrypoint độc lập. |
| **Chưa GO** | Live blue dot/PDR/QR correction/branch matching/reroute mới; phải qua geometry/identity/heading và physical evidence gates trước. |
| Không cần chờ trước khi bắt đầu | API/SQL khởi chạy, database mới, backend migration, Master Plan thay đổi, model điện thoại do người dùng cung cấp. |
| Cần trước nghiệm thu native | Android thật kết nối/ủy quyền ADB, model/OS/API và sensor capability/permission/event evidence. Chỉ tên model chưa đủ chứng minh cảm biến hoạt động. |
| Điều kiện triển khai | Giữ source baseline đang dirty; chỉ sửa/tạo file đã giới hạn cho Sprint 1 ở một lượt được giao riêng; không mở rộng Navigation/Builder/backend. |

**Ước lượng 2–4 ngày công: còn hợp lý có điều kiện** cho một kỹ sư với thiết bị sẵn, toolchain hiện tại hoạt động và không thêm algorithm positioning:

| Công việc | Ngày công đề xuất |
|---|---:|
| Contract/codec/fake và tests nền | 0,5 |
| Native capability/permission/event bridge | 0,75–1,0 |
| Lifecycle/controller/debug probe + races | 0,5–0,75 |
| Test/regression/build và physical validation | 0,75–1,25 |
| Tổng | **2,5–3,5**, dành phần còn lại trong khung 4 ngày cho sửa lỗi nhỏ |

Chờ thiết bị là elapsed-time dependency ngoài ngày công. OEM issue/AGP incompatibility, multi-OEM campaign hoặc thêm phát hiện bước từ accelerometer có thể vượt khung; không cắt physical gate để giữ 2–4 ngày.

Bằng chứng đã đủ: source bridge/embedding/toolchain, dependency hiện tại, manual navigation boundaries, versioned QR/snapshot, test seams. Bằng chứng thiếu: compilation của code sensor chưa tồn tại, runtime permission/sensor trên thiết bị, latency/quality và mọi độ chính xác positioning.

## H. Evidence

### H1. File/line references chính

Line references là trạng thái workspace lúc audit; một số file đã sửa/untracked từ trước. Không dùng HEAD để thay cho source thực tế.

| ID | File / dòng | Điều chứng minh |
|---|---|---|
| E01 | waymark/lib/main.dart:14; services/auth_session.dart:6 | MaterialApp/Navigator và ValueNotifier state |
| E02 | waymark/lib/models/route_models.dart:72,139,159,190,261,286 | Node coordinates, route order/metres; MapGraphEdge mất id |
| E03 | waymark/lib/features/admin/draft_map.dart:71,139,315,353,363,411,467,595 | Directed edges, stable GUID map, local Dijkstra, JSON v2 |
| E04 | waymark/lib/features/admin/local_map_project.dart:36,56,98,181 | JSON v3, floor keys, explicit directed floor links |
| E05 | waymark/lib/features/admin/draft_server_session.dart:12,236,266,279 | Server DTO mapping giữ GUID |
| E06 | waymark/lib/features/navigation/local_map_navigation.dart:150,163,183,227,243,246,346,362,472,479,552,586 | Snapshot copy, session-local IDs, stable mapping, route edge ID gán lại |
| E07 | waymark/lib/features/scanner/scanner_page.dart:18,29,58,96,162,173,325,341,362 | Hai QR branches, camera lifecycle, public→Search |
| E08 | waymark/lib/features/scanner/public_map_entry_page.dart:28,49,93 | Anonymous public entry và paste/camera fallback |
| E09 | waymark/lib/services/published_map_api_service.dart:17,35,64,83,144,295,357,365,387 | QR parser, auth isolation, snapshot images/version guard |
| E10 | waymark/lib/features/search/local_map_search_page.dart:139,205,249,286; route/route_preview_page.dart:107,134 | Start khóa từ QR, target→route→Navigation |
| E11 | waymark/lib/features/navigation/manual_navigation.dart:32,63,99,141,162,185 | Checklist/QR matching/revision/arrival validation |
| E12 | waymark/lib/features/navigation/navigation_page.dart:40,111,124,130,185,253,358,390,583,788 | Reroute/QR/manual progress/render; chưa sensor cleanup |
| E13 | waymark/lib/features/navigation/reroute_navigation.dart:6 | Legacy API reroute giữ target/options và kiểm replacement |
| E14 | waymark/lib/features/route/floor_route_geometry.dart:6,74,110 | Normalized conversion, segments chỉ endpoints, floor transitions |
| E15 | waymark/lib/features/route/floor_plan_canvas.dart:4,36,135,152,228,261; map_paint_scale.dart:5 | Shared contain scene/zoom/pan và scale compensation |
| E16 | waymark/lib/features/route/floor_route_map.dart:41,47,77,271,418,427,594 | Graph Future cache, straight-line painter, render integration |
| E17 | waymark/lib/features/admin/draft_map_editor.dart:1356,1378,1523,1680 | Hai chiều là hai cạnh; Builder tái dùng canvas |
| E18 | waymark/lib/features/admin/draft_files_native.dart:4; draft_recovery.dart:9; Android MainActivity.kt:50,118,170 | SAF/app-private draft recovery, cleanup native hiện hữu |
| E19 | waymark/lib/services/navigation_history_service.dart:65,79,94,158,169 | Account-only Published history, lifecycle khác tracking |
| E20 | WayMark.Api/Models/PublishedMaps.cs:18,35; Contracts/PublishedMapDtos.cs:26,28,30 | Snapshot map/version và Node QR GUID mapping |
| E21 | WayMark.Api/Services/MapDrafts/MapProjectService.cs:166,225,245,252,273,288,290 | Validation, QR binding/revoke, immutable publication lookup |
| E22 | WayMark.Api/Controllers/MapProjectsController.cs:36; Data/PublishedMapModel.cs:23,34,43 | Public AllowAnonymous, composite version key/QR FK constraint |
| E23 | WayMark.Api/Contracts/MapDraftDtos.cs:8,19,42,61 | No edge polyline/north field; place polygon khác edge geometry |
| E24 | WayMark.Api/Data/WayMarkDbContext.cs:10,105,133,151 | SQL graph + snapshot stores cùng context nhưng khác models |
| E25 | WayMark.Api/Services/Routing/DijkstraRouter.cs:24,46,59; RoutePlanner.cs:35,44,72 | Backend directed meter routing; no version pin |
| E26 | WayMark.Api/Controllers/MapsController.cs:12,70; WayMarksController.cs:14,57; RoutesController.cs:11 | Legacy endpoints cần xác thực |
| E27 | waymark/android/app/build.gradle.kts:9,13,22,43; settings.gradle.kts:22; gradle.properties:2 | SDK delegation, Java17, AGP/Kotlin/cờ hiện tại |
| E28 | waymark/android/app/src/main/kotlin/com/example/waymark/MainActivity.kt:15,23,25,50,170 | FlutterActivity v2, hai MethodChannel, chưa sensors |
| E29 | waymark/android/app/src/main/AndroidManifest.xml:2,3,34; pubspec.yaml:21,30 | Permissions/dependencies hiện tại |
| E30 | C:/src/flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt:23,26,34 | Giá trị compile36/min24/target36 cục bộ |
| E31 | waymark/test/published_map_test.dart:62,144,190,217,297 | Tests nguồn cho public load, mismatch/revoke/offline, pinned reroute, UI flow |
| E32 | waymark/test/local_map_navigation_test.dart:514; multifloor_navigation_test.dart:193 | Tests snapshot không đổi khi editor thay đổi |
| E33 | waymark/test/navigation_qr_match_test.dart:13,53,144,153; scanner_camera_test.dart:156 | Node+floor, owner session, single-node explicit finish, camera lifecycle |
| E34 | WayMark.Api.Tests/PublishedMapTests.cs:107,183 | Test nguồn guest resolve/revoke và old QR pin qua draft revision |
| E35 | docs/UiUxPolishAiTimeout20261027.md:73,83,87,88,118 | Báo cáo kiểm thử trước và physical-phone backlog |
| E36 | waymark/build/ui-polish-evidence/full-tests.log:363; analyze.log:2; android-build.log:58; web-build.log:14 | Log có sẵn 357/~4, analyze, Android/Web build |

Một số dòng trong bảng viết rút gọn tên file trong cùng folder; toàn bộ source files đều thuộc workspace nêu ở đầu báo cáo.

### H2. Lệnh read-only đã chạy

Các nhóm dưới đây tóm tắt đúng thao tác; không chạy command build/test/launcher nào. Các batch đọc dùng Get-Content -Encoding UTF8, đánh số dòng trong PowerShell.

~~~powershell
git status --short
git status --porcelain=v1 -uall
git ls-files --cached --others --exclude-standard
rg --files -g AGENTS.md -g '*.sln' -g '*.csproj' -g 'README*' -g 'package.json' -g 'global.json' -g 'Directory.*'
rg --files waymark/lib waymark/android WayMark.Api docs waymark/test
Get-ChildItem -Name
Get-ChildItem D:\project -Filter AGENTS.md -Force
Get-ChildItem D:\ -Filter AGENTS.md -Force
Test-Path docs/WayMark_Live_Indoor_Navigation_Plan.md
Test-Path docs/LiveIndoorNavigationG0Readiness20261027.md
Get-Command adb,flutter,dart,dotnet -ErrorAction SilentlyContinue
Get-Content C:\src\flutter\bin\cache\flutter.version.json
rg -n 'compileSdkVersion|minSdkVersion|targetSdkVersion' C:/src/flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt
Get-Process adb -ErrorAction SilentlyContinue
Get-NetTCPConnection -State Listen -LocalPort 5037 -ErrorAction SilentlyContinue
& 'C:\Users\pc\AppData\Local\Android\sdk\platform-tools\adb.exe' devices -l
Get-NetTCPConnection -State Listen -LocalPort 5121 -ErrorAction SilentlyContinue
Get-FileHash -Algorithm SHA256 -LiteralPath <các file do git ls-files liệt kê>
~~~

Ngoài ra: rg theo các symbol/class/function trong H1; rg kiểm SensorManager/TYPE_STEP/TYPE_ROTATION/EventChannel/MethodChannel/ACTIVITY_RECOGNITION và provider/heading/polyline names trên lib/android/model/contract; đọc source tests và các dòng kết quả có sẵn trong logs; đọc local.properties **chỉ xuất sdk.dir/flutter.sdk** để tìm SDK; kiểm một số cổng thường dùng khác không thấy listener tương ứng. Get-Content C:/src/flutter/version không trả nội dung; version lấy từ cache JSON đã nêu.

Không tìm thấy AGENTS.md áp dụng cho source audit; chỉ có file trong design-reference/figma-make, ngoài phạm vi. Không đọc appsettings/secret store/connection-string credentials. Không gọi SQL hay API có side effect. Tra cứu web chỉ dùng Android documentation và trang package chính chủ ở C2/C3 để xác nhận đặc tính API/plugin, không dùng bài thứ cấp làm bằng chứng kỹ thuật.

### H3. Mức xác minh

| CONFIRMED | INFERRED | NOT VERIFIED |
|---|---|---|
| Model/parser/serializer/routing/renderer/QR control flow trong source; cấu hình SDK cục bộ; ADB không có thiết bị; log test/build cũ hiện diện | Native bridge là lựa chọn phù hợp; adapter GUID + straight-edge interpolation đủ cho corridor có kiểm chứng; overlay có thể repaint độc lập sau hook nhỏ | Sensor phần cứng thật; code bridge mới compile; permission/events/latency; bước/heading/stride/battery; PDR accuracy; live API/SQL và hành lang thực |

## I. Change Safety

- Không sửa Flutter/Kotlin/backend/UI/Gradle/Manifest/dependencies, không sửa dữ liệu/JSON/assets, không migration/SQL, không thay auth/QR/snapshot.
- Không chạy full build/test/launcher/E2E, không cài APK hoặc xin/grant thêm quyền, không restart ADB/API.
- Không git reset/clean/commit/push, không thay chính sách Windows.
- Không tạo/cập nhật Master Plan hoặc tài liệu Live Plan.
- Ngoại lệ ghi duy nhất: **docs/LiveIndoorNavigationG0Readiness20261027.md**, trước khi tạo đã xác nhận chưa tồn tại.
- Working tree ban đầu đã dirty: **42 modified + 280 untracked = 322 entries** với git status --porcelain=v1 -uall. Không có entry staged trong snapshot này.
- Phân bố entries trước audit: WayMark.Api.Tests 19; WayMark.Api 58; waymark 159; .kilo 1; docs 59; scripts 9; tools 17.
- Đã lưu baseline status đầy đủ trong bộ nhớ và hash SHA256 của **466 file Git tracked/untracked không bị ignore**, chỉ đọc bytes để hash, không xuất nội dung cấu hình nhạy cảm.
- Kết quả kiểm tra sau khi tạo báo cáo được ghi ở cuối mục này.

### I1. Git status trước audit — đầy đủ

<details>
<summary>322 entries có sẵn trước audit</summary>

~~~text
 M WayMark.Api.Tests/AdminAuthorizationTests.cs
 M WayMark.Api.Tests/WayMark.Api.Tests.csproj
 M WayMark.Api/Controllers/AuthController.cs
 M WayMark.Api/Controllers/MapsController.cs
 M WayMark.Api/Data/AuthRequests.cs
 M WayMark.Api/Data/WayMarkDbContext.cs
 M WayMark.Api/Data/WayMarkMigrations/WayMarkDbContextModelSnapshot.cs
 M WayMark.Api/Program.cs
 M WayMark.Api/Security/WayMarkSecurity.cs
 M WayMark.Api/Services/EmailTestOptions.cs
 M WayMark.Api/Services/ISmtpEmailService.cs
 M WayMark.Api/Services/SmtpEmailService.cs
 M WayMark.Api/WayMark.Api.csproj
 M WayMark.Api/appsettings.json
 M waymark/android/app/src/debug/AndroidManifest.xml
 M waymark/android/app/src/main/AndroidManifest.xml
 M waymark/android/app/src/main/kotlin/com/example/waymark/MainActivity.kt
 M waymark/android/gradle.properties
 M waymark/lib/features/admin/admin_page_shell.dart
 M waymark/lib/features/admin/draft_file_gateway.dart
 M waymark/lib/features/admin/draft_files.dart
 M waymark/lib/features/admin/draft_map.dart
 M waymark/lib/features/admin/draft_map_editor.dart
 M waymark/lib/features/admin/settings_page.dart
 M waymark/lib/features/auth/login/login_page.dart
 M waymark/lib/features/auth/register/register_page.dart
 M waymark/lib/features/history/history_page.dart
 M waymark/lib/features/home/home_page.dart
 M waymark/lib/features/navigation/manual_navigation.dart
 M waymark/lib/features/navigation/navigation_page.dart
 M waymark/lib/features/route/floor_plan_canvas.dart
 M waymark/lib/features/route/floor_route_map.dart
 M waymark/lib/features/route/route_preview_page.dart
 M waymark/lib/features/scanner/scanner_page.dart
 M waymark/lib/features/search/search_page.dart
 M waymark/lib/services/auth_api_service.dart
 M waymark/lib/services/auth_session.dart
 M waymark/pubspec.lock
 M waymark/pubspec.yaml
 M waymark/test/draft_floor_workflow_test.dart
 M waymark/test/draft_map_test.dart
 M waymark/test/settings_navigation_test.dart
?? .kilo/plans/1792510935397-forgot-password-plan.md
?? WayMark.Api.Tests/AccountSecuritySprint9Tests.cs
?? WayMark.Api.Tests/CoreSqlReadinessTests.cs
?? WayMark.Api.Tests/CreatorAuthorizationTests.cs
?? WayMark.Api.Tests/E2ESafetyTests.cs
?? WayMark.Api.Tests/EvidenceAccess.cs
?? WayMark.Api.Tests/LocalSqlDevelopmentTests.cs
?? WayMark.Api.Tests/ManagedImageStorageTests.cs
?? WayMark.Api.Tests/ManagedImageTestStorage.cs
?? WayMark.Api.Tests/MapDraftApiTests.cs
?? WayMark.Api.Tests/MapDraftImageBoundaryTests.cs
?? WayMark.Api.Tests/MapDraftModelTests.cs
?? WayMark.Api.Tests/MapDraftTestHost.cs
?? WayMark.Api.Tests/MapDraftValidationTests.cs
?? WayMark.Api.Tests/NavigationHistoryTests.cs
?? WayMark.Api.Tests/PersonalMapOnboardingTests.cs
?? WayMark.Api.Tests/PersonalQrPublishHotfixTests.cs
?? WayMark.Api.Tests/PublishedMapTests.cs
?? WayMark.Api/Contracts/MapDraftDtos.cs
?? WayMark.Api/Contracts/PublishedMapDtos.cs
?? WayMark.Api/Controllers/AccountSecurity.cs
?? WayMark.Api/Controllers/MapDraftsController.cs
?? WayMark.Api/Controllers/MapProjectsController.cs
?? WayMark.Api/Controllers/NavigationHistoryController.cs
?? WayMark.Api/Controllers/PersonalMapsController.cs
?? WayMark.Api/Data/E2EDesignTimeFactories.cs
?? WayMark.Api/Data/MapDraftModel.cs
?? WayMark.Api/Data/NavigationHistoryModel.cs
?? WayMark.Api/Data/PublishedMapModel.cs
?? WayMark.Api/Data/WayMarkDatabaseRegistration.cs
?? WayMark.Api/Data/WayMarkMigrations/20261020094848_AddMapDraftFoundation.Designer.cs
?? WayMark.Api/Data/WayMarkMigrations/20261020094848_AddMapDraftFoundation.cs
?? WayMark.Api/Data/WayMarkMigrations/20261020101304_BindMapImagesToDrafts.Designer.cs
?? WayMark.Api/Data/WayMarkMigrations/20261020101304_BindMapImagesToDrafts.cs
?? WayMark.Api/Data/WayMarkMigrations/20261023063955_AddPublishedMapProjects.Designer.cs
?? WayMark.Api/Data/WayMarkMigrations/20261023063955_AddPublishedMapProjects.cs
?? WayMark.Api/Data/WayMarkMigrations/20261025010000_AddNavigationHistory.Designer.cs
?? WayMark.Api/Data/WayMarkMigrations/20261025010000_AddNavigationHistory.cs
?? WayMark.Api/Data/WayMarkMigrations/20261026001522_ExtendNavigationHistoryLifecycle.Designer.cs
?? WayMark.Api/Data/WayMarkMigrations/20261026001522_ExtendNavigationHistoryLifecycle.cs
?? WayMark.Api/Models/MapDrafts.cs
?? WayMark.Api/Models/NavigationHistory.cs
?? WayMark.Api/Models/PublishedMaps.cs
?? WayMark.Api/Security/E2EConnectionInterceptor.cs
?? WayMark.Api/Security/E2ESafetyProfile.cs
?? WayMark.Api/Security/E2EStartupCheck.cs
?? WayMark.Api/Security/E2EStorageAccess.cs
?? WayMark.Api/Services/E2EDisabledEmail.cs
?? WayMark.Api/Services/MapDrafts/BoundedImageStream.cs
?? WayMark.Api/Services/MapDrafts/DraftAccess.cs
?? WayMark.Api/Services/MapDrafts/ManagedFileMapImageStorage.cs
?? WayMark.Api/Services/MapDrafts/ManagedMapImageOptions.cs
?? WayMark.Api/Services/MapDrafts/ManagedStoragePaths.cs
?? WayMark.Api/Services/MapDrafts/MapDraftExceptionFilter.cs
?? WayMark.Api/Services/MapDrafts/MapDraftRegistration.cs
?? WayMark.Api/Services/MapDrafts/MapDraftService.cs
?? WayMark.Api/Services/MapDrafts/MapDraftValidator.cs
?? WayMark.Api/Services/MapDrafts/MapImageCodec.cs
?? WayMark.Api/Services/MapDrafts/MapImageStorage.cs
?? WayMark.Api/Services/MapDrafts/MapProjectService.cs
?? WayMark.Api/Services/MapDrafts/PersonalMapAccess.cs
?? WayMark.Api/Services/MapDrafts/PersonalMapOnboarding.cs
?? WayMark.Api/appsettings.Development.storage.example.json
?? WayMark.Api/appsettings.MapDraftE2E.json
?? docs/AiMapAssistantPhase1.md
?? docs/AiMapAssistantPhase2.md
?? docs/AndroidMapBuilder9B1.md
?? docs/CoreIntegrationSprint1.md
?? docs/CoreSqlE2ESprint4.md
?? docs/CoreSqlE2ESprint6.md
?? docs/CoreSqlReadinessSprint3.md
?? docs/CoreVerificationSprint2.md
?? docs/HotfixQrPersonalPublish.md
?? docs/LocalMapMultiFloor9B2A.md
?? docs/LocalMapNavigation9B2.md
?? docs/MobileNavigationMvp.md
?? docs/P0RuntimeBuilderPublish.md
?? docs/Sprint10HistoryZoomStudio.md
?? docs/Sprint10SqlHistoryAcceptance.md
?? docs/Sprint7QuickStart.md
?? docs/Sprint8QuickStart.md
?? docs/Sprint9QuickStart.md
?? docs/UiUxPolishAiTimeout20261027.md
?? docs/WayMark_Master_Plan.md
?? docs/WayMark_Master_Plan_v1.2.md
?? docs/archive/WayMark_Master_Plan.md
?? docs/archive/WayMark_Master_Plan_v1.1.md
?? docs/archive/WayMark_Master_Plan_v1.3.md
?? docs/database/core-sprint3/PendingMapMigrations.idempotent.review.sql
?? docs/database/core-sprint3/PendingMapMigrations.review.sql
?? docs/database/core-sprint3/README.md
?? docs/database/core-sprint3/approval-plan.sample.json
?? docs/database/core-sprint3/review-manifest.json
?? docs/database/core-sprint6/ApprovalScope.md
?? docs/database/core-sprint6/PrepareWindowsRuntime.review.ps1
?? docs/database/core-sprint6/ProvisionRuntime.review.sql
?? docs/database/core-sprint6/ResumePublishedMigration.review.sql
?? docs/database/e2e/00-ReadOnlyInventory.sql
?? docs/database/e2e/01-ReadOnlyProtectedEvidence.sql
?? docs/database/e2e/10-CreateDatabase.sql
?? docs/database/e2e/20-CreateLogins.sql
?? docs/database/e2e/21-CreateUsersAndMigrationPermissions.sql
?? docs/database/e2e/30-AuthSchema.sql
?? docs/database/e2e/31-WayMarkSchema.sql
?? docs/database/e2e/40-RuntimePermissions.sql
?? docs/database/e2e/50-BootstrapIdentity.sql
?? docs/database/e2e/60-TestSitesAndMemberships.sql
?? docs/database/e2e/70-OptionalQrGraph.sql
?? docs/database/e2e/80-ReadOnlyVerification.sql
?? docs/database/e2e/90-SealMigratorDatabasePermissions.sql
?? docs/database/e2e/91-DisableMigratorLogin.sql
?? docs/database/e2e/DraftRoomFixture.json
?? docs/database/e2e/ReviewManifest.json
?? docs/database/sprint10/ApplyHistory.sql
?? docs/database/sprint10/BackupHistory.sql
?? docs/database/sprint10/NavigationHistory.review.sql
?? docs/database/sprint10/ProtectedFingerprint.sql
?? docs/development/FlutterMapDraftServer7B2C.md
?? docs/development/ManagedImageStorage7B2B.md
?? docs/development/MapPersistence7B2A.md
?? docs/development/MapPersistence7B2DExecutionPlan.md
?? docs/development/MapPersistence7B2DHotfix.md
?? docs/development/MapPersistence7B2DPreflight.md
?? scripts/Start-MapDraftE2E.ps1
?? scripts/Test-CoreSqlTls.ps1
?? scripts/mapdraft-e2e/E2EPlan.psm1
?? scripts/mapdraft-e2e/Export-ReviewedMigrations.ps1
?? scripts/mapdraft-e2e/Invoke-ApprovedE2EStep.ps1
?? scripts/mapdraft-e2e/Prepare-ApprovedE2EStorage.ps1
?? scripts/mapdraft-e2e/Set-ApprovedE2EEnvironment.ps1
?? scripts/mapdraft-e2e/Test-ExecutionPlanOffline.ps1
?? scripts/mapdraft-e2e/Update-PlanReviewManifest.ps1
?? tools/CoreIntegrationDemo/CoreIntegrationDemo.csproj
?? tools/CoreIntegrationDemo/Program.cs
?? tools/CoreSqlReadiness/CoreSqlReadiness.csproj
?? tools/CoreSqlReadiness/MigrationPreview.cs
?? tools/CoreSqlReadiness/Program.cs
?? tools/CoreSqlReadiness/ReadinessPlan.cs
?? tools/CoreSqlReadiness/SqlE2eWorkflow.cs
?? tools/CoreSqlReadiness/TestCreatorAccess.cs
?? tools/CoreSqlReadiness/TestCreatorBootstrap.cs
?? tools/CoreVerificationAudit/CoreVerificationAudit.csproj
?? tools/CoreVerificationAudit/Program.cs
?? tools/P0RuntimeSmoke/P0RuntimeSmoke.csproj
?? tools/P0RuntimeSmoke/Program.cs
?? tools/Sprint10Review/Program.cs
?? tools/Sprint10Review/Sprint10Review.csproj
?? tools/Sprint10SqlSmoke/Program.cs
?? tools/Sprint10SqlSmoke/Sprint10SqlSmoke.csproj
?? waymark/assets/demo_maps/ground.png
?? waymark/assets/demo_maps/hospital_2a.json
?? waymark/assets/demo_maps/level1.png
?? waymark/design-reference/figma-make/.figma/make/analyze-routes
?? waymark/design-reference/figma-make/.figma/make/deploy
?? waymark/design-reference/figma-make/.figma/make/deploy-preview
?? waymark/design-reference/figma-make/.figma/make/dev
?? waymark/design-reference/figma-make/.figma/make/dev.json
?? waymark/design-reference/figma-make/.figma/make/format
?? waymark/design-reference/figma-make/.figma/make/install
?? waymark/design-reference/figma-make/.figma/make/langserver
?? waymark/design-reference/figma-make/.figma/make/site.json
?? waymark/design-reference/figma-make/.gitattributes
?? waymark/design-reference/figma-make/.gitignore
?? waymark/design-reference/figma-make/.mise.toml
?? waymark/design-reference/figma-make/AGENTS.md
?? waymark/design-reference/figma-make/CLAUDE.md
?? waymark/design-reference/figma-make/WAYMARK-PROTOTYPE.md
?? waymark/design-reference/figma-make/index.html
?? waymark/design-reference/figma-make/package.json
?? waymark/design-reference/figma-make/pnpm-lock.yaml
?? waymark/design-reference/figma-make/src/App.tsx
?? waymark/design-reference/figma-make/src/components/AdminLayout.tsx
?? waymark/design-reference/figma-make/src/components/HospitalMap.tsx
?? waymark/design-reference/figma-make/src/components/MobileFrame.tsx
?? waymark/design-reference/figma-make/src/components/RoutePreferences.tsx
?? waymark/design-reference/figma-make/src/components/WaymarkUI.tsx
?? waymark/design-reference/figma-make/src/components/map-builder/AIAnalysis.tsx
?? waymark/design-reference/figma-make/src/components/map-builder/MapCanvas.tsx
?? waymark/design-reference/figma-make/src/components/map-builder/model.ts
?? waymark/design-reference/figma-make/src/index.css
?? waymark/design-reference/figma-make/src/main.tsx
?? waymark/design-reference/figma-make/src/pages/admin/Dashboard.tsx
?? waymark/design-reference/figma-make/src/pages/admin/MapBuilder.tsx
?? waymark/design-reference/figma-make/src/pages/admin/QrManager.tsx
?? waymark/design-reference/figma-make/src/pages/admin/Settings.tsx
?? waymark/design-reference/figma-make/src/pages/mobile/History.tsx
?? waymark/design-reference/figma-make/src/pages/mobile/Home.tsx
?? waymark/design-reference/figma-make/src/pages/mobile/Login.tsx
?? waymark/design-reference/figma-make/src/pages/mobile/Navigation.tsx
?? waymark/design-reference/figma-make/src/pages/mobile/Register.tsx
?? waymark/design-reference/figma-make/src/pages/mobile/RoutePreview.tsx
?? waymark/design-reference/figma-make/src/pages/mobile/Scanner.tsx
?? waymark/design-reference/figma-make/src/pages/mobile/Search.tsx
?? waymark/design-reference/figma-make/src/routes.tsx
?? waymark/design-reference/figma-make/src/vite-env.d.ts
?? waymark/design-reference/figma-make/tsconfig.json
?? waymark/design-reference/figma-make/vite.config.ts
?? waymark/lib/features/admin/ai_graph_review.dart
?? waymark/lib/features/admin/ai_graph_review_panel.dart
?? waymark/lib/features/admin/ai_map_assistant_page.dart
?? waymark/lib/features/admin/ai_timeout_control.dart
?? waymark/lib/features/admin/create_map_page.dart
?? waymark/lib/features/admin/draft_exit_guard.dart
?? waymark/lib/features/admin/draft_exit_guard_stub.dart
?? waymark/lib/features/admin/draft_exit_guard_web.dart
?? waymark/lib/features/admin/draft_files_native.dart
?? waymark/lib/features/admin/draft_map_editor_mobile.dart
?? waymark/lib/features/admin/draft_map_editor_project.dart
?? waymark/lib/features/admin/draft_recovery.dart
?? waymark/lib/features/admin/draft_server_session.dart
?? waymark/lib/features/admin/floor_image_cleanup.dart
?? waymark/lib/features/admin/floor_image_cleanup_page.dart
?? waymark/lib/features/admin/local_map_project.dart
?? waymark/lib/features/admin/map_project_cloud_page.dart
?? waymark/lib/features/admin/my_maps_page.dart
?? waymark/lib/features/admin/project_publish_state.dart
?? waymark/lib/features/auth/account_security_page.dart
?? waymark/lib/features/auth/logout.dart
?? waymark/lib/features/auth/password_reset_page.dart
?? waymark/lib/features/navigation/local_map_navigation.dart
?? waymark/lib/features/profile/account_widgets.dart
?? waymark/lib/features/profile/profile_page.dart
?? waymark/lib/features/route/demo_floor_plan.dart
?? waymark/lib/features/route/map_paint_scale.dart
?? waymark/lib/features/scanner/public_map_entry_page.dart
?? waymark/lib/features/search/local_map_search_page.dart
?? waymark/lib/models/account_profile.dart
?? waymark/lib/models/ai_graph_proposal.dart
?? waymark/lib/models/ai_map_suggestion.dart
?? waymark/lib/services/ai_map_provider.dart
?? waymark/lib/services/ai_timeout_preferences.dart
?? waymark/lib/services/ai_timeout_store.dart
?? waymark/lib/services/ai_timeout_store_native.dart
?? waymark/lib/services/ai_timeout_store_web.dart
?? waymark/lib/services/map_draft_api_service.dart
?? waymark/lib/services/navigation_history_service.dart
?? waymark/lib/services/published_map_api_service.dart
?? waymark/test/ai_graph_assistant_test.dart
?? waymark/test/ai_map_assistant_test.dart
?? waymark/test/ai_timeout_preferences_test.dart
?? waymark/test/android_map_builder_test.dart
?? waymark/test/core_verification_qr_test.dart
?? waymark/test/creator_access_message_test.dart
?? waymark/test/fixtures/local_navigation_fixture.dart
?? waymark/test/fixtures/map_draft_fixture.dart
?? waymark/test/fixtures/multifloor_fixture.dart
?? waymark/test/fixtures/personal_qr_http_fixture.dart
?? waymark/test/fixtures/published_map_fixture.dart
?? waymark/test/floor_image_cleanup_test.dart
?? waymark/test/live_sql_public_navigation_test.dart
?? waymark/test/local_map_navigation_test.dart
?? waymark/test/map_draft_editor_server_test.dart
?? waymark/test/map_draft_server_test.dart
?? waymark/test/map_project_cloud_test.dart
?? waymark/test/map_zoom_smoke_test.dart
?? waymark/test/mobile_demo_map_test.dart
?? waymark/test/multifloor_navigation_test.dart
?? waymark/test/node_first_polish_test.dart
?? waymark/test/p0_builder_state_test.dart
?? waymark/test/p0_live_sql_navigation_test.dart
?? waymark/test/password_reset_smoke_test.dart
?? waymark/test/profile_settings_smoke_test.dart
?? waymark/test/published_map_test.dart
?? waymark/test/qr_publish_hotfix_test.dart
?? waymark/test/self_service_creator_test.dart
?? waymark/test/sprint10_history_test.dart
?? waymark/test/sprint10_studio_test.dart
?? waymark/test/sprint10_zoom_test.dart
?? waymark/test/sprint9_account_history_test.dart
?? waymark/test/ui_polish_builder_test.dart
?? waymark/tool/android_map_builder.dart
?? waymark/tool/generate_custom_plan_test.dart
?? waymark/tool/generate_demo_floor_plans_test.dart
?? waymark/tool/generate_multifloor_test.dart
?? waymark/tool/mobile_demo_data.dart
?? waymark/tool/mobile_map_demo.dart
?? waymark/tool/node_polish_fixture_test.dart
?? waymark/tool/public_map_visitor.dart
?? waymark/tool/public_qr_export_check.dart
?? waymark/tool/real_floor_cleanup_test.dart
~~~

</details>

### I2. Kiểm tra sau khi tạo báo cáo

**Đã kiểm tra sau khi tạo báo cáo:**

| Kiểm tra | Trước | Sau | Kết quả |
|---|---:|---:|---|
| Modified entries | 42 | 42 | Giữ nguyên |
| Untracked entries | 280 | 281 | Chỉ thêm báo cáo |
| Tổng git status entries | 322 | 323 | Không mất hoặc đổi entry có sẵn |
| File trong baseline SHA256 | 466 | 466 file cũ + 1 báo cáo | **466/466 file cũ có SHA256 giữ nguyên** |

Git status sau = toàn bộ snapshot I1 giữ nguyên + đúng dòng sau; đây là biểu diễn đầy đủ bằng delta, không gộp các thư mục untracked:

~~~text
?? docs/LiveIndoorNavigationG0Readiness20261027.md
~~~

Không có dòng bị xóa khỏi status trước. So sánh manifest SHA256 trước/sau chỉ thêm file báo cáo, không có file cũ đổi hash. Không quan sát thay đổi bất ngờ trong tập Git tracked/untracked được kiểm. File ignored/build/cache không thuộc baseline hash này; G0 không chạy build/test/launcher hay chủ động ghi vào chúng.

### I3. Bước xác minh thiết bị còn thiếu

Có thể bắt đầu Sprint 1 với fake ngay. Khi có Android thật đã kết nối và người dùng tự chấp thuận USB debugging, kiểm read-only ngắn:

~~~powershell
adb devices -l
adb -s <serial> shell getprop ro.product.model
adb -s <serial> shell getprop ro.build.version.release
adb -s <serial> shell getprop ro.build.version.sdk
adb -s <serial> shell getprop ro.kernel.qemu
adb -s <serial> shell dumpsys sensorservice
~~~

Chỉ tóm tắt model/OS và danh sách sensor cần thiết, không đưa serial hoặc dump thông tin hoạt động của app khác vào báo cáo công khai. Capability listing là bằng chứng sensor được hệ thống công bố, chưa chứng minh permission/registration/đếm bước/latency của WayMark; những mục đó cần debug probe của Sprint 1 và phép thử thật. Không cần cung cấp model điện thoại trước để bắt đầu code infrastructure.

