-- EF Core SQL Server 10.0.12; 0 -> 20261010032404_CreateAuthSchema; AuthDbContext.
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
IF OBJECT_ID(N'[__AuthMigrationsHistory]') IS NULL
BEGIN
    CREATE TABLE [__AuthMigrationsHistory] (
        [MigrationId] nvarchar(150) NOT NULL,
        [ProductVersion] nvarchar(32) NOT NULL,
        CONSTRAINT [PK___AuthMigrationsHistory] PRIMARY KEY ([MigrationId])
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
    SELECT * FROM [__AuthMigrationsHistory]
    WHERE [MigrationId] = N'20261010032404_CreateAuthSchema'
)
BEGIN
    CREATE TABLE [AspNetRoles] (
        [Id] nvarchar(450) NOT NULL,
        [Name] nvarchar(256) NULL,
        [NormalizedName] nvarchar(256) NULL,
        [ConcurrencyStamp] nvarchar(max) NULL,
        CONSTRAINT [PK_AspNetRoles] PRIMARY KEY ([Id])
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__AuthMigrationsHistory]
    WHERE [MigrationId] = N'20261010032404_CreateAuthSchema'
)
BEGIN
    CREATE TABLE [AspNetUsers] (
        [Id] nvarchar(450) NOT NULL,
        [UserName] nvarchar(256) NULL,
        [NormalizedUserName] nvarchar(256) NULL,
        [Email] nvarchar(256) NULL,
        [NormalizedEmail] nvarchar(256) NULL,
        [EmailConfirmed] bit NOT NULL,
        [PasswordHash] nvarchar(max) NULL,
        [SecurityStamp] nvarchar(max) NULL,
        [ConcurrencyStamp] nvarchar(max) NULL,
        [PhoneNumber] nvarchar(max) NULL,
        [PhoneNumberConfirmed] bit NOT NULL,
        [TwoFactorEnabled] bit NOT NULL,
        [LockoutEnd] datetimeoffset NULL,
        [LockoutEnabled] bit NOT NULL,
        [AccessFailedCount] int NOT NULL,
        CONSTRAINT [PK_AspNetUsers] PRIMARY KEY ([Id])
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__AuthMigrationsHistory]
    WHERE [MigrationId] = N'20261010032404_CreateAuthSchema'
)
BEGIN
    CREATE TABLE [AspNetRoleClaims] (
        [Id] int NOT NULL IDENTITY,
        [RoleId] nvarchar(450) NOT NULL,
        [ClaimType] nvarchar(max) NULL,
        [ClaimValue] nvarchar(max) NULL,
        CONSTRAINT [PK_AspNetRoleClaims] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_AspNetRoleClaims_AspNetRoles_RoleId] FOREIGN KEY ([RoleId]) REFERENCES [AspNetRoles] ([Id]) ON DELETE CASCADE
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__AuthMigrationsHistory]
    WHERE [MigrationId] = N'20261010032404_CreateAuthSchema'
)
BEGIN
    CREATE TABLE [AspNetUserClaims] (
        [Id] int NOT NULL IDENTITY,
        [UserId] nvarchar(450) NOT NULL,
        [ClaimType] nvarchar(max) NULL,
        [ClaimValue] nvarchar(max) NULL,
        CONSTRAINT [PK_AspNetUserClaims] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_AspNetUserClaims_AspNetUsers_UserId] FOREIGN KEY ([UserId]) REFERENCES [AspNetUsers] ([Id]) ON DELETE CASCADE
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__AuthMigrationsHistory]
    WHERE [MigrationId] = N'20261010032404_CreateAuthSchema'
)
BEGIN
    CREATE TABLE [AspNetUserLogins] (
        [LoginProvider] nvarchar(450) NOT NULL,
        [ProviderKey] nvarchar(450) NOT NULL,
        [ProviderDisplayName] nvarchar(max) NULL,
        [UserId] nvarchar(450) NOT NULL,
        CONSTRAINT [PK_AspNetUserLogins] PRIMARY KEY ([LoginProvider], [ProviderKey]),
        CONSTRAINT [FK_AspNetUserLogins_AspNetUsers_UserId] FOREIGN KEY ([UserId]) REFERENCES [AspNetUsers] ([Id]) ON DELETE CASCADE
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__AuthMigrationsHistory]
    WHERE [MigrationId] = N'20261010032404_CreateAuthSchema'
)
BEGIN
    CREATE TABLE [AspNetUserRoles] (
        [UserId] nvarchar(450) NOT NULL,
        [RoleId] nvarchar(450) NOT NULL,
        CONSTRAINT [PK_AspNetUserRoles] PRIMARY KEY ([UserId], [RoleId]),
        CONSTRAINT [FK_AspNetUserRoles_AspNetRoles_RoleId] FOREIGN KEY ([RoleId]) REFERENCES [AspNetRoles] ([Id]) ON DELETE CASCADE,
        CONSTRAINT [FK_AspNetUserRoles_AspNetUsers_UserId] FOREIGN KEY ([UserId]) REFERENCES [AspNetUsers] ([Id]) ON DELETE CASCADE
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__AuthMigrationsHistory]
    WHERE [MigrationId] = N'20261010032404_CreateAuthSchema'
)
BEGIN
    CREATE TABLE [AspNetUserTokens] (
        [UserId] nvarchar(450) NOT NULL,
        [LoginProvider] nvarchar(450) NOT NULL,
        [Name] nvarchar(450) NOT NULL,
        [Value] nvarchar(max) NULL,
        CONSTRAINT [PK_AspNetUserTokens] PRIMARY KEY ([UserId], [LoginProvider], [Name]),
        CONSTRAINT [FK_AspNetUserTokens_AspNetUsers_UserId] FOREIGN KEY ([UserId]) REFERENCES [AspNetUsers] ([Id]) ON DELETE CASCADE
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__AuthMigrationsHistory]
    WHERE [MigrationId] = N'20261010032404_CreateAuthSchema'
)
BEGIN
    CREATE INDEX [IX_AspNetRoleClaims_RoleId] ON [AspNetRoleClaims] ([RoleId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__AuthMigrationsHistory]
    WHERE [MigrationId] = N'20261010032404_CreateAuthSchema'
)
BEGIN
    EXEC(N'CREATE UNIQUE INDEX [RoleNameIndex] ON [AspNetRoles] ([NormalizedName]) WHERE [NormalizedName] IS NOT NULL');
END;

IF NOT EXISTS (
    SELECT * FROM [__AuthMigrationsHistory]
    WHERE [MigrationId] = N'20261010032404_CreateAuthSchema'
)
BEGIN
    CREATE INDEX [IX_AspNetUserClaims_UserId] ON [AspNetUserClaims] ([UserId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__AuthMigrationsHistory]
    WHERE [MigrationId] = N'20261010032404_CreateAuthSchema'
)
BEGIN
    CREATE INDEX [IX_AspNetUserLogins_UserId] ON [AspNetUserLogins] ([UserId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__AuthMigrationsHistory]
    WHERE [MigrationId] = N'20261010032404_CreateAuthSchema'
)
BEGIN
    CREATE INDEX [IX_AspNetUserRoles_RoleId] ON [AspNetUserRoles] ([RoleId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__AuthMigrationsHistory]
    WHERE [MigrationId] = N'20261010032404_CreateAuthSchema'
)
BEGIN
    CREATE INDEX [EmailIndex] ON [AspNetUsers] ([NormalizedEmail]);
END;

IF NOT EXISTS (
    SELECT * FROM [__AuthMigrationsHistory]
    WHERE [MigrationId] = N'20261010032404_CreateAuthSchema'
)
BEGIN
    EXEC(N'CREATE UNIQUE INDEX [UserNameIndex] ON [AspNetUsers] ([NormalizedUserName]) WHERE [NormalizedUserName] IS NOT NULL');
END;

IF NOT EXISTS (
    SELECT * FROM [__AuthMigrationsHistory]
    WHERE [MigrationId] = N'20261010032404_CreateAuthSchema'
)
BEGIN
    INSERT INTO [__AuthMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20261010032404_CreateAuthSchema', N'10.0.12');
END;

COMMIT;
GO
