using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using WayMark.Api.Contracts;
using WayMark.Api.Controllers;
using WayMark.Api.Models;
using WayMark.Api.Services.MapDrafts;
using Xunit;

namespace WayMark.Api.Tests;

// Actual controllers + Identity + relational SQLite + managed image files.
// All state belongs to this fixture; no appsettings, SQL Server or real QR is read.
public sealed class ProductCompletionCycle1Tests
{
    private const string Password = "Fixture-only1!";
    private static async Task Login(MapDraftTestHost host, string user, bool register)
    {
        if (register)
            (await host.Client.PostAsJsonAsync("/api/Auth/register",
                new { username = user, password = Password, email = user + "@example.invalid" })).EnsureSuccessStatusCode();
        using var response = await host.Client.PostAsJsonAsync("/api/Auth/login",
            new { username = user, password = Password });
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        host.Client.DefaultRequestHeaders.Authorization = new("Bearer", body.GetProperty("accessToken").GetString());
    }

    [Fact]
    public async Task Personal_creator_to_public_visitor_and_completed_history_survives_isolated_restart()
    {
        using var disk = new ManagedImageTestStorage();
        Guid mapId, floorKey, startId, destinationId, imageId, historyId = Guid.NewGuid();
        string payload, originalName = "Cycle 1 fixture";
        long publishedVersion;
        await using (var host = new MapDraftTestHost(disk.Provider(), sqlitePath: disk.DatabasePath, withIdentity: true))
        {
            await host.StartAsync();
            await Login(host, "cycle1-creator", register: true);
            var created = await host.Client.PostAsJsonAsync("/api/me/map-workspaces",
                new StartPersonalMapRequest(Guid.NewGuid(), originalName, "PersonalDemo", "Fixture place", null, "Ground", "G"));
            created.EnsureSuccessStatusCode();
            var map = (await created.Content.ReadFromJsonAsync<MapProjectDto>())!;
            mapId = map.Id;
            var floor = Assert.Single(map.Content.Floors);
            floorKey = floor.Id;
            var draftPath = $"/api/admin/floors/{floor.FloorId}/map-drafts";
            (await host.Client.PostAsJsonAsync(draftPath, new MapDraftContent())).EnsureSuccessStatusCode();
            using var imageBody = new ByteArrayContent(ManagedImageTestStorage.Image());
            imageBody.Headers.ContentType = new("image/png");
            using var uploaded = await host.Client.PostAsync(draftPath + "/images", imageBody);
            uploaded.EnsureSuccessStatusCode();
            var image = (await uploaded.Content.ReadFromJsonAsync<MapImageMetadataDto>())!;
            imageId = image.Id;
            startId = Guid.NewGuid(); destinationId = Guid.NewGuid();
            var edgeId = Guid.NewGuid();
            var content = map.Content with
            {
                Floors = [floor with { Content = new()
                {
                    ImageAssetId = imageId,
                    Nodes = [
                        new() { Id = startId, NodeCode = "START", Name = "Start", X = .1m, Y = .5m, NodeType = NavigationNodeType.Entrance },
                        new() { Id = destinationId, NodeCode = "END", Name = "Destination", X = .8m, Y = .5m,
                            NodeType = NavigationNodeType.Destination, SearchableAsDestination = true }
                    ],
                    Edges = [new() { Id = edgeId, FromNodeId = startId, ToNodeId = destinationId, DistanceMeters = 7m }]
                }}]
            };
            var mapPath = $"/api/admin/map-projects/{mapId}";
            (await host.Client.PutAsJsonAsync(mapPath, new SaveMapProjectRequest(1, originalName, content))).EnsureSuccessStatusCode();
            var reloaded = (await host.Client.GetFromJsonAsync<MapProjectDto>(mapPath))!;
            publishedVersion = reloaded.Version;
            Assert.Equal(2, publishedVersion);
            Assert.Equal(edgeId, Assert.Single(reloaded.Content.Floors[0].Content.Edges!).Id);
            Assert.Equal(startId, reloaded.Content.Floors[0].Content.Nodes![0].Id);
            Assert.Equal(imageId, reloaded.Content.Floors[0].Content.ImageAssetId);

            // Source contract requires a start QR before publication.
            using var qrResponse = await host.Client.PostAsJsonAsync(mapPath + "/qrs",
                new CreateNodeQrRequest(publishedVersion, floorKey, startId));
            qrResponse.EnsureSuccessStatusCode();
            var qr = (await qrResponse.Content.ReadFromJsonAsync<NodeQrDto>())!;
            payload = qr.Payload;
            (await host.Client.PostAsJsonAsync(mapPath + "/publish",
                new PublishMapRequest(publishedVersion, true))).EnsureSuccessStatusCode();
            (await host.Client.PutAsJsonAsync(mapPath,
                new SaveMapProjectRequest(publishedVersion, "Private next draft", content))).EnsureSuccessStatusCode();

            using var guest = host.NewClient();
            Assert.Equal(HttpStatusCode.Unauthorized, (await guest.GetAsync(mapPath)).StatusCode);
            var resolved = (await guest.GetFromJsonAsync<ResolveMapQrDto>("/api/public/qr/" + payload[6..]))!;
            Assert.Equal(mapId, resolved.MapId); Assert.Equal(publishedVersion, resolved.Version);
            Assert.Equal(floorKey, resolved.FloorKey); Assert.Equal(startId, resolved.NodeId);
            var publicPath = $"/api/public/maps/{mapId}/versions/{publishedVersion}";
            var snapshot = (await guest.GetFromJsonAsync<PublicMapDto>(publicPath))!;
            Assert.Equal(originalName, snapshot.Name);
            Assert.Equal(destinationId, Assert.Single(snapshot.Content.Floors[0].Content.Nodes!, n => n.SearchableAsDestination).Id);
            using var publicImage = await guest.GetAsync(publicPath + "/images/" + imageId);
            publicImage.EnsureSuccessStatusCode();
            Assert.Equal("image/png", publicImage.Content.Headers.ContentType!.MediaType);
            var bytes = await publicImage.Content.ReadAsByteArrayAsync();
            Assert.Equal(image.Sha256, Convert.ToHexStringLower(SHA256.HashData(bytes)));

            await Login(host, "cycle1-visitor", register: true);
            const string historyPath = "/api/me/navigation-history";
            Assert.Equal(HttpStatusCode.Forbidden, (await host.Client.GetAsync(mapPath)).StatusCode);
            (await host.Client.PostAsJsonAsync(historyPath, new StartHistoryRequest(historyId, payload[6..]))).EnsureSuccessStatusCode();
            Assert.Equal("Scanned", (await host.Client.GetFromJsonAsync<HistoryItemDto>($"{historyPath}/{historyId}"))!.Status);
            (await host.Client.PutAsJsonAsync($"{historyPath}/{historyId}/destination",
                new HistoryDestinationRequest(floorKey, destinationId))).EnsureSuccessStatusCode();
            var selected = (await host.Client.GetFromJsonAsync<HistoryItemDto>($"{historyPath}/{historyId}"))!;
            Assert.Equal(7m, selected.DistanceMeters);
            Assert.Equal("Scanned", selected.Status);
            (await host.Client.PutAsync($"{historyPath}/{historyId}/start", null)).EnsureSuccessStatusCode();
            Assert.Equal("InProgress", (await host.Client.GetFromJsonAsync<HistoryItemDto>($"{historyPath}/{historyId}"))!.Status);
            (await host.Client.PutAsJsonAsync($"{historyPath}/{historyId}", new EndHistoryRequest("Completed"))).EnsureSuccessStatusCode();
            Assert.Equal("Completed", (await host.Client.GetFromJsonAsync<HistoryItemDto>($"{historyPath}/{historyId}"))!.Status);
        }

        await using var restarted = new MapDraftTestHost(disk.Provider(), sqlitePath: disk.DatabasePath, withIdentity: true);
        await restarted.StartAsync();
        await Login(restarted, "cycle1-visitor", register: false);
        var retained = Assert.Single((await restarted.Client.GetFromJsonAsync<HistoryItemDto[]>("/api/me/navigation-history"))!);
        Assert.Equal(historyId, retained.Id);
        Assert.Equal("Completed", retained.Status);
        var pin = await restarted.Client.GetFromJsonAsync<ResolveMapQrDto>("/api/public/qr/" + payload[6..]);
        Assert.Equal(publishedVersion, pin!.Version);
        await Login(restarted, "cycle1-other", register: true);
        Assert.Empty((await restarted.Client.GetFromJsonAsync<HistoryItemDto[]>("/api/me/navigation-history"))!);
        Assert.Equal(HttpStatusCode.NotFound,
            (await restarted.Client.GetAsync($"/api/me/navigation-history/{historyId}/resume")).StatusCode);
    }
}

