using System.ComponentModel.DataAnnotations;

namespace WayMark.Api.Services.Routing;

/// <summary>Restrictions remove edges; preferences order feasible paths.</summary>
public sealed record RoutingOptions
{
    public bool AvoidStairs { get; init; }
    public bool Wheelchair { get; init; }

    [Required, RegularExpression("^(ShortestDistance|PreferElevators|LessWalking)$")]
    public string Preference { get; init; } = "ShortestDistance";
}
