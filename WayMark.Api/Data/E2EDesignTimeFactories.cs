using Microsoft.AspNetCore.Builder;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using WayMark.Api.Security;

namespace WayMark.Api.Data;

/// <summary>EF CLI must explicitly opt into E2E. Never fall back to the normal development database.</summary>
public sealed class WayMarkDesignTimeFactory : IDesignTimeDbContextFactory<WayMarkDbContext>
{
    public WayMarkDbContext CreateDbContext(string[] args) => new(E2EDesignTimeOptions.Create<WayMarkDbContext>("__EFMigrationsHistory"));
}
public sealed class AuthDesignTimeFactory : IDesignTimeDbContextFactory<AuthDbContext>
{
    public AuthDbContext CreateDbContext(string[] args) => new(E2EDesignTimeOptions.Create<AuthDbContext>("__AuthMigrationsHistory"));
}
internal static class E2EDesignTimeOptions
{
    public static DbContextOptions<T> Create<T>(string history) where T : DbContext
    {
        var dotnet = Environment.GetEnvironmentVariable("DOTNET_ENVIRONMENT");
        var aspnet = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT");
        if (dotnet != E2ESafetyProfile.EnvironmentName || (aspnet is not null && aspnet != dotnet))
            throw E2ESafetyProfile.Refused("EF CLI requires explicit matching E2E environment variables");
        var cwd = Directory.GetCurrentDirectory();
        var root = Directory.Exists(Path.Combine(cwd, "WayMark.Api")) ? Path.Combine(cwd, "WayMark.Api") : cwd;
        var builder = WebApplication.CreateBuilder(new WebApplicationOptions {
            Args = [], ContentRootPath = root, EnvironmentName = dotnet,
            ApplicationName = typeof(WayMarkDbContext).Assembly.GetName().Name });
        var profile = E2ESafetyProfile.ReadAndApply(builder.Configuration, builder.Environment)
            ?? throw E2ESafetyProfile.Refused("Missing E2E profile");
        return new DbContextOptionsBuilder<T>().UseSqlServer(profile.ConnectionString,
            sql => sql.MigrationsHistoryTable(history)).AddInterceptors(new E2EConnectionInterceptor(profile)).Options;
    }
}
