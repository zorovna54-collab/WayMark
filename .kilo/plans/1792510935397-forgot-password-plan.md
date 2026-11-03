# Forgot Password Feature Plan (Backend Only)

## Goal
Add password-reset capability to WayMark.Api without changing any UI. Users can request a reset link/token by username or email and set a new password using the token.

## Constraints
- No Flutter/UI changes.
- Reuse existing Identity + SMTP infrastructure.
- Keep responses non-enumerating (same 200 for unknown accounts).

## Affected Files
- `WayMark.Api/Data/AuthRequests.cs` — add `ForgotPasswordRequest`, `ResetPasswordRequest`; add `Email` to `RegisterRequest`.
- `WayMark.Api/Controllers/AuthController.cs` — add `forgot-password` and `reset-password` endpoints; set email on register.
- `WayMark.Api/Services/ISmtpEmailService.cs` + `SmtpEmailService.cs` — add `SendPasswordResetEmailAsync`.
- `WayMark.Api/Program.cs` — enable `RequireUniqueEmail` (optional), configure reset token lifetime, keep Identity options.
- `WayMark.Api/appsettings.json` / dev secrets — add `Jwt:SecretKey` (base64 32 bytes) and `Frontend:ResetPasswordUrl`.
- `WayMark.Api.Tests` — add `AuthApiTests`.

## Data Flow
1. Register stores `Email` when provided.
2. `POST /api/Auth/forgot-password { usernameOrEmail }`:
   - Resolve user by username then email.
   - If not found, return 200 generic.
   - Generate token via `UserManager.GeneratePasswordResetTokenAsync`.
   - Send email with token + reset URL.
   - Return 200 generic.
3. `POST /api/Auth/reset-password { usernameOrEmail, token, newPassword }`:
   - Resolve user; call `ResetPasswordAsync`; return 200 on success, 400 with Identity errors on failure.

## Failure Modes
- Missing SMTP config → throw `SmtpEmailException` (Configuration); endpoint returns 500 with safe message.
- Invalid/expired token → 400 with Identity error descriptions.
- User without email → cannot receive reset; return 200 generic (no enumeration).
- Brute force → mitigate via ASP.NET Core rate limiting (optional, recommended).

## Migration
- No DB schema change required (IdentityUser already has Email column).
- Ensure Auth migration applied.

## Validation
- Build: `dotnet build WayMark.Api`.
- Tests: add and run `AuthApiTests` covering register → forgot → reset → login with new password; invalid token; unknown user returns 200.
- Manual: configure SMTP user secrets, call endpoints via Swagger/http file.

## Open Questions
- Should Email be required at registration? (Recommend: optional but validated if present; reset only works if email exists.)
- Rate limiting scope: per-IP or per-account? (Recommend: per-IP for forgot-password.)
