using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;

namespace WayMark.Api.Security;

/// <summary>Shared production/test registration; no account or role is provisioned here.</summary>
public static class WayMarkSecurity
{
    public const string AdminPolicy = "AdminOnly";
    public const string AdminRole = "Admin";

    public static IServiceCollection AddWayMarkSecurity(
        this IServiceCollection services, IConfiguration configuration)
    {
        var secret = configuration["Jwt:SecretKey"]
            ?? throw new InvalidOperationException("Missing configuration: Jwt:SecretKey");
        var issuer = configuration["Jwt:Issuer"]
            ?? throw new InvalidOperationException("Missing configuration: Jwt:Issuer");
        var audience = configuration["Jwt:Audience"]
            ?? throw new InvalidOperationException("Missing configuration: Jwt:Audience");
        var key = new SymmetricSecurityKey(Convert.FromBase64String(secret));

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
            });

        services.AddAuthorization(options => options.AddPolicy(AdminPolicy,
            policy => policy.RequireAuthenticatedUser().RequireRole(AdminRole)));
        return services;
    }
}
