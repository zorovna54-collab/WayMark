using System.Net;
using System.Net.Http.Json;
using System.IdentityModel.Tokens.Jwt;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using WayMark.Api.Contracts;
using WayMark.Api.Data;
using WayMark.Api.Models;
using WayMark.Api.Security;
using Xunit;

namespace WayMark.Api.Tests;

// Actual production JWT middleware/controllers/services; SQLite and temporary
// managed files only. No SQL Server configuration, users or grants are loaded.
public sealed class CreatorAuthorizationTests
{
    [Fact]
    public async Task Register_login_and_verified_email_cannot_self_grant_Creator_Manager_Admin_or_membership()
    {
        await using var h = new MapDraftTestHost(withIdentity: true); await h.StartAsync();
        var username = "ordinary-" + Guid.NewGuid().ToString("N");
        var password = "Aa1!" + Guid.NewGuid().ToString("N");
        (await h.Client.PostAsJsonAsync("/api/Auth/register", new { username, password,
            email = username + "@example.invalid", emailConfirmed = true, role = "Admin",
            roles = new[] { "Creator", "SiteManager", "SitePublisher:1" }, siteId = 1, canEditDrafts = true })).EnsureSuccessStatusCode();
        using (var scope = h.Scope()) {
            var users = scope.ServiceProvider.GetRequiredService<UserManager<IdentityUser>>();
            var user = (await users.FindByNameAsync(username))!;
            Assert.False(user.EmailConfirmed); Assert.Empty(await users.GetRolesAsync(user));
            user.EmailConfirmed = true; Assert.True((await users.UpdateAsync(user)).Succeeded); // Isolated SQLite only.
        }
        using var login = await h.Client.PostAsJsonAsync("/api/Auth/login", new { username, password, role = "Creator" });
        login.EnsureSuccessStatusCode();
        var json = await login.Content.ReadFromJsonAsync<System.Text.Json.JsonElement>();
        var token = json.GetProperty("accessToken").GetString()!;
        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(token);
        Assert.DoesNotContain(jwt.Claims, c => c.Type == "role" || c.Type == System.Security.Claims.ClaimTypes.Role);
        h.Client.DefaultRequestHeaders.Authorization = new("Bearer", token);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PostAsJsonAsync("/api/admin/floors/10/map-drafts", new MapDraftContent())).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PostAsJsonAsync("/api/WayMarks", new { })).StatusCode);
        using var check = h.Scope();
        Assert.Empty(await check.ServiceProvider.GetRequiredService<AuthDbContext>().UserRoles.ToListAsync());
        Assert.Equal(0, await check.ServiceProvider.GetRequiredService<WayMarkDbContext>().SiteMapMemberships.CountAsync(m => m.UserId != "admin-a" && m.UserId != "admin-b" && m.UserId != "inactive" && m.UserId != "no-edit"));
    }
    private static async Task Members(MapDraftTestHost h)
    {
        using var scope = h.Scope();
        var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
        db.SiteMapMemberships.AddRange(
            new() { SiteId = 1, UserId = "creator-a", IsActive = true, CanEditDrafts = true },
            new() { SiteId = 1, UserId = "creator-b", IsActive = true, CanEditDrafts = true },
            new() { SiteId = 1, UserId = "manager-a", IsActive = true, CanEditDrafts = true },
            new() { SiteId = 2, UserId = "other-owner", IsActive = true, CanEditDrafts = true });
        await db.SaveChangesAsync();
    }
    private static void Creator(MapDraftTestHost h, string id = "creator-a", int? publishSite = null)
        => h.Token(userId: id, roles: publishSite is int site
            ? [WayMarkSecurity.CreatorRole, WayMarkSecurity.SitePublisherRole(site)] : [WayMarkSecurity.CreatorRole]);

    [Fact]
    public async Task Creator_owns_drafts_images_and_maps_but_publish_requires_explicit_Site_permission()
    {
        using var disk = new ManagedImageTestStorage();
        await using var h = new MapDraftTestHost(disk.Provider()); await h.StartAsync(); await Members(h);
        Creator(h);
        var content = await PublishedMapTests.Fixture(h);
        var p = await PublishedMapTests.Create(h, content);
        var floor = content.Floors[0];
        var prefix = $"/api/admin/floors/{floor.FloorId}/map-drafts";
        var head = (await h.Client.GetFromJsonAsync<MapDraftMetadataDto>(prefix))!;
        (await h.Client.PutAsJsonAsync($"{prefix}/{head.Id}", new SaveMapDraftRequest(head.Version, floor.Content)))
            .EnsureSuccessStatusCode();
        (await h.Client.GetAsync($"{prefix}/{head.Id}/graph")).EnsureSuccessStatusCode();
        (await h.Client.GetAsync($"{prefix}/images/{floor.Content.ImageAssetId}")).EnsureSuccessStatusCode();
        (await h.Client.PutAsJsonAsync($"/api/admin/map-projects/{p.Id}", new SaveMapProjectRequest(p.Version, "Creator edit", content)))
            .EnsureSuccessStatusCode();
        p = (await h.Client.GetFromJsonAsync<MapProjectDto>($"/api/admin/map-projects/{p.Id}"))!;
        var qr = await PublishedMapTests.Qr(h, p);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PostAsJsonAsync($"/api/admin/map-projects/{p.Id}/publish", new PublishMapRequest(p.Version, true))).StatusCode);
        Creator(h, publishSite: 2); // Publishing authorization is not portable across Sites.
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PostAsJsonAsync($"/api/admin/map-projects/{p.Id}/publish", new PublishMapRequest(p.Version, true))).StatusCode);
        using (var scope = h.Scope()) Assert.Empty(await scope.ServiceProvider.GetRequiredService<WayMarkDbContext>().MapPublications.ToListAsync());
        Creator(h, publishSite: 1);
        (await h.Client.PostAsJsonAsync($"/api/admin/map-projects/{p.Id}/publish", new PublishMapRequest(p.Version, true))).EnsureSuccessStatusCode();
        h.Token("missing");
        (await h.Client.GetAsync("/api/public/qr/" + qr.Payload[6..])).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Unauthorized, (await h.Client.GetAsync($"/api/admin/map-projects/{p.Id}")).StatusCode);
    }

    [Fact]
    public async Task Same_Site_Creator_B_cannot_access_A_project_floor_revisions_or_private_images()
    {
        using var disk = new ManagedImageTestStorage();
        await using var h = new MapDraftTestHost(disk.Provider()); await h.StartAsync(); await Members(h);
        Creator(h, publishSite: 1);
        var p = await PublishedMapTests.Create(h, await PublishedMapTests.Fixture(h));
        var qr = await PublishedMapTests.Qr(h, p);
        var f = p.Content.Floors[0]; var prefix = $"/api/admin/floors/{f.FloorId}/map-drafts";
        var head = (await h.Client.GetFromJsonAsync<MapDraftMetadataDto>(prefix))!;
        Creator(h, "creator-b", 1);
        foreach (var path in new[] { $"/api/admin/map-projects/{p.Id}", $"/api/admin/map-projects/{p.Id}/qrs",
            prefix, $"{prefix}/{head.Id}/graph", $"{prefix}/{head.Id}/versions", $"{prefix}/{head.Id}/places",
            prefix + "/images", $"{prefix}/images/{f.Content.ImageAssetId}" })
            Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.GetAsync(path)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PutAsJsonAsync($"/api/admin/map-projects/{p.Id}", new SaveMapProjectRequest(1, "hacked", p.Content))).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PostAsJsonAsync($"/api/admin/map-projects/{p.Id}/publish", new PublishMapRequest(1, true))).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PostAsJsonAsync($"/api/admin/map-projects/{p.Id}/qrs",
            new CreateNodeQrRequest(1, f.Id, f.Content.Nodes![0].Id))).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PostAsync($"/api/admin/map-projects/{p.Id}/qrs/{qr.Id}/revoke", null)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PutAsJsonAsync($"{prefix}/{head.Id}", new SaveMapDraftRequest(1, f.Content))).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PostAsJsonAsync($"{prefix}/{head.Id}/restore", new RestoreMapDraftRequest(1, 1))).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PostAsJsonAsync(prefix, new MapDraftContent())).StatusCode);
        using var payload = new ByteArrayContent(ManagedImageTestStorage.Image()); payload.Headers.ContentType = new("image/png");
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PostAsync(prefix + "/images", payload)).StatusCode);
        using var scope = h.Scope(); var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
        Assert.Equal(1, (await db.MapProjects.SingleAsync()).Version);
        Assert.All(await db.FloorMapDrafts.ToListAsync(), draft => Assert.Equal(1, draft.Version));
        Assert.Empty(await db.MapPublications.ToListAsync()); Assert.True((await db.MapNodeQrs.SingleAsync()).IsActive);
        Assert.Equal(2, await db.FloorMapImageAssets.CountAsync());
    }

    [Fact]
    public async Task Site_manager_can_manage_authorized_Site_maps_but_not_other_Site_or_system_admin_APIs()
    {
        using var disk = new ManagedImageTestStorage();
        await using var h = new MapDraftTestHost(disk.Provider()); await h.StartAsync(); await Members(h);
        Creator(h);
        var p = await PublishedMapTests.Create(h, await PublishedMapTests.Fixture(h));
        await PublishedMapTests.Qr(h, p);
        Creator(h, "other-owner");
        (await h.Client.PostAsJsonAsync("/api/admin/floors/20/map-drafts", new MapDraftContent())).EnsureSuccessStatusCode();
        var other = await PublishedMapTests.Create(h, new(Guid.NewGuid(), [new(Guid.NewGuid(), 20, "Other", "O", new())], []));
        h.Token(userId: "manager-a", roles: [WayMarkSecurity.SiteManagerRole]);
        (await h.Client.GetAsync($"/api/admin/map-projects/{p.Id}")).EnsureSuccessStatusCode();
        (await h.Client.PostAsJsonAsync($"/api/admin/map-projects/{p.Id}/publish", new PublishMapRequest(1, true))).EnsureSuccessStatusCode();
        (await h.Client.PutAsJsonAsync($"/api/admin/map-projects/{p.Id}", new SaveMapProjectRequest(1, "Manager edit", p.Content))).EnsureSuccessStatusCode();
        var list = (await h.Client.GetFromJsonAsync<MapProjectSummaryDto[]>("/api/admin/map-projects"))!;
        Assert.Contains(list, x => x.Id == p.Id); Assert.DoesNotContain(list, x => x.Id == other.Id);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.GetAsync($"/api/admin/map-projects/{other.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.GetAsync("/api/admin/floors/20/map-drafts")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PostAsJsonAsync($"/api/admin/map-projects/{other.Id}/publish", new PublishMapRequest(1, true))).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PostAsJsonAsync("/api/WayMarks", new { })).StatusCode);
    }

    [Theory]
    [InlineData("Creator")]
    [InlineData("SiteManager")]
    [InlineData("SitePublisher:1")]
    public async Task Map_roles_do_not_grant_global_WayMark_or_email_administration(string role)
    {
        await using var h = new MapDraftTestHost(); await h.StartAsync(); await Members(h);
        h.Token(userId: "creator-a", roles: [role]);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PostAsJsonAsync("/api/WayMarks", new { })).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PutAsJsonAsync("/api/WayMarks/100", new { })).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.DeleteAsync("/api/WayMarks/100")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PostAsync("/api/Email/test", null)).StatusCode);
        using var scope = h.Scope(); Assert.Equal(2, await scope.ServiceProvider.GetRequiredService<WayMarkDbContext>().WayMarks.CountAsync());
    }

    [Theory]
    [InlineData("user", "creator-a", HttpStatusCode.Forbidden)]
    [InlineData("creator", "unassigned", HttpStatusCode.Forbidden)]
    [InlineData("creator", "inactive", HttpStatusCode.Forbidden)]
    [InlineData("creator", "no-edit", HttpStatusCode.Forbidden)]
    [InlineData("forged-role", "creator-a", HttpStatusCode.Unauthorized)]
    [InlineData("expired", "creator-a", HttpStatusCode.Unauthorized)]
    [InlineData("bad-signature", "creator-a", HttpStatusCode.Unauthorized)]
    [InlineData("missing", "creator-a", HttpStatusCode.Unauthorized)]
    public async Task Invalid_or_unprivileged_identity_cannot_self_assign_permissions(string kind, string id, HttpStatusCode expected)
    {
        await using var h = new MapDraftTestHost(); await h.StartAsync(); await Members(h);
        h.Token(kind, id, kind == "creator" ? [WayMarkSecurity.CreatorRole] : null);
        h.Client.DefaultRequestHeaders.Add("X-Role", "Admin"); h.Client.DefaultRequestHeaders.Add("X-SiteId", "1");
        var valid = await h.Client.PostAsJsonAsync("/api/admin/floors/10/map-drafts", new MapDraftContent());
        Assert.Equal(expected, valid.StatusCode);
        var response = await h.Client.PostAsJsonAsync("/api/admin/floors/10/map-drafts",
            new { nodes = Array.Empty<object>(), edges = Array.Empty<object>(), places = Array.Empty<object>(), transitions = Array.Empty<object>(),
                ownerId = "creator-a", role = "Creator", siteId = 1, emailConfirmed = true });
        // Unmapped ownership/role fields are rejected by JSON binding before
        // the service executes; authentication/policy still run before binding.
        Assert.Equal(kind == "creator" ? HttpStatusCode.BadRequest : expected, response.StatusCode);
        using var scope = h.Scope(); var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
        Assert.Empty(await db.FloorMapDrafts.ToListAsync()); Assert.Empty(await db.MapProjects.ToListAsync());
        Assert.Equal(0, await db.SiteMapMemberships.CountAsync(x => x.UserId == "unassigned"));
    }
}
