using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using WayMark.Api.Data;
using Xunit;

namespace WayMark.Api.Tests;

public sealed class AccountSecuritySprint9Tests
{
    private const string Password = "Isolated-test1!";
    private static async Task<string> Register(MapDraftTestHost h, string name, string? email = null)
    {
        (await h.Client.PostAsJsonAsync("/api/Auth/register", new { username = name, password = Password, email })).EnsureSuccessStatusCode();
        return await Login(h, name, Password);
    }
    private static async Task<string> Login(MapDraftTestHost h, string name, string password)
    {
        var result = await h.Client.PostAsJsonAsync("/api/Auth/login", new { username = name, password });
        result.EnsureSuccessStatusCode();
        var token = (await result.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("accessToken").GetString()!;
        h.Client.DefaultRequestHeaders.Authorization = new("Bearer", token); return token;
    }
    [Fact]
    public async Task Missing_email_is_bound_only_after_confirmation_to_same_identity_and_token_is_single_use()
    {
        await using var h = new MapDraftTestHost(withIdentity: true); await h.StartAsync();
        await Register(h, "email-less");
        var before = await h.Client.GetFromJsonAsync<JsonElement>("/api/Auth/me"); Assert.Equal(JsonValueKind.Null, before.GetProperty("email").ValueKind);
        (await h.Client.PostAsJsonAsync("/api/Auth/me/email/request", new { email = "owned@example.invalid", currentPassword = Password })).EnsureSuccessStatusCode();
        Assert.Equal(1, h.Email.VerificationCalls);
        var token = h.Email.Token!;
        var pending = await h.Client.GetFromJsonAsync<JsonElement>("/api/Auth/me"); Assert.Equal(JsonValueKind.Null, pending.GetProperty("email").ValueKind);
        (await h.Client.PostAsJsonAsync("/api/Auth/me/email/confirm", new { email = "owned@example.invalid", token })).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Unauthorized, (await h.Client.GetAsync("/api/Auth/me")).StatusCode);
        await Login(h, "email-less", Password);
        var after = await h.Client.GetFromJsonAsync<JsonElement>("/api/Auth/me");
        Assert.Equal("email-less", after.GetProperty("userName").GetString()); Assert.True(after.GetProperty("emailVerified").GetBoolean());
        Assert.Empty(after.GetProperty("roles").EnumerateArray());
        Assert.Equal(HttpStatusCode.BadRequest, (await h.Client.PostAsJsonAsync("/api/Auth/me/email/confirm", new { email = "owned@example.invalid", token })).StatusCode);
    }
    [Fact]
    public async Task Duplicate_normalized_email_and_client_privilege_fields_are_rejected()
    {
        await using var h = new MapDraftTestHost(withIdentity: true); await h.StartAsync();
        await Register(h, "owner-a", "Owner@Example.invalid"); await Register(h, "owner-b");
        Assert.Equal(HttpStatusCode.Conflict, (await h.Client.PostAsJsonAsync("/api/Auth/me/email/request", new { email = "owner@example.invalid", currentPassword = Password })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await h.Client.PostAsJsonAsync("/api/Auth/me/email/request", new { email = "other@example.invalid", currentPassword = Password, userId = "owner-a", emailConfirmed = true, role = "Admin" })).StatusCode);
        Assert.Equal(0, h.Email.VerificationCalls);
        Assert.Equal(HttpStatusCode.Conflict, (await h.Client.PostAsJsonAsync("/api/Auth/register", new { username = "duplicate", email = "OWNER@example.invalid", password = Password })).StatusCode);
    }
    [Fact]
    public async Task Wrong_or_expired_token_and_wrong_subject_leave_email_unchanged()
    {
        await using var h = new MapDraftTestHost(withIdentity: true); await h.StartAsync();
        await Register(h, "verify-a");
        (await h.Client.PostAsJsonAsync("/api/Auth/me/email/request", new { email = "new@example.invalid", currentPassword = Password })).EnsureSuccessStatusCode();
        var token = h.Email.Token!;
        Assert.Equal(HttpStatusCode.BadRequest, (await h.Client.PostAsJsonAsync("/api/Auth/me/email/confirm", new { email = "new@example.invalid", token = "bad" })).StatusCode);
        await Register(h, "verify-b");
        Assert.Equal(HttpStatusCode.BadRequest, (await h.Client.PostAsJsonAsync("/api/Auth/me/email/confirm", new { email = "new@example.invalid", token })).StatusCode);
        using (var scope = h.Scope()) scope.ServiceProvider.GetRequiredService<IOptions<DataProtectionTokenProviderOptions>>().Value.TokenLifespan = TimeSpan.FromTicks(-1);
        await Login(h, "verify-a", Password);
        Assert.Equal(HttpStatusCode.BadRequest, (await h.Client.PostAsJsonAsync("/api/Auth/me/email/confirm", new { email = "new@example.invalid", token })).StatusCode);
        using var check = h.Scope(); Assert.True(await check.ServiceProvider.GetRequiredService<AuthDbContext>().Users.AllAsync(u => u.Email == null));
    }
    [Fact]
    public async Task Smtp_failure_is_explicit_and_does_not_bind_email_or_change_security_stamp()
    {
        await using var h = new MapDraftTestHost(withIdentity: true); await h.StartAsync();
        await Register(h, "smtp-failure"); h.Email.Fail = true;
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await h.Client.PostAsJsonAsync("/api/Auth/me/email/request", new { email = "not-sent@example.invalid", currentPassword = Password })).StatusCode);
        var profile = await h.Client.GetFromJsonAsync<JsonElement>("/api/Auth/me");
        Assert.Equal(JsonValueKind.Null, profile.GetProperty("email").ValueKind); Assert.False(profile.GetProperty("emailVerified").GetBoolean());
        Assert.Equal(0, h.Email.VerificationCalls);
    }
    [Fact]
    public async Task Change_password_changes_only_signed_user_and_invalidates_new_stamp_bound_jwt()
    {
        await using var h = new MapDraftTestHost(withIdentity: true); await h.StartAsync();
        await Register(h, "password-b", "b@example.invalid"); await Register(h, "password-a");
        Assert.Equal(HttpStatusCode.BadRequest, (await h.Client.PostAsJsonAsync("/api/Auth/me/change-password", new { currentPassword = Password, newPassword = "New-test-password2!", userId = "password-b" })).StatusCode);
        (await h.Client.PostAsJsonAsync("/api/Auth/me/change-password", new { currentPassword = Password, newPassword = "New-test-password2!" })).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Unauthorized, (await h.Client.GetAsync("/api/Auth/me")).StatusCode);
        await Login(h, "password-b", Password); await Login(h, "password-a", "New-test-password2!");
    }
    [Fact]
    public async Task Forgot_reset_targets_email_owner_not_current_session_and_wrong_subject_token_is_rejected()
    {
        await using var h = new MapDraftTestHost(withIdentity: true); await h.StartAsync();
        await Register(h, "reset-b", "reset-b@example.invalid"); await Register(h, "reset-a");
        (await h.Client.PostAsJsonAsync("/api/Auth/forgot-password", new { usernameOrEmail = "reset-b@example.invalid" })).EnsureSuccessStatusCode();
        Assert.Equal("reset-b@example.invalid", h.Email.ResetRecipient);
        Assert.Equal(HttpStatusCode.BadRequest, (await h.Client.PostAsJsonAsync("/api/Auth/reset-password", new { usernameOrEmail = "reset-a", token = h.Email.ResetToken, newPassword = "Reset-password2!" })).StatusCode);
        (await h.Client.PostAsJsonAsync("/api/Auth/reset-password", new { usernameOrEmail = "reset-b@example.invalid", token = h.Email.ResetToken, newPassword = "Reset-password2!" })).EnsureSuccessStatusCode();
        await Login(h, "reset-a", Password); await Login(h, "reset-b", "Reset-password2!");
    }
    [Fact]
    public async Task Email_lookup_cannot_be_shadowed_by_another_accounts_email_shaped_username()
    {
        await using var h = new MapDraftTestHost(withIdentity: true); await h.StartAsync();
        await Register(h, "mail-owner", "mail-owner@example.invalid");
        await Register(h, "mail-owner@example.invalid", "different-owner@example.invalid");
        (await h.Client.PostAsJsonAsync("/api/Auth/forgot-password", new { usernameOrEmail = "mail-owner@example.invalid" })).EnsureSuccessStatusCode();
        Assert.Equal("mail-owner@example.invalid", h.Email.ResetRecipient);
    }
    [Fact]
    public async Task Confirmation_checks_uniqueness_again_after_another_account_reserves_address()
    {
        await using var h = new MapDraftTestHost(withIdentity: true); await h.StartAsync();
        var a = await Register(h, "race-a");
        (await h.Client.PostAsJsonAsync("/api/Auth/me/email/request", new { email = "race@example.invalid", currentPassword = Password })).EnsureSuccessStatusCode();
        var token = h.Email.Token;
        await Register(h, "race-b", "RACE@example.invalid");
        h.Client.DefaultRequestHeaders.Authorization = new("Bearer", a);
        Assert.Equal(HttpStatusCode.Conflict, (await h.Client.PostAsJsonAsync("/api/Auth/me/email/confirm", new { email = "race@example.invalid", token })).StatusCode);
        using var scope = h.Scope(); var db = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
        Assert.Single(await db.Users.Where(u => u.NormalizedEmail == "RACE@EXAMPLE.INVALID").ToListAsync());
    }
}
