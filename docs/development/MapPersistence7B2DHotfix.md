# Map Draft E2E hotfix — 2026-10-21

Branch: `auth-jwt-assignment`; baseline HEAD: `631a76cd196460318429ebff8da394818ccbdd2d`.
Follow-up to `MapPersistence7B2DPreflight.md`. Its old launch instructions are
superseded by this profile/launcher. No SQL Server connection, DDL, DML, account
grant, migration application, API startup, commit or push was performed here.

## Blockers and changes

| Finding | Resolution |
| --- | --- |
| CS0535 after the email interface changed | CountingEmail implements reset delivery, tracks reset and test mail separately. Tests exercise known/unknown accounts without SMTP; token protection is ephemeral in the test host. |
| Old authorization reflection test classified new anonymous password endpoints as Admin actions | Explicitly allow the four known Auth actions and assert their anonymous attributes; all other write actions retain the Admin policy assertion. Kilo AuthController/interface/SMTP/UI work is preserved. |
| Shared database configuration could leak into E2E | Dedicated `MapDraftE2E` profile, mandatory private settings, blank legacy template connections, fixed catalog allowlist and guarded registration of both contexts. |
| Current Windows SQL login had sysadmin in the prior preflight | E2E requires a separate SQL principal; checks actual server/catalog/login/privileges before EF business commands. Windows integrated auth and elevated principals are refused. No login was created. |
| No enabled isolated image provider | Storage is enabled only by the E2E template, with an explicit external root, protected-root exclusions and bounded quotas. Startup verifies an already provisioned directory without creating probe files. |
| Flutter has no Room creation UI | Confirmed; intentionally unchanged. Room/Place data and entrance GUID references are supported by the existing API and preserved by the Flutter adapter. |

EF supplies an Application Name when none is configured. The E2E profile now pins
it before registering contexts, retaining strict full connection comparisons.

### JWT review

- Removed only the nonempty `Jwt:SecretKey` value from tracked `appsettings.json`.
  Issuer, audience, SMTP and Kilo frontend configuration are preserved.
- Existing Development User Secrets contain a Base64 key of at least 32 bytes,
  issuer and audience; no process-level JWT key override was present during review.
  The removed working-tree literal differs from this active private key.
- Checked 12 reachable commits, known-key matches and common credential patterns;
  no match for the active key or removed literal was found. This is not proof
  about unreachable history, other repositories or previously shared files.
- There is no evidence here of public exposure of these keys. If the removed
  literal was used or shared elsewhere, the owner must rotate it separately.
  No private configuration or active key was changed or printed.
- JWT registration now rejects missing/short/malformed keys and blank issuer or
  audience with messages that do not contain the key.

## E2E configuration and guards

Use a fresh terminal with credentials supplied privately in process environment;
do not put actual keys/passwords in tracked JSON, command history or reports.
`appsettings.MapDraftE2E.json` alone intentionally cannot start the application.

| Setting | Required value/meaning |
| --- | --- |
| `E2E__SqlConnectionString` | SQL-auth connection to exactly `WayMark_MapDraft_E2E_Test`; encrypted, short timeout (1–10 s), no attach/failover, no persisted credentials. Never either protected database. |
| `E2E__SqlDataSource` | Explicit approved connection data source. |
| `E2E__ExpectedServerName` | Approved value to compare to actual SQL SERVERPROPERTY(ServerName). |
| `E2E__JwtSecretKey` | Independent random Base64 key, at least 32 bytes, not the Development/production key. E2E issuer/audience are fixed by the profile. |
| `E2E__ImageRoot`, `MapImages__RootPath` | Same absolute private path ending in `WayMark_MapDraft_E2E_Test/images`, outside the repository/application and all other storage roots. |
| `E2E__ProtectedImageRoots__0` (and further indices) | Actual approved Development/production roots to exclude, including parent/child overlaps. Operator must inventory them. |
| `E2E__StorageIsolationConfirmed` | Explicit `true` after operator validation. |
| `E2E__AllowedOrigin` | One exact loopback HTTP origin; default `http://localhost:5628`. |

Do not set legacy `ConnectionStrings__WayMarkDatabase` or
`ConnectionStrings__WayMarkAuthDatabase` in the launcher terminal. Conflicting
connection entries are rejected; both contexts use the validated profile, with
`__EFMigrationsHistory` and `__AuthMigrationsHistory` respectively.

The EF interceptor verifies metadata on every opened connection and closes it on
failure. Actual protected catalog, unexpected server/login, sysadmin, server-level
administration rights or access to either protected database stop startup/EF work.
Unknown required privilege results also fail closed. This protects registered EF
connections, not arbitrary DBA tools or deliberately bypassed application code.
There is no startup migrator/seeder. EF design-time factories also require explicit
matching E2E environment variables and the guarded profile; ordinary EF CLI calls
outside E2E now stop intentionally. Master/database creation targets are refused;
the approved test database must already exist before a future migration run.

Image settings are pinned against configuration reload: 128 MiB/50 objects total,
8 images and 32 MiB per floor, 20 revisions per floor. Existing image format/codec
limits remain unchanged. No development storage is enabled by this profile.
SMTP is disabled only in E2E. CORS is exact-origin; Swagger is available in E2E.

## Verification performed

| Check | Result |
| --- | --- |
| Backend build, isolated artifacts | PASS, 0 warnings / 0 errors. |
| Full backend suite | 264 passed, 0 failed, 0 skipped. |
| NuGet vulnerable list, both projects, transitive | No reported vulnerabilities from api.nuget.org. |
| Fresh restore with no HTTP cache, audit all/low, warnings as errors | PASS for API and tests; audit enabled, no NU190x warnings. |
| Launcher syntax | PASS; launcher was not executed. |
| Git whitespace check | PASS; line-ending notices only. |
| Flutter | Unchanged by this hotfix; not rerun. Prior preflight 175 pass / 1 skip remains historical. |

New guard tests use fake metadata connections, not SQL Server. They cover missing
configuration, protected/wrong catalogs, connection fallbacks, unsafe login options,
actual identity/privileges, rejected opens, password hiding on reopen, both history
tables, extra unguarded contexts, template masking, storage overlap/pinning and
invalid JWT configuration. Directory access tests use owned temporary directories.
Existing managed-image tests exercise real files and isolated SQLite databases;
fake failure tests remain separate. These results do not prove SQL Server E2E.

SQL-provider model tests confirm the snapshot matches and migration ordering stays:
`20261020094848_AddMapDraftFoundation` then `20261020101304_BindMapImagesToDrafts`.
Migration files/snapshot were not changed; current live history was not queried
again. Room/Place, multiple Entrance GUIDs, image save/load, 409 concurrency, restore,
cross-Site authorization and production-routing isolation pass in isolated tests.

## Files in this hotfix

Modified existing files only:
`WayMark.Api.Tests/AdminAuthorizationTests.cs`, `WayMark.Api/Program.cs`,
`WayMark.Api/Security/WayMarkSecurity.cs`, `WayMark.Api/appsettings.json`.

Added:
`WayMark.Api.Tests/E2ESafetyTests.cs`,
`WayMark.Api/Data/WayMarkDatabaseRegistration.cs`,
`WayMark.Api/Data/E2EDesignTimeFactories.cs`,
`WayMark.Api/Security/E2ESafetyProfile.cs`,
`WayMark.Api/Security/E2EConnectionInterceptor.cs`,
`WayMark.Api/Security/E2EStartupCheck.cs`,
`WayMark.Api/Security/E2EStorageAccess.cs`,
`WayMark.Api/Services/E2EDisabledEmail.cs`,
`WayMark.Api/appsettings.MapDraftE2E.json`,
`scripts/Start-MapDraftE2E.ps1`, and this report.

Hash comparison against the start-of-hotfix baseline preserves every other
preexisting file, including Kilo work, Flutter, Gradle, Windows generated files,
Figma reference, routing, both migrations and snapshot. No staging was performed.

## Decision / remaining approval

**GO for the source hotfix; NO-GO for executing real E2E until provisioning is
approved and verified.** Remaining operator work, not performed here:

1. Approve the exact test instance/database and verify SQL authentication is
   available; never change server authentication mode implicitly.
2. Provision a dedicated least-privilege test principal with no access to either
   protected database and no server admin rights. DDL rights for a separately
   approved migration window must not become general server rights.
3. Approve/create the test database; review/apply full Auth and WayMark migration
   chains only there using the guarded configuration. Never use EnsureCreated.
4. Approve/bootstrap test Site → Building → Floor, test Identity/Admin role and
   active Site membership only in the test database. No username-based elevation.
5. Provision isolated image root/ACLs, protected-root inventory, quotas, paired
   database+image backup and a trusted local HTTPS certificate.
6. Supply private environment settings, then run `scripts/Start-MapDraftE2E.ps1`.
   Start Flutter with port 5628 and base URL `https://localhost:7627/api`.
   Follow the preflight Save/Load/reload/restart/409/restore/cross-Site checklist;
   network/storage failures must retain the local draft. Real Room creation still
   requires a controlled API/import fixture; there is no Room editing UI yet.

Stop here. No database provisioning, grants, seed or migration is authorized by
the hotfix itself; actual SQL, directory ACLs, certificate and browser E2E remain
unverified until the next approved stage.
