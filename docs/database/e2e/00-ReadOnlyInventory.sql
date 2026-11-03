-- READ ONLY. Connect to master; @ExpectedServerName is a SqlParameter, not sqlcmd text.
IF DB_NAME() <> N'master' OR NULLIF(@ExpectedServerName,N'') IS NULL
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) <> @ExpectedServerName
    THROW 51000, 'Unexpected inventory server/catalog.', 1;
SELECT CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) AS ServerName,
 CONVERT(nvarchar(128),SERVERPROPERTY('InstanceName')) AS InstanceName,
 CONVERT(nvarchar(32),SERVERPROPERTY('ProductVersion')) AS ProductVersion,
 CONVERT(int,SERVERPROPERTY('IsIntegratedSecurityOnly')) AS WindowsAuthenticationOnly,
 IS_SRVROLEMEMBER('sysadmin') AS CallerIsSysadmin,
 HAS_PERMS_BY_NAME(NULL,NULL,'CREATE ANY DATABASE') AS CanCreateDatabase,
 HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY LOGIN') AS CanProvisionLogin;
SELECT name,state_desc,is_read_committed_snapshot_on,is_trustworthy_on,containment_desc
 FROM sys.databases WHERE name IN (N'WayMarkDatabase',N'WayMarkAuthDatabase',N'WayMark_MapDraft_E2E_Test');
SELECT name,is_disabled,type_desc FROM sys.server_principals
 WHERE name IN (N'WayMark_E2E_Runtime',N'WayMark_E2E_Migrator');
