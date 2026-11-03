using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using WayMark.Api.Data;

namespace WayMark.CoreSqlReadiness;

public static class MigrationPreview
{
    public const string From = "20261018053754_AddNavigationSchema";
    public const string To = "20261023063955_AddPublishedMapProjects";
    public static string Generate(bool idempotent)
    {
        using var db = new WayMarkDbContext(new DbContextOptionsBuilder<WayMarkDbContext>().UseSqlServer().Options);
        if (db.Database.HasPendingModelChanges()) throw new InvalidOperationException("Model differs from reviewed snapshot");
        var sql = db.GetService<IMigrator>().GenerateScript(From, To,
            idempotent ? MigrationsSqlGenerationOptions.Idempotent : MigrationsSqlGenerationOptions.Default);
        // Every batch independently refuses a wrong DB/server. The future executor
        // must set this nonsecret SESSION_CONTEXT via a parameter on its fresh connection.
        // No secret or machine-specific server name is embedded in the review artifact.
        const string guard = """
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
""";
        var batches = Regex.Split(sql, @"^GO\s*\r?$", RegexOptions.Multiline).Where(x => !string.IsNullOrWhiteSpace(x));
        return "-- REVIEW ONLY. Not executed by this generator. Requires separately approved, fail-on-error executor.\n"
            + "-- Fresh dedicated session: no ambient/implicit transaction. SESSION_CONTEXT is not authorization.\n"
            + "IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2\nBEGIN\n    RAISERROR(N'Fresh session with IMPLICIT_TRANSACTIONS OFF required.',16,1);\n    RETURN;\nEND;\nSET XACT_ABORT ON;\n"
            + string.Join("\nGO\n", batches.Select(x => guard + "\n" + x.Trim())) + "\nGO\n";
    }
}
