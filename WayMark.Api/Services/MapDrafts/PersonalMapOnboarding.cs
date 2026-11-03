using System.Data;
using System.Globalization;
using System.Security.Claims;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using WayMark.Api.Contracts;
using WayMark.Api.Data;
using WayMark.Api.Models;
using System.Text.Json.Serialization;

namespace WayMark.Api.Services.MapDrafts;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StartPersonalMapRequest(Guid RequestId, string Name, string Purpose, string PlaceName,
    string? Description, string FloorName, string FloorCode);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record AddPersonalFloorRequest(string Name, string Code);

public sealed class PersonalMapOnboarding(WayMarkDbContext db, AuthDbContext auth,
    MapProjectService projects, PersonalMapAccess personal)
{
    private static string Clean(string? value, int max) => !string.IsNullOrWhiteSpace(value)
        && value.Trim().Length <= max && !value.Any(char.IsControl) ? value.Trim()
        : throw new DraftOperationException(400, "invalid_onboarding", "Thông tin bản đồ thiếu hoặc không hợp lệ.");

    public async Task<MapProjectDto> StartAsync(ClaimsPrincipal user, StartPersonalMapRequest r, CancellationToken ct)
    {
        var owner = user.FindFirstValue(ClaimTypes.NameIdentifier);
        if (owner is null || !await auth.Users.AnyAsync(u => u.Id == owner, ct))
            throw new DraftOperationException(401, "authentication_required", "Vui lòng đăng nhập lại.");
        var name = Clean(r.Name, 200); var place = Clean(r.PlaceName, 200);
        var floorName = Clean(r.FloorName, 100); var code = Clean(r.FloorCode, 30);
        var description = string.IsNullOrWhiteSpace(r.Description) ? null : Clean(r.Description, 1000);
        if (r.RequestId == Guid.Empty || r.Purpose is not ("PersonalDemo" or "FacilityProposal"))
            throw new DraftOperationException(400, "invalid_onboarding", "Chọn mục đích bản đồ cá nhân hoặc đề xuất cơ sở chưa được ủy quyền.");
        // Both stores MUST use the very same relational connection/transaction.
        // Refuse an unsupported/split provider; no TransactionScope/MSDTC fallback.
        if (!db.Database.IsRelational() || !auth.Database.IsRelational() || db.Database.ProviderName != auth.Database.ProviderName)
            throw new DraftOperationException(503, "workspace_storage_unavailable", "Workspace cần Identity và map trong cùng database.");
        var connection = auth.Database.GetDbConnection();
        if (!ReferenceEquals(connection, db.Database.GetDbConnection()) && connection.ConnectionString != db.Database.GetDbConnection().ConnectionString)
            throw new DraftOperationException(503, "workspace_storage_unavailable", "Workspace chưa được cấu hình cùng database.");
        db.Database.SetDbConnection(connection);
        await using var transaction = await auth.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
        await db.Database.UseTransactionAsync(transaction.GetDbTransaction(), ct);
        var previous = await db.MapProjects.AsNoTracking().SingleOrDefaultAsync(p => p.OwnerId == owner && p.LocalProjectId == r.RequestId, ct);
        if (previous is not null) {
            var found = await projects.GetAsync(user, previous.Id, ct);
            if (found.Name != name || found.Content.Info != new ProjectInfoDto(r.Purpose, place, description)
                || found.Content.Floors[0].Name != floorName || found.Content.Floors[0].Code != code)
                throw new DraftOperationException(409, "onboarding_conflict", "Yêu cầu tạo trước đã có kết quả khác; hãy mở Bản đồ của tôi.");
            await transaction.CommitAsync(ct); return found;
        }
        if (await auth.UserClaims.Where(c => c.UserId == owner && c.ClaimType == PersonalMapAccess.Claim)
                .Select(c => c.ClaimValue).Distinct().CountAsync(ct) >= 10)
            throw new DraftOperationException(409, "personal_map_quota", "Tối đa 10 workspace cá nhân cho MVP.");
        var site = new Site { Name = "Workspace cá nhân — không đại diện cơ sở", Code = PersonalMapAccess.Prefix + Guid.NewGuid().ToString("N") };
        db.Sites.Add(site); await db.SaveChangesAsync(ct);
        var building = new Building { SiteId = site.Id, Name = "Bản đồ cá nhân", BuildingCode = "PERSONAL" };
        db.Buildings.Add(building); await db.SaveChangesAsync(ct);
        var floor = new Floor { BuildingId = building.Id, Name = floorName, FloorCode = code };
        db.Floors.Add(floor);
        db.SiteMapMemberships.Add(new() { SiteId = site.Id, UserId = owner, IsActive = true, CanEditDrafts = true });
        await db.SaveChangesAsync(ct);
        auth.UserClaims.Add(new IdentityUserClaim<string> { UserId = owner, ClaimType = PersonalMapAccess.Claim,
            ClaimValue = site.Id.ToString(CultureInfo.InvariantCulture) });
        await auth.SaveChangesAsync(ct);
        var content = new ProjectContentDto(r.RequestId, [new(Guid.NewGuid(), floor.Id, floorName, code, new MapDraftContent())], [],
            new(r.Purpose, place, description));
        var project = await projects.CreateAsync(user, new(name, content), ct);
        await transaction.CommitAsync(ct);
        return project;
    }

    public async Task<object> AddFloorAsync(ClaimsPrincipal user, Guid mapId, AddPersonalFloorRequest r, CancellationToken ct)
    {
        var project = await projects.GetAsync(user, mapId, ct);
        if (!await personal.OwnsAsync(user, project.SiteId, ct))
            throw new DraftOperationException(403, "personal_scope_required", "Chỉ chủ workspace cá nhân được thêm tầng ở đây.");
        var name = Clean(r.Name, 100); var code = Clean(r.Code, 30);
        await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
        var existing = await db.Floors.SingleOrDefaultAsync(f => f.BuildingId == project.BuildingId && f.FloorCode == code, ct);
        if (existing is not null) return new { existing.Id, existing.Name, Code = existing.FloorCode };
        if (await db.Floors.CountAsync(f => f.BuildingId == project.BuildingId, ct) >= 12)
            throw new DraftOperationException(409, "floor_quota", "Tối đa 12 tầng.");
        var floor = new Floor { BuildingId = project.BuildingId, Name = name, FloorCode = code };
        db.Floors.Add(floor); await db.SaveChangesAsync(ct); await transaction.CommitAsync(ct);
        return new { floor.Id, floor.Name, Code = floor.FloorCode };
    }
}
