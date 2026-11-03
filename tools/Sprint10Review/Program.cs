using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.EntityFrameworkCore.Migrations.Design;
using Microsoft.EntityFrameworkCore.SqlServer.Design.Internal;
using Microsoft.Extensions.DependencyInjection;
using WayMark.Api.Data;

// Offline SQL Server provider only: deliberately no connection string, startup,
// Identity, seeder, migrate, EnsureCreated or SQL execution path.
if (args.Length != 1 || args[0] is not ("scaffold" or "script")) throw new Exception("Use scaffold or script (offline only)");
var root=Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,"../../../../../"));
using var db=new WayMarkDbContext(new DbContextOptionsBuilder<WayMarkDbContext>().UseSqlServer().Options);
if(args[0]=="scaffold") {
    if(db.GetService<IMigrationsAssembly>().Migrations.Keys.Any(x => x.EndsWith("_ExtendNavigationHistoryLifecycle")))
        throw new Exception("Lifecycle migration already exists; never scaffold a duplicate");
    var collection=new ServiceCollection().AddEntityFrameworkDesignTimeServices().AddDbContextDesignTimeServices(db);
#pragma warning disable EF1001
    new SqlServerDesignTimeServices().ConfigureDesignTimeServices(collection);
#pragma warning restore EF1001
    using var provider=collection.BuildServiceProvider();
    var scaffolder=provider.GetRequiredService<IMigrationsScaffolder>();
    var migration=scaffolder.ScaffoldMigration("ExtendNavigationHistoryLifecycle","WayMark.Api", "Data.WayMarkMigrations");
    scaffolder.Save(Path.Combine(root,"WayMark.Api"),migration,Path.Combine(root,"WayMark.Api","Data","WayMarkMigrations"));
    Console.WriteLine(migration.MigrationId);
} else {
    if(db.Database.HasPendingModelChanges())throw new Exception("Snapshot/model mismatch");
    var last=db.GetService<IMigrationsAssembly>().Migrations.Keys.Last();
    if(!last.EndsWith("_ExtendNavigationHistoryLifecycle"))throw new Exception("Unexpected latest migration");
    var script=db.GetService<IMigrator>().GenerateScript("20261023063955_AddPublishedMapProjects",last);
    var directory=Path.Combine(root,"docs/database/sprint10"); Directory.CreateDirectory(directory);
    File.WriteAllText(Path.Combine(directory,"NavigationHistory.review.sql"),script);
    Console.WriteLine($"Offline script through {last}; no database connection");
}
