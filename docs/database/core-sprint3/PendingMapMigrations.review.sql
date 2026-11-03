-- REVIEW ONLY. Not executed by this generator. Requires separately approved, fail-on-error executor.
-- Fresh dedicated session: no ambient/implicit transaction. SESSION_CONTEXT is not authorization.
IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
BEGIN
    RAISERROR(N'Fresh session with IMPLICIT_TRANSACTIONS OFF required.',16,1);
    RETURN;
END;
SET XACT_ABORT ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'WayMarkDatabase'
 OR SERVERPROPERTY('ServerName') IS NULL
 OR SESSION_CONTEXT(N'WayMarkApprovedServer') IS NULL
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) COLLATE Latin1_General_100_BIN2
    <> CONVERT(nvarchar(128),SESSION_CONTEXT(N'WayMarkApprovedServer')) COLLATE Latin1_General_100_BIN2
    THROW 51000, 'Approved server/database context required. Stop execution.', 1;
IF OBJECT_ID(N'[dbo].[__EFMigrationsHistory]',N'U') IS NULL
    THROW 51000, 'Existing map migration history is required.', 1;
IF NOT EXISTS (SELECT 1 FROM [dbo].[__EFMigrationsHistory] WHERE [MigrationId]=N'20261018053754_AddNavigationSchema')
    THROW 51000, 'Expected navigation baseline is missing.', 1;
BEGIN TRANSACTION;
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

CREATE TABLE [SiteMapMemberships] (
    [Id] int NOT NULL IDENTITY,
    [SiteId] int NOT NULL,
    [UserId] nvarchar(450) NOT NULL,
    [IsActive] bit NOT NULL,
    [CanEditDrafts] bit NOT NULL,
    CONSTRAINT [PK_SiteMapMemberships] PRIMARY KEY ([Id]),
    CONSTRAINT [FK_SiteMapMemberships_Sites_SiteId] FOREIGN KEY ([SiteId]) REFERENCES [Sites] ([Id]) ON DELETE NO ACTION
);

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

CREATE INDEX [IX_FloorMapDraftRevisions_ImageAssetId] ON [FloorMapDraftRevisions] ([ImageAssetId]);

CREATE UNIQUE INDEX [IX_FloorMapDrafts_FloorId] ON [FloorMapDrafts] ([FloorId]);

CREATE INDEX [IX_FloorMapImageAssets_FloorId] ON [FloorMapImageAssets] ([FloorId]);

CREATE UNIQUE INDEX [IX_FloorMapImageAssets_StorageKey] ON [FloorMapImageAssets] ([StorageKey]);

CREATE UNIQUE INDEX [IX_SiteMapMemberships_SiteId_UserId] ON [SiteMapMemberships] ([SiteId], [UserId]);

CREATE INDEX [IX_SiteMapMemberships_UserId] ON [SiteMapMemberships] ([UserId]);

INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
VALUES (N'20261020094848_AddMapDraftFoundation', N'10.0.12');

COMMIT;
GO
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'WayMarkDatabase'
 OR SERVERPROPERTY('ServerName') IS NULL
 OR SESSION_CONTEXT(N'WayMarkApprovedServer') IS NULL
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) COLLATE Latin1_General_100_BIN2
    <> CONVERT(nvarchar(128),SESSION_CONTEXT(N'WayMarkApprovedServer')) COLLATE Latin1_General_100_BIN2
    THROW 51000, 'Approved server/database context required. Stop execution.', 1;
IF OBJECT_ID(N'[dbo].[__EFMigrationsHistory]',N'U') IS NULL
    THROW 51000, 'Existing map migration history is required.', 1;
IF NOT EXISTS (SELECT 1 FROM [dbo].[__EFMigrationsHistory] WHERE [MigrationId]=N'20261018053754_AddNavigationSchema')
    THROW 51000, 'Expected navigation baseline is missing.', 1;
BEGIN TRANSACTION;
ALTER TABLE [FloorMapDrafts] ADD CONSTRAINT [AK_FloorMapDrafts_FloorId] UNIQUE ([FloorId]);

ALTER TABLE [FloorMapImageAssets] ADD CONSTRAINT [FK_FloorMapImageAssets_FloorMapDrafts_FloorId] FOREIGN KEY ([FloorId]) REFERENCES [FloorMapDrafts] ([FloorId]) ON DELETE NO ACTION;

INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
VALUES (N'20261020101304_BindMapImagesToDrafts', N'10.0.12');

COMMIT;
GO
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'WayMarkDatabase'
 OR SERVERPROPERTY('ServerName') IS NULL
 OR SESSION_CONTEXT(N'WayMarkApprovedServer') IS NULL
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) COLLATE Latin1_General_100_BIN2
    <> CONVERT(nvarchar(128),SESSION_CONTEXT(N'WayMarkApprovedServer')) COLLATE Latin1_General_100_BIN2
    THROW 51000, 'Approved server/database context required. Stop execution.', 1;
IF OBJECT_ID(N'[dbo].[__EFMigrationsHistory]',N'U') IS NULL
    THROW 51000, 'Existing map migration history is required.', 1;
IF NOT EXISTS (SELECT 1 FROM [dbo].[__EFMigrationsHistory] WHERE [MigrationId]=N'20261018053754_AddNavigationSchema')
    THROW 51000, 'Expected navigation baseline is missing.', 1;
BEGIN TRANSACTION;
CREATE TABLE [MapProjects] (
    [Id] uniqueidentifier NOT NULL,
    [LocalProjectId] uniqueidentifier NOT NULL,
    [SiteId] int NOT NULL,
    [BuildingId] int NOT NULL,
    [OwnerId] nvarchar(450) NOT NULL,
    [Name] nvarchar(200) NOT NULL,
    [Version] bigint NOT NULL,
    [ContentJson] nvarchar(max) NOT NULL,
    [UpdatedAt] datetimeoffset NOT NULL,
    CONSTRAINT [PK_MapProjects] PRIMARY KEY ([Id]),
    CONSTRAINT [CK_MapProjects_Version] CHECK ([Version] > 0),
    CONSTRAINT [FK_MapProjects_Buildings_BuildingId] FOREIGN KEY ([BuildingId]) REFERENCES [Buildings] ([Id]) ON DELETE NO ACTION,
    CONSTRAINT [FK_MapProjects_Sites_SiteId] FOREIGN KEY ([SiteId]) REFERENCES [Sites] ([Id]) ON DELETE NO ACTION
);

CREATE TABLE [MapPublications] (
    [MapId] uniqueidentifier NOT NULL,
    [Version] bigint NOT NULL,
    [Name] nvarchar(200) NOT NULL,
    [ContentJson] nvarchar(max) NOT NULL,
    [PublishedBy] nvarchar(450) NOT NULL,
    [PublishedAt] datetimeoffset NOT NULL,
    CONSTRAINT [PK_MapPublications] PRIMARY KEY ([MapId], [Version]),
    CONSTRAINT [CK_MapPublications_Version] CHECK ([Version] > 0),
    CONSTRAINT [FK_MapPublications_MapProjects_MapId] FOREIGN KEY ([MapId]) REFERENCES [MapProjects] ([Id]) ON DELETE NO ACTION
);

CREATE TABLE [MapNodeQrs] (
    [Id] uniqueidentifier NOT NULL,
    [MapId] uniqueidentifier NOT NULL,
    [FloorKey] uniqueidentifier NOT NULL,
    [NodeId] uniqueidentifier NOT NULL,
    [DraftVersion] bigint NOT NULL,
    [PublishedVersion] bigint NULL,
    [Token] nvarchar(64) NOT NULL,
    [IsActive] bit NOT NULL,
    [CreatedBy] nvarchar(450) NOT NULL,
    [CreatedAt] datetimeoffset NOT NULL,
    [RevokedAt] datetimeoffset NULL,
    CONSTRAINT [PK_MapNodeQrs] PRIMARY KEY ([Id]),
    CONSTRAINT [CK_MapNodeQrs_Version] CHECK ([DraftVersion] > 0 AND ([PublishedVersion] IS NULL OR [PublishedVersion] = [DraftVersion])),
    CONSTRAINT [FK_MapNodeQrs_MapProjects_MapId] FOREIGN KEY ([MapId]) REFERENCES [MapProjects] ([Id]) ON DELETE NO ACTION,
    CONSTRAINT [FK_MapNodeQrs_MapPublications_MapId_PublishedVersion] FOREIGN KEY ([MapId], [PublishedVersion]) REFERENCES [MapPublications] ([MapId], [Version]) ON DELETE NO ACTION
);

CREATE TABLE [MapPublicationImages] (
    [MapId] uniqueidentifier NOT NULL,
    [Version] bigint NOT NULL,
    [AssetId] uniqueidentifier NOT NULL,
    CONSTRAINT [PK_MapPublicationImages] PRIMARY KEY ([MapId], [Version], [AssetId]),
    CONSTRAINT [FK_MapPublicationImages_FloorMapImageAssets_AssetId] FOREIGN KEY ([AssetId]) REFERENCES [FloorMapImageAssets] ([Id]) ON DELETE NO ACTION,
    CONSTRAINT [FK_MapPublicationImages_MapPublications_MapId_Version] FOREIGN KEY ([MapId], [Version]) REFERENCES [MapPublications] ([MapId], [Version]) ON DELETE NO ACTION
);

CREATE UNIQUE INDEX [IX_MapNodeQrs_MapId_DraftVersion_FloorKey_NodeId] ON [MapNodeQrs] ([MapId], [DraftVersion], [FloorKey], [NodeId]) WHERE [IsActive] = 1;

CREATE INDEX [IX_MapNodeQrs_MapId_PublishedVersion] ON [MapNodeQrs] ([MapId], [PublishedVersion]);

CREATE UNIQUE INDEX [IX_MapNodeQrs_Token] ON [MapNodeQrs] ([Token]);

CREATE INDEX [IX_MapProjects_BuildingId] ON [MapProjects] ([BuildingId]);

CREATE UNIQUE INDEX [IX_MapProjects_OwnerId_LocalProjectId] ON [MapProjects] ([OwnerId], [LocalProjectId]);

CREATE INDEX [IX_MapProjects_SiteId] ON [MapProjects] ([SiteId]);

CREATE INDEX [IX_MapPublicationImages_AssetId] ON [MapPublicationImages] ([AssetId]);

INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
VALUES (N'20261023063955_AddPublishedMapProjects', N'10.0.12');

COMMIT;
GO
