IF @@TRANCOUNT<>0 OR (2 & @@OPTIONS)=2 THROW 51000, 'Fresh session required.', 1;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'WayMark_MapDraft_E2E_Test'
 OR NULLIF(@ExpectedServerName,N'') IS NULL OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))<>@ExpectedServerName
 OR NULLIF(@ExpectedProvisioningLogin,N'') IS NULL OR ORIGINAL_LOGIN()<>@ExpectedProvisioningLogin OR ISNULL(HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','CONTROL'),0)<>1
    THROW 51000, 'Runtime grant target/permission refused.', 1;
IF USER_ID(N'WayMark_E2E_Runtime') IS NULL
 OR NOT EXISTS(SELECT 1 FROM dbo.__AuthMigrationsHistory WHERE MigrationId=N'20261010032404_CreateAuthSchema')
 OR NOT EXISTS(SELECT 1 FROM dbo.__EFMigrationsHistory WHERE MigrationId=N'20261020101304_BindMapImagesToDrafts')
    THROW 51000, 'Required users/migrations missing.', 1;
SET XACT_ABORT ON;
BEGIN TRY
 BEGIN TRANSACTION;
 GRANT SELECT ON OBJECT::dbo.Sites TO [WayMark_E2E_Runtime];
 GRANT SELECT ON OBJECT::dbo.Buildings TO [WayMark_E2E_Runtime];
 GRANT SELECT ON OBJECT::dbo.Floors TO [WayMark_E2E_Runtime];
 GRANT SELECT ON OBJECT::dbo.NavigationNodes TO [WayMark_E2E_Runtime];
 GRANT SELECT ON OBJECT::dbo.NavigationEdges TO [WayMark_E2E_Runtime];
 GRANT SELECT ON OBJECT::dbo.WayMarks TO [WayMark_E2E_Runtime];
 GRANT SELECT, INSERT, UPDATE ON OBJECT::dbo.AspNetUsers TO [WayMark_E2E_Runtime];
 GRANT SELECT ON OBJECT::dbo.AspNetRoles TO [WayMark_E2E_Runtime];
 GRANT SELECT ON OBJECT::dbo.AspNetUserRoles TO [WayMark_E2E_Runtime];
 GRANT SELECT ON OBJECT::dbo.AspNetUserClaims TO [WayMark_E2E_Runtime];
 GRANT SELECT ON OBJECT::dbo.AspNetRoleClaims TO [WayMark_E2E_Runtime];
 GRANT SELECT ON OBJECT::dbo.AspNetUserLogins TO [WayMark_E2E_Runtime];
 GRANT SELECT ON OBJECT::dbo.AspNetUserTokens TO [WayMark_E2E_Runtime];
 GRANT SELECT ON OBJECT::dbo.SiteMapMemberships TO [WayMark_E2E_Runtime];
 GRANT SELECT, INSERT, UPDATE ON OBJECT::dbo.FloorMapDrafts TO [WayMark_E2E_Runtime];
 GRANT SELECT, INSERT ON OBJECT::dbo.FloorMapDraftRevisions TO [WayMark_E2E_Runtime];
 GRANT SELECT, INSERT ON OBJECT::dbo.FloorMapImageAssets TO [WayMark_E2E_Runtime];
 GRANT SELECT ON OBJECT::dbo.__AuthMigrationsHistory TO [WayMark_E2E_Runtime];
 GRANT SELECT ON OBJECT::dbo.__EFMigrationsHistory TO [WayMark_E2E_Runtime];
 -- No db_owner/db_datawriter, DELETE, graph writes, membership/role writes or DDL.
 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
