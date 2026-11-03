-- Native SQLCMD operation, approved Sprint 10 scope. RunId is a generated 12-character lowercase hex value.
:On Error exit
SET NOCOUNT ON;
IF @@TRANCOUNT <> 0 THROW 51000, 'Requires a clean session; caller transaction is untouched.', 1;
IF (2 & @@OPTIONS) = 2 THROW 51000, 'IMPLICIT_TRANSACTIONS must be OFF.', 1;
IF CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) <> N'LAPTOP-PFRPMR3O'
 OR DB_NAME() <> N'WayMarkDatabase' OR ORIGINAL_LOGIN() <> N'LAPTOP-PFRPMR3O\pc'
 THROW 51000, 'Unexpected server/database/session. No backup or migration.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.dm_exec_connections WHERE session_id=@@SPID AND encrypt_option=N'TRUE')
 THROW 51000, 'Encrypted SQL connection required.', 1;
DECLARE @run nvarchar(100)=N'$(RunId)';
IF LEN(@run)<>12 OR @run COLLATE Latin1_General_100_BIN2 LIKE N'%[^a-f0-9]%'
 THROW 51000, 'Invalid RunId.', 1;
DECLARE @root nvarchar(4000)=CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultBackupPath'));
IF @root IS NULL OR @root=N'' THROW 51000, 'Default backup directory unavailable.', 1;
IF RIGHT(@root,1)<>N'\' SET @root+=N'\';
DECLARE @path nvarchar(4000)=@root+N'WayMarkDatabase_Sprint10_'+@run+N'_copyonly.bak';
IF EXISTS (SELECT 1 FROM sys.dm_os_file_exists(@path) WHERE file_exists=1)
 THROW 51000, 'Backup already exists; never overwrite or append.', 1;
BACKUP DATABASE [WayMarkDatabase] TO DISK=@path WITH COPY_ONLY,CHECKSUM;
IF (SELECT COUNT(*) FROM msdb.dbo.backupset b JOIN msdb.dbo.backupmediafamily f ON b.media_set_id=f.media_set_id
 WHERE b.database_name=N'WayMarkDatabase' AND b.type='D' AND b.is_copy_only=1 AND b.has_backup_checksums=1
 AND b.backup_finish_date IS NOT NULL AND f.physical_device_name=@path)<>1
 THROW 51000, 'Backup metadata gate failed; do not migrate.', 1;
RESTORE VERIFYONLY FROM DISK=@path WITH CHECKSUM;
SELECT N'BACKUP_METADATA_CHECKSUM_VERIFYONLY_PASS' AS Result,@path AS BackupPath,
 b.backup_finish_date,b.is_copy_only,b.has_backup_checksums
FROM msdb.dbo.backupset b JOIN msdb.dbo.backupmediafamily f ON b.media_set_id=f.media_set_id WHERE f.physical_device_name=@path;
GO
