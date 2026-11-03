using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace WayMark.Api.Data.WayMarkMigrations
{
    /// <inheritdoc />
    public partial class BindMapImagesToDrafts : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddUniqueConstraint(
                name: "AK_FloorMapDrafts_FloorId",
                table: "FloorMapDrafts",
                column: "FloorId");

            migrationBuilder.AddForeignKey(
                name: "FK_FloorMapImageAssets_FloorMapDrafts_FloorId",
                table: "FloorMapImageAssets",
                column: "FloorId",
                principalTable: "FloorMapDrafts",
                principalColumn: "FloorId",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_FloorMapImageAssets_FloorMapDrafts_FloorId",
                table: "FloorMapImageAssets");

            migrationBuilder.DropUniqueConstraint(
                name: "AK_FloorMapDrafts_FloorId",
                table: "FloorMapDrafts");
        }
    }
}
