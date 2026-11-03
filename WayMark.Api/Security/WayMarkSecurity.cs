using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Authorization;
using WayMark.Api.Services.MapDrafts;

namespace WayMark.Api.Security;

/// <summary>Shared production/test registration; no account or role is provisioned here.</summary>
public static class WayMarkSecurity
{
    public static IServiceCollection AddPasswordResetLimits(this IServiceCollection services) => services.AddRateLimiter(options => {
        options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
        options.AddPolicy("PasswordReset", context => RateLimitPartition.GetFixedWindowLimiter(
            context.Connection.RemoteIpAddress?.ToString() ?? "unknown-client",
            _ => new FixedWindowRateLimiterOptions { PermitLimit = 5, Window = TimeSpan.FromMinutes(10), QueueLimit = 0 }));
    });
    public const string AdminPolicy = "AdminOnly";
    public const string AdminRole = "Admin";
    public const string MapAuthorPolicy = "MapAuthor";
    public const string CreatorRole = "Creator";
    public const string SiteManagerRole = "SiteManager";
    // Explicit server-provisioned permission, constrained to one Site and an owned map.
    public static string SitePublisherRole(int siteId) => "SitePublisher:" + siteId.ToString(System.Globalization.CultureInfo.InvariantCulture);
    public static bool IsMapAuthor(ClaimsPrincipal user) => user.IsInRole(AdminRole)
        || user.IsInRole(CreatorRole) || user.IsInRole(SiteManagerRole);

    public static IServiceCollection AddWayMarkSecurity(
        this IServiceCollection services, IConfiguration configuration)
    {
        var secret = configuration["Jwt:SecretKey"]
            ?? throw new InvalidOperationException("Missing configuration: Jwt:SecretKey");
        var issuer = configuration["Jwt:Issuer"]
            ?? throw new InvalidOperationException("Missing configuration: Jwt:Issuer");
        var audience = configuration["Jwt:Audience"]
            ?? throw new InvalidOperationException("Missing configuration: Jwt:Audience");
        byte[] bytes;
        try { bytes = Convert.FromBase64String(secret); }
        catch (FormatException) { throw new InvalidOperationException("Jwt:SecretKey must be supplied as a Base64 key outside tracked configuration"); }
        if (bytes.Length < 32 || string.IsNullOrWhiteSpace(issuer) || string.IsNullOrWhiteSpace(audience))
            throw new InvalidOperationException("JWT configuration requires a key of at least 32 bytes and nonempty issuer/audience");
        var key = new SymmetricSecurityKey(bytes);

        services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
            .AddJwtBearer(options =>
            {
                // The issuer writes standard role claims. Map JWT "role" to
                // ClaimTypes.Role explicitly; never inspect a client role header/body.
                options.MapInboundClaims = true;
                options.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidateIssuer = true,
                    ValidIssuer = issuer,
                    ValidateAudience = true,
                    ValidAudience = audience,
                    ValidateLifetime = true,
                    ValidateIssuerSigningKey = true,
                    RequireSignedTokens = true,
                    IssuerSigningKey = key,
                    ValidAlgorithms = [SecurityAlgorithms.HmacSha256],
                    RoleClaimType = ClaimTypes.Role,
                    ClockSkew = TimeSpan.FromSeconds(30)
                };
                options.Events = new JwtBearerEvents { OnTokenValidated = async context => {
                    var stamp = context.Principal?.FindFirstValue("waymark:security_stamp");
                    if (stamp is null) return; // Legacy JWTs expire normally; newly issued JWTs are stamp-bound.
                    var users = context.HttpContext.RequestServices.GetService<Microsoft.AspNetCore.Identity.UserManager<Microsoft.AspNetCore.Identity.IdentityUser>>();
                    var user = users is null ? null : await users.GetUserAsync(context.Principal!);
                    if (user is null || await users!.GetSecurityStampAsync(user) != stamp) context.Fail("Account credentials changed; sign in again");
                }};
            });

        services.AddScoped<IAuthorizationHandler, MapAuthorHandler>();
        services.AddScoped<IAuthorizationHandler, CurrentAdminHandler>();
        services.AddAuthorization(options => {
            options.AddPolicy(AdminPolicy, policy => policy.RequireAuthenticatedUser().AddRequirements(new CurrentAdminRequirement()));
            options.AddPolicy(MapAuthorPolicy, policy => policy.RequireAuthenticatedUser()
                .AddRequirements(new MapAuthorRequirement()));
        });
        return services;
    }
}
