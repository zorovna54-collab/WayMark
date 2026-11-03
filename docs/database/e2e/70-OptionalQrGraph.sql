-- OPTIONAL, separately approved synthetic fixture. NOT a real accessible hospital map.
IF @@TRANCOUNT<>0 OR (2 & @@OPTIONS)=2 THROW 51000, 'Fresh session required.', 1;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'WayMark_MapDraft_E2E_Test'
 OR NULLIF(@ExpectedServerName,N'') IS NULL OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))<>@ExpectedServerName
 OR NULLIF(@ExpectedProvisioningLogin,N'') IS NULL OR ORIGINAL_LOGIN()<>@ExpectedProvisioningLogin OR ISNULL(HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','CONTROL'),0)<>1
    THROW 51000, 'QR fixture target/permission refused.', 1;
IF EXISTS(SELECT 1 FROM dbo.NavigationNodes) OR EXISTS(SELECT 1 FROM dbo.NavigationEdges) OR EXISTS(SELECT 1 FROM dbo.WayMarks)
    THROW 51000, 'Existing graph/QR found; no overwrite or duplication allowed.', 1;
DECLARE @ground int,@level int;
SELECT @ground=f.Id FROM dbo.Floors f JOIN dbo.Buildings b ON b.Id=f.BuildingId JOIN dbo.Sites s ON s.Id=b.SiteId
 WHERE s.Code=N'E2E-7B2D-A' AND b.BuildingCode=N'E2E-B1' AND f.FloorCode=N'G';
SELECT @level=f.Id FROM dbo.Floors f JOIN dbo.Buildings b ON b.Id=f.BuildingId JOIN dbo.Sites s ON s.Id=b.SiteId
 WHERE s.Code=N'E2E-7B2D-A' AND b.BuildingCode=N'E2E-B1' AND f.FloorCode=N'L1';
IF @ground IS NULL OR @level IS NULL THROW 51000, 'Create the controlled test hierarchy first.', 1;
SET XACT_ABORT ON;
BEGIN TRY
 BEGIN TRANSACTION;
 -- Enum values match current NavigationNodeType / NavigationEdgeType source.
 INSERT dbo.NavigationNodes(FloorId,NodeCode,Name,X,Y,NodeType) VALUES
 (@ground,N'E2E7B2D-G-START',N'E2E Entrance',.2,.2,0),
 (@ground,N'E2E7B2D-G-LIFT',N'E2E Ground Elevator',.5,.5,3),
 (@level,N'E2E7B2D-L1-LIFT',N'E2E Level 1 Elevator',.5,.5,3),
 (@level,N'E2E7B2D-L1-END',N'E2E Destination Entrance',.8,.8,0),
 (@level,N'E2E7B2D-L1-ISOLATED',N'E2E Isolated Entrance',.1,.8,0);
 INSERT dbo.NavigationEdges(FromNodeId,ToNodeId,EdgeType,DistanceMeters,IsActive,IsAccessible)
 SELECT a.Id,b.Id,v.EdgeType,v.DistanceMeters,1,0 FROM (VALUES
 (N'E2E7B2D-G-START',N'E2E7B2D-G-LIFT',0,CAST(8 AS decimal(12,3))),
 (N'E2E7B2D-G-LIFT',N'E2E7B2D-G-START',0,CAST(8 AS decimal(12,3))),
 (N'E2E7B2D-G-LIFT',N'E2E7B2D-L1-LIFT',2,CAST(6 AS decimal(12,3))),
 (N'E2E7B2D-L1-LIFT',N'E2E7B2D-G-LIFT',2,CAST(6 AS decimal(12,3))),
 (N'E2E7B2D-L1-LIFT',N'E2E7B2D-L1-END',0,CAST(9 AS decimal(12,3))),
 (N'E2E7B2D-L1-END',N'E2E7B2D-L1-LIFT',0,CAST(9 AS decimal(12,3)))) v(FromCode,ToCode,EdgeType,DistanceMeters)
 JOIN dbo.NavigationNodes a ON a.NodeCode=v.FromCode JOIN dbo.NavigationNodes b ON b.NodeCode=v.ToCode;
 INSERT dbo.WayMarks(Name,Location,WayMarkCode,NavigationNodeId)
 SELECT n.Name,N'E2E synthetic test location',v.Code,n.Id FROM (VALUES
 (N'E2E7B2D-G-START',N'WM-E2E-7B2D-START'),(N'E2E7B2D-L1-END',N'WM-E2E-7B2D-DEST'),
 (N'E2E7B2D-L1-ISOLATED',N'WM-E2E-7B2D-ISOLATED')) v(NodeCode,Code) JOIN dbo.NavigationNodes n ON n.NodeCode=v.NodeCode;
 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
