-- Run manually only after review, against WayMarkDatabase.
-- Reserved namespace: WM-DEMO-2A. Existing conflicting rows abort the whole seed.
-- Enum values match NavigationNodeType and NavigationEdgeType in the API.
-- Execute the entire file as one batch. Refuse caller-owned transactions before
-- changing session options. RAISERROR deliberately does not honor XACT_ABORT,
-- even if the caller already enabled it; RETURN prevents entry into seed cleanup.
IF @@TRANCOUNT > 0
BEGIN
    RAISERROR(N'Seed refused: this session already has an open transaction. Finish that transaction yourself, then run the entire seed in a clean session.', 16, 1);
    RETURN;
END;

IF (@@OPTIONS & 2) = 2 -- IMPLICIT_TRANSACTIONS
BEGIN
    RAISERROR(N'Seed refused: IMPLICIT_TRANSACTIONS is ON. Use a clean session with IMPLICIT_TRANSACTIONS OFF; the seed will not change this setting.', 16, 1);
    RETURN;
END;

IF DB_NAME() <> N'WayMarkDatabase'
    THROW 51000, 'Select WayMarkDatabase before running this script.', 1;

SET NOCOUNT ON;
DECLARE @SeedXactAbortWasOn bit = CASE WHEN (@@OPTIONS & 16384) = 16384 THEN 1 ELSE 0 END;
DECLARE @SeedOwnsTransaction bit = 0;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;
    SET @SeedOwnsTransaction = 1;

    DECLARE @LockResult int;
    EXEC @LockResult = sys.sp_getapplock
        @Resource = N'WayMark:Seed:WM-DEMO-2A',
        @LockMode = N'Exclusive', @LockOwner = N'Transaction', @LockTimeout = 10000;
    IF @LockResult < 0
        THROW 51001, 'Could not acquire the demo seed lock.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.__EFMigrationsHistory
        WHERE MigrationId = N'20261018053754_AddNavigationSchema')
        THROW 51002, 'AddNavigationSchema must already be applied.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Sites WITH (UPDLOCK, HOLDLOCK)
        WHERE Code = N'WM-DEMO-2A'
          AND (Name <> N'WayMark Demo 2A' OR Address IS NOT NULL))
        THROW 51003, 'Demo Site code conflicts with existing data.', 1;

    INSERT INTO dbo.Sites (Name, Code, Address)
    SELECT N'WayMark Demo 2A', N'WM-DEMO-2A', NULL
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Sites WITH (UPDLOCK, HOLDLOCK)
        WHERE Code = N'WM-DEMO-2A');

    DECLARE @SiteId int = (SELECT Id FROM dbo.Sites WHERE Code = N'WM-DEMO-2A');

    IF EXISTS (SELECT 1 FROM dbo.Buildings WITH (UPDLOCK, HOLDLOCK)
        WHERE SiteId = @SiteId AND BuildingCode = N'WM-DEMO-2A-B'
          AND Name <> N'Demo Building')
        THROW 51004, 'Demo Building code conflicts with existing data.', 1;

    INSERT INTO dbo.Buildings (SiteId, Name, BuildingCode)
    SELECT @SiteId, N'Demo Building', N'WM-DEMO-2A-B'
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Buildings WITH (UPDLOCK, HOLDLOCK)
        WHERE SiteId = @SiteId AND BuildingCode = N'WM-DEMO-2A-B');

    DECLARE @BuildingId int = (SELECT Id FROM dbo.Buildings
        WHERE SiteId = @SiteId AND BuildingCode = N'WM-DEMO-2A-B');
    DECLARE @Floors table (Code nvarchar(30) PRIMARY KEY, Name nvarchar(200), SortOrder int);
    INSERT INTO @Floors VALUES (N'G', N'Demo Ground Floor', 0), (N'L1', N'Demo Level 1', 1);

    IF EXISTS (SELECT 1 FROM dbo.Floors f WITH (UPDLOCK, HOLDLOCK)
        JOIN @Floors expected ON expected.Code = f.FloorCode
        WHERE f.BuildingId = @BuildingId AND
            (f.Name <> expected.Name OR f.SortOrder <> expected.SortOrder
                OR f.FloorPlanImageUrl IS NOT NULL))
        THROW 51005, 'Demo Floor conflicts with existing data.', 1;

    INSERT INTO dbo.Floors (BuildingId, Name, FloorCode, SortOrder, FloorPlanImageUrl)
    SELECT @BuildingId, expected.Name, expected.Code, expected.SortOrder, NULL
    FROM @Floors expected
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Floors f WITH (UPDLOCK, HOLDLOCK)
        WHERE f.BuildingId = @BuildingId AND f.FloorCode = expected.Code);

    DECLARE @Nodes table (
        Code nvarchar(100) PRIMARY KEY, FloorCode nvarchar(30), Name nvarchar(200),
        X decimal(9,6), Y decimal(9,6), NodeType int);
    -- Entrance=0, Junction=1, Destination=2, Elevator=3.
    INSERT INTO @Nodes VALUES
        (N'WM-DEMO-2A-G-ENTRY', N'G', N'Demo entrance', .10, .80, 0),
        (N'WM-DEMO-2A-G-JUNCTION', N'G', N'Ground corridor', .40, .80, 1),
        (N'WM-DEMO-2A-G-LIFT', N'G', N'Ground elevator', .40, .30, 3),
        (N'WM-DEMO-2A-L1-LIFT', N'L1', N'Level 1 elevator', .40, .30, 3),
        (N'WM-DEMO-2A-L1-JUNCTION', N'L1', N'Level 1 corridor', .70, .30, 1),
        (N'WM-DEMO-2A-L1-DEST', N'L1', N'Demo destination', .70, .70, 2),
        (N'WM-DEMO-2A-G-ISOLATED', N'G', N'Isolated demo point', .90, .90, 2);

    IF EXISTS (SELECT 1 FROM dbo.NavigationNodes n WITH (UPDLOCK, HOLDLOCK)
        JOIN @Nodes expected ON expected.Code = n.NodeCode
        JOIN dbo.Floors f ON f.BuildingId = @BuildingId AND f.FloorCode = expected.FloorCode
        WHERE n.FloorId <> f.Id OR n.Name <> expected.Name OR n.X <> expected.X
            OR n.Y <> expected.Y OR n.NodeType <> expected.NodeType)
        THROW 51006, 'Global demo NodeCode conflicts with existing data.', 1;

    INSERT INTO dbo.NavigationNodes (FloorId, NodeCode, Name, X, Y, NodeType)
    SELECT f.Id, expected.Code, expected.Name, expected.X, expected.Y, expected.NodeType
    FROM @Nodes expected
    JOIN dbo.Floors f ON f.BuildingId = @BuildingId AND f.FloorCode = expected.FloorCode
    WHERE NOT EXISTS (SELECT 1 FROM dbo.NavigationNodes n WITH (UPDLOCK, HOLDLOCK)
        WHERE n.NodeCode = expected.Code);

    DECLARE @NodeIds table (Code nvarchar(100) PRIMARY KEY, Id int UNIQUE);
    INSERT INTO @NodeIds
    SELECT n.NodeCode, n.Id FROM dbo.NavigationNodes n JOIN @Nodes expected ON expected.Code = n.NodeCode;

    DECLARE @Segments table (FromCode nvarchar(100), ToCode nvarchar(100), EdgeType int,
        DistanceMeters decimal(12,3), IsActive bit, IsAccessible bit);
    -- Corridor=0, Elevator=2. All sample segments are open and deliberately marked accessible.
    INSERT INTO @Segments VALUES
        (N'WM-DEMO-2A-G-ENTRY', N'WM-DEMO-2A-G-JUNCTION', 0, 10, 1, 1),
        (N'WM-DEMO-2A-G-JUNCTION', N'WM-DEMO-2A-G-LIFT', 0, 8, 1, 1),
        (N'WM-DEMO-2A-G-LIFT', N'WM-DEMO-2A-L1-LIFT', 2, 4, 1, 1),
        (N'WM-DEMO-2A-L1-LIFT', N'WM-DEMO-2A-L1-JUNCTION', 0, 12, 1, 1),
        (N'WM-DEMO-2A-L1-JUNCTION', N'WM-DEMO-2A-L1-DEST', 0, 6, 1, 1);

    DECLARE @Edges table (FromNodeId int, ToNodeId int, EdgeType int,
        DistanceMeters decimal(12,3), IsActive bit, IsAccessible bit,
        PRIMARY KEY (FromNodeId, ToNodeId));
    INSERT INTO @Edges
    SELECT src.Id, dst.Id, s.EdgeType, s.DistanceMeters, s.IsActive, s.IsAccessible
    FROM @Segments s JOIN @NodeIds src ON src.Code = s.FromCode JOIN @NodeIds dst ON dst.Code = s.ToCode
    UNION ALL
    SELECT dst.Id, src.Id, s.EdgeType, s.DistanceMeters, s.IsActive, s.IsAccessible
    FROM @Segments s JOIN @NodeIds src ON src.Code = s.FromCode JOIN @NodeIds dst ON dst.Code = s.ToCode;

    IF EXISTS (SELECT 1 FROM dbo.NavigationEdges e WITH (UPDLOCK, HOLDLOCK)
        LEFT JOIN @Edges expected ON expected.FromNodeId = e.FromNodeId AND expected.ToNodeId = e.ToNodeId
        WHERE (e.FromNodeId IN (SELECT Id FROM @NodeIds) OR e.ToNodeId IN (SELECT Id FROM @NodeIds))
          AND (expected.FromNodeId IS NULL OR e.EdgeType <> expected.EdgeType
            OR e.DistanceMeters <> expected.DistanceMeters OR e.IsActive <> expected.IsActive
            OR e.IsAccessible <> expected.IsAccessible))
        THROW 51007, 'Demo edges were modified or connected to other data; seed aborted.', 1;

    IF EXISTS (SELECT 1 FROM dbo.NavigationEdges e WITH (UPDLOCK, HOLDLOCK)
        JOIN @Edges expected ON expected.FromNodeId = e.FromNodeId AND expected.ToNodeId = e.ToNodeId
        GROUP BY e.FromNodeId, e.ToNodeId HAVING COUNT(*) > 1)
        THROW 51008, 'Duplicate demo edges already exist; seed aborted.', 1;

    INSERT INTO dbo.NavigationEdges (FromNodeId, ToNodeId, EdgeType, DistanceMeters, IsActive, IsAccessible)
    SELECT expected.FromNodeId, expected.ToNodeId, expected.EdgeType, expected.DistanceMeters,
        expected.IsActive, expected.IsAccessible FROM @Edges expected
    WHERE NOT EXISTS (SELECT 1 FROM dbo.NavigationEdges e WITH (UPDLOCK, HOLDLOCK)
        WHERE e.FromNodeId = expected.FromNodeId AND e.ToNodeId = expected.ToNodeId);

    DECLARE @WayMarks table (Code nvarchar(100) PRIMARY KEY, Name nvarchar(200),
        Location nvarchar(300), NodeCode nvarchar(100));
    INSERT INTO @WayMarks VALUES
        (N'WM-DEMO-2A-START', N'Demo start', N'Demo Building / Ground Floor', N'WM-DEMO-2A-G-ENTRY'),
        (N'WM-DEMO-2A-DEST', N'Demo destination', N'Demo Building / Level 1', N'WM-DEMO-2A-L1-DEST');

    IF EXISTS (SELECT 1 FROM dbo.WayMarks w WITH (UPDLOCK, HOLDLOCK)
        JOIN @WayMarks expected ON expected.Code = w.WayMarkCode
        JOIN @NodeIds n ON n.Code = expected.NodeCode
        WHERE w.Name <> expected.Name OR w.Location <> expected.Location
            OR w.NavigationNodeId IS NULL OR w.NavigationNodeId <> n.Id)
        THROW 51009, 'Demo WayMark code conflicts with existing data; no existing WayMark will be overwritten.', 1;

    IF EXISTS (SELECT 1 FROM dbo.WayMarks w WITH (UPDLOCK, HOLDLOCK)
        JOIN @NodeIds n ON n.Id = w.NavigationNodeId
        JOIN @WayMarks expected ON expected.NodeCode = n.Code
        WHERE w.WayMarkCode <> expected.Code)
        THROW 51010, 'Demo start or destination node is already linked to another WayMark.', 1;

    INSERT INTO dbo.WayMarks (Name, Location, WayMarkCode, NavigationNodeId)
    SELECT expected.Name, expected.Location, expected.Code, n.Id
    FROM @WayMarks expected JOIN @NodeIds n ON n.Code = expected.NodeCode
    WHERE NOT EXISTS (SELECT 1 FROM dbo.WayMarks w WITH (UPDLOCK, HOLDLOCK)
        WHERE w.WayMarkCode = expected.Code);

    COMMIT TRANSACTION;
    SET @SeedOwnsTransaction = 0;
END TRY
BEGIN CATCH
    IF @SeedOwnsTransaction = 1 AND XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    IF @SeedXactAbortWasOn = 0 SET XACT_ABORT OFF;
    THROW;
END CATCH;

IF @SeedXactAbortWasOn = 0 SET XACT_ABORT OFF;
RAISERROR(N'Seed data was COMMITTED successfully. Result sets below are read-only reporting.', 10, 1) WITH NOWAIT;

-- Reporting is outside transaction cleanup. A reporting failure cannot undo a
-- successful COMMIT and is reported as a warning, not as a seed rollback.
BEGIN TRY
    SELECT @SiteId AS SiteId, @BuildingId AS BuildingId;
    SELECT Id, Name, FloorCode FROM dbo.Floors WHERE BuildingId = @BuildingId ORDER BY SortOrder;
    SELECT Code AS NodeCode, Id FROM @NodeIds ORDER BY Code;
    SELECT w.Id, w.WayMarkCode, w.NavigationNodeId FROM dbo.WayMarks w
        JOIN @WayMarks expected ON expected.Code = w.WayMarkCode;
END TRY
BEGIN CATCH
    DECLARE @SeedReportError nvarchar(1800) = ERROR_MESSAGE();
    RAISERROR(N'Seed data was COMMITTED, but post-commit reporting failed: %s', 10, 1, @SeedReportError) WITH NOWAIT;
END CATCH;
