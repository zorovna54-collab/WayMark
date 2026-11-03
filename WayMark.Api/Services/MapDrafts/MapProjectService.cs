using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using WayMark.Api.Contracts;
using WayMark.Api.Data;
using WayMark.Api.Models;
using WayMark.Api.Security;

namespace WayMark.Api.Services.MapDrafts;

public sealed class MapProjectService(WayMarkDbContext db, IDraftSiteAccess access, MapDraftService drafts, TimeProvider clock, PersonalMapAccess personal)
{
    public const int MaxBytes = 8 * 1024 * 1024;
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private static DraftOperationException Invalid(string message) => new(400, "invalid_project", message);
    private static DraftOperationException Conflict() => new(409, "project_version_conflict", "Project changed; reload before saving or publishing");
    private static DraftOperationException Missing() => new(404, "map_not_found", "Map or publication was not found");
    private static bool Text(string? s, int limit) => !string.IsNullOrWhiteSpace(s) && s == s.Trim() && s.Length <= limit && !s.Any(char.IsControl);
    private static string Subject(ClaimsPrincipal user) => user.FindFirstValue(ClaimTypes.NameIdentifier)
        ?? throw new DraftOperationException(403, "map_access_denied", "Map access denied");
    private static ProjectContentDto Content(MapProject p) => JsonSerializer.Deserialize<ProjectContentDto>(p.ContentJson, Json) ?? throw Missing();
    private static PublicMapDto Public(MapPublication p) => new(p.MapId, p.Version, p.Name,
        JsonSerializer.Deserialize<ProjectContentDto>(p.ContentJson, Json) ?? throw Missing(), p.PublishedAt);
    private static NodeQrDto Qr(MapNodeQr q) => new(q.Id, q.MapId, q.FloorKey, q.NodeId, q.DraftVersion,
        q.PublishedVersion, "WMQR1:" + q.Token, q.IsActive);
    private async Task<MapProjectDto> Dto(ClaimsPrincipal user, MapProject p, CancellationToken ct) {
        var isPersonal = await IsPersonal(p.SiteId, ct);
        return new(p.Id, p.Name, p.Version, p.SiteId, p.BuildingId, Content(p), p.UpdatedAt,
            isPersonal ? p.OwnerId == Subject(user) && await personal.OwnsAsync(user, p.SiteId, ct) : await CanPublishFacility(user, p.SiteId, ct),
            isPersonal ? "PersonalDemo" : "FacilityScoped");
    }
    private Task<bool> IsPersonal(int siteId, CancellationToken ct) => db.Sites.AsNoTracking()
        .AnyAsync(s => s.Id == siteId && s.Code.StartsWith(PersonalMapAccess.Prefix), ct);
    private async Task<bool> CanPublishFacility(ClaimsPrincipal user, int siteId, CancellationToken ct) {
        var roles = await personal.RolesAsync(user, ct);
        return roles.Contains(WayMarkSecurity.AdminRole) || roles.Contains(WayMarkSecurity.SiteManagerRole)
            || roles.Contains(WayMarkSecurity.SitePublisherRole(siteId));
    }

    private async Task<MapProject> Owned(ClaimsPrincipal user, Guid id, CancellationToken ct)
    {
        var p = await db.MapProjects.SingleOrDefaultAsync(x => x.Id == id, ct) ?? throw Missing();
        if (p.OwnerId != Subject(user) && !(await personal.RolesAsync(user, ct)).Contains(WayMarkSecurity.SiteManagerRole))
            throw new DraftOperationException(403, "map_access_denied", "Map access denied");
        foreach (var f in Content(p).Floors)
        {
            var scope = await access.RequireAsync(user, f.FloorId, ct);
            if (scope.SiteId != p.SiteId || scope.BuildingId != p.BuildingId)
                throw new DraftOperationException(403, "map_access_denied", "Map scope changed");
        }
        return p;
    }

    public async Task<IReadOnlyList<MapProjectSummaryDto>> ListAsync(ClaimsPrincipal user, CancellationToken ct)
    {
        var owner = Subject(user);
        var manager = (await personal.RolesAsync(user, ct)).Contains(WayMarkSecurity.SiteManagerRole);
        var ids = await db.MapProjects.AsNoTracking().Where(x => x.OwnerId == owner || (manager
            && db.SiteMapMemberships.Any(m => m.SiteId == x.SiteId && m.UserId == owner && m.IsActive && m.CanEditDrafts)))
            .OrderBy(x => x.Id).Take(100).Select(x => x.Id).ToListAsync(ct);
        var list = new List<MapProjectSummaryDto>();
        foreach (var id in ids)
            try { var p = await Owned(user, id, ct);
                var published = await db.MapPublications.Where(v => v.MapId == id).OrderByDescending(v => v.Version).Select(v => (long?)v.Version).FirstOrDefaultAsync(ct);
                list.Add(new(p.Id, p.Name, p.Version, p.LocalProjectId, published, await IsPersonal(p.SiteId, ct) ? "PersonalDemo" : "FacilityScoped")); }
            catch (DraftOperationException ex) when (ex.Status == 403) { /* Revoked Site membership is not a grant. */ }
        return list;
    }
    public async Task<MapProjectDto> GetAsync(ClaimsPrincipal user, Guid id, CancellationToken ct) => await Dto(user, await Owned(user, id, ct), ct);

    public async Task<PublishReadinessDto> ReadinessAsync(ClaimsPrincipal user, Guid id, IMapImageStorage images, CancellationToken ct)
    {
        var p = await Owned(user, id, ct); var c = Content(p); var dto = await Dto(user, p, ct);
        var checks = new List<PublishCheckDto>();
        var nodes = c.Floors.SelectMany(f => f.Content.Nodes!).ToList();
        var edges = c.Floors.SelectMany(f => f.Content.Edges!).ToList();
        checks.Add(new("publish_permission", dto.CanPublish, dto.CanPublish ? "Quyền xuất bản hợp lệ." : "Chưa có quyền xuất bản bản đồ này."));
        try {
            if (images is ManagedFileMapImageStorage disk) disk.ValidateConfiguration();
            checks.Add(new("image_storage_configuration", true, "Cấu hình kho ảnh hợp lệ; quyền ghi filesystem chỉ được xác nhận khi upload thành công."));
        } catch (DraftOperationException e) {
            checks.Add(new(e.Code, false, e.Code == "image_storage_unavailable"
                ? "Backend chưa bật kho ảnh. Chưa thể lưu ảnh/graph để Publish; cấu hình MapImages ngoài Git rồi restart API."
                : "Cấu hình kho ảnh chưa hợp lệ. Operator cần kiểm tra root/quota; không đổi database hoặc quyền tài khoản."));
        }
        checks.Add(new("saved_nodes", nodes.Count > 0, nodes.Count > 0 ? $"Đã lưu {nodes.Count} node trên server." : "Chưa có Node được lưu trên Server; workspace v1 trống chưa phải graph đã lưu."));
        var hasImages = c.Floors.All(f => f.Content.ImageAssetId.HasValue);
        checks.Add(new("floor_images", hasImages, hasImages ? "Các tầng có tham chiếu ảnh." : "Chưa lưu ảnh cho mọi tầng."));
        var hasDestination = nodes.Any(n => n.SearchableAsDestination) || c.Floors.Any(f => f.Content.Places!.Count > 0);
        checks.Add(new("searchable_destination", hasDestination, hasDestination ? "Có điểm đến tìm kiếm được." : "Chưa có Node đích hoặc Room/cửa hợp lệ."));
        var meters = edges.Count + c.Links.Count > 0 && edges.All(e => e.DistanceMeters is > 0);
        checks.Add(new("edge_meters", meters, meters ? "Cạnh có khoảng cách mét." : "Cần cạnh có hướng và khoảng cách mét hợp lệ."));
        var qrs = await db.MapNodeQrs.AsNoTracking().Where(q => q.MapId == id && q.DraftVersion == p.Version && q.IsActive).ToListAsync(ct);
        var starts = qrs.Where(q => c.Floors.Any(f => f.Id == q.FloorKey && f.Content.Nodes!.Any(n => n.Id == q.NodeId))).Select(q => q.NodeId).ToHashSet();
        checks.Add(new("qr_start", starts.Count > 0, starts.Count > 0 ? "Có QR active đúng phiên bản đã lưu." : "Chọn một node đã lưu rồi tạo QR; không cần node loại Start và không cần Publish trước."));
        var reachable = starts.Count > 0 && ReachableDestination(c, starts);
        checks.Add(new("directed_route", reachable, reachable ? "Có tuyến có hướng từ QR tới đích." : "Chưa có tuyến hợp lệ từ QR Node đến Destination; kiểm tra QR, đích, hướng cạnh và active."));
        try {
            await Validate(user, c, true, ct);
            checks.Add(new("saved_graph_validation", true, "Graph và ảnh đã lưu hợp lệ cho xuất bản; chưa xác minh an toàn thực địa."));
        } catch (DraftOperationException e) {
            checks.Add(new("saved_graph_validation", false, e.Code == "invalid_project" ? e.Message switch {
                "Every published floor needs a retrievable floor image" => "Ảnh tầng chưa được lưu trên máy chủ hoặc chưa truy xuất được.",
                "At least one searchable destination is required" => "Chưa có điểm đến tìm kiếm được. Bật điểm đến cho Node hoặc dùng Room/cửa hợp lệ.",
                "Published navigation needs at least one explicit graph edge" => "Chưa có cạnh nối để dẫn đường.",
                "Measure all edge distances in meters before publication" => "Cần nhập khoảng cách mét cho các cạnh trước khi xuất bản.",
                _ => "Graph đã lưu chưa hợp lệ; kiểm tra Node/Edge, tầng, ảnh và liên kết."
            } : "Chưa xác minh được ảnh/graph đã lưu; kiểm tra storage và tham chiếu tầng."));
        }
        return new(id, p.Version, nodes.Count, edges.Count + c.Links.Count, checks);
    }

    private static bool ReachableDestination(ProjectContentDto c, HashSet<Guid> starts)
    {
        var destinations = c.Floors.SelectMany(f => f.Content.Nodes!).Where(n => n.SearchableAsDestination).Select(n => n.Id)
            .Concat(c.Floors.SelectMany(f => f.Content.Places!).SelectMany(p => p.EntranceNodeIds!)).ToHashSet();
        var edges = c.Floors.SelectMany(f => f.Content.Edges!).Where(e => e.IsActive).Select(e => (e.FromNodeId, e.ToNodeId))
            .Concat(c.Links.Where(e => e.Active).Select(e => (e.FromNode, e.ToNode))).ToLookup(e => e.Item1, e => e.Item2);
        var visited = new HashSet<Guid>(starts); var queue = new Queue<Guid>(starts);
        while (queue.TryDequeue(out var n)) foreach (var to in edges[n]) if (visited.Add(to)) queue.Enqueue(to);
        return visited.Any(destinations.Contains);
    }

    public async Task<MapProjectDto> CreateAsync(ClaimsPrincipal user, CreateMapProjectRequest r, CancellationToken ct)
    {
        if (!Text(r.Name, 200)) throw Invalid("Map name is required (max 200)");
        var scope = await Validate(user, r.Content, false, ct);
        var owner = Subject(user);
        var existing = await db.MapProjects.SingleOrDefaultAsync(x => x.OwnerId == owner && x.LocalProjectId == r.Content.Id, ct);
        if (existing is not null)
        {
            if (existing.Name == r.Name && existing.ContentJson == JsonSerializer.Serialize(r.Content, Json)) return await Dto(user, existing, ct);
            throw Conflict(); // Never overwrite a changed document on a repeated create.
        }
        var p = new MapProject { Id = Guid.NewGuid(), LocalProjectId = r.Content.Id, SiteId = scope.SiteId,
            BuildingId = scope.BuildingId, OwnerId = owner, Name = r.Name, Version = 1,
            ContentJson = JsonSerializer.Serialize(r.Content, Json), UpdatedAt = clock.GetUtcNow() };
        db.MapProjects.Add(p);
        await db.SaveChangesAsync(ct);
        return await Dto(user, p, ct);
    }
    public async Task<MapProjectDto> SaveAsync(ClaimsPrincipal user, Guid id, SaveMapProjectRequest r, CancellationToken ct)
    {
        var p = await Owned(user, id, ct);
        if (r.Content is not null && r.Content.Info is null && Content(p).Info is not null)
            r = r with { Content = r.Content with { Info = Content(p).Info } };
        if (r.ExpectedVersion != p.Version || p.Version == long.MaxValue) throw Conflict();
        if (!Text(r.Name, 200) || r.Content?.Id != p.LocalProjectId) throw Invalid("Map name or stable project ID changed");
        var scope = await Validate(user, r.Content, false, ct);
        if (scope.BuildingId != p.BuildingId || scope.SiteId != p.SiteId) throw Invalid("A saved project cannot move to another Building/Site");
        var json = JsonSerializer.Serialize(r.Content, Json);
        if (p.ContentJson == json && p.Name == r.Name) return await Dto(user, p, ct);
        p.ContentJson = json; p.Name = r.Name; p.Version++; p.UpdatedAt = clock.GetUtcNow();
        await Persist(ct);
        return await Dto(user, p, ct);
    }
    private async Task Persist(CancellationToken ct)
    {
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateConcurrencyException) { throw Conflict(); }
    }

    private async Task<DraftFloorScope> Validate(ClaimsPrincipal user, ProjectContentDto? content, bool publish, CancellationToken ct)
    {
        if (content is null || content.Id == Guid.Empty || content.Floors is null || content.Links is null
            || content.Floors.Count is < 1 or > 12 || content.Links.Count > 1000) throw Invalid("Project needs 1–12 floors and bounded links");
        if (Encoding.UTF8.GetByteCount(JsonSerializer.Serialize(content, Json)) > MaxBytes) throw Invalid("Project is too large");
        var ids = new HashSet<Guid> { content.Id }; var sqlFloors = new HashSet<int>();
        var codes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var nodes = new Dictionary<Guid, (ProjectFloorDto Floor, DraftNodeDto Node)>();
        var pairs = new HashSet<(Guid, Guid)>();
        DraftFloorScope? first = null;
        var edges = 0;
        foreach (var f in content.Floors)
        {
            if (f is null || f.Id == Guid.Empty || !ids.Add(f.Id) || !sqlFloors.Add(f.FloorId)
                || !Text(f.Name, 200) || !Text(f.Code, 30) || !codes.Add(f.Code)) throw Invalid("Invalid/duplicate floor identity or label");
            var scope = await access.RequireAsync(user, f.FloorId, ct);
            first ??= scope;
            if (scope.BuildingId != first.BuildingId || scope.SiteId != first.SiteId) throw Invalid("Floors must belong to one authorized Building/Site");
            var valid = await drafts.ValidateAsync(user, f.FloorId, f.Content, ct);
            if (!valid.IsValid) throw Invalid(valid.Errors[0].Message);
            if (f.Content.Transitions!.Count != 0) throw Invalid("Project transitions must use the project link collection");
            if (publish && f.Content.ImageAssetId is null) throw Invalid("Every published floor needs a retrievable floor image");
            foreach (var n in f.Content.Nodes!)
            {
                if (!ids.Add(n.Id) || !nodes.TryAdd(n.Id, (f, n))) throw Invalid("Node identities must be globally unique in project");
            }
            foreach (var e in f.Content.Edges!)
            {
                if (!ids.Add(e.Id)) throw Invalid("Duplicate graph identity");
                if (publish && e.DistanceMeters is null) throw Invalid("Measure all edge distances in meters before publication");
                edges++;
            }
            foreach (var room in f.Content.Places!) if (!ids.Add(room.Id)) throw Invalid("Duplicate Room identity");
        }
        foreach (var link in content.Links)
        {
            if (link is null || link.Id == Guid.Empty || !ids.Add(link.Id) || link.FromFloor == link.ToFloor
                || !nodes.TryGetValue(link.FromNode, out var from) || !nodes.TryGetValue(link.ToNode, out var to)
                || from.Floor.Id != link.FromFloor || to.Floor.Id != link.ToFloor || !pairs.Add((link.FromNode, link.ToNode))
                || link.Type is not ("Stairs" or "Elevator") || from.Node.NodeType.ToString() != link.Type || to.Node.NodeType.ToString() != link.Type
                || link.DistanceMeters <= 0 || link.DistanceMeters > 999999999.999m || decimal.Round(link.DistanceMeters, 3) != link.DistanceMeters
                || link.Accessibility != "Unknown") throw Invalid("Invalid explicit directed floor transition");
        }
        if (nodes.Count > 2000 || edges + content.Links.Count > 10000) throw Invalid("Project exceeds 2000 nodes / 10000 edges");
        if (publish && edges + content.Links.Count == 0) throw Invalid("Published navigation needs at least one explicit graph edge");
        if (publish && !nodes.Values.Any(n => n.Node.SearchableAsDestination) && !content.Floors.Any(f => f.Content.Places!.Count > 0))
            throw Invalid("At least one searchable destination is required");
        if (content.Info is { } info && (!Text(info.PlaceName, 200) || info.Purpose is not ("PersonalDemo" or "FacilityProposal")
            || (info.Description is not null && !Text(info.Description, 1000)) || info.Kind != "PersonalDemo"
            || !await IsPersonal(first!.SiteId, ct))) throw Invalid("Personal metadata cannot grant facility authority");
        if (content.Info is null && await IsPersonal(first!.SiteId, ct)) throw Invalid("Personal publication metadata is required");
        return first!;
    }

    public async Task<IReadOnlyList<NodeQrDto>> QrsAsync(ClaimsPrincipal user, Guid id, CancellationToken ct)
    {
        await Owned(user, id, ct);
        return (await db.MapNodeQrs.AsNoTracking().Where(x => x.MapId == id).OrderBy(x => x.Id).Take(2000).ToListAsync(ct)).Select(Qr).ToArray();
    }
    public async Task<NodeQrDto> CreateQrAsync(ClaimsPrincipal user, Guid id, CreateNodeQrRequest r, CancellationToken ct)
    {
        var p = await Owned(user, id, ct);
        if (p.Version != r.ExpectedVersion) throw Conflict();
        var floor = Content(p).Floors.SingleOrDefault(f => f.Id == r.FloorKey);
        if (floor?.Content.Nodes?.Any(n => n.Id == r.NodeId) != true) throw Invalid("QR must reference an existing stable node of this floor");
        var existing = await db.MapNodeQrs.SingleOrDefaultAsync(x => x.MapId == id && x.FloorKey == r.FloorKey && x.NodeId == r.NodeId
            && x.DraftVersion == p.Version && x.IsActive, ct);
        if (existing is not null)
        {
            if (existing.PublishedVersion is null && await db.MapPublications.AnyAsync(x => x.MapId == id && x.Version == p.Version, ct))
            { existing.PublishedVersion = p.Version; await Persist(ct); }
            return Qr(existing);
        }
        var q = new MapNodeQr { Id = Guid.NewGuid(), MapId = id, FloorKey = r.FloorKey, NodeId = r.NodeId,
            DraftVersion = p.Version, Token = Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(32)),
            CreatedBy = Subject(user), CreatedAt = clock.GetUtcNow(),
            PublishedVersion = await db.MapPublications.AnyAsync(x => x.MapId == id && x.Version == p.Version, ct) ? p.Version : null };
        db.MapNodeQrs.Add(q); await db.SaveChangesAsync(ct); return Qr(q);
    }
    public async Task<NodeQrDto> RevokeAsync(ClaimsPrincipal user, Guid id, Guid qrId, CancellationToken ct)
    {
        await Owned(user, id, ct);
        var q = await db.MapNodeQrs.SingleOrDefaultAsync(x => x.Id == qrId && x.MapId == id, ct) ?? throw Missing();
        q.IsActive = false; q.RevokedAt ??= clock.GetUtcNow(); await db.SaveChangesAsync(ct); return Qr(q);
    }

    public async Task<PublicMapDto> PublishAsync(ClaimsPrincipal user, Guid id, PublishMapRequest r, CancellationToken ct)
    {
        var p = await Owned(user, id, ct);
        // Editing membership/email verification alone does not authorize public
        // disclosure on behalf of a facility. Require explicit Site publish grant.
        var personalSite = await IsPersonal(p.SiteId, ct);
        if (personalSite ? p.OwnerId != Subject(user) || !await personal.OwnsAsync(user, p.SiteId, ct)
            : !await CanPublishFacility(user, p.SiteId, ct))
            throw new DraftOperationException(403, "site_publish_denied", "Publication requires an explicit grant for this Site");
        if (r.ExpectedVersion != p.Version) throw Conflict();
        if (!r.ConfirmPublic) throw Invalid("Explicit public disclosure confirmation is required");
        var old = await db.MapPublications.AsNoTracking().SingleOrDefaultAsync(x => x.MapId == id && x.Version == p.Version, ct);
        if (old is not null) return Public(old);
        var c = Content(p);
        await Validate(user, c, true, ct);
        var qrs = await db.MapNodeQrs.Where(x => x.MapId == id && x.DraftVersion == p.Version && x.IsActive).ToListAsync(ct);
        var byId = c.Floors.SelectMany(f => f.Content.Nodes!.Select(n => (f.Id, Node: n))).ToDictionary(n => n.Node.Id);
        var starts = qrs.Where(q => byId.TryGetValue(q.NodeId, out var n) && n.Id == q.FloorKey).Select(q => q.NodeId).ToHashSet();
        if (starts.Count == 0) throw Invalid("Create an active QR for a start node of this saved version before publishing");
        if (!ReachableDestination(c, starts)) throw Invalid("No directed path from a QR start to a searchable destination");
        // Remove provenance of unrelated production QR/nodes from public read contract.
        var snapshot = c with { Floors = c.Floors.Select(f => f with { Content = f.Content with {
            Nodes = f.Content.Nodes!.Select(n => n with { SourceNodeId = null, ExistingWayMarkCode = null }).ToArray()
        }}).ToArray() };
        var publication = new MapPublication { MapId = id, Version = p.Version, Name = p.Name,
            ContentJson = JsonSerializer.Serialize(snapshot, Json), PublishedBy = Subject(user), PublishedAt = clock.GetUtcNow() };
        db.MapPublications.Add(publication);
        foreach (var asset in c.Floors.Select(f => f.Content.ImageAssetId!.Value).Distinct())
            db.MapPublicationImages.Add(new() { MapId = id, Version = p.Version, AssetId = asset });
        foreach (var q in qrs.Where(q => starts.Contains(q.NodeId))) q.PublishedVersion = p.Version;
        // Force a concurrency-token checked head write along with publication and QR pins.
        p.UpdatedAt = clock.GetUtcNow(); db.Entry(p).Property(x => x.UpdatedAt).IsModified = true;
        await Persist(ct);
        return Public(publication);
    }

    public async Task<PublicMapDto> PublicAsync(Guid id, long version, CancellationToken ct) => Public(
        await db.MapPublications.AsNoTracking().SingleOrDefaultAsync(x => x.MapId == id && x.Version == version, ct) ?? throw Missing());
    public async Task<ResolveMapQrDto> ResolveAsync(string token, CancellationToken ct)
    {
        if (!Regex.IsMatch(token, "^[a-f0-9]{64}$", RegexOptions.CultureInvariant)) throw Missing();
        var q = await db.MapNodeQrs.AsNoTracking().SingleOrDefaultAsync(x => x.Token == token, ct) ?? throw Missing();
        if (!q.IsActive) throw new DraftOperationException(410, "qr_revoked", "This QR has been revoked; do not use it for positioning");
        if (q.PublishedVersion is not long version) throw new DraftOperationException(409, "map_not_published", "QR map version has not been published");
        var p = await PublicAsync(q.MapId, version, ct);
        var node = p.Content.Floors.SingleOrDefault(f => f.Id == q.FloorKey)?.Content.Nodes?.SingleOrDefault(n => n.Id == q.NodeId);
        if (node is null) throw new DraftOperationException(410, "qr_node_missing", "QR node is unavailable in its pinned snapshot");
        return new(q.MapId, version, q.FloorKey, q.NodeId, p.Name, node.DisplayName ?? node.Name);
    }
    public async Task<(Stream Content, string Mime)> PublicImageAsync(Guid id, long version, Guid assetId, CancellationToken ct)
    {
        if (!await db.MapPublicationImages.AsNoTracking().AnyAsync(x => x.MapId == id && x.Version == version && x.AssetId == assetId, ct)) throw Missing();
        var asset = await db.FloorMapImageAssets.AsNoTracking().SingleOrDefaultAsync(x => x.Id == assetId, ct) ?? throw Missing();
        return (await drafts.OpenVerifiedImageAsync(asset, ct), asset.MimeType);
    }
}
