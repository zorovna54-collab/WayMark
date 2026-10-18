using System.Data.Common;
using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.IdentityModel.Tokens;
using WayMark.Api.Contracts;
using WayMark.Api.Controllers;
using WayMark.Api.Data;
using WayMark.Api.Models;
using WayMark.Api.Services.Routing;
using Xunit;
using WayMarkEntity = WayMark.Api.Models.WayMark;

namespace WayMark.Api.Tests;

public sealed class RouteApiTests : IAsyncLifetime
{
    private readonly SymmetricSecurityKey key = new(RandomNumberGenerator.GetBytes(32));
    private IHost host = null!;
    private HttpClient client = null!;
    private Exception? plannerFailure;

    public async Task InitializeAsync()
    {
        var databaseName = Guid.NewGuid().ToString();
        host = await new HostBuilder().ConfigureWebHost(web => web.UseTestServer()
            .ConfigureServices(services =>
            {
                services.AddDbContext<WayMarkDbContext>(options => options.UseInMemoryDatabase(databaseName));
                services.AddSingleton<DijkstraRouter>();
                services.AddScoped<RoutePlanner>();
                services.AddScoped<IRoutePlanner>(provider => new FailureInjectingPlanner(
                    provider.GetRequiredService<RoutePlanner>(), () => plannerFailure));
                services.AddControllers().AddApplicationPart(typeof(RoutesController).Assembly);
                services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options =>
                    options.TokenValidationParameters = new TokenValidationParameters
                    {
                        ValidateIssuer = true, ValidIssuer = "route-test",
                        ValidateAudience = true, ValidAudience = "route-test",
                        ValidateLifetime = true, ValidateIssuerSigningKey = true,
                        IssuerSigningKey = key, ClockSkew = TimeSpan.Zero
                    });
                services.AddAuthorization();
            })
            .Configure(app =>
            {
                app.UseRouting();
                app.UseAuthentication();
                app.UseAuthorization();
                app.UseEndpoints(endpoints => endpoints.MapControllers());
            })).StartAsync();

        using (var scope = host.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
            db.Sites.Add(new Site { Id = 1, Code = "TEST", Name = "Test site" });
            db.Buildings.Add(new Building { Id = 1, SiteId = 1, BuildingCode = "TEST", Name = "Test building" });
            db.Floors.AddRange(
                new Floor { Id = 10, BuildingId = 1, FloorCode = "G", Name = "Ground" },
                new Floor { Id = 20, BuildingId = 1, FloorCode = "L1", Name = "Level 1", SortOrder = 1 });
            db.NavigationNodes.AddRange(Node(101, 10), Node(102, 10), Node(103, 20), Node(104, 20));
            db.NavigationEdges.AddRange(
                new NavigationEdge { Id = 1, FromNodeId = 101, ToNodeId = 103, DistanceMeters = 50m, EdgeType = NavigationEdgeType.Elevator, IsAccessible = true },
                new NavigationEdge { Id = 2, FromNodeId = 101, ToNodeId = 102, DistanceMeters = 4m, IsAccessible = false },
                new NavigationEdge { Id = 3, FromNodeId = 102, ToNodeId = 103, DistanceMeters = 6m, EdgeType = NavigationEdgeType.Elevator, IsAccessible = true },
                new NavigationEdge { Id = 4, FromNodeId = 103, ToNodeId = 101, DistanceMeters = 1m, IsActive = false });
            db.WayMarks.AddRange(
                Mark(1, "START", 101), Mark(2, "END", 103), Mark(3, "UNMAPPED", null),
                Mark(4, "ISOLATED", 104),
                // InMemory deliberately permits this invalid FK to exercise defensive API handling.
                Mark(5, "BROKEN", 999));
            await db.SaveChangesAsync();
        }
        client = host.GetTestClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", Token(false));
    }

    [Fact]
    public async Task ShortestPathHasOrderedNodesEdgesAndCrossFloorElevator()
    {
        using var response = await Post(" START ", "END");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var route = (await response.Content.ReadFromJsonAsync<RouteResponseDto>())!;
        Assert.Equal("START", route.Start.WayMarkCode);
        Assert.Equal(10m, route.TotalDistanceMeters);
        Assert.False(route.AccessibleOnly);
        Assert.Equal(new[] { 101, 102, 103 }, route.Nodes.Select(node => node.Id));
        Assert.Equal(new[] { 2, 3 }, route.Edges.Select(edge => edge.Id));
        Assert.Equal(new[] { 1, 2 }, route.Edges.Select(edge => edge.Sequence));
        Assert.Equal("SameFloor", route.Edges[0].Movement);
        Assert.Equal("ChangeFloor", route.Edges[1].Movement);
        Assert.Equal("Elevator", route.Edges[1].EdgeType);
        Assert.Equal(10, route.Edges[1].FromFloorId);
        Assert.Equal(20, route.Edges[1].ToFloorId);
        Assert.Equal("L1", route.Nodes[^1].Floor.FloorCode);
        Assert.Equal(route.TotalDistanceMeters, route.Edges.Sum(edge => edge.DistanceMeters));
    }

    [Fact]
    public async Task AccessibleQueryFiltersOnlyOnExplicitRequest()
    {
        using var response = await Post("START", "END", "?accessibleOnly=true");
        var route = (await response.Content.ReadFromJsonAsync<RouteResponseDto>())!;
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(route.AccessibleOnly);
        Assert.Equal(50m, route.TotalDistanceMeters);
        Assert.True(Assert.Single(route.Edges).IsAccessible);
    }

    [Fact]
    public async Task AccessibleRequestCanHaveNoRouteWhileDefaultRouteExists()
    {
        using (var scope = host.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
            (await db.NavigationEdges.SingleAsync(edge => edge.Id == 1)).IsActive = false;
            await db.SaveChangesAsync();
        }
        using var accessible = await Post("START", "END", "?accessibleOnly=true");
        await AssertProblem(accessible, 422, "no_route");
        using var normal = await Post("START", "END");
        Assert.Equal(HttpStatusCode.OK, normal.StatusCode);
    }

    [Fact]
    public async Task SameWayMarkReturnsZeroDistance()
    {
        using var response = await Post("START", "START");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var route = (await response.Content.ReadFromJsonAsync<RouteResponseDto>())!;
        Assert.Equal(0m, route.TotalDistanceMeters);
        Assert.Single(route.Nodes);
        Assert.Empty(route.Edges);
    }

    [Theory]
    [InlineData("MISSING", "END", 404, "start_waymark_not_found")]
    [InlineData("START", "MISSING", 404, "destination_waymark_not_found")]
    [InlineData("UNMAPPED", "END", 409, "start_not_mapped")]
    [InlineData("START", "UNMAPPED", 409, "destination_not_mapped")]
    [InlineData("BROKEN", "END", 409, "start_node_not_found")]
    [InlineData("START", "BROKEN", 409, "destination_node_not_found")]
    [InlineData("START", "ISOLATED", 422, "no_route")]
    [InlineData("END", "START", 422, "no_route")]
    public async Task DomainFailuresHaveDistinctStatusAndCode(string start, string end, int status, string code)
    {
        using var response = await Post(start, end);
        await AssertProblem(response, status, code);
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("null")]
    [InlineData("{\"startWayMarkCode\":\" \",\"destinationWayMarkCode\":\"END\"}")]
    [InlineData("{\"startWayMarkCode\":\"START\",\"destinationWayMarkCode\":null}")]
    [InlineData("{bad-json")]
    public async Task InvalidRequestReturns400(string body)
    {
        using var response = await client.PostAsync("/api/routes", new StringContent(body, Encoding.UTF8, "application/json"));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task TooLongCodeReturns400()
    {
        using var response = await Post(new string('x', 101), "END");
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task MissingInvalidExpiredJwtAreRejected()
    {
        foreach (var token in new string?[] { null, "invalid-token", Token(true) })
        {
            client.DefaultRequestHeaders.Authorization = token is null ? null : new AuthenticationHeaderValue("Bearer", token);
            using var response = await Post("START", "END");
            Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        }
    }

    [Fact]
    public async Task InvalidGraphReturnsSanitized500()
    {
        using (var scope = host.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
            (await db.NavigationEdges.SingleAsync(edge => edge.Id == 3)).DistanceMeters = 0m;
            await db.SaveChangesAsync();
        }
        using var response = await Post("START", "END");
        await AssertProblem(response, 500, "invalid_graph");
    }

    [Theory]
    [InlineData(true, 503, "route_data_unavailable")]
    [InlineData(false, 500, "route_calculation_failed")]
    public async Task InternalFailuresDoNotExposeExceptionDetails(bool databaseFailure, int status, string code)
    {
        plannerFailure = databaseFailure ? new TestDbException("PRIVATE_DATABASE_DETAIL") : new InvalidOperationException("PRIVATE_DATABASE_DETAIL");
        using var response = await Post("START", "END");
        await AssertProblem(response, status, code);
        var body = await response.Content.ReadAsStringAsync();
        Assert.DoesNotContain("PRIVATE_DATABASE_DETAIL", body);
        Assert.DoesNotContain("stackTrace", body, StringComparison.OrdinalIgnoreCase);
    }

    private Task<HttpResponseMessage> Post(string start, string end, string query = "") =>
        client.PostAsJsonAsync("/api/routes" + query, new { startWayMarkCode = start, destinationWayMarkCode = end });

    private static async Task AssertProblem(HttpResponseMessage response, int status, string code)
    {
        Assert.Equal(status, (int)response.StatusCode);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(status, json.RootElement.GetProperty("status").GetInt32());
        Assert.Equal(code, json.RootElement.GetProperty("code").GetString());
    }

    private string Token(bool expired) => new JwtSecurityTokenHandler().WriteToken(new JwtSecurityToken(
        "route-test", "route-test", notBefore: DateTime.UtcNow.AddMinutes(-10),
        expires: DateTime.UtcNow.AddMinutes(expired ? -5 : 5),
        signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256)));
    private static NavigationNode Node(int id, int floorId) => new()
    { Id = id, FloorId = floorId, NodeCode = $"TEST-{id}", Name = $"Node {id}", NodeType = NavigationNodeType.Junction };
    private static WayMarkEntity Mark(int id, string code, int? nodeId) => new()
    { Id = id, WayMarkCode = code, Name = code, Location = "Test", NavigationNodeId = nodeId };

    public async Task DisposeAsync()
    {
        client.Dispose();
        await host.StopAsync();
        host.Dispose();
    }

    private sealed class TestDbException(string message) : DbException(message);
    private sealed class FailureInjectingPlanner(RoutePlanner actual, Func<Exception?> failure) : IRoutePlanner
    {
        public Task<RoutePlanResult> PlanAsync(string startCode, string destinationCode, bool accessibleOnly, CancellationToken cancellationToken) =>
            failure() is Exception exception ? Task.FromException<RoutePlanResult>(exception)
                : actual.PlanAsync(startCode, destinationCode, accessibleOnly, cancellationToken);
    }
}
