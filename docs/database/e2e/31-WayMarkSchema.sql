-- EF Core SQL Server 10.0.12; 0 -> 20261020101304_BindMapImagesToDrafts; WayMarkDbContext.
-- Generated offline; only guards added per batch; NEVER EXECUTED by this generator.
-- Execution requires a parameterized runner; never paste a secret into this file.
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'WayMark_MapDraft_E2E_Test'
 OR NULLIF(@ExpectedServerName,N'') IS NULL
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) <> @ExpectedServerName
 OR SUSER_SNAME() <> N'WayMark_E2E_Migrator' OR ORIGINAL_LOGIN() <> N'WayMark_E2E_Migrator'
 OR ISNULL(IS_SRVROLEMEMBER('sysadmin'),1) <> 0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'CONTROL SERVER'),1) <> 0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY LOGIN'),1) <> 0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY DATABASE'),1) <> 0
 OR ISNULL(HAS_DBACCESS(N'WayMarkDatabase'),0) <> 0 OR ISNULL(HAS_DBACCESS(N'WayMarkAuthDatabase'),0) <> 0
    THROW 51000, 'Migration target/principal guard refused execution.', 1;
IF OBJECT_ID(N'[__EFMigrationsHistory]') IS NULL
BEGIN
    CREATE TABLE [__EFMigrationsHistory] (
        [MigrationId] nvarchar(150) NOT NULL,
        [ProductVersion] nvarchar(32) NOT NULL,
        CONSTRAINT [PK___EFMigrationsHistory] PRIMARY KEY ([MigrationId])
    );
END;
GO

-- Execution requires a parameterized runner; never paste a secret into this file.
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'WayMark_MapDraft_E2E_Test'
 OR NULLIF(@ExpectedServerName,N'') IS NULL
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) <> @ExpectedServerName
 OR SUSER_SNAME() <> N'WayMark_E2E_Migrator' OR ORIGINAL_LOGIN() <> N'WayMark_E2E_Migrator'
 OR ISNULL(IS_SRVROLEMEMBER('sysadmin'),1) <> 0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'CONTROL SERVER'),1) <> 0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY LOGIN'),1) <> 0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY DATABASE'),1) <> 0
 OR ISNULL(HAS_DBACCESS(N'WayMarkDatabase'),0) <> 0 OR ISNULL(HAS_DBACCESS(N'WayMarkAuthDatabase'),0) <> 0
    THROW 51000, 'Migration target/principal guard refused execution.', 1;
BEGIN TRANSACTION;
IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261018022742_CreateWayMarkSchema'
)
BEGIN
    CREATE TABLE [WayMarks] (
        [Id] int NOT NULL IDENTITY,
        [Name] nvarchar(200) NOT NULL,
        [Location] nvarchar(300) NOT NULL,
        [WayMarkCode] nvarchar(100) NOT NULL,
        CONSTRAINT [PK_WayMarks] PRIMARY KEY ([Id])
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261018022742_CreateWayMarkSchema'
)
BEGIN
    CREATE UNIQUE INDEX [IX_WayMarks_WayMarkCode] ON [WayMarks] ([WayMarkCode]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261018022742_CreateWayMarkSchema'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20261018022742_CreateWayMarkSchema', N'10.0.12');
END;

COMMIT;
GO

-- Execution requires a parameterized runner; never paste a secret into this file.
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'WayMark_MapDraft_E2E_Test'
 OR NULLIF(@ExpectedServerName,N'') IS NULL
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) <> @ExpectedServerName
 OR SUSER_SNAME() <> N'WayMark_E2E_Migrator' OR ORIGINAL_LOGIN() <> N'WayMark_E2E_Migrator'
 OR ISNULL(IS_SRVROLEMEMBER('sysadmin'),1) <> 0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'CONTROL SERVER'),1) <> 0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY LOGIN'),1) <> 0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY DATABASE'),1) <> 0
 OR ISNULL(HAS_DBACCESS(N'WayMarkDatabase'),0) <> 0 OR ISNULL(HAS_DBACCESS(N'WayMarkAuthDatabase'),0) <> 0
    THROW 51000, 'Migration target/principal guard refused execution.', 1;
BEGIN TRANSACTION;
IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261018053754_AddNavigationSchema'
)
BEGIN
    ALTER TABLE [WayMarks] ADD [NavigationNodeId] int NULL;
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261018053754_AddNavigationSchema'
)
BEGIN
    CREATE TABLE [Sites] (
        [Id] int NOT NULL IDENTITY,
        [Name] nvarchar(200) NOT NULL,
        [Code] nvarchar(50) NOT NULL,
        [Address] nvarchar(500) NULL,
        CONSTRAINT [PK_Sites] PRIMARY KEY ([Id])
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261018053754_AddNavigationSchema'
)
BEGIN
    CREATE TABLE [Buildings] (
        [Id] int NOT NULL IDENTITY,
        [SiteId] int NOT NULL,
        [Name] nvarchar(200) NOT NULL,
        [BuildingCode] nvarchar(50) NOT NULL,
        CONSTRAINT [PK_Buildings] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_Buildings_Sites_SiteId] FOREIGN KEY ([SiteId]) REFERENCES [Sites] ([Id]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261018053754_AddNavigationSchema'
)
BEGIN
    CREATE TABLE [Floors] (
        [Id] int NOT NULL IDENTITY,
        [BuildingId] int NOT NULL,
        [Name] nvarchar(200) NOT NULL,
        [FloorCode] nvarchar(30) NOT NULL,
        [SortOrder] int NOT NULL,
        [FloorPlanImageUrl] nvarchar(1000) NULL,
        CONSTRAINT [PK_Floors] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_Floors_Buildings_BuildingId] FOREIGN KEY ([BuildingId]) REFERENCES [Buildings] ([Id]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261018053754_AddNavigationSchema'
)
BEGIN
    CREATE TABLE [NavigationNodes] (
        [Id] int NOT NULL IDENTITY,
        [FloorId] int NOT NULL,
        [NodeCode] nvarchar(100) NOT NULL,
        [Name] nvarchar(200) NOT NULL,
        [X] decimal(9,6) NOT NULL,
        [Y] decimal(9,6) NOT NULL,
        [NodeType] int NOT NULL,
        CONSTRAINT [PK_NavigationNodes] PRIMARY KEY ([Id]),
        CONSTRAINT [CK_NavigationNodes_X_Range] CHECK ([X] >= 0 AND [X] <= 1),
        CONSTRAINT [CK_NavigationNodes_Y_Range] CHECK ([Y] >= 0 AND [Y] <= 1),
        CONSTRAINT [FK_NavigationNodes_Floors_FloorId] FOREIGN KEY ([FloorId]) REFERENCES [Floors] ([Id]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261018053754_AddNavigationSchema'
)
BEGIN
    CREATE TABLE [NavigationEdges] (
        [Id] int NOT NULL IDENTITY,
        [FromNodeId] int NOT NULL,
        [ToNodeId] int NOT NULL,
        [EdgeType] int NOT NULL,
        [DistanceMeters] decimal(12,3) NOT NULL,
        [IsActive] bit NOT NULL DEFAULT CAST(1 AS bit),
        [IsAccessible] bit NOT NULL DEFAULT CAST(0 AS bit),
        CONSTRAINT [PK_NavigationEdges] PRIMARY KEY ([Id]),
        CONSTRAINT [CK_NavigationEdges_DifferentNodes] CHECK ([FromNodeId] <> [ToNodeId]),
        CONSTRAINT [CK_NavigationEdges_DistanceMeters_Positive] CHECK ([DistanceMeters] > 0),
        CONSTRAINT [FK_NavigationEdges_NavigationNodes_FromNodeId] FOREIGN KEY ([FromNodeId]) REFERENCES [NavigationNodes] ([Id]) ON DELETE NO ACTION,
        CONSTRAINT [FK_NavigationEdges_NavigationNodes_ToNodeId] FOREIGN KEY ([ToNodeId]) REFERENCES [NavigationNodes] ([Id]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261018053754_AddNavigationSchema'
)
BEGIN
    EXEC(N'CREATE UNIQUE INDEX [IX_WayMarks_NavigationNodeId] ON [WayMarks] ([NavigationNodeId]) WHERE [NavigationNodeId] IS NOT NULL');
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261018053754_AddNavigationSchema'
)
BEGIN
    CREATE UNIQUE INDEX [IX_Buildings_SiteId_BuildingCode] ON [Buildings] ([SiteId], [BuildingCode]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261018053754_AddNavigationSchema'
)
BEGIN
    CREATE UNIQUE INDEX [IX_Floors_BuildingId_FloorCode] ON [Floors] ([BuildingId], [FloorCode]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261018053754_AddNavigationSchema'
)
BEGIN
    CREATE INDEX [IX_NavigationEdges_FromNodeId] ON [NavigationEdges] ([FromNodeId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261018053754_AddNavigationSchema'
)
BEGIN
    CREATE INDEX [IX_NavigationEdges_ToNodeId] ON [NavigationEdges] ([ToNodeId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261018053754_AddNavigationSchema'
)
BEGIN
    CREATE INDEX [IX_NavigationNodes_FloorId] ON [NavigationNodes] ([FloorId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261018053754_AddNavigationSchema'
)
BEGIN
    CREATE UNIQUE INDEX [IX_NavigationNodes_NodeCode] ON [NavigationNodes] ([NodeCode]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261018053754_AddNavigationSchema'
)
BEGIN
    CREATE UNIQUE INDEX [IX_Sites_Code] ON [Sites] ([Code]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261018053754_AddNavigationSchema'
)
BEGIN
    ALTER TABLE [WayMarks] ADD CONSTRAINT [FK_WayMarks_NavigationNodes_NavigationNodeId] FOREIGN KEY ([NavigationNodeId]) REFERENCES [NavigationNodes] ([Id]) ON DELETE NO ACTION;
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261018053754_AddNavigationSchema'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20261018053754_AddNavigationSchema', N'10.0.12');
END;

COMMIT;
GO

-- Execution requires a parameterized runner; never paste a secret into this file.
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'WayMark_MapDraft_E2E_Test'
 OR NULLIF(@ExpectedServerName,N'') IS NULL
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) <> @ExpectedServerName
 OR SUSER_SNAME() <> N'WayMark_E2E_Migrator' OR ORIGINAL_LOGIN() <> N'WayMark_E2E_Migrator'
 OR ISNULL(IS_SRVROLEMEMBER('sysadmin'),1) <> 0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'CONTROL SERVER'),1) <> 0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY LOGIN'),1) <> 0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY DATABASE'),1) <> 0
 OR ISNULL(HAS_DBACCESS(N'WayMarkDatabase'),0) <> 0 OR ISNULL(HAS_DBACCESS(N'WayMarkAuthDatabase'),0) <> 0
    THROW 51000, 'Migration target/principal guard refused execution.', 1;
BEGIN TRANSACTION;
IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261020094848_AddMapDraftFoundation'
)
BEGIN
    CREATE TABLE [FloorMapDrafts] (
        [Id] uniqueidentifier NOT NULL,
        [FloorId] int NOT NULL,
        [Version] bigint NOT NULL,
        [Status] nvarchar(20) NOT NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        [UpdatedAt] datetimeoffset NOT NULL,
        [CreatedBy] nvarchar(450) NOT NULL,
        [UpdatedBy] nvarchar(450) NOT NULL,
        CONSTRAINT [PK_FloorMapDrafts] PRIMARY KEY ([Id]),
        CONSTRAINT [CK_FloorMapDrafts_Status] CHECK ([Status] = 'Draft'),
        CONSTRAINT [CK_FloorMapDrafts_Version] CHECK ([Version] > 0),
        CONSTRAINT [FK_FloorMapDrafts_Floors_FloorId] FOREIGN KEY ([FloorId]) REFERENCES [Floors] ([Id]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261020094848_AddMapDraftFoundation'
)
BEGIN
    CREATE TABLE [FloorMapImageAssets] (
        [Id] uniqueidentifier NOT NULL,
        [FloorId] int NOT NULL,
        [StorageKey] nvarchar(64) NOT NULL,
        [MimeType] nvarchar(20) NOT NULL,
        [Width] int NOT NULL,
        [Height] int NOT NULL,
        [ByteLength] bigint NOT NULL,
        [Sha256] nvarchar(64) NOT NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        [CreatedBy] nvarchar(450) NOT NULL,
        CONSTRAINT [PK_FloorMapImageAssets] PRIMARY KEY ([Id]),
        CONSTRAINT [CK_FloorMapImageAssets_Bytes] CHECK ([ByteLength] > 0 AND [ByteLength] <= 10485760),
        CONSTRAINT [CK_FloorMapImageAssets_Height] CHECK ([Height] > 0 AND [Height] <= 8192),
        CONSTRAINT [CK_FloorMapImageAssets_Mime] CHECK ([MimeType] IN ('image/png', 'image/jpeg')),
        CONSTRAINT [CK_FloorMapImageAssets_Pixels] CHECK (CAST([Width] AS bigint) * [Height] <= 32000000),
        CONSTRAINT [CK_FloorMapImageAssets_Width] CHECK ([Width] > 0 AND [Width] <= 8192),
        CONSTRAINT [FK_FloorMapImageAssets_Floors_FloorId] FOREIGN KEY ([FloorId]) REFERENCES [Floors] ([Id]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261020094848_AddMapDraftFoundation'
)
BEGIN
    CREATE TABLE [SiteMapMemberships] (
        [Id] int NOT NULL IDENTITY,
        [SiteId] int NOT NULL,
        [UserId] nvarchar(450) NOT NULL,
        [IsActive] bit NOT NULL,
        [CanEditDrafts] bit NOT NULL,
        CONSTRAINT [PK_SiteMapMemberships] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_SiteMapMemberships_Sites_SiteId] FOREIGN KEY ([SiteId]) REFERENCES [Sites] ([Id]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261020094848_AddMapDraftFoundation'
)
BEGIN
    CREATE TABLE [FloorMapDraftRevisions] (
        [DraftId] uniqueidentifier NOT NULL,
        [Version] bigint NOT NULL,
        [ContentJson] nvarchar(max) NOT NULL,
        [ImageAssetId] uniqueidentifier NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        [CreatedBy] nvarchar(450) NOT NULL,
        CONSTRAINT [PK_FloorMapDraftRevisions] PRIMARY KEY ([DraftId], [Version]),
        CONSTRAINT [CK_FloorMapDraftRevisions_Version] CHECK ([Version] > 0),
        CONSTRAINT [FK_FloorMapDraftRevisions_FloorMapDrafts_DraftId] FOREIGN KEY ([DraftId]) REFERENCES [FloorMapDrafts] ([Id]) ON DELETE NO ACTION,
        CONSTRAINT [FK_FloorMapDraftRevisions_FloorMapImageAssets_ImageAssetId] FOREIGN KEY ([ImageAssetId]) REFERENCES [FloorMapImageAssets] ([Id]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261020094848_AddMapDraftFoundation'
)
BEGIN
    CREATE INDEX [IX_FloorMapDraftRevisions_ImageAssetId] ON [FloorMapDraftRevisions] ([ImageAssetId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261020094848_AddMapDraftFoundation'
)
BEGIN
    CREATE UNIQUE INDEX [IX_FloorMapDrafts_FloorId] ON [FloorMapDrafts] ([FloorId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261020094848_AddMapDraftFoundation'
)
BEGIN
    CREATE INDEX [IX_FloorMapImageAssets_FloorId] ON [FloorMapImageAssets] ([FloorId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261020094848_AddMapDraftFoundation'
)
BEGIN
    CREATE UNIQUE INDEX [IX_FloorMapImageAssets_StorageKey] ON [FloorMapImageAssets] ([StorageKey]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261020094848_AddMapDraftFoundation'
)
BEGIN
    CREATE UNIQUE INDEX [IX_SiteMapMemberships_SiteId_UserId] ON [SiteMapMemberships] ([SiteId], [UserId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261020094848_AddMapDraftFoundation'
)
BEGIN
    CREATE INDEX [IX_SiteMapMemberships_UserId] ON [SiteMapMemberships] ([UserId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261020094848_AddMapDraftFoundation'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20261020094848_AddMapDraftFoundation', N'10.0.12');
END;

COMMIT;
GO

-- Execution requires a parameterized runner; never paste a secret into this file.
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'WayMark_MapDraft_E2E_Test'
 OR NULLIF(@ExpectedServerName,N'') IS NULL
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) <> @ExpectedServerName
 OR SUSER_SNAME() <> N'WayMark_E2E_Migrator' OR ORIGINAL_LOGIN() <> N'WayMark_E2E_Migrator'
 OR ISNULL(IS_SRVROLEMEMBER('sysadmin'),1) <> 0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'CONTROL SERVER'),1) <> 0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY LOGIN'),1) <> 0
 OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY DATABASE'),1) <> 0
 OR ISNULL(HAS_DBACCESS(N'WayMarkDatabase'),0) <> 0 OR ISNULL(HAS_DBACCESS(N'WayMarkAuthDatabase'),0) <> 0
    THROW 51000, 'Migration target/principal guard refused execution.', 1;
BEGIN TRANSACTION;
IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261020101304_BindMapImagesToDrafts'
)
BEGIN
    ALTER TABLE [FloorMapDrafts] ADD CONSTRAINT [AK_FloorMapDrafts_FloorId] UNIQUE ([FloorId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261020101304_BindMapImagesToDrafts'
)
BEGIN
    ALTER TABLE [FloorMapImageAssets] ADD CONSTRAINT [FK_FloorMapImageAssets_FloorMapDrafts_FloorId] FOREIGN KEY ([FloorId]) REFERENCES [FloorMapDrafts] ([FloorId]) ON DELETE NO ACTION;
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261020101304_BindMapImagesToDrafts'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20261020101304_BindMapImagesToDrafts', N'10.0.12');
END;

COMMIT;
GO
