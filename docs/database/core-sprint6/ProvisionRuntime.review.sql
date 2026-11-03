-- REVIEW ONLY. Not executed. Requires approved Windows account to exist,
-- verified backup, and all three reviewed migrations to have been applied.
-- Run in a fresh dedicated connection; sqlcmd must stop on the first error.
RAISERROR('RETIRED: current Sprint 6 uses the existing Windows identity. Do not provision another SQL login.',16,1);
RETURN;
IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
BEGIN
    RAISERROR('Use a clean session without implicit transactions',16,1);
    RETURN;
END;
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'WayMarkDatabase'
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) IS NULL
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) COLLATE Latin1_General_100_BIN2 <> N'LAPTOP-PFRPMR3O'
 OR CONVERT(nvarchar(128),SESSION_CONTEXT(N'WayMarkApprovedServer')) IS NULL
 OR CONVERT(nvarchar(128),SESSION_CONTEXT(N'WayMarkApprovedServer')) COLLATE Latin1_General_100_BIN2 <> N'LAPTOP-PFRPMR3O'
    THROW 51000,'Unapproved runtime provisioning target',1;
IF (SELECT COUNT(*) FROM dbo.__EFMigrationsHistory) <> 5
 OR (SELECT COUNT(*) FROM dbo.__EFMigrationsHistory WHERE MigrationId IN
 (N'20261018022742_CreateWayMarkSchema',N'20261018053754_AddNavigationSchema',
 N'20261020094848_AddMapDraftFoundation',N'20261020101304_BindMapImagesToDrafts',N'20261023063955_AddPublishedMapProjects')) <> 5
 OR (SELECT COUNT(*) FROM dbo.__AuthMigrationsHistory) <> 1
 OR NOT EXISTS (SELECT 1 FROM dbo.__AuthMigrationsHistory WHERE MigrationId=N'20261010032404_CreateAuthSchema')
    THROW 51001,'Reviewed migration history required before runtime provisioning',1;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name=N'LAPTOP-PFRPMR3O\wmcore6_2e5448b2')
 OR EXISTS (SELECT 1 FROM sys.database_principals WHERE name=N'LAPTOP-PFRPMR3O\wmcore6_2e5448b2')
    THROW 51002,'Reserved principal already exists; stop rather than adopt or overwrite',1;

SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;
    CREATE LOGIN [LAPTOP-PFRPMR3O\wmcore6_2e5448b2] FROM WINDOWS WITH DEFAULT_DATABASE=[WayMarkDatabase];
    CREATE USER [LAPTOP-PFRPMR3O\wmcore6_2e5448b2] FOR LOGIN [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT CONNECT TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];

    GRANT SELECT ON OBJECT::dbo.Sites TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT SELECT ON OBJECT::dbo.Buildings TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT SELECT ON OBJECT::dbo.Floors TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT SELECT ON OBJECT::dbo.NavigationNodes TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT SELECT ON OBJECT::dbo.NavigationEdges TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT SELECT ON OBJECT::dbo.WayMarks TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT SELECT ON OBJECT::dbo.__EFMigrationsHistory TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT SELECT ON OBJECT::dbo.__AuthMigrationsHistory TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT SELECT ON OBJECT::dbo.SiteMapMemberships TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT SELECT ON OBJECT::dbo.AspNetUsers TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT SELECT ON OBJECT::dbo.AspNetRoles TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT SELECT ON OBJECT::dbo.AspNetUserRoles TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT SELECT ON OBJECT::dbo.AspNetUserClaims TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT SELECT ON OBJECT::dbo.AspNetRoleClaims TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT SELECT ON OBJECT::dbo.AspNetUserLogins TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT SELECT ON OBJECT::dbo.AspNetUserTokens TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];

    GRANT SELECT,INSERT,UPDATE ON OBJECT::dbo.FloorMapDrafts TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT SELECT,INSERT ON OBJECT::dbo.FloorMapDraftRevisions TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT SELECT,INSERT ON OBJECT::dbo.FloorMapImageAssets TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT SELECT,INSERT,UPDATE ON OBJECT::dbo.MapProjects TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT SELECT,INSERT ON OBJECT::dbo.MapPublications TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT SELECT,INSERT ON OBJECT::dbo.MapPublicationImages TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    GRANT SELECT,INSERT,UPDATE ON OBJECT::dbo.MapNodeQrs TO [LAPTOP-PFRPMR3O\wmcore6_2e5448b2];
    -- No DELETE, DDL, db_datawriter/db_owner, Identity writes, legacy graph
    -- writes, role/membership/history writes or grants in any other database.
    -- Login-only fixture runtime; account creation/bootstrap uses setup identity.
    COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    THROW;
END CATCH;
