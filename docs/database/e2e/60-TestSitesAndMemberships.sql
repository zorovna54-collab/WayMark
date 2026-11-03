IF @@TRANCOUNT<>0 OR (2 & @@OPTIONS)=2 THROW 51000, 'Fresh session required.', 1;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'WayMark_MapDraft_E2E_Test'
 OR NULLIF(@ExpectedServerName,N'') IS NULL OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))<>@ExpectedServerName
 OR NULLIF(@ExpectedProvisioningLogin,N'') IS NULL OR ORIGINAL_LOGIN()<>@ExpectedProvisioningLogin OR ISNULL(HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','CONTROL'),0)<>1
    THROW 51000, 'Fixture bootstrap target/permission refused.', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.AspNetUsers)<>4
 OR (SELECT COUNT_BIG(*) FROM dbo.AspNetUsers WHERE UserName IN
  (N'wm-e2e-admin-a',N'wm-e2e-admin-b',N'wm-e2e-admin-none',N'wm-e2e-reader') AND Email=UserName+N'@example.invalid')<>4
 OR EXISTS(SELECT 1 FROM dbo.AspNetRoles) OR EXISTS(SELECT 1 FROM dbo.AspNetUserRoles)
 OR EXISTS(SELECT 1 FROM dbo.Sites) OR EXISTS(SELECT 1 FROM dbo.Buildings) OR EXISTS(SELECT 1 FROM dbo.Floors)
 OR EXISTS(SELECT 1 FROM dbo.SiteMapMemberships) OR EXISTS(SELECT 1 FROM dbo.NavigationNodes)
 OR EXISTS(SELECT 1 FROM dbo.WayMarks) OR EXISTS(SELECT 1 FROM dbo.FloorMapDrafts)
    THROW 51000, 'Expected the exact newly bootstrapped Identity and empty test map; no existing-data changes allowed.', 1;
SET XACT_ABORT ON;
BEGIN TRY
 BEGIN TRANSACTION;
 DECLARE @role nvarchar(450)=CONVERT(nvarchar(450),NEWID());
 INSERT dbo.AspNetRoles(Id,Name,NormalizedName,ConcurrencyStamp)
 VALUES(@role,N'Admin',N'ADMIN',CONVERT(nvarchar(36),NEWID()));
 INSERT dbo.AspNetUserRoles(UserId,RoleId) SELECT Id,@role FROM dbo.AspNetUsers
 WHERE UserName IN(N'wm-e2e-admin-a',N'wm-e2e-admin-b',N'wm-e2e-admin-none');
 INSERT dbo.Sites(Name,Code,Address) VALUES(N'E2E Test Site A',N'E2E-7B2D-A',NULL),(N'E2E Test Site B',N'E2E-7B2D-B',NULL);
 INSERT dbo.Buildings(SiteId,Name,BuildingCode) SELECT Id,N'E2E Test Building',N'E2E-B1' FROM dbo.Sites;
 INSERT dbo.Floors(BuildingId,Name,FloorCode,SortOrder,FloorPlanImageUrl)
 SELECT b.Id,N'E2E Ground Floor',N'G',0,NULL FROM dbo.Buildings b;
 INSERT dbo.Floors(BuildingId,Name,FloorCode,SortOrder,FloorPlanImageUrl)
 SELECT b.Id,N'E2E Level 1',N'L1',1,NULL FROM dbo.Buildings b JOIN dbo.Sites s ON s.Id=b.SiteId WHERE s.Code=N'E2E-7B2D-A';
 INSERT dbo.SiteMapMemberships(SiteId,UserId,IsActive,CanEditDrafts)
 SELECT s.Id,u.Id,1,1 FROM dbo.Sites s JOIN dbo.AspNetUsers u
 ON (s.Code=N'E2E-7B2D-A' AND u.UserName=N'wm-e2e-admin-a')
 OR (s.Code=N'E2E-7B2D-B' AND u.UserName=N'wm-e2e-admin-b');
 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
SELECT s.Code,b.BuildingCode,f.Id AS FloorId,f.FloorCode FROM dbo.Floors f
 JOIN dbo.Buildings b ON b.Id=f.BuildingId JOIN dbo.Sites s ON s.Id=b.SiteId ORDER BY s.Code,f.SortOrder;
