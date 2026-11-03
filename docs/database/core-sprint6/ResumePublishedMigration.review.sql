-- Executed successfully on 24/10/2026 for RunId 2e5448b2-7c06-4a93-a438-f0d22a2edca6.
-- Historical resume launcher: its four-entry history guard now refuses re-execution.
-- Recheck reviewed artifact SHA256 + verified backup evidence before invoking:
-- sqlcmd -S . -d WayMarkDatabase -E -N -C -I -b -V 16 -i <this-file>
-- -C is only the approved local Development exception; -I enables quoted identifiers.
:On Error exit
IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS)=2
BEGIN
    RAISERROR('Fresh session without implicit transactions required',16,1);
    RETURN;
END;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'WayMarkDatabase'
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) IS NULL
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) COLLATE Latin1_General_100_BIN2<>N'LAPTOP-PFRPMR3O'
 OR CONVERT(nvarchar(128),ORIGINAL_LOGIN()) COLLATE Latin1_General_100_BIN2<>N'LAPTOP-PFRPMR3O\pc'
    THROW 51000,'Wrong approved local target or identity',1;
IF NOT EXISTS(SELECT 1 FROM sys.dm_exec_connections WHERE session_id=@@SPID
    AND auth_scheme IN(N'NTLM',N'KERBEROS') AND encrypt_option=N'TRUE')
    THROW 51001,'Encrypted Windows session required',1;
IF (SELECT COUNT(*) FROM dbo.__EFMigrationsHistory)<>4
 OR (SELECT COUNT(*) FROM dbo.__EFMigrationsHistory WHERE MigrationId IN
 (N'20261018022742_CreateWayMarkSchema',N'20261018053754_AddNavigationSchema',
 N'20261020094848_AddMapDraftFoundation',N'20261020101304_BindMapImagesToDrafts'))<>4
 OR (SELECT COUNT(*) FROM dbo.__AuthMigrationsHistory)<>1
 OR NOT EXISTS(SELECT 1 FROM dbo.__AuthMigrationsHistory WHERE MigrationId=N'20261010032404_CreateAuthSchema')
    THROW 51002,'Exact stopped migration prefix required; do not alter history',1;
IF EXISTS(SELECT 1 FROM sys.tables WHERE name IN(N'MapProjects',N'MapPublications',N'MapPublicationImages',N'MapNodeQrs'))
    THROW 51003,'Unexpected publication schema residue; inspect rather than overwrite',1;
IF NOT EXISTS(SELECT 1 FROM msdb.dbo.backupset WHERE database_name=N'WayMarkDatabase'
    AND name=N'WayMark Core6 2e5448b27c064a93a438f0d22a2edca6'
    AND type=N'D' AND is_copy_only=1 AND has_backup_checksums=1 AND is_damaged=0 AND backup_finish_date IS NOT NULL)
    THROW 51004,'Approved backup metadata required; also recheck VERIFYONLY evidence and file',1;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
IF ISNULL(CONVERT(int,SESSIONPROPERTY('ANSI_NULLS')),0)<>1
 OR ISNULL(CONVERT(int,SESSIONPROPERTY('ANSI_PADDING')),0)<>1
 OR ISNULL(CONVERT(int,SESSIONPROPERTY('ANSI_WARNINGS')),0)<>1
 OR ISNULL(CONVERT(int,SESSIONPROPERTY('ARITHABORT')),0)<>1
 OR ISNULL(CONVERT(int,SESSIONPROPERTY('CONCAT_NULL_YIELDS_NULL')),0)<>1
 OR ISNULL(CONVERT(int,SESSIONPROPERTY('QUOTED_IDENTIFIER')),0)<>1
 OR ISNULL(CONVERT(int,SESSIONPROPERTY('NUMERIC_ROUNDABORT')),-1)<>0
    THROW 51005,'Filtered-index session options gate failed',1;
SELECT N'FILTERED_INDEX_OPTIONS_PASS' AS Gate,
 CONVERT(int,SESSIONPROPERTY('ANSI_NULLS')) AS ANSI_NULLS,
 CONVERT(int,SESSIONPROPERTY('ANSI_PADDING')) AS ANSI_PADDING,
 CONVERT(int,SESSIONPROPERTY('ANSI_WARNINGS')) AS ANSI_WARNINGS,
 CONVERT(int,SESSIONPROPERTY('ARITHABORT')) AS ARITHABORT,
 CONVERT(int,SESSIONPROPERTY('CONCAT_NULL_YIELDS_NULL')) AS CONCAT_NULL_YIELDS_NULL,
 CONVERT(int,SESSIONPROPERTY('QUOTED_IDENTIFIER')) AS QUOTED_IDENTIFIER,
 CONVERT(int,SESSIONPROPERTY('NUMERIC_ROUNDABORT')) AS NUMERIC_ROUNDABORT;
EXEC sys.sp_set_session_context @key=N'WayMarkApprovedServer',@value=N'LAPTOP-PFRPMR3O',@read_only=1;
GO
-- Same reviewed idempotent artifact: first two approved additions are skipped;
-- only AddPublishedMapProjects is pending. Do not regenerate or edit the artifact.
:r "D:\project\WayMark\docs\database\core-sprint3\PendingMapMigrations.idempotent.review.sql"
