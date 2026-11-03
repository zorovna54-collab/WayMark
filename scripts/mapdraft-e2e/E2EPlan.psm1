Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:Repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$script:Catalog='WayMark_MapDraft_E2E_Test'
function Initialize-PlanSqlClient {
    param([Parameter(Mandatory)][string]$SqlClientDirectory)
    $base=[IO.Path]::GetFullPath($SqlClientDirectory)
    $serverTypes=Join-Path $base 'Microsoft.SqlServer.Server.dll'
    if (!(Test-Path -LiteralPath $serverTypes)) { throw 'SqlClient server-types dependency artifact missing.' }
    [Reflection.Assembly]::LoadFrom($serverTypes) | Out-Null
    # PowerShell has no API .deps.json host selection. Load the actual Windows
    # implementation, not SqlClient's portable facade (which throws on Open).
    $platform=if([OperatingSystem]::IsWindows()){'win'}else{'unix'}
    $dll=Join-Path $base ('runtimes/'+$platform+'/lib/net9.0/Microsoft.Data.SqlClient.dll')
    if (!(Test-Path -LiteralPath $dll)) { $dll=Join-Path $base ('runtimes/'+$platform+'/lib/net8.0/Microsoft.Data.SqlClient.dll') }
    if (!(Test-Path -LiteralPath $dll -PathType Leaf)) { throw 'Build artifact SqlClient assembly missing; no automatic install/build.' }
    # Preload the matching native SNI for PowerShell (no API .deps.json host).
    # Preserve native shared-memory/named-pipe support; do not enable SQL TCP or
    # change any server setting merely to make a provisioning tool connect.
    if ([OperatingSystem]::IsWindows()) {
        $arch=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLowerInvariant()
        $native=Join-Path $base ('runtimes/win-'+$arch+'/native/Microsoft.Data.SqlClient.SNI.dll')
        if (!(Test-Path -LiteralPath $native)) { throw 'Matching native SqlClient SNI artifact missing.' }
        $script:NativeSniHandle=[Runtime.InteropServices.NativeLibrary]::Load($native)
    }
    [Reflection.Assembly]::LoadFrom($dll) | Out-Null
}
function Assert-PlanManifest {
    param([Parameter(Mandatory)][string]$ApprovedManifestSha256,[switch]$ForWrite)
    $file=Join-Path $script:Repo 'docs/database/e2e/ReviewManifest.json'
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $ApprovedManifestSha256) { throw 'Manifest differs from approved review.' }
    $manifest=Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    foreach ($entry in $manifest.Files) {
        $path=[IO.Path]::GetFullPath((Join-Path $script:Repo $entry.Path))
        $relative=[IO.Path]::GetRelativePath($script:Repo,$path)
        if ([IO.Path]::IsPathRooted($relative) -or $relative.StartsWith('..') -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.Sha256) { throw 'Reviewed file drift; stop for a new review.' }
    }
    if ($ForWrite -and $manifest.Decision -ne 'GO') { throw 'APPROVAL GATE CLOSED: review manifest is NO-GO. Resolve blockers and obtain a new review/approval.' }
}
function New-PlanConnection {
    param([string]$SqlDataSource,[string]$Database,[pscredential]$Credential,[switch]$Provisioning,[switch]$AllowLocalSelfSignedSqlCertificate)
    if ($Database -notin @('master',$script:Catalog)) { throw 'Unapproved connection catalog.' }
    if ([string]::IsNullOrWhiteSpace($SqlDataSource)) { throw 'Explicit SQL source required; no fallback.' }
    $builder=[Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source']=$SqlDataSource; $builder['Initial Catalog']=$Database; $builder['Encrypt']=$true
    $builder['Trust Server Certificate']=[bool]$AllowLocalSelfSignedSqlCertificate
    $builder['Connect Timeout']=5; $builder['Pooling']=$false; $builder['Enlist']=$false
    $builder['Application Name']='WayMark-E2E-Approved-Plan'
    if ($Provisioning) { $builder['Integrated Security']=$true }
    elseif ($null -eq $Credential -or $Credential.UserName -notin @('WayMark_E2E_Runtime','WayMark_E2E_Migrator')) { throw 'Explicit dedicated SQL credential required.' }
    $connection=[Microsoft.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    if (!$Provisioning) {
        $secret=$Credential.Password.Copy(); $secret.MakeReadOnly()
        $connection.Credential=[Microsoft.Data.SqlClient.SqlCredential]::new($Credential.UserName,$secret)
    }
    return $connection
}
function Assert-PlanConnectedTarget {
    param($Connection,[string]$ExpectedServerName,[string]$ExpectedLogin,[switch]$Provisioning,[switch]$RequireSqlAuthentication)
    $command=$Connection.CreateCommand(); $command.CommandTimeout=5
    $command.CommandText=@'
SELECT DB_NAME(),CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')),SUSER_SNAME(),ORIGINAL_LOGIN(),
 IS_SRVROLEMEMBER('sysadmin'),HAS_PERMS_BY_NAME(NULL,NULL,'CONTROL SERVER'),
 HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY LOGIN'),HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY DATABASE'),
 HAS_DBACCESS(N'WayMarkDatabase'),HAS_DBACCESS(N'WayMarkAuthDatabase'),CONVERT(int,SERVERPROPERTY('IsIntegratedSecurityOnly'));
'@
    try {
        $reader=$command.ExecuteReader()
        try {
            if (!$reader.Read() -or $reader.GetString(0) -cne $Connection.Database -or
                $Connection.Database -notin @('master',$script:Catalog) -or
                [string]::IsNullOrWhiteSpace($ExpectedServerName) -or $reader.GetString(1) -ne $ExpectedServerName -or
                $reader.GetString(2) -ne $ExpectedLogin -or $reader.GetString(3) -ne $ExpectedLogin) { throw 'Actual SQL target/login mismatch.' }
            if ($RequireSqlAuthentication -and ($reader.IsDBNull(10) -or $reader.GetInt32(10) -ne 0)) { throw 'Windows-only SQL instance: separate environment decision required; no setting changed.' }
            if (!$Provisioning) {
                for ($i=4; $i -le 7; $i++) { if ($reader.IsDBNull($i) -or [Convert]::ToInt32($reader.GetValue($i)) -ne 0) { throw 'Elevated or unknown server privileges refused.' } }
                for ($i=8; $i -le 9; $i++) { if (!$reader.IsDBNull($i) -and [Convert]::ToInt32($reader.GetValue($i)) -ne 0) { throw 'Protected database access refused.' } }
            }
        }
        finally { $reader.Dispose() }
    }
    finally { $command.Dispose() }
}
function Invoke-PlanSqlFile {
    param($Connection,[string]$Path,[hashtable]$Parameters)
    $text=[IO.File]::ReadAllText($Path)
    if ($text -match '(?im)^\s*(USE|DROP|TRUNCATE|DELETE)\b' -or $text -match '(?i)\bsp_configure\b') { throw 'Forbidden statement in reviewed plan SQL.' }
    $batches=[regex]::Split($text,'(?im)^\s*GO\s*\r?$') | Where-Object { ![string]::IsNullOrWhiteSpace($_) }
    foreach ($batch in $batches) {
        $command=$Connection.CreateCommand(); $command.CommandTimeout=60; $command.CommandText=$batch
        try {
            foreach ($key in $Parameters.Keys) {
                $p=$command.Parameters.Add('@'+$key,[Data.SqlDbType]::NVarChar,-1); $p.Value=$Parameters[$key]
            }
            $reader=$command.ExecuteReader()
            try {
                do {
                    while ($reader.Read()) {
                        $row=[ordered]@{}
                        for ($i=0;$i -lt $reader.FieldCount;$i++) { $row[$reader.GetName($i)]=if($reader.IsDBNull($i)){$null}else{$reader.GetValue($i)} }
                        [pscustomobject]$row
                    }
                } while ($reader.NextResult())
            }
            finally { $reader.Dispose() }
        }
        finally { $command.Dispose() }
    }
}
function New-PlanIdentityHashes {
    param([hashtable]$TestAccounts,[Parameter(Mandatory)][string]$AspNetRuntimeDirectory)
    foreach ($name in @('Microsoft.Extensions.Options.dll','Microsoft.AspNetCore.Cryptography.KeyDerivation.dll','Microsoft.Extensions.Identity.Stores.dll','Microsoft.Extensions.Identity.Core.dll')) {
        [Reflection.Assembly]::LoadFrom((Join-Path $AspNetRuntimeDirectory $name)) | Out-Null
    }
    $parameters=@{}
    $names=@{ AdminAHash='wm-e2e-admin-a'; AdminBHash='wm-e2e-admin-b'; AdminNoneHash='wm-e2e-admin-none'; ReaderHash='wm-e2e-reader' }
    foreach ($parameter in $names.Keys) {
        $credential=$TestAccounts[$names[$parameter]]
        if ($credential -isnot [pscredential] -or $credential.UserName -cne $names[$parameter]) { throw 'Four explicitly named private test credentials required.' }
        $password=$credential.GetNetworkCredential().Password
        if ($password.Length -lt 16 -or $password -cnotmatch '[A-Z]' -or $password -cnotmatch '[a-z]' -or $password -notmatch '[0-9]') { throw 'Test password does not meet the reviewed policy.' }
        $user=[Microsoft.AspNetCore.Identity.IdentityUser]::new($credential.UserName)
        $hasher=[Microsoft.AspNetCore.Identity.PasswordHasher[Microsoft.AspNetCore.Identity.IdentityUser]]::new($null)
        $hash=$hasher.HashPassword($user,$password)
        if ($hasher.VerifyHashedPassword($user,$hash,$password).ToString() -ne 'Success') { throw 'Offline Identity hash self-check failed.' }
        $parameters[$parameter]=$hash; $password=$null
    }
    return $parameters
}
Export-ModuleMember -Function Initialize-PlanSqlClient,Assert-PlanManifest,New-PlanConnection,Assert-PlanConnectedTarget,Invoke-PlanSqlFile,New-PlanIdentityHashes
