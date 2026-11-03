IF @@TRANCOUNT<>0 OR (2 & @@OPTIONS)=2 THROW 51000, 'Fresh session required.', 1;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'WayMark_MapDraft_E2E_Test'
 OR NULLIF(@ExpectedServerName,N'') IS NULL OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))<>@ExpectedServerName
 OR NULLIF(@ExpectedProvisioningLogin,N'') IS NULL OR ORIGINAL_LOGIN()<>@ExpectedProvisioningLogin
 OR ISNULL(HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','CONTROL'),0)<>1
    THROW 51000, 'User/schema provisioning target or permission refused.', 1;
IF EXISTS(SELECT 1 FROM sys.tables) OR USER_ID(N'WayMark_E2E_Runtime') IS NOT NULL
 OR USER_ID(N'WayMark_E2E_Migrator') IS NOT NULL
    THROW 51000, 'Expected a new empty test database. Do not adopt existing data.', 1;
IF SUSER_ID(N'WayMark_E2E_Runtime') IS NULL OR SUSER_ID(N'WayMark_E2E_Migrator') IS NULL
    THROW 51000, 'Provision the two approved logins first.', 1;
SET XACT_ABORT ON;
BEGIN TRY
 BEGIN TRANSACTION;
 CREATE USER [WayMark_E2E_Runtime] FOR LOGIN [WayMark_E2E_Runtime] WITH DEFAULT_SCHEMA=[dbo];
 CREATE USER [WayMark_E2E_Migrator] FOR LOGIN [WayMark_E2E_Migrator] WITH DEFAULT_SCHEMA=[dbo];
 -- Same definitions as EF's IHistoryRepository. Precreation enables object-specific DML grants.
 CREATE TABLE [dbo].[__AuthMigrationsHistory] ([MigrationId] nvarchar(150) NOT NULL,[ProductVersion] nvarchar(32) NOT NULL,
  CONSTRAINT [PK___AuthMigrationsHistory] PRIMARY KEY ([MigrationId]));
 CREATE TABLE [dbo].[__EFMigrationsHistory] ([MigrationId] nvarchar(150) NOT NULL,[ProductVersion] nvarchar(32) NOT NULL,
  CONSTRAINT [PK___EFMigrationsHistory] PRIMARY KEY ([MigrationId]));
 GRANT CONNECT TO [WayMark_E2E_Runtime];
 GRANT CONNECT TO [WayMark_E2E_Migrator];
 GRANT CREATE TABLE TO [WayMark_E2E_Migrator];
 GRANT ALTER, REFERENCES, VIEW DEFINITION ON SCHEMA::[dbo] TO [WayMark_E2E_Migrator];
 GRANT SELECT, INSERT ON OBJECT::[dbo].[__AuthMigrationsHistory] TO [WayMark_E2E_Migrator];
 GRANT SELECT, INSERT ON OBJECT::[dbo].[__EFMigrationsHistory] TO [WayMark_E2E_Migrator];
 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
