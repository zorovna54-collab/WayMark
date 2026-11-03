-- SQLCMD from repository root. Requires the same verified backup RunId.
-- Executes the reviewed EF provider SQL verbatim; never loads Sprint10SqlSmoke.dll.
:On Error exit
SET NOCOUNT ON;
IF @@TRANCOUNT <> 0 THROW 51000, 'Requires a clean session; caller transaction is untouched.', 1;
IF (2 & @@OPTIONS) = 2 THROW 51000, 'IMPLICIT_TRANSACTIONS must be OFF.', 1;
IF CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))<>N'LAPTOP-PFRPMR3O'
 OR DB_NAME()<>N'WayMarkDatabase' OR ORIGINAL_LOGIN()<>N'LAPTOP-PFRPMR3O\pc'
 THROW 51000, 'Unexpected server/database/session. No migration.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.dm_exec_connections WHERE session_id=@@SPID AND encrypt_option=N'TRUE')
 THROW 51000, 'Encrypted SQL connection required.', 1;
IF (SELECT STRING_AGG(CONVERT(nvarchar(max),MigrationId),'|') WITHIN GROUP (ORDER BY MigrationId) FROM dbo.__EFMigrationsHistory)<>
 N'20261018022742_CreateWayMarkSchema|20261018053754_AddNavigationSchema|20261020094848_AddMapDraftFoundation|20261020101304_BindMapImagesToDrafts|20261023063955_AddPublishedMapProjects'
 OR (SELECT COUNT(*) FROM dbo.__EFMigrationsHistory)<>5 OR OBJECT_ID(N'dbo.NavigationHistory',N'U') IS NOT NULL
 THROW 51000, 'Unexpected migration/schema baseline; stop and review.', 1;
DECLARE @run nvarchar(100)=N'$(RunId)';
IF LEN(@run)<>12 OR @run COLLATE Latin1_General_100_BIN2 LIKE N'%[^a-f0-9]%'
 THROW 51000, 'Invalid backup RunId.', 1;
DECLARE @root nvarchar(4000)=CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultBackupPath'));
IF @root IS NULL OR @root=N'' THROW 51000, 'Default backup directory unavailable.', 1;
IF RIGHT(@root,1)<>N'\' SET @root+=N'\';
DECLARE @path nvarchar(4000)=@root+N'WayMarkDatabase_Sprint10_'+@run+N'_copyonly.bak';
IF (SELECT COUNT(*) FROM msdb.dbo.backupset b JOIN msdb.dbo.backupmediafamily f ON b.media_set_id=f.media_set_id
 WHERE b.database_name=N'WayMarkDatabase' AND b.type='D' AND b.is_copy_only=1 AND b.has_backup_checksums=1
 AND b.backup_finish_date>=DATEADD(hour,-6,SYSDATETIME()) AND f.physical_device_name=@path)<>1
 THROW 51000, 'Fresh verified COPY_ONLY checksum backup metadata required.', 1;
RESTORE VERIFYONLY FROM DISK=@path WITH CHECKSUM;
SET XACT_ABORT ON;
GO
:r "docs/database/sprint10/NavigationHistory.review.sql"
IF (SELECT COUNT(*) FROM dbo.__EFMigrationsHistory)<>7
 OR NOT EXISTS (SELECT 1 FROM dbo.__EFMigrationsHistory WHERE MigrationId=N'20261025010000_AddNavigationHistory')
 OR NOT EXISTS (SELECT 1 FROM dbo.__EFMigrationsHistory WHERE MigrationId=N'20261026001522_ExtendNavigationHistoryLifecycle')
 OR COL_LENGTH(N'dbo.NavigationHistory',N'ScannedAtUtc') IS NULL
 OR COL_LENGTH(N'dbo.NavigationHistory',N'DistanceMeters') IS NULL
 THROW 51000, 'Migration postcondition failed. Stop; no automatic Down or restore.', 1;
SELECT N'TWO_HISTORY_MIGRATIONS_APPLIED' AS Result;
SELECT MigrationId FROM dbo.__EFMigrationsHistory ORDER BY MigrationId;
GO
