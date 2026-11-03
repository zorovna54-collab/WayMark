[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$paths=@(
    Get-ChildItem (Join-Path $repo 'scripts/mapdraft-e2e') -File | Where-Object { $_.Extension -in '.ps1','.psm1' }
    Get-ChildItem (Join-Path $repo 'docs/database/e2e') -File | Where-Object { $_.Extension -in '.sql' -or $_.Name -eq 'DraftRoomFixture.json' }
    Get-Item (Join-Path $repo 'scripts/Start-MapDraftE2E.ps1')
    Get-Item (Join-Path $repo 'docs/development/MapPersistence7B2DExecutionPlan.md')
    Get-Item (Join-Path $repo 'WayMark.Api/Program.cs')
    Get-Item (Join-Path $repo 'WayMark.Api/appsettings.MapDraftE2E.json')
    Get-ChildItem (Join-Path $repo 'WayMark.Api/Security') -Filter 'E2E*.cs' -File
    Get-Item (Join-Path $repo 'WayMark.Api/Data/WayMarkDatabaseRegistration.cs')
    Get-Item (Join-Path $repo 'WayMark.Api/Data/E2EDesignTimeFactories.cs')
    Get-Item (Join-Path $repo 'WayMark.Api/Security/WayMarkSecurity.cs')
    Get-Item (Join-Path $repo 'WayMark.Api/WayMark.Api.csproj')
    Get-Item (Join-Path $repo 'WayMark.Api/Data/AuthDbContext.cs')
    Get-Item (Join-Path $repo 'WayMark.Api/Data/WayMarkDbContext.cs')
    Get-Item (Join-Path $repo 'WayMark.Api/Data/MapDraftModel.cs')
    Get-Item (Join-Path $repo 'WayMark.Api/Models/MapDrafts.cs')
    Get-Item (Join-Path $repo 'WayMark.Api/Contracts/MapDraftDtos.cs')
    Get-ChildItem (Join-Path $repo 'WayMark.Api/Controllers') -Filter '*.cs' -File
    Get-ChildItem (Join-Path $repo 'WayMark.Api/Services/MapDrafts') -Filter '*.cs' -File
    Get-ChildItem (Join-Path $repo 'WayMark.Api/Data/WayMarkMigrations') -Filter '*.cs' -File
    Get-ChildItem (Join-Path $repo 'WayMark.Api/Data/AuthMigrations') -Filter '*.cs' -File
)
$entries=@($paths | Sort-Object FullName -Unique | ForEach-Object {
    [ordered]@{Path=[IO.Path]::GetRelativePath($repo,$_.FullName).Replace('\','/');Sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
})
$manifest=[ordered]@{Version=1;Decision='NO-GO';GeneratedUtc=[DateTimeOffset]::UtcNow.ToString('o');
 Blockers=@('Backend HAS_PERMS_BY_NAME server-class defect requires a separately approved source fix and regression tests.',
 'Current SQL instance is Windows-authentication-only; choose an approved compatible isolated instance. No settings change is authorized.',
 'Provisioning, migrations, fixtures, storage/ACL, private configuration and HTTPS trust still require explicit approval.');Files=$entries}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $repo 'docs/database/e2e/ReviewManifest.json') -Encoding utf8
Write-Output 'Created NO-GO review manifest only. No database/storage setup was executed.'
