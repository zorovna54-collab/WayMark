using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using WayMark.Api.Security;
using WayMark.Api.Services.MapDrafts;

namespace WayMark.Api.Data;

public static class WayMarkDatabaseRegistration
{
    public static IServiceCollection AddWayMarkDatabases(this IServiceCollection services,
        IConfiguration configuration, E2ESafetyProfile? e2e)
    {
        if (e2e is not null)
        {
            services.AddSingleton(e2e);
            services.AddSingleton<E2EConnectionInterceptor>();
            // Pinned validated settings; config reload cannot move the E2E provider to another root.
            services.PostConfigure<ManagedMapImageOptions>(o => {
                o.Enabled = true; o.RootPath = e2e.ImageRoot;
                o.MaxStorageBytes = e2e.Images.MaxStorageBytes; o.MaxObjects = e2e.Images.MaxObjects;
            });
            services.PostConfigure<MapDraftLimitsOptions>(o => {
                o.MaxImagesPerFloor = e2e.Limits.MaxImagesPerFloor;
                o.MaxImageBytesPerFloor = e2e.Limits.MaxImageBytesPerFloor;
                o.MaxRevisionsPerFloor = e2e.Limits.MaxRevisionsPerFloor;
            });
        }
        services.AddDbContext<WayMarkDbContext>((sp, options) => Configure(sp, options, "__EFMigrationsHistory"));
        services.AddDbContext<AuthDbContext>((sp, options) => Configure(sp, options, "__AuthMigrationsHistory"));
        return services;

        void Configure(IServiceProvider sp, DbContextOptionsBuilder options, string history)
        {
            options.UseSqlServer(e2e?.ConnectionString ?? configuration.GetConnectionString("WayMarkDatabase"),
                sql => sql.MigrationsHistoryTable(history));
            if (e2e is not null) options.AddInterceptors(sp.GetRequiredService<E2EConnectionInterceptor>());
        }
    }

    public static IServiceCollection AddE2EStartupCheck(this IServiceCollection services, E2ESafetyProfile? e2e)
    {
        if (e2e is null) return services;
        // Capture all current contexts, including any future registered before this final hook.
        var types = services.Select(d => d.ServiceType).Where(t => !t.IsAbstract && t.IsSubclassOf(typeof(DbContext))).Distinct().ToArray();
        services.AddSingleton<IHostedService>(sp => new E2EStartupCheck(e2e,
            sp.GetRequiredService<IServiceScopeFactory>(), sp.GetRequiredService<IHostEnvironment>(), types));
        return services;
    }
}
