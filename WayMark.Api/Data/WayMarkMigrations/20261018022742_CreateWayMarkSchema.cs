using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace WayMark.Api.Data.WayMarkMigrations
{
    /// <inheritdoc />
    public partial class CreateWayMarkSchema : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "WayMarks",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    Name = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    Location = table.Column<string>(type: "nvarchar(300)", maxLength: 300, nullable: false),
                    WayMarkCode = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_WayMarks", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_WayMarks_WayMarkCode",
                table: "WayMarks",
                column: "WayMarkCode",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "WayMarks");
        }
    }
}
