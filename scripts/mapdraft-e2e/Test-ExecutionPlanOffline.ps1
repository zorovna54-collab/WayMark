[CmdletBinding()]
param([Parameter(Mandatory)][string]$SqlClientDirectory,[Parameter(Mandatory)][string]$AspNetRuntimeDirectory)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$checks=0
foreach ($file in Get-ChildItem $PSScriptRoot -File | Where-Object { $_.Extension -in '.ps1','.psm1' }) {
    $tokens=$null; $errors=$null
    [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count) { throw ('PowerShell syntax failed: '+$file.Name) }; $checks++
}
foreach ($file in Get-ChildItem (Join-Path $repo 'docs/database/e2e') -Filter '*.sql' -File) {
    $text=[IO.File]::ReadAllText($file.FullName)
    if ($text -match '(?im)^\s*(USE|DROP|TRUNCATE|DELETE)\b|\bsp_configure\b' -or $text -match "HAS_PERMS_BY_NAME\(NULL,\s*'SERVER'") { throw ('Unsafe SQL pattern: '+$file.Name) }
    if ($text -notmatch 'DB_NAME\(\)' -or $text -notmatch '@ExpectedServerName') { throw ('Missing SQL target guard: '+$file.Name) }
    $checks++
}
Import-Module (Join-Path $PSScriptRoot 'E2EPlan.psm1') -Force
$manifestPath=Join-Path $repo 'docs/database/e2e/ReviewManifest.json'
$approvedHash=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
Assert-PlanManifest -ApprovedManifestSha256 $approvedHash
$checks++
$refused=$false
try { Assert-PlanManifest -ApprovedManifestSha256 $approvedHash -ForWrite } catch { $refused=$true }
if (!$refused) { throw 'Expected current NO-GO manifest to refuse writes.' }; $checks++
Initialize-PlanSqlClient -SqlClientDirectory $SqlClientDirectory
foreach ($db in @('WayMarkDatabase','WayMarkAuthDatabase','master_typo')) {
    $refused=$false
    try { $null=New-PlanConnection -SqlDataSource 'offline.invalid' -Database $db -Provisioning } catch { $refused=$true }
    if (!$refused) { throw 'Protected/unapproved database was accepted.' }; $checks++
}
$credential=[pscredential]::new('WayMark_E2E_Runtime',(ConvertTo-SecureString ([Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))) -AsPlainText -Force))
$connection=New-PlanConnection -SqlDataSource 'offline.invalid' -Database 'WayMark_MapDraft_E2E_Test' -Credential $credential
try {
    if ($connection.State -ne [Data.ConnectionState]::Closed -or $connection.Database -cne 'WayMark_MapDraft_E2E_Test' -or $connection.ConnectionString -match 'Password=') { throw 'Connection construction is not isolated.' }
    $checks++
} finally { $connection.Dispose() }
$accounts=@{}
foreach ($name in @('wm-e2e-admin-a','wm-e2e-admin-b','wm-e2e-admin-none','wm-e2e-reader')) {
    $password=[Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))+'aA1!'
    $accounts[$name]=[pscredential]::new($name,(ConvertTo-SecureString $password -AsPlainText -Force))
}
$hashes=New-PlanIdentityHashes -TestAccounts $accounts -AspNetRuntimeDirectory $AspNetRuntimeDirectory
if ($hashes.Count -ne 4 -or @($hashes.Values | Sort-Object -Unique).Count -ne 4) { throw 'Expected four independent Identity password hashes.' }; $checks++
$fixture=Get-Content (Join-Path $repo 'docs/database/e2e/DraftRoomFixture.json') -Raw | ConvertFrom-Json
if ($fixture.places[0].entranceNodeIds.Count -ne 2 -or $fixture.places[0].accessibility -ne 'Unknown') { throw 'Room fixture safety check failed.' }; $checks++
Write-Output ('PASS '+$checks+' offline checks; no SQL connection opened, no provisioning runner or storage setup invoked.')
