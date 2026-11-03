using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace WayMark.Api.Data.WayMarkMigrations
{
    /// <inheritdoc />
    public partial class ExtendNavigationHistoryLifecycle : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "CK_NavigationHistory_Status",
                table: "NavigationHistory");

            migrationBuilder.AlterColumn<Guid>(
                name: "DestinationNodeId",
                table: "NavigationHistory",
                type: "uniqueidentifier",
                nullable: true,
                oldClrType: typeof(Guid),
                oldType: "uniqueidentifier");

            migrationBuilder.AlterColumn<Guid>(
                name: "DestinationFloorKey",
                table: "NavigationHistory",
                type: "uniqueidentifier",
                nullable: true,
                oldClrType: typeof(Guid),
                oldType: "uniqueidentifier");

            migrationBuilder.AddColumn<decimal>(
                name: "DistanceMeters",
                table: "NavigationHistory",
                type: "decimal(18,3)",
                precision: 18,
                scale: 3,
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "NavigationStartedAtUtc",
                table: "NavigationHistory",
                type: "datetime2",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "ScannedAtUtc",
                table: "NavigationHistory",
                type: "datetime2",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "StartFloorKey",
                table: "NavigationHistory",
                type: "uniqueidentifier",
                nullable: true);

            migrationBuilder.AddCheckConstraint(
                name: "CK_NavigationHistory_Status",
                table: "NavigationHistory",
                sql: "[Status] IN ('Scanned', 'InProgress', 'Completed', 'Cancelled')");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "CK_NavigationHistory_Status",
                table: "NavigationHistory");

            migrationBuilder.DropColumn(
                name: "DistanceMeters",
                table: "NavigationHistory");

            migrationBuilder.DropColumn(
                name: "NavigationStartedAtUtc",
                table: "NavigationHistory");

            migrationBuilder.DropColumn(
                name: "ScannedAtUtc",
                table: "NavigationHistory");

            migrationBuilder.DropColumn(
                name: "StartFloorKey",
                table: "NavigationHistory");

            migrationBuilder.AlterColumn<Guid>(
                name: "DestinationNodeId",
                table: "NavigationHistory",
                type: "uniqueidentifier",
                nullable: false,
                defaultValue: new Guid("00000000-0000-0000-0000-000000000000"),
                oldClrType: typeof(Guid),
                oldType: "uniqueidentifier",
                oldNullable: true);

            migrationBuilder.AlterColumn<Guid>(
                name: "DestinationFloorKey",
                table: "NavigationHistory",
                type: "uniqueidentifier",
                nullable: false,
                defaultValue: new Guid("00000000-0000-0000-0000-000000000000"),
                oldClrType: typeof(Guid),
                oldType: "uniqueidentifier",
                oldNullable: true);

            migrationBuilder.AddCheckConstraint(
                name: "CK_NavigationHistory_Status",
                table: "NavigationHistory",
                sql: "[Status] IN ('InProgress', 'Completed', 'Cancelled')");
        }
    }
}
