-- READ ONLY in master. No Identity data, password hashes, keys or user rows are exported.
IF DB_NAME()<>N'master' OR NULLIF(@ExpectedServerName,N'') IS NULL
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))<>@ExpectedServerName
    THROW 51000, 'Evidence target refused.', 1;
SELECT name,state_desc,is_read_committed_snapshot_on FROM sys.databases
 WHERE name IN(N'WayMarkDatabase',N'WayMarkAuthDatabase',N'WayMark_MapDraft_E2E_Test');
SELECT N'Sites' AS TableName,COUNT_BIG(*) AS [RowCount],
 CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT Id,Name,Code,Address FROM [WayMarkDatabase].dbo.Sites ORDER BY Id FOR JSON PATH,INCLUDE_NULL_VALUES)),2) AS ContentSha256 FROM [WayMarkDatabase].dbo.Sites
UNION ALL SELECT N'Buildings',COUNT_BIG(*),
 CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT Id,SiteId,Name,BuildingCode FROM [WayMarkDatabase].dbo.Buildings ORDER BY Id FOR JSON PATH,INCLUDE_NULL_VALUES)),2) FROM [WayMarkDatabase].dbo.Buildings
UNION ALL SELECT N'Floors',COUNT_BIG(*),
 CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT Id,BuildingId,Name,FloorCode,SortOrder,FloorPlanImageUrl FROM [WayMarkDatabase].dbo.Floors ORDER BY Id FOR JSON PATH,INCLUDE_NULL_VALUES)),2) FROM [WayMarkDatabase].dbo.Floors
UNION ALL SELECT N'NavigationNodes',COUNT_BIG(*),
 CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT Id,FloorId,NodeCode,Name,X,Y,NodeType FROM [WayMarkDatabase].dbo.NavigationNodes ORDER BY Id FOR JSON PATH,INCLUDE_NULL_VALUES)),2) FROM [WayMarkDatabase].dbo.NavigationNodes
UNION ALL SELECT N'NavigationEdges',COUNT_BIG(*),
 CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT Id,FromNodeId,ToNodeId,EdgeType,DistanceMeters,IsActive,IsAccessible FROM [WayMarkDatabase].dbo.NavigationEdges ORDER BY Id FOR JSON PATH,INCLUDE_NULL_VALUES)),2) FROM [WayMarkDatabase].dbo.NavigationEdges
UNION ALL SELECT N'WayMarks',COUNT_BIG(*),
 CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT Id,Name,Location,WayMarkCode,NavigationNodeId FROM [WayMarkDatabase].dbo.WayMarks ORDER BY Id FOR JSON PATH,INCLUDE_NULL_VALUES)),2) FROM [WayMarkDatabase].dbo.WayMarks;
SELECT MigrationId,ProductVersion FROM [WayMarkDatabase].dbo.__EFMigrationsHistory ORDER BY MigrationId;
SELECT MigrationId,ProductVersion FROM [WayMarkDatabase].dbo.__AuthMigrationsHistory ORDER BY MigrationId;
SELECT N'WayMarkAuthDatabase' AS DatabaseName,s.name AS SchemaName,t.name AS TableName
 FROM [WayMarkAuthDatabase].sys.tables t JOIN [WayMarkAuthDatabase].sys.schemas s ON s.schema_id=t.schema_id ORDER BY s.name,t.name;
