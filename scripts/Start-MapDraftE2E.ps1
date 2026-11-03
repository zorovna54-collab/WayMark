[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

# This launcher never creates directories/databases, migrates, seeds or grants roles.
# Supply credentials in process environment from an approved private source.
$required = @('E2E__SqlConnectionString', 'E2E__SqlDataSource', 'E2E__ExpectedServerName',
    'E2E__JwtSecretKey', 'E2E__ImageRoot', 'MapImages__RootPath', 'E2E__ProtectedImageRoots__0')
foreach ($name in $required) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, 'Process'))) {
        throw "Missing $name. Refusing configuration fallback."
    }
}
if ($env:E2E__StorageIsolationConfirmed -ne 'true') { throw 'Storage isolation has not been confirmed.' }
if (![string]::IsNullOrWhiteSpace($env:ConnectionStrings__WayMarkDatabase) -or
    ![string]::IsNullOrWhiteSpace($env:ConnectionStrings__WayMarkAuthDatabase)) {
    throw 'Use a fresh E2E terminal without legacy connection overrides.'
}
$previousDotnet = $env:DOTNET_ENVIRONMENT
$previousAspnet = $env:ASPNETCORE_ENVIRONMENT
try {
    $env:DOTNET_ENVIRONMENT = 'MapDraftE2E'
    $env:ASPNETCORE_ENVIRONMENT = 'MapDraftE2E'
    $project = Join-Path $PSScriptRoot '../WayMark.Api/WayMark.Api.csproj'
    & dotnet run --project $project --no-launch-profile -- --environment MapDraftE2E --urls https://localhost:7627
    if ($LASTEXITCODE -ne 0) { throw 'E2E API did not start. Review the sanitized guard failure.' }
}
finally {
    $env:DOTNET_ENVIRONMENT = $previousDotnet
    $env:ASPNETCORE_ENVIRONMENT = $previousAspnet
}
