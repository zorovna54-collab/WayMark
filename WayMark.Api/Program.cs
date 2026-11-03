using Microsoft.EntityFrameworkCore;
using WayMark.Api.Data;
using Microsoft.AspNetCore.Identity;
using Microsoft.OpenApi;
using WayMark.Api.Services;
using WayMark.Api.Services.Routing;
using WayMark.Api.Security;
using WayMark.Api.Services.MapDrafts;

var builder = WebApplication.CreateBuilder(args);
var e2e = E2ESafetyProfile.ReadAndApply(builder.Configuration, builder.Environment);
builder.Services.AddWayMarkSecurity(builder.Configuration);
builder.Services.AddPasswordResetLimits();
builder.Services.Configure<DataProtectionTokenProviderOptions>(o => o.TokenLifespan = TimeSpan.FromMinutes(30));

// Add services to the container.
// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddControllers();
builder.Services.Configure<EmailTestOptions>(
    builder.Configuration.GetSection(EmailTestOptions.SectionName));
if (e2e is null) builder.Services.AddScoped<ISmtpEmailService, SmtpEmailService>();
else builder.Services.AddScoped<ISmtpEmailService, E2EDisabledEmail>();
builder.Services.AddSingleton<DijkstraRouter>();
builder.Services.AddScoped<IRoutePlanner, RoutePlanner>();
builder.Services.AddMapDraftFoundation(builder.Configuration);

builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "WayMark API",
        Version = "v1"
    });

    options.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        Description = "Nhập JWT token để gọi các API được bảo vệ."
    });

    options.AddSecurityRequirement(document =>
        new OpenApiSecurityRequirement
        {
            [new OpenApiSecuritySchemeReference("Bearer", document)] = []
        });
});
builder.Services.AddCors(options => options.AddPolicy("Development", policy =>
    policy
        .SetIsOriginAllowed(origin =>
            Uri.TryCreate(origin, UriKind.Absolute, out var uri) && uri.IsLoopback)
        .WithMethods("GET", "POST", "PUT", "DELETE", "OPTIONS")
        .AllowAnyHeader()));
if (e2e is not null)
    builder.Services.AddCors(options => options.AddPolicy("MapDraftE2E", policy =>
        policy.WithOrigins(e2e.AllowedOrigin).WithMethods("GET", "POST", "PUT", "DELETE", "OPTIONS").AllowAnyHeader()));
builder.Services.AddWayMarkDatabases(builder.Configuration, e2e);
builder.Services
    .AddIdentityCore<IdentityUser>(options =>
    {
        options.Password.RequiredLength = 8;
        options.Password.RequireDigit = true;
        options.Password.RequireLowercase = true;
        options.Password.RequireUppercase = true;
        options.Password.RequireNonAlphanumeric = false;

        options.User.RequireUniqueEmail = false;
    })
    .AddRoles<IdentityRole>()
    .AddEntityFrameworkStores<AuthDbContext>()
    .AddDefaultTokenProviders();
builder.Services.AddE2EStartupCheck(e2e);
var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment() || e2e is not null)
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
if (e2e is not null) app.UseCors("MapDraftE2E");
else if (app.Environment.IsDevelopment())
{
    app.UseCors("Development");
}

app.UseAuthentication();
app.UseRateLimiter();
app.UseAuthorization();

app.MapControllers();

var summaries = new[]
{
    "Freezing", "Bracing", "Chilly", "Cool", "Mild", "Warm", "Balmy", "Hot", "Sweltering", "Scorching"
};

app.MapGet("/weatherforecast", () =>
{
    var forecast =  Enumerable.Range(1, 5).Select(index =>
        new WeatherForecast
        (
            DateOnly.FromDateTime(DateTime.Now.AddDays(index)),
            Random.Shared.Next(-20, 55),
            summaries[Random.Shared.Next(summaries.Length)]
        ))
        .ToArray();
    return forecast;
})
.WithName("GetWeatherForecast");

app.Run();

record WeatherForecast(DateOnly Date, int TemperatureC, string? Summary)
{
    public int TemperatureF => 32 + (int)(TemperatureC / 0.5556);
}
