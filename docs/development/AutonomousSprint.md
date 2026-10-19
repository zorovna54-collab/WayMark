# WayMark autonomous sprint — 2026-10-18

## Baseline and boundaries

- Branch: `auth-jwt-assignment`. Existing Flutter changes from 4B–4D and Android
  configuration retained. No SQL connection, seed, migration application or Git publication.
- Baseline: Flutter analyzer clean; 107 Flutter tests pass, one browser-only skip.
- .NET executable exists at `C:\Program Files\dotnet\dotnet.exe`, absent from terminal PATH.
- Figma Make context returned resource links for the requested React/CSS files.
  Reading `src/App.tsx` via the available resource reader failed `Unknown resource`.
  No source body or screenshot was received. Screenshot tool explicitly excludes Make.
  Browser fetch also failed. The user subsequently supplied an export, located at
  `waymark/design-reference/figma-make` (one level below the path in their message).
  Read HospitalMap, RoutePreferences, WaymarkUI, RoutePreview, Navigation, Scanner,
  MapBuilder, App, CSS and WAYMARK-PROTOTYPE.md. That resolved source access.
  No rendered Make screenshot was available; pixel-for-pixel fidelity is not claimed.
  Reference files are untouched and are not Flutter assets/backend content.

## Progress

| Phase | State | Scope |
| --- | --- | --- |
| 0 | Audited | Existing routes, manual/QR confirmation, floor graph and admin placeholder inspected |
| 1 / 4E | Implemented | Confirmed off-route QR rerouting; validated replacement, destination/restrictions retained; Preview updated too |
| 2 / 5A | Foundation implemented | Shared aspect-preserving image/overlay viewport; PNG/JPG checks; draft bound to real hierarchy |
| 3 / 5B | Implemented from TSX/CSS, visual differences documented | Map-first Preview, expandable instructions, vertical floors, scoped Inter/tokens, separate QR/manual markers |
| 4 / 5C | Local draft vertical slice implemented | Read API hierarchy; edit nodes/directed edges; Web file import/export; no production write API |
| 5 / 6A | Partial | Avoid-stairs restriction and elevator/walking preferences work; wheelchair explicitly blocked without verified metadata |
| 6 | Automated verification complete | See results below and MapNavigationSprint.md for remaining manual checks |

4D has not been verified with live camera/API after its implementation. Automated
camera/HTTP fixtures do not verify installed QR locations or physical accessibility.

## Architectural limits requiring follow-up

- Production draft storage, review/publish workflow and server authorization policy
  require a separate design. Existing login tokens do not carry an admin role;
  no new write API was exposed to ordinary JWT users.
- No verified wheelchair metadata exists. No migration was needed for the safe
  subset implemented here; no migrations were created or applied.
- No real hospital floor plans or field measurements were supplied. A graph-only
  schematic remains the fallback; the Figma room geometry is not production data.
- Inter was retrieved from Google Fonts and bundled with OFL.txt. There is no
  runtime font download or dependency on the reference React project.

## Final verification

Commands below ran from `waymark/` unless noted otherwise:

| Command | Result |
| --- | --- |
| `flutter analyze --no-pub` | Passed; no issues |
| `flutter test --no-pub --reporter expanded` | 134 passed, one existing browser-only test skipped on VM |
| `flutter build web --no-pub` | Passed; Wasm dry run also passed |
| `flutter build apk --debug --no-pub` | Passed; final build with bundled Inter/OFL, assembleDebug 12.8 s |
| `dotnet build WayMark.Api/WayMark.Api.csproj --no-restore --artifacts-path D:\project\WayMark\WayMark.Api.Tests\bin\sprint` | Passed; 0 errors, NU1900 warning |
| `dotnet test WayMark.Api.Tests/WayMark.Api.Tests.csproj --no-restore --artifacts-path D:\project\WayMark\WayMark.Api.Tests\bin\sprint` | 55 passed, no skips or failures |
| `git diff --check` | Passed; only LF/CRLF normalization notices |
| `flutter test --no-pub --dart-define=WAYMARK_CAPTURE_PREVIEWS=true test/map_layout_test.dart` | Passed; phone/Web fixture renderings inspected |

.NET commands used `C:\Program Files\dotnet\dotnet.exe` from repository root.
The initial normal-output build hit an existing running API executable lock;
isolated artifacts avoided that lock. No backend process was stopped.
An escalated restore retry was also performed. NuGet vulnerability feeds remained
unavailable (NU1900); baseline cached audit had reported NU1902/NU1903 for existing
System.Security.Cryptography.Pkcs 10.0.0. Dependency versions were not upgraded.

Web and Android Flutter assets contain the four Inter TTF files and OFL.txt. No
TSX, HospitalMap or WAYMARK-PROTOTYPE reference files were found in either output. Source searches found
no hardcoded demo route/code, physical progress timer, private-key block or JWT
token literal in the changed routing/map implementation. This is a scoped source
review, not a full repository security audit.

Protected Windows generated files, Android gradle.properties and API appsettings
match baseline SHA-256 hashes. Git shows no changes to backend entities, DbContexts,
Program/authentication, migrations or configuration. No real database command,
seed, commit, push, reset or restore was executed. Manual camera/API/browser file
dialog and real hospital routing checks remain outstanding.
