using Microsoft.Extensions.DependencyInjection.Extensions;

namespace WayMark.Api.Services.MapDrafts;

public static class MapDraftRegistration
{
    public static IServiceCollection AddMapDraftFoundation(this IServiceCollection services, IConfiguration? configuration = null)
    {
        services.AddOptions<ManagedMapImageOptions>();
        services.AddOptions<MapDraftLimitsOptions>();
        if (configuration is not null)
        {
            services.Configure<ManagedMapImageOptions>(configuration.GetSection(ManagedMapImageOptions.Section));
            services.Configure<MapDraftLimitsOptions>(configuration.GetSection(MapDraftLimitsOptions.Section));
        }
        services.AddSingleton<MapDraftValidator>();
        services.TryAddSingleton<WayMark.Api.Services.Routing.DijkstraRouter>();
        services.TryAddSingleton<TimeProvider>(TimeProvider.System);
        services.TryAddSingleton<MapImageCodec>();
        services.TryAddSingleton<IMapImageStorage, ManagedFileMapImageStorage>();
        services.AddScoped<IDraftSiteAccess, DraftSiteAccess>();
        services.AddScoped<MapDraftService>();
        services.AddScoped<MapProjectService>();
        services.AddScoped<PersonalMapAccess>();
        services.AddScoped<PersonalMapOnboarding>();
        services.AddScoped<MapDraftExceptionFilter>();
        return services;
    }
}
