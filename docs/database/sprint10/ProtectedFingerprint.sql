-- SELECT-only data inspection. Hashes only, no row contents or credentials emitted.
SET NOCOUNT ON;
IF CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))<>N'LAPTOP-PFRPMR3O' OR DB_NAME()<>N'WayMarkDatabase'
 THROW 51000,'Unexpected fingerprint target.',1;
SELECT N'WayMarks' AS Resource,CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT * FROM dbo.WayMarks ORDER BY Id FOR JSON PATH)),2) AS Hash
UNION ALL SELECT N'NavigationNodes',CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT * FROM dbo.NavigationNodes ORDER BY Id FOR JSON PATH)),2)
UNION ALL SELECT N'NavigationEdges',CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT * FROM dbo.NavigationEdges ORDER BY Id FOR JSON PATH)),2)
UNION ALL SELECT N'MapProjects',CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT * FROM dbo.MapProjects ORDER BY Id FOR JSON PATH)),2)
UNION ALL SELECT N'MapPublications',CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT * FROM dbo.MapPublications ORDER BY MapId,Version FOR JSON PATH)),2)
UNION ALL SELECT N'MapNodeQrs',CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT * FROM dbo.MapNodeQrs ORDER BY Id FOR JSON PATH)),2)
UNION ALL SELECT N'LegacyIdentityUsers',CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT * FROM WayMarkAuthDatabase.dbo.AspNetUsers ORDER BY Id FOR JSON PATH)),2)
UNION ALL SELECT N'AuthMigrationHistory',CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT * FROM dbo.__AuthMigrationsHistory ORDER BY MigrationId FOR JSON PATH)),2)
ORDER BY Resource;
