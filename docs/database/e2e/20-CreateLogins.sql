-- APPROVAL REQUIRED. Passwords arrive only as SqlParameters from PSCredential.
IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 51000, 'Caller transaction/implicit transactions refused.', 1;
IF DB_NAME()<>N'master' OR NULLIF(@ExpectedServerName,N'') IS NULL
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))<>@ExpectedServerName
 OR NULLIF(@ExpectedProvisioningLogin,N'') IS NULL OR ORIGINAL_LOGIN()<>@ExpectedProvisioningLogin
 OR ISNULL(CONVERT(int,SERVERPROPERTY('IsIntegratedSecurityOnly')),1)<>0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY LOGIN'),0)<>1
 OR DB_ID(N'WayMark_MapDraft_E2E_Test') IS NULL
    THROW 51000, 'Login provisioning target/permission guard refused.', 1;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name IN (N'WayMark_E2E_Runtime',N'WayMark_E2E_Migrator'))
    THROW 51000, 'A proposed login already exists; no password reset or adoption is permitted.', 1;
IF LEN(@RuntimePassword)<16 OR LEN(@RuntimePassword)>128 OR LEN(@MigratorPassword)<16
 OR LEN(@MigratorPassword)>128 OR @RuntimePassword IS NULL OR @MigratorPassword IS NULL
 OR @RuntimePassword=@MigratorPassword
    THROW 51000, 'Supply two independent private passwords of 16-128 characters.', 1;
SET XACT_ABORT ON;
BEGIN TRY
 BEGIN TRANSACTION;
 DECLARE @ddl nvarchar(max)=N'CREATE LOGIN [WayMark_E2E_Runtime] WITH PASSWORD=' + QUOTENAME(@RuntimePassword,'''')
  + N', CHECK_POLICY=ON, CHECK_EXPIRATION=ON, DEFAULT_DATABASE=[WayMark_MapDraft_E2E_Test];';
 EXEC sys.sp_executesql @ddl;
 SET @ddl=N'CREATE LOGIN [WayMark_E2E_Migrator] WITH PASSWORD=' + QUOTENAME(@MigratorPassword,'''')
  + N', CHECK_POLICY=ON, CHECK_EXPIRATION=ON, DEFAULT_DATABASE=[WayMark_MapDraft_E2E_Test];';
 EXEC sys.sp_executesql @ddl;
 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW 51000, 'Login provisioning failed. Inspect safely; do not log command parameters.', 1;
END CATCH;
