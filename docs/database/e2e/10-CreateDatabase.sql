-- APPROVAL REQUIRED. New E2E database only. Autocommit DDL: no automatic cleanup.
IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 51000, 'Use a fresh session with implicit transactions OFF.', 1;
IF DB_NAME() <> N'master' OR NULLIF(@ExpectedServerName,N'') IS NULL
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) <> @ExpectedServerName
 OR NULLIF(@ExpectedProvisioningLogin,N'') IS NULL OR ORIGINAL_LOGIN()<>@ExpectedProvisioningLogin
    THROW 51000, 'Provisioning server/catalog/login mismatch.', 1;
IF ISNULL(CONVERT(int,SERVERPROPERTY('IsIntegratedSecurityOnly')),1) <> 0
    THROW 51000, 'SQL authentication is unavailable; no server setting will be changed.', 1;
IF ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'CREATE ANY DATABASE'),0) <> 1
    THROW 51000, 'Database provisioning permission required.', 1;
IF DB_ID(N'WayMark_MapDraft_E2E_Test') IS NOT NULL
    THROW 51000, 'Test database already exists. Stop; never adopt or recreate it automatically.', 1;
CREATE DATABASE [WayMark_MapDraft_E2E_Test];
-- Options affect ONLY the database just created above, never server/model/protected DBs.
ALTER DATABASE [WayMark_MapDraft_E2E_Test] SET READ_COMMITTED_SNAPSHOT OFF;
ALTER DATABASE [WayMark_MapDraft_E2E_Test] SET RECOVERY SIMPLE;
IF EXISTS (SELECT 1 FROM sys.databases WHERE name=N'WayMark_MapDraft_E2E_Test'
 AND (state_desc<>N'ONLINE' OR is_trustworthy_on<>0 OR containment<>0 OR is_read_committed_snapshot_on<>0))
    THROW 51000, 'Unexpected new database settings; stop for review, no automatic repair.', 1;
SELECT name,state_desc,recovery_model_desc,is_read_committed_snapshot_on
 FROM sys.databases WHERE name=N'WayMark_MapDraft_E2E_Test';
