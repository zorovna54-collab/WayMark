using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable
namespace WayMark.Api.Data.WayMarkMigrations;

// Prepared source only. Applying this migration requires separate SQL approval.
public partial class AddNavigationHistory : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(name: "NavigationHistory", columns: table => new {
            Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
            UserId = table.Column<string>(type: "nvarchar(450)", maxLength: 450, nullable: false),
            MapId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
            PublishedVersion = table.Column<long>(type: "bigint", nullable: false),
            StartQrId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
            StartNodeId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
            DestinationNodeId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
            DestinationFloorKey = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
            MapName = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
            StartName = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
            DestinationName = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
            StartedAtUtc = table.Column<DateTime>(type: "datetime2", nullable: false),
            EndedAtUtc = table.Column<DateTime>(type: "datetime2", nullable: true),
            Status = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false)
        }, constraints: table => {
            table.PrimaryKey("PK_NavigationHistory", x => x.Id);
            table.CheckConstraint("CK_NavigationHistory_Status", "[Status] IN ('InProgress', 'Completed', 'Cancelled')");
        });
        migrationBuilder.CreateIndex(name: "IX_NavigationHistory_UserId_StartedAtUtc", table: "NavigationHistory", columns: new[] { "UserId", "StartedAtUtc" });
    }
    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.DropTable(name: "NavigationHistory");
}
