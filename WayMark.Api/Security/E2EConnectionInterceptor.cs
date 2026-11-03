using System.Data.Common;
using System.Runtime.CompilerServices;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace WayMark.Api.Security;

/// <summary>EF queries, migrations and future EF seed tools share the same target check.</summary>
public sealed class E2EConnectionInterceptor(E2ESafetyProfile profile) : DbConnectionInterceptor
{
    private readonly ConditionalWeakTable<DbConnection, object> verified = new();
    // Only metadata reads. There is no DDL, migration, seed or privilege grant here.
    public const string IdentityQuery = """
        SELECT DB_NAME(), CONVERT(nvarchar(128), SERVERPROPERTY('ServerName')),
          SUSER_SNAME(), ORIGINAL_LOGIN(), IS_SRVROLEMEMBER('sysadmin'),
          HAS_PERMS_BY_NAME(NULL, 'SERVER', 'CONTROL SERVER'),
          HAS_PERMS_BY_NAME(NULL, 'SERVER', 'ALTER ANY LOGIN'),
          HAS_PERMS_BY_NAME(NULL, 'SERVER', 'ALTER ANY DATABASE'),
          HAS_DBACCESS(N'WayMarkDatabase'), HAS_DBACCESS(N'WayMarkAuthDatabase');
        """;

    public override InterceptionResult ConnectionOpening(DbConnection connection, ConnectionEventData eventData, InterceptionResult result)
    { ValidateOpening(connection); return result; }
    public override ValueTask<InterceptionResult> ConnectionOpeningAsync(DbConnection connection, ConnectionEventData eventData,
        InterceptionResult result, CancellationToken cancellationToken = default)
    { ValidateOpening(connection); return ValueTask.FromResult(result); }

    private void ValidateOpening(DbConnection connection) =>
        profile.ValidateConnection(connection.ConnectionString, beforeOpen: !verified.TryGetValue(connection, out _));

    public override void ConnectionOpened(DbConnection connection, ConnectionEndEventData eventData)
    {
        try
        {
            profile.ValidateConnection(connection.ConnectionString, beforeOpen: false);
            using var command = MetadataCommand(connection);
            using var reader = command.ExecuteReader();
            if (!reader.Read()) throw E2ESafetyProfile.Refused("SQL identity was unavailable");
            profile.ValidateIdentity(ReadIdentity(reader));
            verified.GetValue(connection, _ => new object());
        }
        catch { verified.Remove(connection); connection.Close(); throw E2ESafetyProfile.Refused("SQL target/identity verification failed"); }
    }
    public override async Task ConnectionOpenedAsync(DbConnection connection, ConnectionEndEventData eventData,
        CancellationToken cancellationToken = default) => await VerifyOpenAsync(connection, cancellationToken);

    public async Task VerifyOpenAsync(DbConnection connection, CancellationToken cancellationToken)
    {
        try
        {
            profile.ValidateConnection(connection.ConnectionString, beforeOpen: false);
            await using var command = MetadataCommand(connection);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken)) throw E2ESafetyProfile.Refused("SQL identity was unavailable");
            profile.ValidateIdentity(ReadIdentity(reader));
            verified.GetValue(connection, _ => new object());
        }
        catch
        {
            verified.Remove(connection);
            await connection.CloseAsync();
            throw E2ESafetyProfile.Refused("SQL target/identity verification failed");
        }
    }
    private static DbCommand MetadataCommand(DbConnection connection)
    { var command = connection.CreateCommand(); command.CommandText = IdentityQuery; command.CommandTimeout = 5; return command; }
    private static E2ESqlIdentity ReadIdentity(DbDataReader r)
    {
        bool? Flag(int n) => r.IsDBNull(n) ? null : Convert.ToInt32(r.GetValue(n)) == 1;
        return new(r.GetString(0), r.GetString(1), r.GetString(2), r.GetString(3),
            Flag(4), Flag(5), Flag(6), Flag(7), Flag(8), Flag(9));
    }
}
