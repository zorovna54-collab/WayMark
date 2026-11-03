IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'WayMark_MapDraft_E2E_Test'
 OR NULLIF(@ExpectedServerName,N'') IS NULL OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))<>@ExpectedServerName
    THROW 51000, 'Verification target refused.', 1;
IF SUSER_SNAME()<>N'WayMark_E2E_Runtime' OR ORIGINAL_LOGIN()<>N'WayMark_E2E_Runtime'
 OR ISNULL(IS_SRVROLEMEMBER('sysadmin'),1)<>0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'CONTROL SERVER'),1)<>0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY LOGIN'),1)<>0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY DATABASE'),1)<>0
 OR ISNULL(HAS_DBACCESS(N'WayMarkDatabase'),0)<>0 OR ISNULL(HAS_DBACCESS(N'WayMarkAuthDatabase'),0)<>0
 OR ISNULL(HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','CONTROL'),1)<>0
 OR ISNULL(HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','CREATE TABLE'),1)<>0
 OR ISNULL(HAS_PERMS_BY_NAME(N'dbo','SCHEMA','ALTER'),1)<>0
 OR ISNULL(HAS_PERMS_BY_NAME(N'dbo.AspNetUserRoles','OBJECT','INSERT'),1)<>0
 OR ISNULL(HAS_PERMS_BY_NAME(N'dbo.SiteMapMemberships','OBJECT','INSERT'),1)<>0
 OR ISNULL(HAS_PERMS_BY_NAME(N'dbo.NavigationNodes','OBJECT','INSERT'),1)<>0
 OR ISNULL(HAS_PERMS_BY_NAME(N'dbo.FloorMapDrafts','OBJECT','DELETE'),1)<>0
 OR ISNULL(HAS_PERMS_BY_NAME(N'dbo.FloorMapDrafts','OBJECT','SELECT'),0)<>1
 OR ISNULL(HAS_PERMS_BY_NAME(N'dbo.FloorMapDrafts','OBJECT','INSERT'),0)<>1
 OR ISNULL(HAS_PERMS_BY_NAME(N'dbo.FloorMapDrafts','OBJECT','UPDATE'),0)<>1
    THROW 51000, 'Runtime privilege verification failed closed; do not launch API.', 1;
SELECT DB_NAME() AS DatabaseName,SUSER_SNAME() AS SqlLogin,ORIGINAL_LOGIN() AS OriginalLogin,
 IS_SRVROLEMEMBER('sysadmin') AS IsSysadmin,
 HAS_PERMS_BY_NAME(NULL,NULL,'CONTROL SERVER') AS ControlServer,
 HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY LOGIN') AS AlterLogins,
 HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY DATABASE') AS AlterDatabases,
 HAS_DBACCESS(N'WayMarkDatabase') AS AccessProtectedMap,HAS_DBACCESS(N'WayMarkAuthDatabase') AS AccessProtectedAuth;
SELECT MigrationId,ProductVersion FROM dbo.__AuthMigrationsHistory ORDER BY MigrationId;
SELECT MigrationId,ProductVersion FROM dbo.__EFMigrationsHistory ORDER BY MigrationId;
SELECT N'CanCreateTable' AS CheckName,HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','CREATE TABLE') AS Allowed
 UNION ALL SELECT N'CanAlterDbo',HAS_PERMS_BY_NAME(N'dbo','SCHEMA','ALTER')
 UNION ALL SELECT N'CanGrantAdmin',HAS_PERMS_BY_NAME(N'dbo.AspNetUserRoles','OBJECT','INSERT')
 UNION ALL SELECT N'CanGrantMembership',HAS_PERMS_BY_NAME(N'dbo.SiteMapMemberships','OBJECT','INSERT')
 UNION ALL SELECT N'CanWriteProductionGraph',HAS_PERMS_BY_NAME(N'dbo.NavigationNodes','OBJECT','INSERT')
 UNION ALL SELECT N'CanDeleteDraft',HAS_PERMS_BY_NAME(N'dbo.FloorMapDrafts','OBJECT','DELETE')
 UNION ALL SELECT N'CanReadDraft',HAS_PERMS_BY_NAME(N'dbo.FloorMapDrafts','OBJECT','SELECT')
 UNION ALL SELECT N'CanCreateDraft',HAS_PERMS_BY_NAME(N'dbo.FloorMapDrafts','OBJECT','INSERT')
 UNION ALL SELECT N'CanUpdateHead',HAS_PERMS_BY_NAME(N'dbo.FloorMapDrafts','OBJECT','UPDATE');

-- Fingerprint test published graph before and after draft operations.
SELECT N'Sites' AS TableName,COUNT_BIG(*) AS [RowCount],
 CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT Id,Name,Code,Address FROM dbo.Sites ORDER BY Id FOR JSON PATH,INCLUDE_NULL_VALUES)),2) AS ContentSha256 FROM dbo.Sites
UNION ALL SELECT N'Buildings',COUNT_BIG(*),
 CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT Id,SiteId,Name,BuildingCode FROM dbo.Buildings ORDER BY Id FOR JSON PATH,INCLUDE_NULL_VALUES)),2) FROM dbo.Buildings
UNION ALL SELECT N'Floors',COUNT_BIG(*),
 CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT Id,BuildingId,Name,FloorCode,SortOrder,FloorPlanImageUrl FROM dbo.Floors ORDER BY Id FOR JSON PATH,INCLUDE_NULL_VALUES)),2) FROM dbo.Floors
UNION ALL SELECT N'NavigationNodes',COUNT_BIG(*),
 CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT Id,FloorId,NodeCode,Name,X,Y,NodeType FROM dbo.NavigationNodes ORDER BY Id FOR JSON PATH,INCLUDE_NULL_VALUES)),2) FROM dbo.NavigationNodes
UNION ALL SELECT N'NavigationEdges',COUNT_BIG(*),
 CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT Id,FromNodeId,ToNodeId,EdgeType,DistanceMeters,IsActive,IsAccessible FROM dbo.NavigationEdges ORDER BY Id FOR JSON PATH,INCLUDE_NULL_VALUES)),2) FROM dbo.NavigationEdges
UNION ALL SELECT N'WayMarks',COUNT_BIG(*),
 CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT Id,Name,Location,WayMarkCode,NavigationNodeId FROM dbo.WayMarks ORDER BY Id FOR JSON PATH,INCLUDE_NULL_VALUES)),2) FROM dbo.WayMarks;
