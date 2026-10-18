using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using WayMark.Api.Data;
using WayMarkEntity = global::WayMark.Api.Models.WayMark;
using Microsoft.AspNetCore.Authorization;
using WayMark.Api.Contracts;

namespace WayMark.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class WayMarksController(WayMarkDbContext dbContext) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<IEnumerable<WayMarkEntity>>> GetAll()
    {
        var wayMarks = await dbContext.WayMarks.ToListAsync();
        return Ok(wayMarks);
    }

    [HttpGet("code/{code}")]
    public async Task<ActionResult<WayMarkEntity>> GetByCode(string code)
    {
        var wayMark = await dbContext.WayMarks
            .FirstOrDefaultAsync(item => item.WayMarkCode == code);

        if (wayMark is null)
        {
            return NotFound(new ProblemDetails
            {
                Status = StatusCodes.Status404NotFound,
                Title = "WayMark not found",
                Detail = $"No WayMark with code '{code}' exists."
            });
        }

        return Ok(wayMark);
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<WayMarkEntity>> GetById(int id)
    {
        var wayMark = await dbContext.WayMarks
            .FirstOrDefaultAsync(item => item.Id == id);

        if (wayMark is null)
        {
            return NotFound();
        }

        return wayMark;
    }

    [HttpGet("code/{code}/map-location")]
    public async Task<ActionResult<WayMarkMapDto>> GetMapLocation(
        string code, CancellationToken cancellationToken)
    {
        var wayMark = await dbContext.WayMarks.AsNoTracking()
            .SingleOrDefaultAsync(item => item.WayMarkCode == code, cancellationToken);
        if (wayMark is null)
        {
            return NotFound(new ProblemDetails { Status = 404, Title = "WayMark not found" });
        }

        var node = wayMark.NavigationNodeId is int nodeId
            ? await dbContext.NavigationNodes.AsNoTracking()
                .Where(item => item.Id == nodeId)
                .Select(item => new NavigationNodeDto(item.Id, item.FloorId,
                    item.NodeCode, item.Name, item.X, item.Y, item.NodeType.ToString()))
                .SingleOrDefaultAsync(cancellationToken)
            : null;

        return Ok(new WayMarkMapDto(wayMark.Id, wayMark.Name, wayMark.Location,
            wayMark.WayMarkCode, node));
    }

    [HttpPost]
    public async Task<ActionResult<WayMarkEntity>> Create(WayMarkEntity input)
    {
        Normalize(input);
        if (await dbContext.WayMarks.AnyAsync(item => item.WayMarkCode == input.WayMarkCode))
        {
            return DuplicateCode(input.WayMarkCode);
        }

        input.Id = 0;
        dbContext.WayMarks.Add(input);
        try
        {
            await dbContext.SaveChangesAsync();
        }
        catch (DbUpdateException exception) when (IsUniqueConstraintViolation(exception))
        {
            return DuplicateCode(input.WayMarkCode);
        }

        return CreatedAtAction(nameof(GetById), new { id = input.Id }, input);
    }

    [HttpPut("{id:int}")]
    public async Task<IActionResult> Update(int id, WayMarkEntity input)
    {
        var wayMark = await dbContext.WayMarks.FirstOrDefaultAsync(item => item.Id == id);
        if (wayMark is null)
        {
            return NotFound();
        }

        Normalize(input);
        if (await dbContext.WayMarks.AnyAsync(item =>
                item.Id != id && item.WayMarkCode == input.WayMarkCode))
        {
            return DuplicateCode(input.WayMarkCode);
        }

        wayMark.Name = input.Name;
        wayMark.Location = input.Location;
        wayMark.WayMarkCode = input.WayMarkCode;
        try
        {
            await dbContext.SaveChangesAsync();
        }
        catch (DbUpdateException exception) when (IsUniqueConstraintViolation(exception))
        {
            return DuplicateCode(input.WayMarkCode);
        }

        return Ok(wayMark);
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        var wayMark = await dbContext.WayMarks.FirstOrDefaultAsync(item => item.Id == id);
        if (wayMark is null)
        {
            return NotFound();
        }

        dbContext.WayMarks.Remove(wayMark);
        await dbContext.SaveChangesAsync();
        return NoContent();
    }

    private static void Normalize(WayMarkEntity wayMark)
    {
        wayMark.Name = wayMark.Name.Trim();
        wayMark.Location = wayMark.Location.Trim();
        wayMark.WayMarkCode = wayMark.WayMarkCode.Trim();
    }

    private ConflictObjectResult DuplicateCode(string code) => Conflict(new ProblemDetails
    {
        Status = StatusCodes.Status409Conflict,
        Title = "WayMark code already exists",
        Detail = $"A WayMark with code '{code}' already exists."
    });

    private static bool IsUniqueConstraintViolation(DbUpdateException exception) =>
        exception.InnerException is SqlException { Number: 2601 or 2627 };
}
