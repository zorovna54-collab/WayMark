[CmdletBinding()]
param(
    [ValidatePattern('^(tcp:)?[A-Za-z0-9_.-]+(\\[A-Za-z0-9_-]+|,[0-9]{1,5})?$')]
    [string]$Server = $env:COMPUTERNAME,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9_.-]+(\\[A-Za-z0-9_-]+)?$')]
    [string]$ExpectedServerName
)

# SELECT-only diagnostic for the installed ODBC sqlcmd. Never launches a
# migration, supplies a SQL password or bypasses certificate validation.
$ErrorActionPreference = 'Stop'
$sqlcmdTool = Get-Command sqlcmd -CommandType Application -ErrorAction Stop
$readOnlyQuery = @"
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'WayMarkDatabase'
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) IS NULL
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) COLLATE Latin1_General_100_BIN2 <> N'$ExpectedServerName'
    THROW 51000,'Unexpected SQL diagnostic target',1;
SELECT DB_NAME() AS DatabaseName,
 CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) AS ServerName;
SELECT encrypt_option,auth_scheme FROM sys.dm_exec_connections WHERE session_id=@@SPID;
"@

# -N requests encryption. Omitting the trust override retains certificate chain
# and hostname verification. No retry with weaker options is permitted here.
& $sqlcmdTool.Source -S $Server -d WayMarkDatabase -E -N -l 5 -t 10 -b -V 16 -X1 -Q $readOnlyQuery
if ($LASTEXITCODE -ne 0) {
    throw 'Strict TLS/target diagnostic failed. Stop; review certificate chain, hostname and server configuration. No migration or SQL write was attempted.'
}
