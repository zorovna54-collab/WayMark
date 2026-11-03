[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SqlDataSource,
    [Parameter(Mandatory)][string]$ExpectedServerName,
    [Parameter(Mandatory)][pscredential]$RuntimeCredential,
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string[]]$ProtectedRoots,
    [Parameter(Mandatory)][string]$SqlClientDirectory,
    [Parameter(Mandatory)][string]$ApprovalId,
    [Parameter(Mandatory)][ValidateSet('WayMark_MapDraft_E2E_Test')][string]$ConfirmDatabase,
    [Parameter(Mandatory)][string]$ApprovedManifestSha256,
    [switch]$AllowLocalSelfSignedSqlCertificate
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'E2EPlan.psm1') -Force
Assert-PlanManifest -ApprovedManifestSha256 $ApprovedManifestSha256 -ForWrite
if ($ApprovalId -notmatch '^7B2D2-[A-Za-z0-9_-]{4,}$' -or $RuntimeCredential.UserName -cne 'WayMark_E2E_Runtime') { throw 'Approved runtime-only configuration required.' }
if (![IO.Path]::IsPathFullyQualified($Root) -or !(Test-Path -LiteralPath $Root -PathType Container) -or
    [string]::IsNullOrWhiteSpace($SqlDataSource) -or [string]::IsNullOrWhiteSpace($ExpectedServerName) -or $ProtectedRoots.Count -eq 0) { throw 'Explicit approved target, provisioned root and protected-root inventory required.' }
$Root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Root))
if ($Root.StartsWith('\\') -or (Split-Path (Split-Path $Root -Parent) -Leaf) -cne 'WayMark_MapDraft_E2E_Test' -or
    (Split-Path $Root -Leaf) -cne 'images') { throw 'Wrong dedicated root.' }
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
foreach ($other in @($ProtectedRoots)+@($repo)) {
    if (![IO.Path]::IsPathFullyQualified($other)) { throw 'Absolute protected roots required.' }
    foreach ($pair in @(@($Root,$other),@($other,$Root))) {
        $relative=[IO.Path]::GetRelativePath($pair[0],$pair[1])
        if ($relative -eq '.' -or (!$relative.StartsWith('..'+[IO.Path]::DirectorySeparatorChar) -and $relative -ne '..' -and ![IO.Path]::IsPathRooted($relative))) { throw 'Root overlap refused.' }
    }
}
for ($parent=[IO.DirectoryInfo]::new($Root);$null -ne $parent;$parent=$parent.Parent) {
    if (($parent.Exists -and ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint)) -or (Test-Path -LiteralPath (Join-Path $parent.FullName '.git'))) { throw 'Git/reparse root refused.' }
}
if (![string]::IsNullOrWhiteSpace($env:ConnectionStrings__WayMarkDatabase) -or ![string]::IsNullOrWhiteSpace($env:ConnectionStrings__WayMarkAuthDatabase)) { throw 'Fresh terminal without legacy connection overrides required.' }
Initialize-PlanSqlClient -SqlClientDirectory $SqlClientDirectory
$builder=[Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new()
$builder['Data Source']=$SqlDataSource; $builder['Initial Catalog']='WayMark_MapDraft_E2E_Test'
$builder['User ID']=$RuntimeCredential.UserName; $builder['Password']=$RuntimeCredential.GetNetworkCredential().Password
$builder['Encrypt']=$true; $builder['Trust Server Certificate']=[bool]$AllowLocalSelfSignedSqlCertificate
$builder['Connect Timeout']=5; $builder['Persist Security Info']=$false
$env:E2E__Enabled='true'
$env:E2E__SqlConnectionString=$builder.ConnectionString
$env:E2E__SqlDataSource=$SqlDataSource; $env:E2E__ExpectedServerName=$ExpectedServerName
$env:E2E__JwtSecretKey=[Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
$env:E2E__ImageRoot=[IO.Path]::GetFullPath($Root); $env:MapImages__RootPath=$env:E2E__ImageRoot
# Do not retain stale array elements from a prior process profile.
Get-ChildItem Env: | Where-Object Name -Like 'E2E__ProtectedImageRoots__*' | ForEach-Object { [Environment]::SetEnvironmentVariable($_.Name,$null,'Process') }
for ($i=0;$i -lt $ProtectedRoots.Count;$i++) { [Environment]::SetEnvironmentVariable('E2E__ProtectedImageRoots__'+$i,[IO.Path]::GetFullPath($ProtectedRoots[$i]),'Process') }
$env:E2E__StorageIsolationConfirmed='true'; $env:E2E__AllowedOrigin='http://localhost:5628'
$builder.Clear()
Write-Output 'Configured private E2E process environment only. No file, User Secrets, SQL or certificate was changed. Close this dedicated terminal after testing.'
