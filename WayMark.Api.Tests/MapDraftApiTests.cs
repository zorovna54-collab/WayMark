using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using WayMark.Api.Contracts;
using WayMark.Api.Data;
using WayMark.Api.Models;
using WayMark.Api.Services.MapDrafts;
using WayMark.Api.Services.Routing;
using Xunit;

namespace WayMark.Api.Tests;

public sealed class MapDraftApiTests : IAsyncLifetime
{
    private readonly MapDraftTestHost test = new();
    private const string Base = "/api/admin/floors/10/map-drafts";
    public Task InitializeAsync() => test.StartAsync();
    public async Task DisposeAsync() => await test.DisposeAsync();

    [Theory]
    [InlineData("missing", 401)]
    [InlineData("expired", 401)]
    [InlineData("bad-signature", 401)]
    [InlineData("forged-role", 401)]
    [InlineData("missing-subject", 403)]
    [InlineData("user", 403)]
    public async Task InvalidOrUnprivilegedJwtCannotReadOrWriteDrafts(string kind, int status)
    {
        test.Token(kind);
        using var read = await test.Client.GetAsync(Base);
        using var write = await test.Client.PostAsJsonAsync(Base, MapDraftValidationTests.Content());
        Assert.Equal(status, (int)read.StatusCode);
        Assert.Equal(status, (int)write.StatusCode);
        using var scope = test.Scope();
        var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
        Assert.Empty(await db.FloorMapDrafts.ToListAsync());
        Assert.Empty(await db.FloorMapDraftRevisions.ToListAsync());
        Assert.Equal(2, await db.WayMarks.CountAsync());
    }

    [Theory]
    [InlineData("global-admin-without-membership")]
    [InlineData("admin-b")]
    [InlineData("inactive")]
    [InlineData("no-edit")]
    public async Task GlobalAdminAndClientSiteClaimsDoNotGrantScope(string userId)
    {
        test.Token(userId: userId);
        test.Client.DefaultRequestHeaders.Add("X-Site-Id", "1");
        using var response = await test.Client.PostAsJsonAsync(Base, MapDraftValidationTests.Content());
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task ScopeIsCheckedBeforeDraftEnumerationAndMissingInScopeReturns404()
    {
        Assert.Equal(HttpStatusCode.NotFound, (await test.Client.GetAsync(Base)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await test.Client.GetAsync("/api/admin/floors/20/map-drafts")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await test.Client.GetAsync("/api/admin/floors/999/map-drafts")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await test.Client.GetAsync(Base + $"/{Guid.NewGuid()}/graph")).StatusCode);
    }

    [Fact]
    public async Task AuthorizedAdminCanSaveReadSearchAndRestoreImmutableVersions()
    {
        var content = MapDraftValidationTests.Content();
        var created = await Create(content);
        Assert.Equal("admin-a", created.CreatedBy);
        Assert.Equal(1, created.SiteId);
        Assert.Equal(1, created.Version);
        Assert.Equal("Draft", created.Status);
        var changed = content with { Places = [content.Places![0] with { Name = "Updated room" }] };
        using var update = await test.Client.PutAsJsonAsync(Base + $"/{created.Id}", new SaveMapDraftRequest(1, changed));
        Assert.Equal(HttpStatusCode.OK, update.StatusCode);
        var current = await test.Client.GetFromJsonAsync<MapDraftMetadataDto>(Base);
        Assert.Equal(2, current!.Version);
        var old = await test.Client.GetFromJsonAsync<MapDraftGraphDto>(Base + $"/{created.Id}/graph?version=1");
        Assert.Equal("Phòng khám", old!.Content.Places![0].Name);
        var found = await test.Client.GetFromJsonAsync<DraftPlaceDto[]>(Base + $"/{created.Id}/places?query=updated");
        Assert.Single(found!);
        Assert.Equal(2, found![0].EntranceNodeIds!.Count);
        Assert.Empty((await test.Client.GetFromJsonAsync<DraftPlaceDto[]>(Base + $"/{created.Id}/places?query=absent"))!);
        using var restore = await test.Client.PostAsJsonAsync(Base + $"/{created.Id}/restore", new RestoreMapDraftRequest(2, 1));
        Assert.Equal(HttpStatusCode.OK, restore.StatusCode);
        Assert.Equal(3, (await restore.Content.ReadFromJsonAsync<MapDraftMetadataDto>())!.Version);
        var latest = await test.Client.GetFromJsonAsync<MapDraftGraphDto>(Base + $"/{created.Id}/graph");
        Assert.Equal("Phòng khám", latest!.Content.Places![0].Name);
        var versions = await test.Client.GetFromJsonAsync<MapDraftRevisionDto[]>(Base + $"/{created.Id}/versions");
        Assert.Equal(new long[] { 3, 2, 1 }, versions!.Select(x => x.Version));
        var page = await test.Client.GetFromJsonAsync<MapDraftRevisionDto[]>(Base + $"/{created.Id}/versions?beforeVersion=3&take=1");
        Assert.Equal(2, Assert.Single(page!).Version);
    }

    [Fact]
    public async Task StaleSaveRestoreAndDuplicateCreateReturn409WithoutNewRevision()
    {
        var content = MapDraftValidationTests.Content();
        var draft = await Create(content);
        Assert.Equal(HttpStatusCode.Conflict, (await test.Client.PostAsJsonAsync(Base, content)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await test.Client.PutAsJsonAsync(Base + $"/{draft.Id}", new SaveMapDraftRequest(1, content))).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await test.Client.PutAsJsonAsync(Base + $"/{draft.Id}", new SaveMapDraftRequest(1, content))).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await test.Client.PostAsJsonAsync(Base + $"/{draft.Id}/restore", new RestoreMapDraftRequest(1, 1))).StatusCode);
        using var scope = test.Scope();
        var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
        Assert.Equal(2, await db.FloorMapDraftRevisions.CountAsync());
    }

    [Fact]
    public async Task MembershipRevocationIsEffectiveOnNextDraftRequestWithoutChangingJwt()
    {
        await Create(MapDraftValidationTests.Content());
        using (var scope = test.Scope())
        {
            var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
            (await db.SiteMapMemberships.SingleAsync(x => x.UserId == "admin-a")).IsActive = false;
            await db.SaveChangesAsync();
        }
        Assert.Equal(HttpStatusCode.Forbidden, (await test.Client.GetAsync(Base)).StatusCode);
    }

    [Fact]
    public async Task InvalidDraftAndInjectedOwnershipAreRejected()
    {
        var invalid = MapDraftValidationTests.Content() with { Edges = [new DraftEdgeDto { Id = Guid.NewGuid() }] };
        Assert.Equal(HttpStatusCode.BadRequest, (await test.Client.PostAsJsonAsync(Base, invalid)).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await test.Client.PostAsJsonAsync(Base + "/validate", invalid)).StatusCode);
        using var body = new StringContent("{\"siteId\":1,\"createdBy\":\"other\",\"imageBase64\":\"hidden\"}", Encoding.UTF8, "application/json");
        Assert.Equal(HttpStatusCode.BadRequest, (await test.Client.PostAsync(Base, body)).StatusCode);
        var validation = await test.Client.PostAsJsonAsync(Base + "/validate", MapDraftValidationTests.Content());
        Assert.False((await validation.Content.ReadFromJsonAsync<DraftValidationDto>())!.ReadyForProduction);
    }

    [Fact]
    public async Task MissingNodeTypeOrCoordinatesAreNotInferredAsAnEntranceAtZero()
    {
        var body = new { nodes = new[] { new { id = Guid.NewGuid(), nodeCode = "NO-TYPE", name = "Unknown" } } };
        Assert.Equal(HttpStatusCode.BadRequest, (await test.Client.PostAsJsonAsync(Base, body)).StatusCode);
    }

    [Fact]
    public async Task ReadIsNotCacheableAndCannotExposeAnotherFloorsDraftOrImage()
    {
        var draft = await Create(MapDraftValidationTests.Content());
        using var read = await test.Client.GetAsync(Base + $"/{draft.Id}/graph");
        Assert.True(read.Headers.CacheControl!.NoStore);
        Assert.Equal(HttpStatusCode.NotFound, (await test.Client.GetAsync($"/api/admin/floors/11/map-drafts/{draft.Id}/graph")).StatusCode);
        var id = Guid.NewGuid();
        await Create(new(), "/api/admin/floors/11/map-drafts");
        using (var scope = test.Scope())
        {
            var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
            db.FloorMapImageAssets.Add(new FloorMapImageAsset { Id = id, FloorId = 11, StorageKey = id.ToString("N"),
                MimeType = "image/png", Width = 900, Height = 598, ByteLength = 100, Sha256 = new string('a', 64), CreatedBy = "admin-a" });
            await db.SaveChangesAsync();
        }
        Assert.Equal(HttpStatusCode.NotFound, (await test.Client.GetAsync(Base + $"/images/{id}")).StatusCode);
        var content = MapDraftValidationTests.Content() with { ImageAssetId = id };
        Assert.Equal(HttpStatusCode.BadRequest, (await test.Client.PostAsJsonAsync(Base + "/validate", content)).StatusCode);
    }

    [Fact]
    public async Task DocumentsOverTheBoundedJsonLimitReturn413()
    {
        var content = MapDraftValidationTests.Content();
        content = content with { Nodes = [content.Nodes![0] with { Name = new string('x', MapDraftValidator.MaxDocumentBytes) }] };
        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, (await test.Client.PostAsJsonAsync(Base, content)).StatusCode);
    }

    [Fact]
    public async Task PublishedQrReferencesMustMatchTheirSourceAndFloor()
    {
        var content = MapDraftValidationTests.Content();
        var first = content.Nodes![0] with { SourceNodeId = 100, ExistingWayMarkCode = "PUBLISHED-QR-A" };
        var valid = content with { Nodes = [first, content.Nodes[1]] };
        Assert.Equal(HttpStatusCode.OK, (await test.Client.PostAsJsonAsync(Base + "/validate", valid)).StatusCode);
        var mismatched = valid with { Nodes = [first with { SourceNodeId = 101 }, content.Nodes[1]] };
        Assert.Equal(HttpStatusCode.BadRequest, (await test.Client.PostAsJsonAsync(Base + "/validate", mismatched)).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await test.Client.PostAsJsonAsync("/api/admin/floors/11/map-drafts/validate", valid)).StatusCode);
    }

    [Fact]
    public async Task TransitionPinsAnotherFloorRevisionAndRejectsOtherSitesOrUnknownNodes()
    {
        var lowerNode = new DraftNodeDto { Id = Guid.NewGuid(), NodeCode = "LIFT-G", Name = "Lift G", NodeType = NavigationNodeType.Elevator };
        var upperNode = lowerNode with { Id = Guid.NewGuid(), NodeCode = "LIFT-1", Name = "Lift 1" };
        var upper = await Create(new() { Nodes = [upperNode] }, "/api/admin/floors/11/map-drafts");
        var transition = new DraftTransitionDto { Id = Guid.NewGuid(), FromNodeId = lowerNode.Id,
            TargetDraftId = upper.Id, TargetVersion = 1, TargetNodeId = upperNode.Id,
            EdgeType = NavigationEdgeType.Elevator, DistanceMeters = 4 };
        var lower = new MapDraftContent { Nodes = [lowerNode], Transitions = [transition] };
        var saved = await Create(lower);
        var graph = await test.Client.GetFromJsonAsync<MapDraftGraphDto>(Base + $"/{saved.Id}/graph");
        Assert.Equal(upper.Id, Assert.Single(graph!.Content.Transitions!).TargetDraftId);
        Assert.Equal(HttpStatusCode.BadRequest, (await test.Client.PostAsJsonAsync(Base + "/validate", lower with
            { Transitions = [transition with { TargetNodeId = Guid.NewGuid() }] })).StatusCode);
        test.Token(userId: "admin-b");
        var other = await Create(new() { Nodes = [upperNode] }, "/api/admin/floors/20/map-drafts");
        test.Token();
        Assert.Equal(HttpStatusCode.BadRequest, (await test.Client.PostAsJsonAsync(Base + "/validate", lower with
            { Transitions = [transition with { TargetDraftId = other.Id }] })).StatusCode);
    }

    [Fact]
    public async Task ImageUploadIsBoundedPrivateAndFailsClosedWithoutAValidatedProvider()
    {
        await Create(new());
        using var invalid = new ByteArrayContent([1, 2, 3]);
        invalid.Headers.ContentType = new("image/svg+xml");
        Assert.Equal(HttpStatusCode.BadRequest, (await test.Client.PostAsync(Base + "/images", invalid)).StatusCode);
        using var png = new ByteArrayContent([137, 80, 78, 71]);
        png.Headers.ContentType = new("image/png");
        var disabled = await test.Client.PostAsync(Base + "/images", png);
        Assert.Equal(HttpStatusCode.ServiceUnavailable, disabled.StatusCode);
        Assert.Contains("image_storage_unavailable", await disabled.Content.ReadAsStringAsync());
        using var huge = new ByteArrayContent(new byte[MapImageRules.MaxBytes + 1]);
        huge.Headers.ContentType = new("image/png");
        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, (await test.Client.PostAsync(Base + "/images", huge)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await test.Client.GetAsync($"/api/admin/floors/20/map-drafts/images/{Guid.NewGuid()}")).StatusCode);
        using var scope = test.Scope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<WayMarkDbContext>().FloorMapImageAssets.ToListAsync());
    }

    [Fact]
    public async Task SavingAndRestoringDraftNeverChangesProductionRoutingOrQr()
    {
        using var scope = test.Scope();
        var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
        var before = await PublishedSnapshot(db);
        var planner = new RoutePlanner(db, new DijkstraRouter());
        var originalRoute = await planner.PlanAsync("PUBLISHED-QR-A", "PUBLISHED-QR-B", false, default);
        Assert.Equal(40m, originalRoute.Route!.TotalDistanceMeters);
        var content = MapDraftValidationTests.Content();
        var draft = await Create(content);
        await test.Client.PutAsJsonAsync(Base + $"/{draft.Id}", new SaveMapDraftRequest(1, new()));
        await test.Client.PostAsJsonAsync(Base + $"/{draft.Id}/restore", new RestoreMapDraftRequest(2, 1));
        Assert.Equal(before, await PublishedSnapshot(db));
        var route = await planner.PlanAsync("PUBLISHED-QR-A", "PUBLISHED-QR-B", false, default);
        Assert.Equal(originalRoute.Route, route.Route, new RouteDistanceComparer());
    }

    [Fact]
    public async Task RelationalFailureDuringSecondWriteRollsBackBothHeadAndRevision()
    {
        var draft = await Create(MapDraftValidationTests.Content());
        test.Failure.Armed = true;
        var failure = await test.Client.PutAsJsonAsync(Base + $"/{draft.Id}", new SaveMapDraftRequest(1, new()));
        Assert.Equal(HttpStatusCode.ServiceUnavailable, failure.StatusCode);
        Assert.Equal(2, test.Failure.WritesObserved);
        Assert.DoesNotContain("Injected", await failure.Content.ReadAsStringAsync());
        Assert.DoesNotContain("StackTrace", await failure.Content.ReadAsStringAsync());
        using var scope = test.Scope();
        var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
        Assert.Equal(1, (await db.FloorMapDrafts.SingleAsync()).Version);
        Assert.Single(await db.FloorMapDraftRevisions.ToListAsync());
    }

    [Fact]
    public async Task RacingRelationalWritesCannotOverwriteAnImmutableRevisionAndReturn409()
    {
        var content = MapDraftValidationTests.Content();
        var draft = await Create(content);
        using var firstScope = test.Scope();
        using var secondScope = test.Scope();
        var firstDb = firstScope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
        var secondDb = secondScope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
        await firstDb.FloorMapDrafts.SingleAsync();
        await secondDb.FloorMapDrafts.SingleAsync();
        await firstScope.ServiceProvider.GetRequiredService<MapDraftService>().SaveAsync(test.Principal(), 10,
            draft.Id, new(1, content), default);
        var conflict = await Assert.ThrowsAsync<DraftOperationException>(() => secondScope.ServiceProvider.GetRequiredService<MapDraftService>()
            .SaveAsync(test.Principal(), 10, draft.Id, new(1, content), default));
        Assert.Equal(409, conflict.Status);
        Assert.True(secondDb.Model.FindEntityType(typeof(FloorMapDraft))!.FindProperty(nameof(FloorMapDraft.Version))!.IsConcurrencyToken);
        using var fresh = test.Scope();
        var db = fresh.ServiceProvider.GetRequiredService<WayMarkDbContext>();
        Assert.Equal(2, (await db.FloorMapDrafts.SingleAsync()).Version);
        Assert.Equal(2, await db.FloorMapDraftRevisions.CountAsync());
    }

    private async Task<MapDraftMetadataDto> Create(MapDraftContent content, string path = Base)
    {
        using var response = await test.Client.PostAsJsonAsync(path, content);
        Assert.True(response.StatusCode == HttpStatusCode.Created, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<MapDraftMetadataDto>())!;
    }
    private static async Task<string> PublishedSnapshot(WayMarkDbContext db) => JsonSerializer.Serialize(new
    {
        nodes = await db.NavigationNodes.AsNoTracking().OrderBy(x => x.Id).ToListAsync(),
        edges = await db.NavigationEdges.AsNoTracking().OrderBy(x => x.Id).ToListAsync(),
        qr = await db.WayMarks.AsNoTracking().OrderBy(x => x.Id).ToListAsync()
    });
    private sealed class RouteDistanceComparer : IEqualityComparer<RouteResponseDto?>
    {
        public bool Equals(RouteResponseDto? a, RouteResponseDto? b) => a?.TotalDistanceMeters == b?.TotalDistanceMeters
            && a!.Edges.Select(x => x.Id).SequenceEqual(b!.Edges.Select(x => x.Id));
        public int GetHashCode(RouteResponseDto? route) => route?.TotalDistanceMeters.GetHashCode() ?? 0;
    }
}
