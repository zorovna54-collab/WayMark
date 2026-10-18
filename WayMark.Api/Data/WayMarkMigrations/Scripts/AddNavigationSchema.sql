BEGIN TRANSACTION;
ALTER TABLE [WayMarks] ADD [NavigationNodeId] int NULL;
GO

CREATE TABLE [Sites] (
    [Id] int NOT NULL IDENTITY,
    [Name] nvarchar(200) NOT NULL,
    [Code] nvarchar(50) NOT NULL,
    [Address] nvarchar(500) NULL,
    CONSTRAINT [PK_Sites] PRIMARY KEY ([Id])
);
GO

CREATE TABLE [Buildings] (
    [Id] int NOT NULL IDENTITY,
    [SiteId] int NOT NULL,
    [Name] nvarchar(200) NOT NULL,
    [BuildingCode] nvarchar(50) NOT NULL,
    CONSTRAINT [PK_Buildings] PRIMARY KEY ([Id]),
    CONSTRAINT [FK_Buildings_Sites_SiteId] FOREIGN KEY ([SiteId]) REFERENCES [Sites] ([Id]) ON DELETE NO ACTION
);
GO

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
GO

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
GO

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
GO

CREATE UNIQUE INDEX [IX_WayMarks_NavigationNodeId] ON [WayMarks] ([NavigationNodeId]) WHERE [NavigationNodeId] IS NOT NULL;

CREATE UNIQUE INDEX [IX_Buildings_SiteId_BuildingCode] ON [Buildings] ([SiteId], [BuildingCode]);

CREATE UNIQUE INDEX [IX_Floors_BuildingId_FloorCode] ON [Floors] ([BuildingId], [FloorCode]);

CREATE INDEX [IX_NavigationEdges_FromNodeId] ON [NavigationEdges] ([FromNodeId]);

CREATE INDEX [IX_NavigationEdges_ToNodeId] ON [NavigationEdges] ([ToNodeId]);

CREATE INDEX [IX_NavigationNodes_FloorId] ON [NavigationNodes] ([FloorId]);

CREATE UNIQUE INDEX [IX_NavigationNodes_NodeCode] ON [NavigationNodes] ([NodeCode]);

CREATE UNIQUE INDEX [IX_Sites_Code] ON [Sites] ([Code]);

ALTER TABLE [WayMarks] ADD CONSTRAINT [FK_WayMarks_NavigationNodes_NavigationNodeId] FOREIGN KEY ([NavigationNodeId]) REFERENCES [NavigationNodes] ([Id]) ON DELETE NO ACTION;

INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
VALUES (N'20261018053754_AddNavigationSchema', N'10.0.12');

COMMIT;
GO

