# Core Sprint 6 — real SQL Server E2E results

Date: **24/10/2026, Asia/Saigon**. RunId `2e5448b2-7c06-4a93-a438-f0d22a2edca6`.

**Backup PASS; approved migrations 3/3 PASS; SQL business E2E 16/16 PASS. Full regression remains BLOCKED by Windows Application Control.** Android APK built; no Android camera/UI rerun. This replaces the earlier 2/3 migration and 0/16 E2E report.

## Target and backup

Actual target: `LAPTOP-PFRPMR3O`, instance `.`, `WayMarkDatabase`, Windows `LAPTOP-PFRPMR3O\pc`. Execution session reported Shared memory / NTLM / `encrypt_option=TRUE`. Approved certificate-trust and existing sysadmin exceptions were used only for this local Development run. No Windows/SQL principal, sysadmin membership, trust store, firewall or server setting changed.

New FULL COPY_ONLY with CHECKSUM/STOP_ON_ERROR, without overwrite:

`C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Backup\WayMarkDatabase_Core6_2e5448b27c064a93a438f0d22a2edca6.bak`

- File **6,213,632 bytes**; metadata backup size **6,184,960 bytes**.
- COPY_ONLY=1, has_backup_checksums=1, is_damaged=0; HEADERONLY/FILELISTONLY checked.
- VERIFYONLY WITH CHECKSUM/STOP_ON_ERROR passed, including recheck before resuming. No restore rehearsal/restore.
- SHA256: `9864266ABE674B629A2AAE6B338C6E4FF6EEE5031851DE7EE29D2A0192F15C9E`.

## Migration recovery — PASS

First attempt committed Foundation and Bind, then failed SQL 1934 with QUOTED_IDENTIFIER OFF. No publication-table/history residue remained after the failed connection closed.

The resume launcher verified exact target/identity, encrypted session, four-entry migration prefix, unchanged Auth history, backup metadata and absence of publication tables. It set and checked seven filtered-index options in the actual session: **1,1,1,1,1,1,0**. Original reviewed SQL artifacts were not regenerated or modified.

Executed successfully:

```powershell
sqlcmd -S . -d WayMarkDatabase -E -N -C -I -b -V 16 -i docs/database/core-sprint6/ResumePublishedMigration.review.sql
```

This is an execution record, **not a command to rerun**: the launcher's four-entry history guard now rejects the completed five-entry state.

| Approved migration | Final result |
|---|---|
| `20261020094848_AddMapDraftFoundation` | Previously committed; skipped during resume |
| `20261020101304_BindMapImagesToDrafts` | Previously committed; skipped during resume |
| `20261023063955_AddPublishedMapProjects` | Applied successfully during resume |

Map history: exactly **5 entries**, including the two original migrations. Auth history: unchanged `20261010032404_CreateAuthSchema`. All eight new tables exist: FloorMapDrafts, FloorMapDraftRevisions, FloorMapImageAssets, SiteMapMemberships, MapProjects, MapPublications, MapPublicationImages, MapNodeQrs. New FKs/check constraints are enabled/trusted; MapNodeQrs active-only filtered unique index exists.

Manifest SHA256 still matches: ordinary SQL `ae0494a7934a5f196f972755c202e5bb51a80aaef12855bdb7966485325acf57`; idempotent SQL `9b0ef8402d79810909bcfc39a4f262ac5e55fc226b25ed361e0f8446099fab22`. No manual history edits, Down, DROP or restore.

## Accounts, storage and execution method

Existing bootstrap/grant commands created two RunId-scoped Identity accounts with random passwords. A: Creator + SitePublisher for Site 1. B: Creator only. Both have active editable Site membership for the verified demo hierarchy and G/L1 (SQL Floor IDs 1/2). Neither has Admin/SiteManager; no existing user was reset/adopted.

Private image root: `%LOCALAPPDATA%\WayMark\CoreSprint6\2e5448b27c064a93a438f0d22a2edca6\images`, outside Git, quota128 MiB/20 objects. Passwords are stored DPAPI-encrypted in the private parent directory. No passwords/JWTs in source, process arguments or this report; existing JWT settings unchanged.

The CLI's first e2e attempt refused before creating drafts because its server-permission query used `HAS_PERMS_BY_NAME(NULL,'SERVER',...)`, returning NULL. Source now uses correct `(NULL,NULL,...)` for all six server permissions, preserving fail-closed handling; added a regression assertion. SQL SELECT verified corrected probes.

After rebuilding, Windows Application Control blocked CoreSqlReadiness.dll (`0x800711C7`; Code Integrity events3077/3033). **The CLI e2e entry point did not complete.** Approved business checks instead ran through the normally launched WayMark.Api process, ordinary HTTP clients and an opt-in live Flutter test. No alternate assembly loader or Windows policy change. Evidence is actual SQL Server + managed filesystem, not earlier SQLite results.

## SQL E2E — 16/16 business scenarios PASS

These groups map the approved workflow to recorded HTTP assertions and the live Flutter test; they do not claim the blocked CLI harness passed.

| # | Scenario | Actual evidence |
|---|---|---|
| 1 | Creator A/B Identity login | Both200; signed JWT on private APIs |
| 2 | Two-floor Node-first project | POST201; G/L1, four stable GUID nodes, zero Rooms, explicit stairs |
| 3 | PNG/JPG upload | Both201; decoded120×80, correct MIME, distinct checksums |
| 4 | Save floor drafts | PUT200; revision2, image and directed edges retained |
| 5 | Reload floor/project drafts | GET200; image IDs, node GUIDs, floors/links match |
| 6 | Creator A publish | 200; immutable snapshot, patient verification false |
| 7 | Guest published read | Snapshot/images200 without JWT; SHA256/MIME verified |
| 8 | Guest private/write denial | Private draft/images401; unpublished404; edit/publish401 |
| 9 | QR to stable Node GUID | QR creation200; not based on N01/UI label |
| 10 | Guest QR resolution | 200; exact Map/Version/FloorKey/Node GUID |
| 11 | Search → Preview → Navigation | Existing Flutter client fetched real SQL snapshot/images; directed13m, four-node G→L1 route; manual Arrival; AuthSession preserved, no timer advance |
| 12 | Creator B denied on A's project | Edit/Publish/Revoke each403 |
| 13 | Private edit / concurrency | Edit200 version2; stale save409 |
| 14 | Immutable publication | Version1 retains original content/name after draft version2 edit |
| 15 | QR revoke | Revoke200, resolve410; still410 after second API restart |
| 16 | Persistence/integrity | Real process restarts preserve drafts, snapshot, QR binding and image bytes;14 legacy digests match outside approved account/role additions |

Navigation evidence is a **Flutter widget flow with live SQL HTTP data**, not an Android camera/UI rerun. Final adb devices had no attached device. Earlier VirtualScene evidence is not relabeled as new SQL camera evidence.

Synthetic images match fixture coordinates. They are not real hospital maps or patient-safe routes. Distances5+3+5m are explicit fixture values, not inferred from pixels.

## Persisted fixture and integrity

Final additions: **2 floor drafts,4 revisions,2 image assets,1 project,2 publications,2 QR records**. Version1 QR remains revoked. A separate active version2 QR was created/published within the approved RunId fixture for a subsequent demo, with the same stable start GUID.

Private evidence state: `%LOCALAPPDATA%\WayMark\CoreSprint6\2e5448b27c064a93a438f0d22a2edca6\http-e2e-state.json`; active location QR PNG: `demo-start-qr.png` in that directory. It is not a JWT. Credentials remain outside Git.

Original graph counts unchanged:1 Site,1 Building,2 Floors,7 Nodes,10 Edges,3 WayMarks. All **14 baseline digests** match after excluding only approved new test-user/Creator/SitePublisher rows. Original five users and legacy role/claim/login/token data unchanged. Identity totals now7 users,2 roles,3 user-role links;2 Site memberships. Auth history and both ONLINE databases checked. WayMarkAuthDatabase untouched; no third database/principal or sysadmin changes.

## Regression and blockers

| Check | Actual result |
|---|---|
| Backend build | PASS,0 warnings/errors |
| Full backend run | **117 passed /233 failed /350 total**; blocked CoreSqlReadiness.dll caused direct load/controller-discovery failures and secondary teardown failures |
| Latest backend retry | BLOCKED before tests ran: Application Control also refused rebuilt WayMark.Api.Tests.dll; not an empty-success run |
| Flutter analyze | PASS, no issues |
| Default Flutter tests | **265 passed /2 skipped** (Web-only + opt-in live SQL test) |
| Opt-in live SQL Flutter | **1 passed**; actual API/images → Search/Preview/manual multi-floor Arrival; active version2 QR tested |
| Android debug build | PASS, `waymark/build/app/outputs/flutter-apk/app-debug.apk`; compiled API URL `http://10.0.2.2:62509/api` |
| Android/emulator/camera rerun | NOT RUN; no attached device |
| git diff --check | PASS; existing LF/CRLF advisories only |

A narrow test-host discovery adjustment was tried, but retry was blocked at assembly load. Those unverified adjustments were removed; tests were not disabled to claim success. Earlier349/349 is historical, not the current regression result.

The tested API used **loopback only `http://127.0.0.1:62509`**, with two actual process restarts. At final continuation it was no longer listening. A final restart command was **rejected by automatic approval review**, whose only supplied reason was `blocked by policy`. It did not execute; no protection was weakened or equivalent restart retried. API needs an allowed local start before using the APK/demo QR again. No API opened to LAN/public network.

**Conclusion: CORE SQL business E2E PASS16/16; full Sprint regression/demo handoff PARTIAL.** Remaining blockers: Windows Application Control on test assemblies, unavailable final API process, and Android SQL camera/UI acceptance not repeated. These do not invalidate recorded persistence evidence; full regression green/currently-running Android demo are not claimed. Sysadmin/certificate exceptions are unsuitable for production.

## Source changes and evidence

Continuation changes: resume launcher session-option gate/execution note; `tools/CoreSqlReadiness/ReadinessPlan.cs` and `Program.cs` permission probe; `WayMark.Api.Tests/LocalSqlDevelopmentTests.cs`; `waymark/test/live_sql_public_navigation_test.dart`; this report. Existing user changes preserved. Master Plan, Gradle, Windows generated files, AI code and original SQL artifacts unchanged by this continuation. No commit/push/reset/clean or automatic fixture cleanup.

Git-ignored evidence: `waymark/build/core-sql-evidence/2e5448b27c064a93a438f0d22a2edca6/`: backup verification, migration resume/options, before/after digests, http-e2e-checks.log, snapshot, SQL counts, regression/build logs and blocked retry TRX. Private DPAPI credentials were not copied into repo evidence.
