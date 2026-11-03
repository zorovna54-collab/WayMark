BEGIN TRANSACTION;
CREATE TABLE [NavigationHistory] (
    [Id] uniqueidentifier NOT NULL,
    [UserId] nvarchar(450) NOT NULL,
    [MapId] uniqueidentifier NOT NULL,
    [PublishedVersion] bigint NOT NULL,
    [StartQrId] uniqueidentifier NOT NULL,
    [StartNodeId] uniqueidentifier NOT NULL,
    [DestinationNodeId] uniqueidentifier NOT NULL,
    [DestinationFloorKey] uniqueidentifier NOT NULL,
    [MapName] nvarchar(200) NOT NULL,
    [StartName] nvarchar(200) NOT NULL,
    [DestinationName] nvarchar(200) NOT NULL,
    [StartedAtUtc] datetime2 NOT NULL,
    [EndedAtUtc] datetime2 NULL,
    [Status] nvarchar(20) NOT NULL,
    CONSTRAINT [PK_NavigationHistory] PRIMARY KEY ([Id]),
    CONSTRAINT [CK_NavigationHistory_Status] CHECK ([Status] IN ('InProgress', 'Completed', 'Cancelled'))
);

CREATE INDEX [IX_NavigationHistory_UserId_StartedAtUtc] ON [NavigationHistory] ([UserId], [StartedAtUtc]);

INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
VALUES (N'20261025010000_AddNavigationHistory', N'10.0.12');

COMMIT;
GO

BEGIN TRANSACTION;
ALTER TABLE [NavigationHistory] DROP CONSTRAINT [CK_NavigationHistory_Status];

DECLARE @var nvarchar(max);
SELECT @var = QUOTENAME([d].[name])
FROM [sys].[default_constraints] [d]
INNER JOIN [sys].[columns] [c] ON [d].[parent_column_id] = [c].[column_id] AND [d].[parent_object_id] = [c].[object_id]
WHERE ([d].[parent_object_id] = OBJECT_ID(N'[NavigationHistory]') AND [c].[name] = N'DestinationNodeId');
IF @var IS NOT NULL EXEC(N'ALTER TABLE [NavigationHistory] DROP CONSTRAINT ' + @var + ';');
ALTER TABLE [NavigationHistory] ALTER COLUMN [DestinationNodeId] uniqueidentifier NULL;

DECLARE @var1 nvarchar(max);
SELECT @var1 = QUOTENAME([d].[name])
FROM [sys].[default_constraints] [d]
INNER JOIN [sys].[columns] [c] ON [d].[parent_column_id] = [c].[column_id] AND [d].[parent_object_id] = [c].[object_id]
WHERE ([d].[parent_object_id] = OBJECT_ID(N'[NavigationHistory]') AND [c].[name] = N'DestinationFloorKey');
IF @var1 IS NOT NULL EXEC(N'ALTER TABLE [NavigationHistory] DROP CONSTRAINT ' + @var1 + ';');
ALTER TABLE [NavigationHistory] ALTER COLUMN [DestinationFloorKey] uniqueidentifier NULL;

ALTER TABLE [NavigationHistory] ADD [DistanceMeters] decimal(18,3) NULL;

ALTER TABLE [NavigationHistory] ADD [NavigationStartedAtUtc] datetime2 NULL;

ALTER TABLE [NavigationHistory] ADD [ScannedAtUtc] datetime2 NULL;

ALTER TABLE [NavigationHistory] ADD [StartFloorKey] uniqueidentifier NULL;

ALTER TABLE [NavigationHistory] ADD CONSTRAINT [CK_NavigationHistory_Status] CHECK ([Status] IN ('Scanned', 'InProgress', 'Completed', 'Cancelled'));

INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
VALUES (N'20261026001522_ExtendNavigationHistoryLifecycle', N'10.0.12');

COMMIT;
GO

