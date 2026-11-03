using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using WayMark.Api.Contracts;
using WayMark.Api.Data;
using WayMark.Api.Models;
using WayMark.Api.Services;
using WayMark.Api.Services.MapDrafts;
using Xunit;

namespace WayMark.Api.Tests;

public sealed class PersonalMapOnboardingTests
{
    private static async Task<string> User(MapDraftTestHost h, string username)
    {
        var password = "Test-only1!" + Guid.NewGuid().ToString("N");
        (await h.Client.PostAsJsonAsync("/api/Auth/register", new { username, password, email = username + "@example.invalid" })).EnsureSuccessStatusCode();
        using var login = await h.Client.PostAsJsonAsync("/api/Auth/login", new { username, password });
        login.EnsureSuccessStatusCode();
        var token = (await login.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("accessToken").GetString()!;
        h.Client.DefaultRequestHeaders.Authorization = new("Bearer", token); return token;
    }
    private static StartPersonalMapRequest Request() => new(Guid.NewGuid(), "My map", "PersonalDemo", "My place", "Not an official hospital map", "Ground", "G");
    private static async Task<MapProjectDto> Start(MapDraftTestHost h, StartPersonalMapRequest? r = null)
    {
        var response = await h.Client.PostAsJsonAsync("/api/me/map-workspaces", r ?? Request());
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<MapProjectDto>())!;
    }

    [Fact]
    public async Task User_creates_owned_personal_scope_without_roles_refresh_and_can_publish_QR_snapshot()
    {
        using var disk = new ManagedImageTestStorage();
        await using var h = new MapDraftTestHost(disk.Provider(), withIdentity: true); await h.StartAsync();
        var a = await User(h, "personal-a"); var request = Request(); var map = await Start(h, request);
        var again = await Start(h, request); Assert.Equal(map.Id, again.Id);
        Assert.True(map.CanPublish); Assert.Equal("PersonalDemo", map.PublicationKind);
        Assert.NotEqual(1, map.SiteId); Assert.NotEqual(2, map.SiteId);
        var me = await h.Client.GetFromJsonAsync<JsonElement>("/api/Auth/me");
        Assert.Empty(me.GetProperty("roles").EnumerateArray());
        Assert.True(me.GetProperty("capabilities").GetProperty("canManageMaps").GetBoolean());
        using (var scope = h.Scope()) {
            var auth = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
            var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
            Assert.Empty(await auth.UserRoles.ToListAsync());
            Assert.Equal((await auth.Users.SingleAsync(u => u.UserName == "personal-a")).Id,
                (await db.MapProjects.SingleAsync(p => p.Id == map.Id)).OwnerId);
        }
        var floor = map.Content.Floors[0]; var prefix = $"/api/admin/floors/{floor.FloorId}/map-drafts";
        (await h.Client.PostAsJsonAsync(prefix, new MapDraftContent())).EnsureSuccessStatusCode();
        using var imageBody = new ByteArrayContent(ManagedImageTestStorage.Image()); imageBody.Headers.ContentType = new("image/png");
        var image = (await (await h.Client.PostAsync(prefix + "/images", imageBody)).Content.ReadFromJsonAsync<MapImageMetadataDto>())!;
        var start = Guid.NewGuid(); var dest = Guid.NewGuid();
        var content = map.Content with { Floors = [floor with { Content = new() { ImageAssetId = image.Id,
            Nodes = [new() { Id = start, NodeCode = "START", Name = "Door", X = .1m, Y = .5m, NodeType = NavigationNodeType.Entrance },
                new() { Id = dest, NodeCode = "DEST", Name = "Destination", X = .8m, Y = .5m, NodeType = NavigationNodeType.Destination, SearchableAsDestination = true }],
            Edges = [new() { Id = Guid.NewGuid(), FromNodeId = start, ToNodeId = dest, DistanceMeters = 7m }] } }] };
        var path = $"/api/admin/map-projects/{map.Id}";
        (await h.Client.PutAsJsonAsync(path, new SaveMapProjectRequest(1, map.Name, content))).EnsureSuccessStatusCode();
        var saved = (await h.Client.GetFromJsonAsync<MapProjectDto>(path))!;
        Assert.Equal(JsonSerializer.Serialize(content), JsonSerializer.Serialize(saved.Content));
        var qr = (await (await h.Client.PostAsJsonAsync(path + "/qrs", new CreateNodeQrRequest(2, floor.Id, start))).Content.ReadFromJsonAsync<NodeQrDto>())!;
        (await h.Client.PostAsJsonAsync(path + "/publish", new PublishMapRequest(2, true))).EnsureSuccessStatusCode();
        (await h.Client.PutAsJsonAsync(path, new SaveMapProjectRequest(2, "Private edit", content))).EnsureSuccessStatusCode();
        using var guest = h.NewClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await guest.GetAsync(path)).StatusCode);
        var published = (await guest.GetFromJsonAsync<PublicMapDto>($"/api/public/maps/{map.Id}/versions/2"))!;
        Assert.Equal("My map", published.Name); Assert.False(published.VerifiedForPatientUse);
        Assert.Equal("PersonalDemo", published.Content.Info!.Kind);
        var resolved = (await guest.GetFromJsonAsync<ResolveMapQrDto>("/api/public/qr/" + qr.Payload[6..]))!;
        Assert.Equal(start, resolved.NodeId); Assert.Equal(floor.Id, resolved.FloorKey);
        Assert.Equal(HttpStatusCode.OK, (await guest.GetAsync($"/api/public/maps/{map.Id}/versions/2/images/{image.Id}")).StatusCode);
        var b = await User(h, "personal-b"); await Start(h);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.GetAsync(path)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PutAsJsonAsync(path, new SaveMapProjectRequest(3, "stolen", content))).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PostAsJsonAsync(path + "/publish", new PublishMapRequest(3, true))).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PostAsync(path + $"/qrs/{qr.Id}/revoke", null)).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await h.Client.GetAsync($"/api/Maps/sites/{map.SiteId}/buildings")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await h.Client.GetAsync($"/api/Maps/floors/{floor.FloorId}/graph")).StatusCode);
        var visible = await h.Client.GetFromJsonAsync<JsonElement>("/api/Maps/sites");
        Assert.DoesNotContain(visible.EnumerateArray(), s => s.GetProperty("id").GetInt32() == map.SiteId);
        h.Client.DefaultRequestHeaders.Authorization = new("Bearer", a);
        (await h.Client.PostAsJsonAsync($"/api/me/map-workspaces/{map.Id}/floors", new AddPersonalFloorRequest("Level 1", "L1"))).EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task Onboarding_failure_rolls_back_hierarchy_membership_and_entitlement()
    {
        await using var h = new MapDraftTestHost(withIdentity: true); await h.StartAsync(); await User(h, "failure-user");
        h.Failure.Armed = true; h.Failure.FailAtWrite = 2;
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await h.Client.PostAsJsonAsync("/api/me/map-workspaces", Request())).StatusCode);
        using var scope = h.Scope();
        Assert.False(await scope.ServiceProvider.GetRequiredService<AuthDbContext>().UserClaims.AnyAsync(c => c.ClaimType == PersonalMapAccess.Claim));
        Assert.False(await scope.ServiceProvider.GetRequiredService<WayMarkDbContext>().Sites.AnyAsync(s => s.Code.StartsWith(PersonalMapAccess.Prefix)));
    }

    [Fact]
    public async Task Removed_entitlement_is_effective_without_relogin_and_client_cannot_choose_owner_or_facility()
    {
        await using var h = new MapDraftTestHost(withIdentity: true); await h.StartAsync(); await User(h, "revoked-user");
        var invalid = await h.Client.PostAsJsonAsync("/api/me/map-workspaces", new { requestId = Guid.NewGuid(), name = "x", purpose = "PersonalDemo", placeName = "x", floorName = "G", floorCode = "G", siteId = 1, role = "Admin", ownerId = "admin-a" });
        Assert.Equal(HttpStatusCode.BadRequest, invalid.StatusCode);
        var map = await Start(h);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PostAsJsonAsync("/api/admin/floors/10/map-drafts", new MapDraftContent())).StatusCode);
        using (var scope = h.Scope()) {
            var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
            (await db.SiteMapMemberships.SingleAsync(m => m.SiteId == map.SiteId)).IsActive = false; await db.SaveChangesAsync();
        }
        var me = await h.Client.GetFromJsonAsync<JsonElement>("/api/Auth/me");
        Assert.False(me.GetProperty("capabilities").GetProperty("canManageMaps").GetBoolean());
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.GetAsync($"/api/admin/map-projects/{map.Id}")).StatusCode);
        using (var scope = h.Scope()) {
            var auth = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
            auth.UserClaims.RemoveRange(await auth.UserClaims.Where(c => c.ClaimType == PersonalMapAccess.Claim).ToListAsync()); await auth.SaveChangesAsync();
            var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
            (await db.SiteMapMemberships.SingleAsync(m => m.SiteId == map.SiteId)).IsActive = true; await db.SaveChangesAsync();
        }
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.GetAsync($"/api/admin/map-projects/{map.Id}")).StatusCode);
    }
    [Fact]
    public void Reset_delivery_does_not_require_admin_test_recipient()
    {
        var settings = new EmailTestOptions { Host = "smtp.example.invalid", Username = "fixture", AppPassword = "fixture-only-not-real", FromEmail = "fixture@example.invalid" };
        Assert.True(settings.HasDeliverySettings); Assert.False(settings.HasRequiredSettings);
    }

    [Fact]
    public async Task SiteManager_capabilities_exclude_personal_workspaces_and_require_live_Site_membership()
    {
        await using var h = new MapDraftTestHost(withIdentity: true); await h.StartAsync(); await User(h, "manager-user"); await Start(h);
        string userId;
        using (var scope = h.Scope()) {
            var roles = scope.ServiceProvider.GetRequiredService<RoleManager<IdentityRole>>();
            var users = scope.ServiceProvider.GetRequiredService<UserManager<IdentityUser>>();
            Assert.True((await roles.CreateAsync(new("SiteManager"))).Succeeded);
            var user = (await users.FindByNameAsync("manager-user"))!; userId = user.Id;
            Assert.True((await users.AddToRoleAsync(user, "SiteManager")).Succeeded);
        }
        var me = await h.Client.GetFromJsonAsync<JsonElement>("/api/Auth/me");
        Assert.False(me.GetProperty("capabilities").GetProperty("canManageFacility").GetBoolean());
        using (var scope = h.Scope()) {
            var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
            db.SiteMapMemberships.Add(new() { SiteId = 1, UserId = userId, IsActive = true, CanEditDrafts = true }); await db.SaveChangesAsync();
        }
        me = await h.Client.GetFromJsonAsync<JsonElement>("/api/Auth/me");
        Assert.True(me.GetProperty("capabilities").GetProperty("canManageFacility").GetBoolean());
        Assert.Equal(1, Assert.Single(me.GetProperty("capabilities").GetProperty("managedSites").EnumerateArray()).GetProperty("id").GetInt32());
    }
}
