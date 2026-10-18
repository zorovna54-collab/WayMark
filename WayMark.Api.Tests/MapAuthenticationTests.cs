using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.IdentityModel.Tokens;
using WayMark.Api.Controllers;
using WayMark.Api.Data;
using Xunit;

namespace WayMark.Api.Tests;

public sealed class MapAuthenticationTests
{
    [Fact]
    public async Task HttpEndpointsRejectMissingInvalidExpiredTokensAndAcceptSignedToken()
    {
        var key = new SymmetricSecurityKey(RandomNumberGenerator.GetBytes(32));
        var databaseName = Guid.NewGuid().ToString();
        using var host = await new HostBuilder().ConfigureWebHost(web => web
            .UseTestServer()
            .ConfigureServices(services =>
            {
                services.AddDbContext<WayMarkDbContext>(options => options.UseInMemoryDatabase(databaseName));
                services.AddControllers().AddApplicationPart(typeof(MapsController).Assembly);
                services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options =>
                    options.TokenValidationParameters = new TokenValidationParameters
                    {
                        ValidateIssuer = true, ValidIssuer = "test-issuer",
                        ValidateAudience = true, ValidAudience = "test-audience",
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
        using var client = host.GetTestClient();
        var urls = new[]
        {
            "/api/Maps/sites", "/api/Maps/floors/1/graph", "/api/WayMarks/code/QR/map-location",
            "/api/Maps/sites/1/buildings", "/api/Maps/buildings/1/floors"
        };
        foreach (var url in urls)
        {
            using var response = await client.GetAsync(url);
            Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        }
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", "invalid-token");
        using (var response = await client.GetAsync(urls[0]))
            Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", Token(key, true));
        using (var response = await client.GetAsync(urls[0]))
            Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", Token(key, false));
        using (var response = await client.GetAsync(urls[0]))
        {
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            Assert.Equal("[]", await response.Content.ReadAsStringAsync());
        }
        foreach (var url in urls.Skip(1))
        {
            using var response = await client.GetAsync(url);
            Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        }
    }

    private static string Token(SecurityKey key, bool expired) => new JwtSecurityTokenHandler().WriteToken(
        new JwtSecurityToken("test-issuer", "test-audience",
            notBefore: DateTime.UtcNow.AddMinutes(-10),
            expires: expired ? DateTime.UtcNow.AddMinutes(-5) : DateTime.UtcNow.AddMinutes(5),
            signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256)));
}
