-- Password hashes are produced in memory by the installed ASP.NET Identity PasswordHasher.
-- This step refuses ALL existing accounts; it never upgrades or resets an account.
IF @@TRANCOUNT<>0 OR (2 & @@OPTIONS)=2 THROW 51000, 'Fresh session required.', 1;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'WayMark_MapDraft_E2E_Test'
 OR NULLIF(@ExpectedServerName,N'') IS NULL OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))<>@ExpectedServerName
 OR NULLIF(@ExpectedProvisioningLogin,N'') IS NULL OR ORIGINAL_LOGIN()<>@ExpectedProvisioningLogin OR ISNULL(HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','CONTROL'),0)<>1
    THROW 51000, 'Identity bootstrap target/permission refused.', 1;
IF EXISTS(SELECT 1 FROM dbo.AspNetUsers) OR EXISTS(SELECT 1 FROM dbo.AspNetRoles)
 OR EXISTS(SELECT 1 FROM dbo.AspNetUserRoles)
    THROW 51000, 'Expected empty test Identity; no adoption, overwrite or elevation allowed.', 1;
IF NULLIF(@AdminAHash,N'') IS NULL OR NULLIF(@AdminBHash,N'') IS NULL
 OR NULLIF(@AdminNoneHash,N'') IS NULL OR NULLIF(@ReaderHash,N'') IS NULL
    THROW 51000, 'Four privately supplied Identity password hashes required.', 1;
SET XACT_ABORT ON;
BEGIN TRY
 BEGIN TRANSACTION;
 INSERT dbo.AspNetUsers (Id,UserName,NormalizedUserName,Email,NormalizedEmail,EmailConfirmed,
  PasswordHash,SecurityStamp,ConcurrencyStamp,PhoneNumberConfirmed,TwoFactorEnabled,LockoutEnabled,AccessFailedCount)
 SELECT CONVERT(nvarchar(450),NEWID()),v.UserName,UPPER(v.UserName),v.UserName+N'@example.invalid',
  UPPER(v.UserName+N'@example.invalid'),0,v.PasswordHash,CONVERT(nvarchar(36),NEWID()),CONVERT(nvarchar(36),NEWID()),0,0,1,0
 FROM (VALUES (N'wm-e2e-admin-a',@AdminAHash),(N'wm-e2e-admin-b',@AdminBHash),
  (N'wm-e2e-admin-none',@AdminNoneHash),(N'wm-e2e-reader',@ReaderHash)) v(UserName,PasswordHash);
 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW 51000, 'Identity bootstrap failed; private parameters withheld.', 1;
END CATCH;
SELECT UserName,Id FROM dbo.AspNetUsers ORDER BY UserName;
