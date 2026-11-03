using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;

namespace WayMark.Api.Security;

/// <summary>Runs before Kestrel receives requests; every registered DbContext must be guarded.</summary>
public sealed class E2EStartupCheck(E2ESafetyProfile profile, IServiceScopeFactory scopes,
    IHostEnvironment environment, Type[] contextTypes) : IHostedService
{
    public static IReadOnlyList<DbContext> ValidateContexts(IServiceProvider scope, IEnumerable<Type> types, E2ESafetyProfile profile)
    {
        var contexts = types.Select(t => (DbContext)scope.GetRequiredService(t)).ToArray();
        if (contexts.Length < 2) throw E2ESafetyProfile.Refused("Identity and map DbContexts must both be registered");
        foreach (var context in contexts)
        {
            if (context.Database.ProviderName != "Microsoft.EntityFrameworkCore.SqlServer")
                throw E2ESafetyProfile.Refused("Every E2E DbContext must use guarded SQL Server");
            profile.ValidateConnection(context.Database.GetConnectionString()!);
            if (!context.GetService<IDbContextOptions>().Extensions.OfType<CoreOptionsExtension>()
                .SelectMany(e => e.Interceptors ?? []).OfType<E2EConnectionInterceptor>().Any())
                throw E2ESafetyProfile.Refused("An unguarded DbContext was registered");
        }
        return contexts;
    }
    public async Task StartAsync(CancellationToken cancellationToken)
    {
        E2EStorageAccess.Verify(profile, environment.ContentRootPath);
        using var scope = scopes.CreateScope();
        var contexts = ValidateContexts(scope.ServiceProvider, contextTypes, profile);
        try
        {
            foreach (var context in contexts)
            {
                // Only OPEN + metadata SELECT through the interceptor. Never CanConnect/Create/Migrate.
                await context.Database.OpenConnectionAsync(cancellationToken);
                await context.Database.CloseConnectionAsync();
            }
        }
        catch { throw E2ESafetyProfile.Refused("Could not confirm the approved SQL target; startup stopped"); }
    }
    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
