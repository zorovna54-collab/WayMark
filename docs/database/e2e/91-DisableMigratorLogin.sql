IF @@TRANCOUNT<>0 OR (2 & @@OPTIONS)=2 THROW 51000, 'Fresh session required.', 1;
IF DB_NAME()<>N'master' OR NULLIF(@ExpectedServerName,N'') IS NULL
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))<>@ExpectedServerName
 OR NULLIF(@ExpectedProvisioningLogin,N'') IS NULL OR ORIGINAL_LOGIN()<>@ExpectedProvisioningLogin OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY LOGIN'),0)<>1
 OR SUSER_ID(N'WayMark_E2E_Migrator') IS NULL
    THROW 51000, 'Migrator disabling target/permission refused.', 1;
ALTER LOGIN [WayMark_E2E_Migrator] DISABLE;
