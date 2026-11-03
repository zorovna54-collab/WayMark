[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Inventory','ProtectedEvidence','CreateDatabase','CreateLogins','CreateUsers','MigrateAuth','MigrateMap','RuntimeGrants','BootstrapIdentity','BootstrapSites','OptionalQrGraph','VerifyRuntime','SealMigrator','DisableMigrator')][string]$Step,
    [Parameter(Mandatory)][string]$SqlDataSource,
    [Parameter(Mandatory)][string]$ExpectedServerName,
    [Parameter(Mandatory)][string]$SqlClientDirectory,
    [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ApprovedManifestSha256,
    [string]$ApprovalId,
    [ValidateSet('WayMark_MapDraft_E2E_Test')][string]$ConfirmDatabase,
    [pscredential]$Credential,
    [pscredential]$RuntimeCredential,
    [pscredential]$MigratorCredential,
    [hashtable]$TestAccounts,
    [string]$AspNetRuntimeDirectory,
    [switch]$AllowLocalSelfSignedSqlCertificate
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'E2EPlan.psm1') -Force
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$write=$Step -notin @('Inventory','ProtectedEvidence','VerifyRuntime')
Assert-PlanManifest -ApprovedManifestSha256 $ApprovedManifestSha256 -ForWrite:$write
if ($write) {
    if ($ConfirmDatabase -cne 'WayMark_MapDraft_E2E_Test' -or $ApprovalId -notmatch '^7B2D2-[A-Za-z0-9_-]{4,}$') { throw 'Explicit per-step approval ID and exact database confirmation required.' }
    $guard=[IO.File]::ReadAllText((Join-Path $repo 'WayMark.Api/Security/E2EConnectionInterceptor.cs'))
    if ($guard -match "HAS_PERMS_BY_NAME\(NULL,\s*'SERVER'") { throw 'Known backend guard defect remains unresolved; no SQL executed.' }
}
$files=@{Inventory='00-ReadOnlyInventory.sql';ProtectedEvidence='01-ReadOnlyProtectedEvidence.sql';CreateDatabase='10-CreateDatabase.sql';CreateLogins='20-CreateLogins.sql';CreateUsers='21-CreateUsersAndMigrationPermissions.sql';
 MigrateAuth='30-AuthSchema.sql';MigrateMap='31-WayMarkSchema.sql';RuntimeGrants='40-RuntimePermissions.sql';BootstrapIdentity='50-BootstrapIdentity.sql';
 BootstrapSites='60-TestSitesAndMemberships.sql';OptionalQrGraph='70-OptionalQrGraph.sql';VerifyRuntime='80-ReadOnlyVerification.sql';
 SealMigrator='90-SealMigratorDatabasePermissions.sql';DisableMigrator='91-DisableMigratorLogin.sql'}
$provisioning=$Step -notin @('MigrateAuth','MigrateMap','VerifyRuntime')
$database=if($Step -in @('Inventory','ProtectedEvidence','CreateDatabase','CreateLogins','DisableMigrator')){'master'}else{'WayMark_MapDraft_E2E_Test'}
$expectedLogin=if($provisioning){[Security.Principal.WindowsIdentity]::GetCurrent().Name}elseif($Step -eq 'VerifyRuntime'){'WayMark_E2E_Runtime'}else{'WayMark_E2E_Migrator'}
if (!$provisioning -and ($null -eq $Credential -or $Credential.UserName -cne $expectedLogin)) { throw 'Wrong dedicated SQL credential for this step.' }
$parameters=@{ExpectedServerName=$ExpectedServerName;ExpectedProvisioningLogin=$expectedLogin}
if ($Step -eq 'CreateLogins') {
    if ($null -eq $RuntimeCredential -or $RuntimeCredential.UserName -cne 'WayMark_E2E_Runtime' -or
        $null -eq $MigratorCredential -or $MigratorCredential.UserName -cne 'WayMark_E2E_Migrator') { throw 'Two exact dedicated login credentials required.' }
    $parameters.RuntimePassword=$RuntimeCredential.GetNetworkCredential().Password
    $parameters.MigratorPassword=$MigratorCredential.GetNetworkCredential().Password
}
if ($Step -eq 'BootstrapIdentity') {
    $hashes=New-PlanIdentityHashes -TestAccounts $TestAccounts -AspNetRuntimeDirectory $AspNetRuntimeDirectory
    foreach ($key in $hashes.Keys) { $parameters[$key]=$hashes[$key] }
}
Initialize-PlanSqlClient -SqlClientDirectory $SqlClientDirectory
$connection=New-PlanConnection -SqlDataSource $SqlDataSource -Database $database -Credential $Credential -Provisioning:$provisioning -AllowLocalSelfSignedSqlCertificate:$AllowLocalSelfSignedSqlCertificate
try {
    $connection.Open()
    Assert-PlanConnectedTarget -Connection $connection -ExpectedServerName $ExpectedServerName -ExpectedLogin $expectedLogin -Provisioning:$provisioning -RequireSqlAuthentication:$write
    Invoke-PlanSqlFile -Connection $connection -Path (Join-Path $repo ('docs/database/e2e/'+$files[$Step])) -Parameters $parameters
    Write-Output ('Completed reviewed step: '+$Step)
}
catch {
    # Do not print SqlException, command/parameters, PSCredential, token or password hash.
    throw ('Step '+$Step+' stopped. Private details withheld. Inspect target state read-only before retrying; no automatic rollback of earlier committed steps.')
}
finally {
    # Dedicated non-pooled connection; close aborts any uncommitted failed migration transaction.
    $connection.Dispose(); $parameters.Clear()
}
