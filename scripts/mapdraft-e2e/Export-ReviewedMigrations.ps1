[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ApiOutputDirectory,
    [Parameter(Mandatory)][string]$EfToolDll
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$output = Join-Path $repo 'docs/database/e2e'
if (!(Test-Path -LiteralPath $output -PathType Container)) { throw 'Create the reviewed script directory in the repository first.' }
$api = [IO.Path]::GetFullPath($ApiOutputDirectory)
$ef = [IO.Path]::GetFullPath($EfToolDll)
foreach ($file in @('WayMark.Api.dll','WayMark.Api.deps.json','WayMark.Api.runtimeconfig.json')) {
    if (!(Test-Path -LiteralPath (Join-Path $api $file))) { throw 'Missing current compiled API artifacts.' }
}
if (!(Test-Path -LiteralPath $ef)) { throw 'Missing workspace-local EF tool assembly.' }
# Offline only: IMigrator.GenerateScript, not database update. No API Build/Run,
# database connection, storage directory creation, or private credential is needed.
$settings = @{
    DOTNET_ENVIRONMENT='MapDraftE2E'; ASPNETCORE_ENVIRONMENT='MapDraftE2E';
    E2E__Enabled='true'; E2E__SqlDataSource='offline-generator.invalid';
    E2E__ExpectedServerName='OFFLINE-GENERATOR';
    E2E__SqlConnectionString=('Server=offline-generator.invalid;Database=WayMark_MapDraft_E2E_Test;User ID=offline-generator;Password=' + [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)) + ';Encrypt=True;Connect Timeout=3');
    E2E__JwtSecretKey=[Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32));
    E2E__ImageRoot=(Join-Path ([IO.Path]::GetTempPath()) 'WayMarkOfflineReview/WayMark_MapDraft_E2E_Test/images');
    MapImages__RootPath=(Join-Path ([IO.Path]::GetTempPath()) 'WayMarkOfflineReview/WayMark_MapDraft_E2E_Test/images');
    E2E__ProtectedImageRoots__0=(Join-Path ([IO.Path]::GetTempPath()) 'WayMarkOfflineReview/protected-images');
    E2E__StorageIsolationConfirmed='true'; ConnectionStrings__WayMarkDatabase=''; ConnectionStrings__WayMarkAuthDatabase=''
}
$previous = @{}
$guard = @'
-- Execution requires a parameterized runner; never paste a secret into this file.
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'WayMark_MapDraft_E2E_Test'
 OR NULLIF(@ExpectedServerName,N'') IS NULL
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) <> @ExpectedServerName
 OR SUSER_SNAME() <> N'WayMark_E2E_Migrator' OR ORIGINAL_LOGIN() <> N'WayMark_E2E_Migrator'
 OR ISNULL(IS_SRVROLEMEMBER('sysadmin'),1) <> 0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'CONTROL SERVER'),1) <> 0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY LOGIN'),1) <> 0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY DATABASE'),1) <> 0
 OR ISNULL(HAS_DBACCESS(N'WayMarkDatabase'),0) <> 0 OR ISNULL(HAS_DBACCESS(N'WayMarkAuthDatabase'),0) <> 0
    THROW 51000, 'Migration target/principal guard refused execution.', 1;
'@
try {
    foreach ($name in $settings.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name,'Process')
        [Environment]::SetEnvironmentVariable($name,$settings[$name],'Process')
    }
    Push-Location $repo
    try {
        foreach ($item in @(
            @{ Context='AuthDbContext'; Last='20261010032404_CreateAuthSchema'; File='30-AuthSchema.sql' },
            @{ Context='WayMarkDbContext'; Last='20261020101304_BindMapImagesToDrafts'; File='31-WayMarkSchema.sql' }
        )) {
            $temporary = Join-Path $output (([guid]::NewGuid().ToString('N')) + '.generated.tmp')
            try {
                & dotnet exec --depsfile (Join-Path $api 'WayMark.Api.deps.json') --runtimeconfig (Join-Path $api 'WayMark.Api.runtimeconfig.json') $ef migrations script 0 $item.Last --idempotent --context $item.Context --assembly (Join-Path $api 'WayMark.Api.dll') --startup-assembly (Join-Path $api 'WayMark.Api.dll') --project (Join-Path $repo 'WayMark.Api/WayMark.Api.csproj') --startup-project (Join-Path $repo 'WayMark.Api/WayMark.Api.csproj') --project-dir (Join-Path $repo 'WayMark.Api') --output $temporary
                if ($LASTEXITCODE -ne 0) { throw 'Offline EF SQL generation failed.' }
                $sql = [IO.File]::ReadAllText($temporary)
                if ($sql -match '(?im)^\s*(DROP|TRUNCATE|DELETE|UPDATE)\b') { throw 'Unexpected destructive/business-data command in forward migration SQL.' }
                $batches = [regex]::Split($sql,'(?im)^\s*GO\s*\r?$') | Where-Object { ![string]::IsNullOrWhiteSpace($_) }
                $guarded = $batches | ForEach-Object { $guard + "`r`n" + $_.Trim() + "`r`nGO`r`n" }
                $header = "-- EF Core SQL Server 10.0.12; 0 -> $($item.Last); $($item.Context).`r`n-- Generated offline; only guards added per batch; NEVER EXECUTED by this generator.`r`n"
                [IO.File]::WriteAllText((Join-Path $output $item.File), $header + ($guarded -join "`r`n"), [Text.UTF8Encoding]::new($false))
                Write-Output ('Generated SQL only: ' + $item.File)
            }
            finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
        }
    }
    finally { Pop-Location }
}
finally {
    foreach ($name in $previous.Keys) { [Environment]::SetEnvironmentVariable($name,$previous[$name],'Process') }
}
