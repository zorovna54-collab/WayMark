using System.Data.Common;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace WayMark.Api.Services.MapDrafts;

public sealed class MapDraftExceptionFilter(ILogger<MapDraftExceptionFilter> logger) : IExceptionFilter
{
    public void OnException(ExceptionContext context)
    {
        if (context.Exception is OperationCanceledException && context.HttpContext.RequestAborted.IsCancellationRequested) return;
        var (status, code, title) = context.Exception switch
        {
            DraftOperationException error => (error.Status, error.Code, error.Message),
            DbUpdateConcurrencyException => (409, "draft_version_conflict", "Draft version changed; reload before saving"),
            DbUpdateException { InnerException: SqlException { Number: 2601 or 2627 } } => (409, "draft_version_conflict", "Draft was changed concurrently"),
            DbUpdateException => (503, "draft_storage_unavailable", "Draft storage operation failed; no successful save is confirmed"),
            DbException => (503, "draft_storage_unavailable", "Draft storage is unavailable"),
            _ => (503, "draft_unavailable", "Draft operation is unavailable")
        };
        if (status >= 500) logger.LogError("Draft operation failed ({ExceptionType}); no internal details returned to caller", context.Exception.GetType().Name);
        var problem = new ProblemDetails { Status = status, Title = title };
        problem.Extensions["code"] = code;
        context.Result = new ObjectResult(problem) { StatusCode = status };
        context.ExceptionHandled = true;
    }
}
