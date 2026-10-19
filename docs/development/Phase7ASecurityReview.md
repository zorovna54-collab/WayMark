# WayMark Phase 7A — Authorization & dependency security fix

Date: 2026-10-19. Branch: `auth-jwt-assignment`.

## Decision

**GO to rerun SAFE GIT FINALIZATION, COMMIT & PUSH.** Both High findings from the
initial audit are fixed in the working tree and covered by verification below.
This phase has not staged, committed, pushed or deployed these changes. It is not
production approval or a claim that the currently running API has been retested.
The public remote still needs a separately authorized finalization/deployment.

Map Builder remains a local draft workflow. No server map publication, admin
CRUD for graph entities, reviewer workflow or AI feature was added.

## 1. Write endpoint audit and final authorization

| Method / path | Effect | Authorization after fix |
| --- | --- | --- |
| POST `/api/WayMarks` | Insert business WayMark | JWT + `AdminOnly` policy |
| PUT `/api/WayMarks/{id:int}` | Update business WayMark | JWT + `AdminOnly` policy |
| DELETE `/api/WayMarks/{id:int}` | Delete business WayMark | JWT + `AdminOnly` policy |
| POST `/api/Email/test` | External SMTP send | JWT + `AdminOnly` policy |
| POST `/api/Auth/register` | Register ordinary Identity user | Existing anonymous registration; no role accepted or assigned |
| POST `/api/Auth/login` | Validate credentials and issue JWT | Existing anonymous login; role claims read from server Identity membership |
| POST `/api/routes` | Read graph and calculate route | Existing JWT requirement, ordinary users allowed; no business-data write |
| GET `/api/WayMarks`, ID/code/map-location variants | Read WayMarks / QR location | Existing JWT requirement, ordinary users allowed |
| GET `/api/Maps/...` | Read hierarchy / floor graph | Existing JWT requirement, ordinary users allowed |
| GET `/weatherforecast` | Generated sample response | Existing anonymous sample, no persistent write |

No other controller write actions or mapped write endpoints were found. A new
reflection regression test requires the Admin policy for every non-auth/non-routing
POST/PUT/PATCH/DELETE action in the current controller assembly. Four protected
actions are expected. Hiding Flutter buttons is not part of this enforcement.

Missing, expired, incorrectly signed, unsigned, wrong-issuer/audience or tampered
JWT: **401**. Valid ordinary user or non-Admin role: **403**. A valid Admin JWT is
allowed through the policy; normal validation/resource/conflict rules still apply.
Admin success paths were tested as create 201, update 200, delete 204 and fake SMTP 200.

## 2. Trusted Admin identification and JWT compatibility

- Existing `AuthDbContext : IdentityDbContext<IdentityUser>` and `CreateAuthSchema`
  already define `AspNetRoles`, `AspNetUserRoles` and their Identity relations.
  Neither context, schema, migration nor model snapshot was changed.
- `Program.cs` now registers `.AddRoles<IdentityRole>()`. No startup seed, account,
  role creation, role grant, allowlist or privileged username was introduced.
- `AuthController.Login` calls `UserManager.GetRolesAsync(user)` and writes standard
  `ClaimTypes.Role` claims from those server-controlled memberships only. It does
  not copy roles or arbitrary claims from a request body/header/query or Flutter.
- `AdminOnly` requires authenticated membership in the exact canonical role `Admin`.
  A username of `admin` does not grant access. Register/login DTOs still accept only
  username/password; extra client role properties do not grant a membership.
- `Security/WayMarkSecurity.cs` shares the actual JWT/policy registration between
  production and security integration tests. Issuer, audience, signing key source,
  expiry validation and 30-second clock skew remain. Standard inbound role mapping
  is explicit; signed HMAC-SHA256 tokens are required, matching the existing issuer.
- Login JSON still returns accessToken/tokenType/expiresAtUtc/username. Existing
  ordinary JWTs without a role remain usable for authenticated reads and routing,
  but receive 403 on Admin writes. Flutter/AuthSession was not changed.

This follows [ASP.NET Core role services/policies](https://learn.microsoft.com/en-us/aspnet/core/security/authorization/roles?view=aspnetcore-10.0).

### Operator work still required before real Admin use

No live database was read or written in this phase, so no production Admin account
or existing membership has been verified. Until an operator grants a trusted user
the role, all ordinary users are correctly denied Admin writes.

1. Before deployment, confirm the already-applied Auth schema has the Identity role
   tables on the configured database. Source migrations contain them; no new
   migration is required by this change. A missing live table is a deployment issue,
   not a reason to auto-create/reset the database or fall back to unprotected writes.
2. In a separately approved maintenance task, identify the intended existing user
   by verified Identity ID. Use trusted server-side `RoleManager`/`UserManager` to
   create the canonical `Admin` role if absent and grant that exact user membership,
   checking each IdentityResult. Record/review this privileged action. No grant
   script, user-management API or automatic bootstrap executes in this phase.
3. Sign out and sign in again to obtain a fresh JWT with server-issued roles.
   Old JWTs are not upgraded by client UI state. Keep actual tokens and secrets out
   of screenshots, docs and commits.
4. Test ordinary-user 403 and approved-Admin write behavior on controlled data;
   do not test delete/update against production records without separate approval.

Roles are a snapshot in the issued JWT. Removing membership removes Admin from
the **next login**, covered by a test; an already-issued token remains valid until
expiry (plus existing clock skew). Immediate revocation/security-stamp validation,
rate limiting and production audit logging are not claimed by this change.

## 3. NuGet vulnerability fix

Before: Pkcs **10.0.0**, transitive through MimeKit 4.18.1 (>=10.0.0) and
Microsoft.Data.SqlClient 6.1.6 (>=9.0.11). The pre-fix command actually reported:

- NU1903 / High: [GHSA-846f-f764-76mx](https://github.com/advisories/GHSA-846f-f764-76mx).
- NU1902 / Moderate: [GHSA-2fmv-rv2c-59x7](https://github.com/advisories/GHSA-2fmv-rv2c-59x7).

Both advisories list 10.0.0–10.0.12 as affected and **10.0.13** as the patched 10.x
version. Added one explicit `System.Security.Cryptography.Pkcs` PackageReference
at 10.0.13 in the API project, satisfying both dependency chains. The
[NuGet package](https://www.nuget.org/packages/System.Security.Cryptography.Pkcs/10.0.13)
supports net10.0. Target framework remains net10.0; EF/ASP.NET Core/MailKit/MimeKit/
SqlClient versions remain unchanged.

A comparison of the pre/post resolved API package lists found only Pkcs changing
from 10.0.0 to 10.0.13. No bulk upgrade, audit suppression, NoWarn or feed disabling
was added. Both project audits now report no vulnerable packages **given the current
sources**; this is not a guarantee against unknown/future advisories.

The NuGet vulnerability resource was independently requested and returned HTTP 200.
Final restore/build/audit emitted no NU1900, NU1902 or NU1903 warning, so a network
failure is not being presented as a clean result.

## 4. Tests actually run

| Check | Result |
| --- | --- |
| Backend build in isolated ignored artifacts path | Passed, 0 warnings, 0 errors |
| Backend full test suite | **108/108 passed**, 0 failures, 0 skips |
| New authorization suite within that total | **48 tests**; old 60-test baseline retained |
| `flutter analyze` | Passed, no issues |
| `flutter test --reporter expanded` | **147 passed**, 1 existing browser-only test skipped on VM |
| `flutter build web` | Passed, 34.1 s; Wasm dry run succeeded |
| API and test-project vulnerable package audits, including transitive | No vulnerable packages reported by current NuGet source |
| `git diff --check` | Passed; existing LF/CRLF conversion notices only |

The new tests use the real Auth/WayMarks/Email/Maps/Routes controllers and production
JWT/policy registration with EF InMemory, random ephemeral signing keys/passwords,
and an SMTP counter. Test Admin accounts and memberships exist only in those isolated
in-memory fixtures. No email was sent, no SQL Server connection was made, and no
production user or role was created/modified.

Coverage: all four protected actions reject missing/user/spoofed-role/expired/
wrong-signature/tampered/unsigned/wrong-issuer/wrong-audience tokens as appropriate;
rejected writes preserve the data snapshot and do not invoke SMTP. Actual database
role membership → real login → authorized mutation succeeds. Registration/username/
login-body role injection fails. A signed Reviewer role is denied. Removing role
membership affects the next login. Ordinary user graph/QR reads and legacy/new
routing request formats still work. No camera/SQL/live API test is claimed here.

Commands, with ignored local output:

```powershell
dotnet build WayMark.Api/WayMark.Api.csproj --artifacts-path waymark/.dart_tool/phase7a/dotnet
dotnet test WayMark.Api.Tests/WayMark.Api.Tests.csproj --artifacts-path waymark/.dart_tool/phase7a/dotnet --logger "trx;LogFileName=backend-full.trx" --results-directory waymark/.dart_tool/phase7a/results
dotnet list WayMark.Api/WayMark.Api.csproj package --vulnerable --include-transitive
dotnet list WayMark.Api.Tests/WayMark.Api.Tests.csproj package --vulnerable --include-transitive
# From waymark/:
flutter analyze
flutter test --reporter expanded
flutter build web
# From repository root:
git diff --check
```

## 5. Files changed in this phase

Modified:

1. `WayMark.Api/Program.cs` — shared security registration and Identity role services.
2. `WayMark.Api/Controllers/AuthController.cs` — server-owned role claims at login.
3. `WayMark.Api/Controllers/WayMarksController.cs` — Admin policy on three writes.
4. `WayMark.Api/Controllers/EmailController.cs` — Admin policy on SMTP side effect.
5. `WayMark.Api/WayMark.Api.csproj` — explicit patched Pkcs dependency.
6. `docs/development/GitFinalizationAudit20261019.md` — historical audit follow-up link.

New:

7. `WayMark.Api/Security/WayMarkSecurity.cs`.
8. `WayMark.Api.Tests/AdminAuthorizationTests.cs`.
9. This report: `docs/development/Phase7ASecurityReview.md`.

No Flutter source, Gradle, Windows generated file, JWT secret, connection string,
entity, context, migration or SQL file was modified. Protected-file SHA-256 values
still match the prior audit. Existing unrelated working-tree changes are preserved.

## 6. Commit readiness and manifest reconciliation

All **71 candidate paths** from `GitFinalizationAudit20261019.md` still exist; none
was removed. Its audit report is already in that manifest. Add these **eight** paths
to the next explicit-path staging review, making **79 candidate paths** total:

```text
WayMark.Api/Program.cs
WayMark.Api/Controllers/AuthController.cs
WayMark.Api/Controllers/WayMarksController.cs
WayMark.Api/Controllers/EmailController.cs
WayMark.Api/WayMark.Api.csproj
WayMark.Api/Security/WayMarkSecurity.cs
WayMark.Api.Tests/AdminAuthorizationTests.cs
docs/development/Phase7ASecurityReview.md
```

Keep the original exclusions: all 45 Figma-reference files, existing Gradle change,
three protected Windows generated files, ignored build/cache outputs and local
configuration/secrets. No file is currently staged. The next finalization must
repeat remote/divergence/secret checks and inspect its complete cached diff before
commit/push; this report does not bypass those gates.

Final manifest comparison found **79 expected / 79 actual** eligible pending paths,
with no missing baseline path or unexpected addition. Working tree: 23 modified,
102 untracked paths including the excluded reference files; no merge conflicts.
The current phase's repeated secret-pattern scan covered 137 tracked/proposed text
files outside the excluded Figma folder. No confirmed production secret was found:
matches were random test credential generation, existing synthetic test session
markers and controller text reads. The prior history/reference scan remains in the
initial audit; no new Git history was created here. Pattern scans have bounded
coverage and do not replace a complete security audit.

Pending operator role provisioning and real deployment verification do not require
granting any account privileges merely to commit these server-side guards. They do
remain prerequisites for using Admin features in the actual environment.
