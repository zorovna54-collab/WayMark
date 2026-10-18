using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace WayMark.Api.Data.WayMarkMigrations
{
    /// <inheritdoc />
    public partial class AddNavigationSchema : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "NavigationNodeId",
                table: "WayMarks",
                type: "int",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "Sites",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    Name = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    Code = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false),
                    Address = table.Column<string>(type: "nvarchar(500)", maxLength: 500, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Sites", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Buildings",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    SiteId = table.Column<int>(type: "int", nullable: false),
                    Name = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    BuildingCode = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Buildings", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Buildings_Sites_SiteId",
                        column: x => x.SiteId,
                        principalTable: "Sites",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "Floors",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    BuildingId = table.Column<int>(type: "int", nullable: false),
                    Name = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    FloorCode = table.Column<string>(type: "nvarchar(30)", maxLength: 30, nullable: false),
                    SortOrder = table.Column<int>(type: "int", nullable: false),
                    FloorPlanImageUrl = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Floors", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Floors_Buildings_BuildingId",
                        column: x => x.BuildingId,
                        principalTable: "Buildings",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "NavigationNodes",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    FloorId = table.Column<int>(type: "int", nullable: false),
                    NodeCode = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    Name = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    X = table.Column<decimal>(type: "decimal(9,6)", nullable: false),
                    Y = table.Column<decimal>(type: "decimal(9,6)", nullable: false),
                    NodeType = table.Column<int>(type: "int", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_NavigationNodes", x => x.Id);
                    table.CheckConstraint("CK_NavigationNodes_X_Range", "[X] >= 0 AND [X] <= 1");
                    table.CheckConstraint("CK_NavigationNodes_Y_Range", "[Y] >= 0 AND [Y] <= 1");
                    table.ForeignKey(
                        name: "FK_NavigationNodes_Floors_FloorId",
                        column: x => x.FloorId,
                        principalTable: "Floors",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "NavigationEdges",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    FromNodeId = table.Column<int>(type: "int", nullable: false),
                    ToNodeId = table.Column<int>(type: "int", nullable: false),
                    EdgeType = table.Column<int>(type: "int", nullable: false),
                    DistanceMeters = table.Column<decimal>(type: "decimal(12,3)", precision: 12, scale: 3, nullable: false),
                    IsActive = table.Column<bool>(type: "bit", nullable: false, defaultValue: true),
                    IsAccessible = table.Column<bool>(type: "bit", nullable: false, defaultValue: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_NavigationEdges", x => x.Id);
                    table.CheckConstraint("CK_NavigationEdges_DifferentNodes", "[FromNodeId] <> [ToNodeId]");
                    table.CheckConstraint("CK_NavigationEdges_DistanceMeters_Positive", "[DistanceMeters] > 0");
                    table.ForeignKey(
                        name: "FK_NavigationEdges_NavigationNodes_FromNodeId",
                        column: x => x.FromNodeId,
                        principalTable: "NavigationNodes",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_NavigationEdges_NavigationNodes_ToNodeId",
                        column: x => x.ToNodeId,
                        principalTable: "NavigationNodes",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_WayMarks_NavigationNodeId",
                table: "WayMarks",
                column: "NavigationNodeId",
                unique: true,
                filter: "[NavigationNodeId] IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_Buildings_SiteId_BuildingCode",
                table: "Buildings",
                columns: new[] { "SiteId", "BuildingCode" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Floors_BuildingId_FloorCode",
                table: "Floors",
                columns: new[] { "BuildingId", "FloorCode" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_NavigationEdges_FromNodeId",
                table: "NavigationEdges",
                column: "FromNodeId");

            migrationBuilder.CreateIndex(
                name: "IX_NavigationEdges_ToNodeId",
                table: "NavigationEdges",
                column: "ToNodeId");

            migrationBuilder.CreateIndex(
                name: "IX_NavigationNodes_FloorId",
                table: "NavigationNodes",
                column: "FloorId");

            migrationBuilder.CreateIndex(
                name: "IX_NavigationNodes_NodeCode",
                table: "NavigationNodes",
                column: "NodeCode",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Sites_Code",
                table: "Sites",
                column: "Code",
                unique: true);

            migrationBuilder.AddForeignKey(
                name: "FK_WayMarks_NavigationNodes_NavigationNodeId",
                table: "WayMarks",
                column: "NavigationNodeId",
                principalTable: "NavigationNodes",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_WayMarks_NavigationNodes_NavigationNodeId",
                table: "WayMarks");

            migrationBuilder.DropTable(
                name: "NavigationEdges");

            migrationBuilder.DropTable(
                name: "NavigationNodes");

            migrationBuilder.DropTable(
                name: "Floors");

            migrationBuilder.DropTable(
                name: "Buildings");

            migrationBuilder.DropTable(
                name: "Sites");

            migrationBuilder.DropIndex(
                name: "IX_WayMarks_NavigationNodeId",
                table: "WayMarks");

            migrationBuilder.DropColumn(
                name: "NavigationNodeId",
                table: "WayMarks");
        }
    }
}
