using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.DependencyInjection;
using WayMark.Api.Contracts;
using WayMark.Api.Controllers;
using WayMark.Api.Data;
using Xunit;

namespace WayMark.Api.Tests;

public sealed class NavigationHistoryTests
{
    private const string Path = "/api/me/navigation-history";
    private static async Task<(MapProjectDto Map, NodeQrDto Qr, StartHistoryRequest Request)> Fixture(MapDraftTestHost h)
    {
        var map = await PublishedMapTests.Create(h, await PublishedMapTests.Fixture(h));
        var qr = await PublishedMapTests.Qr(h, map);
        (await h.Client.PostAsJsonAsync($"/api/admin/map-projects/{map.Id}/publish", new PublishMapRequest(1, true))).EnsureSuccessStatusCode();
        return (map, qr, new(Guid.NewGuid(), qr.Payload[6..], map.Content.Floors[1].Id, map.Content.Floors[1].Content.Nodes![0].Id));
    }
    [Fact]
    public async Task Start_is_idempotent_terminal_is_single_assignment_delete_persists_and_guest_is_denied()
    {
        using var disk = new ManagedImageTestStorage();
        await using var h = new MapDraftTestHost(disk.Provider()); await h.StartAsync();
        var f = await Fixture(h); var r = f.Request;
        h.Token("user", "visitor-a");
        Assert.Equal(HttpStatusCode.Created, (await h.Client.PostAsJsonAsync(Path, r)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await h.Client.PostAsJsonAsync(Path, r)).StatusCode);
        var list = (await h.Client.GetFromJsonAsync<HistoryItemDto[]>(Path))!; Assert.Single(list); Assert.Equal("InProgress", list[0].Status);
        Assert.Equal("Fixture map", list[0].MapName); Assert.Equal("Clinic destination", list[0].DestinationName);
        (await h.Client.PutAsJsonAsync($"{Path}/{r.SessionId}", new EndHistoryRequest("Completed"))).EnsureSuccessStatusCode();
        (await h.Client.PutAsJsonAsync($"{Path}/{r.SessionId}", new EndHistoryRequest("Completed"))).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Conflict, (await h.Client.PutAsJsonAsync($"{Path}/{r.SessionId}", new EndHistoryRequest("Cancelled"))).StatusCode);
        Assert.Equal("Completed", (await h.Client.GetFromJsonAsync<HistoryItemDto[]>(Path))![0].Status);
        (await h.Client.DeleteAsync($"{Path}/{r.SessionId}")).EnsureSuccessStatusCode();
        Assert.Empty((await h.Client.GetFromJsonAsync<HistoryItemDto[]>(Path))!);
        h.Token("missing"); Assert.Equal(HttpStatusCode.Unauthorized, (await h.Client.GetAsync(Path)).StatusCode);
    }
    [Fact]
    public async Task Other_user_even_admin_cannot_read_modify_delete_or_resume_private_history()
    {
        using var disk = new ManagedImageTestStorage(); await using var h = new MapDraftTestHost(disk.Provider()); await h.StartAsync();
        var f = await Fixture(h); h.Token("user", "a"); (await h.Client.PostAsJsonAsync(Path, f.Request)).EnsureSuccessStatusCode();
        h.Token("admin", "admin-b"); Assert.Empty((await h.Client.GetFromJsonAsync<HistoryItemDto[]>(Path))!);
        Assert.Equal(HttpStatusCode.NotFound, (await h.Client.GetAsync($"{Path}/{f.Request.SessionId}/resume")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await h.Client.DeleteAsync($"{Path}/{f.Request.SessionId}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await h.Client.PutAsJsonAsync($"{Path}/{f.Request.SessionId}", new EndHistoryRequest("Cancelled"))).StatusCode);
        h.Token("user", "a"); Assert.Single((await h.Client.GetFromJsonAsync<HistoryItemDto[]>(Path))!);
        Assert.Equal(HttpStatusCode.BadRequest, (await h.Client.PostAsJsonAsync(Path, new { sessionId = Guid.NewGuid(), qrToken = f.Qr.Payload[6..],
            destinationFloorKey = f.Request.DestinationFloorKey, destinationNodeId = f.Request.DestinationNodeId, userId = "b" })).StatusCode);
    }
    [Fact]
    public async Task Resume_revalidates_qr_and_public_snapshot_and_cancel_is_persisted()
    {
        using var disk = new ManagedImageTestStorage(); await using var h = new MapDraftTestHost(disk.Provider()); await h.StartAsync();
        var f = await Fixture(h); h.Token("user", "history-user");
        (await h.Client.PostAsJsonAsync(Path, f.Request)).EnsureSuccessStatusCode();
        (await h.Client.PutAsJsonAsync($"{Path}/{f.Request.SessionId}", new EndHistoryRequest("Cancelled"))).EnsureSuccessStatusCode();
        var resume = await h.Client.GetFromJsonAsync<JsonElement>($"{Path}/{f.Request.SessionId}/resume");
        Assert.Equal(f.Qr.Payload, resume.GetProperty("payload").GetString());
        h.Token(); (await h.Client.PostAsync($"/api/admin/map-projects/{f.Map.Id}/qrs/{f.Qr.Id}/revoke", null)).EnsureSuccessStatusCode();
        h.Token("user", "history-user"); Assert.Equal(HttpStatusCode.Gone, (await h.Client.GetAsync($"{Path}/{f.Request.SessionId}/resume")).StatusCode);
        Assert.Equal("Cancelled", (await h.Client.GetFromJsonAsync<HistoryItemDto[]>(Path))![0].Status);
    }
    [Fact]
    public async Task History_survives_database_host_restart_without_rerecording_navigation()
    {
        using var disk = new ManagedImageTestStorage();
        await using (var h = new MapDraftTestHost(disk.Provider(), sqlitePath: disk.DatabasePath)) {
            await h.StartAsync(); var f = await Fixture(h); h.Token("user", "persistent-user");
            (await h.Client.PostAsJsonAsync(Path, f.Request)).EnsureSuccessStatusCode();
            (await h.Client.PutAsJsonAsync($"{Path}/{f.Request.SessionId}", new EndHistoryRequest("Completed"))).EnsureSuccessStatusCode();
        }
        await using var restarted = new MapDraftTestHost(disk.Provider(), sqlitePath: disk.DatabasePath); await restarted.StartAsync();
        restarted.Token("user", "persistent-user"); Assert.Single((await restarted.Client.GetFromJsonAsync<HistoryItemDto[]>(Path))!);
        restarted.Token("user", "other-user"); Assert.Empty((await restarted.Client.GetFromJsonAsync<HistoryItemDto[]>(Path))!);
    }
    [Fact]
    public async Task Invalid_destination_and_draft_only_qr_never_create_history()
    {
        using var disk = new ManagedImageTestStorage(); await using var h = new MapDraftTestHost(disk.Provider()); await h.StartAsync();
        var f = await Fixture(h); h.Token("user", "a");
        Assert.Equal(HttpStatusCode.BadRequest, (await h.Client.PostAsJsonAsync(Path, f.Request with { DestinationNodeId = Guid.NewGuid() })).StatusCode);
        Assert.Empty((await h.Client.GetFromJsonAsync<HistoryItemDto[]>(Path))!);
    }
    [Fact]
    public async Task Scan_without_destination_is_idempotent_then_same_session_selects_starts_finishes()
    {
        using var disk=new ManagedImageTestStorage(); await using var h=new MapDraftTestHost(disk.Provider()); await h.StartAsync();
        var f=await Fixture(h); h.Token("user","scan-a");
        var r=new StartHistoryRequest(Guid.NewGuid(),f.Qr.Payload[6..]);
        Assert.Equal(HttpStatusCode.Created,(await h.Client.PostAsJsonAsync(Path,r)).StatusCode);
        for(var n=0;n<8;n++)Assert.Equal(HttpStatusCode.OK,(await h.Client.PostAsJsonAsync(Path,r)).StatusCode);
        var scanned=(await h.Client.GetFromJsonAsync<HistoryItemDto[]>(Path))!.Single();
        Assert.Equal("Scanned",scanned.Status);Assert.Null(scanned.DestinationNodeId);Assert.Null(scanned.NavigationStartedAtUtc);Assert.NotNull(scanned.StartFloorKey);
        Assert.Equal(HttpStatusCode.Conflict,(await h.Client.PutAsJsonAsync($"{Path}/{r.SessionId}",new EndHistoryRequest("Completed"))).StatusCode);
        var target=new HistoryDestinationRequest(f.Request.DestinationFloorKey!.Value,f.Request.DestinationNodeId!.Value);
        (await h.Client.PutAsJsonAsync($"{Path}/{r.SessionId}/destination",target)).EnsureSuccessStatusCode();
        var selected=(await h.Client.GetFromJsonAsync<HistoryItemDto>($"{Path}/{r.SessionId}"))!;
        Assert.Equal("Scanned",selected.Status);Assert.True(selected.DistanceMeters>0);
        (await h.Client.PutAsync($"{Path}/{r.SessionId}/start",null)).EnsureSuccessStatusCode();
        (await h.Client.PutAsync($"{Path}/{r.SessionId}/start",null)).EnsureSuccessStatusCode();
        var begun=(await h.Client.GetFromJsonAsync<HistoryItemDto>($"{Path}/{r.SessionId}"))!;
        Assert.Equal("InProgress",begun.Status);Assert.NotNull(begun.NavigationStartedAtUtc);Assert.Equal(scanned.ScannedAtUtc,begun.ScannedAtUtc);
        (await h.Client.PutAsJsonAsync($"{Path}/{r.SessionId}",new EndHistoryRequest("Completed"))).EnsureSuccessStatusCode();
        Assert.Single((await h.Client.GetFromJsonAsync<HistoryItemDto[]>(Path))!);
        h.Token("user","scan-b");
        Assert.Equal(HttpStatusCode.NotFound,(await h.Client.GetAsync($"{Path}/{r.SessionId}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound,(await h.Client.PutAsJsonAsync($"{Path}/{r.SessionId}/destination",target)).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound,(await h.Client.PutAsync($"{Path}/{r.SessionId}/start",null)).StatusCode);
    }
    [Fact]
    public async Task Scanned_can_cancel_without_destination_and_revoked_qr_cannot_create_another_session()
    {
        using var disk=new ManagedImageTestStorage(); await using var h=new MapDraftTestHost(disk.Provider()); await h.StartAsync();
        var f=await Fixture(h);h.Token("user","a");var r=new StartHistoryRequest(Guid.NewGuid(),f.Qr.Payload[6..]);
        (await h.Client.PostAsJsonAsync(Path,r)).EnsureSuccessStatusCode();
        (await h.Client.PutAsJsonAsync($"{Path}/{r.SessionId}",new EndHistoryRequest("Cancelled"))).EnsureSuccessStatusCode();
        h.Token();(await h.Client.PostAsync($"/api/admin/map-projects/{f.Map.Id}/qrs/{f.Qr.Id}/revoke",null)).EnsureSuccessStatusCode();
        h.Token("user","a");Assert.Equal(HttpStatusCode.Gone,(await h.Client.PostAsJsonAsync(Path,r with {SessionId=Guid.NewGuid()})).StatusCode);
        var only=(await h.Client.GetFromJsonAsync<HistoryItemDto[]>(Path))!.Single();Assert.Equal("Cancelled",only.Status);Assert.Null(only.DestinationNodeId);
    }
    [Fact]
    public void SqlServer_snapshot_and_migration_match_model_offline_and_up_is_additive_only()
    {
        using var db = new WayMarkDbContext(new DbContextOptionsBuilder<WayMarkDbContext>().UseSqlServer().Options);
        Assert.False(db.Database.HasPendingModelChanges());
        var sql = db.GetService<IMigrator>().GenerateScript("20261023063955_AddPublishedMapProjects", "20261025010000_AddNavigationHistory");
        Assert.Contains("CREATE TABLE [NavigationHistory]", sql); Assert.Contains("IX_NavigationHistory_UserId_StartedAtUtc", sql);
        Assert.DoesNotContain("DROP ", sql); Assert.DoesNotContain("ALTER TABLE [AspNet", sql);
        Assert.DoesNotContain("DELETE ", sql); Assert.DoesNotContain("TRUNCATE ", sql);
    }
}
