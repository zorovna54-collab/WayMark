using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace WayMark.Api.Data.WayMarkMigrations
{
    /// <inheritdoc />
    public partial class AddMapDraftFoundation : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "FloorMapDrafts",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    FloorId = table.Column<int>(type: "int", nullable: false),
                    Version = table.Column<long>(type: "bigint", nullable: false),
                    Status = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                    CreatedBy = table.Column<string>(type: "nvarchar(450)", maxLength: 450, nullable: false),
                    UpdatedBy = table.Column<string>(type: "nvarchar(450)", maxLength: 450, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_FloorMapDrafts", x => x.Id);
                    table.CheckConstraint("CK_FloorMapDrafts_Status", "[Status] = 'Draft'");
                    table.CheckConstraint("CK_FloorMapDrafts_Version", "[Version] > 0");
                    table.ForeignKey(
                        name: "FK_FloorMapDrafts_Floors_FloorId",
                        column: x => x.FloorId,
                        principalTable: "Floors",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "FloorMapImageAssets",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    FloorId = table.Column<int>(type: "int", nullable: false),
                    StorageKey = table.Column<string>(type: "nvarchar(64)", maxLength: 64, nullable: false),
                    MimeType = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false),
                    Width = table.Column<int>(type: "int", nullable: false),
                    Height = table.Column<int>(type: "int", nullable: false),
                    ByteLength = table.Column<long>(type: "bigint", nullable: false),
                    Sha256 = table.Column<string>(type: "nvarchar(64)", maxLength: 64, nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                    CreatedBy = table.Column<string>(type: "nvarchar(450)", maxLength: 450, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_FloorMapImageAssets", x => x.Id);
                    table.CheckConstraint("CK_FloorMapImageAssets_Bytes", "[ByteLength] > 0 AND [ByteLength] <= 10485760");
                    table.CheckConstraint("CK_FloorMapImageAssets_Height", "[Height] > 0 AND [Height] <= 8192");
                    table.CheckConstraint("CK_FloorMapImageAssets_Mime", "[MimeType] IN ('image/png', 'image/jpeg')");
                    table.CheckConstraint("CK_FloorMapImageAssets_Pixels", "CAST([Width] AS bigint) * [Height] <= 32000000");
                    table.CheckConstraint("CK_FloorMapImageAssets_Width", "[Width] > 0 AND [Width] <= 8192");
                    table.ForeignKey(
                        name: "FK_FloorMapImageAssets_Floors_FloorId",
                        column: x => x.FloorId,
                        principalTable: "Floors",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "SiteMapMemberships",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    SiteId = table.Column<int>(type: "int", nullable: false),
                    UserId = table.Column<string>(type: "nvarchar(450)", maxLength: 450, nullable: false),
                    IsActive = table.Column<bool>(type: "bit", nullable: false),
                    CanEditDrafts = table.Column<bool>(type: "bit", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SiteMapMemberships", x => x.Id);
                    table.ForeignKey(
                        name: "FK_SiteMapMemberships_Sites_SiteId",
                        column: x => x.SiteId,
                        principalTable: "Sites",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "FloorMapDraftRevisions",
                columns: table => new
                {
                    DraftId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    Version = table.Column<long>(type: "bigint", nullable: false),
                    ContentJson = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    ImageAssetId = table.Column<Guid>(type: "uniqueidentifier", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                    CreatedBy = table.Column<string>(type: "nvarchar(450)", maxLength: 450, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_FloorMapDraftRevisions", x => new { x.DraftId, x.Version });
                    table.CheckConstraint("CK_FloorMapDraftRevisions_Version", "[Version] > 0");
                    table.ForeignKey(
                        name: "FK_FloorMapDraftRevisions_FloorMapDrafts_DraftId",
                        column: x => x.DraftId,
                        principalTable: "FloorMapDrafts",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_FloorMapDraftRevisions_FloorMapImageAssets_ImageAssetId",
                        column: x => x.ImageAssetId,
                        principalTable: "FloorMapImageAssets",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_FloorMapDraftRevisions_ImageAssetId",
                table: "FloorMapDraftRevisions",
                column: "ImageAssetId");

            migrationBuilder.CreateIndex(
                name: "IX_FloorMapDrafts_FloorId",
                table: "FloorMapDrafts",
                column: "FloorId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_FloorMapImageAssets_FloorId",
                table: "FloorMapImageAssets",
                column: "FloorId");

            migrationBuilder.CreateIndex(
                name: "IX_FloorMapImageAssets_StorageKey",
                table: "FloorMapImageAssets",
                column: "StorageKey",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_SiteMapMemberships_SiteId_UserId",
                table: "SiteMapMemberships",
                columns: new[] { "SiteId", "UserId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_SiteMapMemberships_UserId",
                table: "SiteMapMemberships",
                column: "UserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "FloorMapDraftRevisions");

            migrationBuilder.DropTable(
                name: "SiteMapMemberships");

            migrationBuilder.DropTable(
                name: "FloorMapDrafts");

            migrationBuilder.DropTable(
                name: "FloorMapImageAssets");
        }
    }
}
