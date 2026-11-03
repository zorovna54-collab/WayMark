IF @@TRANCOUNT<>0 OR (2 & @@OPTIONS)=2 THROW 51000, 'Fresh session required.', 1;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'WayMark_MapDraft_E2E_Test'
 OR NULLIF(@ExpectedServerName,N'') IS NULL OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))<>@ExpectedServerName
 OR NULLIF(@ExpectedProvisioningLogin,N'') IS NULL OR ORIGINAL_LOGIN()<>@ExpectedProvisioningLogin OR ISNULL(HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','CONTROL'),0)<>1
    THROW 51000, 'Migrator sealing target/permission refused.', 1;
SET XACT_ABORT ON;
BEGIN TRY
 BEGIN TRANSACTION;
 REVOKE CREATE TABLE FROM [WayMark_E2E_Migrator];
 REVOKE ALTER, REFERENCES, VIEW DEFINITION ON SCHEMA::dbo FROM [WayMark_E2E_Migrator];
 REVOKE SELECT, INSERT ON OBJECT::dbo.__AuthMigrationsHistory FROM [WayMark_E2E_Migrator];
 REVOKE SELECT, INSERT ON OBJECT::dbo.__EFMigrationsHistory FROM [WayMark_E2E_Migrator];
 REVOKE CONNECT FROM [WayMark_E2E_Migrator];
 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
