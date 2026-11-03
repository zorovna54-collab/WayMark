using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace WayMark.Api.Data.WayMarkMigrations
{
    /// <inheritdoc />
    public partial class AddPublishedMapProjects : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "MapProjects",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    LocalProjectId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    SiteId = table.Column<int>(type: "int", nullable: false),
                    BuildingId = table.Column<int>(type: "int", nullable: false),
                    OwnerId = table.Column<string>(type: "nvarchar(450)", maxLength: 450, nullable: false),
                    Name = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    Version = table.Column<long>(type: "bigint", nullable: false),
                    ContentJson = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_MapProjects", x => x.Id);
                    table.CheckConstraint("CK_MapProjects_Version", "[Version] > 0");
                    table.ForeignKey(
                        name: "FK_MapProjects_Buildings_BuildingId",
                        column: x => x.BuildingId,
                        principalTable: "Buildings",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_MapProjects_Sites_SiteId",
                        column: x => x.SiteId,
                        principalTable: "Sites",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "MapPublications",
                columns: table => new
                {
                    MapId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    Version = table.Column<long>(type: "bigint", nullable: false),
                    Name = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    ContentJson = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    PublishedBy = table.Column<string>(type: "nvarchar(450)", maxLength: 450, nullable: false),
                    PublishedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_MapPublications", x => new { x.MapId, x.Version });
                    table.CheckConstraint("CK_MapPublications_Version", "[Version] > 0");
                    table.ForeignKey(
                        name: "FK_MapPublications_MapProjects_MapId",
                        column: x => x.MapId,
                        principalTable: "MapProjects",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "MapNodeQrs",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    MapId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    FloorKey = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    NodeId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    DraftVersion = table.Column<long>(type: "bigint", nullable: false),
                    PublishedVersion = table.Column<long>(type: "bigint", nullable: true),
                    Token = table.Column<string>(type: "nvarchar(64)", maxLength: 64, nullable: false),
                    IsActive = table.Column<bool>(type: "bit", nullable: false),
                    CreatedBy = table.Column<string>(type: "nvarchar(450)", maxLength: 450, nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                    RevokedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_MapNodeQrs", x => x.Id);
                    table.CheckConstraint("CK_MapNodeQrs_Version", "[DraftVersion] > 0 AND ([PublishedVersion] IS NULL OR [PublishedVersion] = [DraftVersion])");
                    table.ForeignKey(
                        name: "FK_MapNodeQrs_MapProjects_MapId",
                        column: x => x.MapId,
                        principalTable: "MapProjects",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_MapNodeQrs_MapPublications_MapId_PublishedVersion",
                        columns: x => new { x.MapId, x.PublishedVersion },
                        principalTable: "MapPublications",
                        principalColumns: new[] { "MapId", "Version" },
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "MapPublicationImages",
                columns: table => new
                {
                    MapId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    Version = table.Column<long>(type: "bigint", nullable: false),
                    AssetId = table.Column<Guid>(type: "uniqueidentifier", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_MapPublicationImages", x => new { x.MapId, x.Version, x.AssetId });
                    table.ForeignKey(
                        name: "FK_MapPublicationImages_FloorMapImageAssets_AssetId",
                        column: x => x.AssetId,
                        principalTable: "FloorMapImageAssets",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_MapPublicationImages_MapPublications_MapId_Version",
                        columns: x => new { x.MapId, x.Version },
                        principalTable: "MapPublications",
                        principalColumns: new[] { "MapId", "Version" },
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_MapNodeQrs_MapId_DraftVersion_FloorKey_NodeId",
                table: "MapNodeQrs",
                columns: new[] { "MapId", "DraftVersion", "FloorKey", "NodeId" },
                unique: true,
                filter: "[IsActive] = 1");

            migrationBuilder.CreateIndex(
                name: "IX_MapNodeQrs_MapId_PublishedVersion",
                table: "MapNodeQrs",
                columns: new[] { "MapId", "PublishedVersion" });

            migrationBuilder.CreateIndex(
                name: "IX_MapNodeQrs_Token",
                table: "MapNodeQrs",
                column: "Token",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_MapProjects_BuildingId",
                table: "MapProjects",
                column: "BuildingId");

            migrationBuilder.CreateIndex(
                name: "IX_MapProjects_OwnerId_LocalProjectId",
                table: "MapProjects",
                columns: new[] { "OwnerId", "LocalProjectId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_MapProjects_SiteId",
                table: "MapProjects",
                column: "SiteId");

            migrationBuilder.CreateIndex(
                name: "IX_MapPublicationImages_AssetId",
                table: "MapPublicationImages",
                column: "AssetId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "MapNodeQrs");

            migrationBuilder.DropTable(
                name: "MapPublicationImages");

            migrationBuilder.DropTable(
                name: "MapPublications");

            migrationBuilder.DropTable(
                name: "MapProjects");
        }
    }
}
