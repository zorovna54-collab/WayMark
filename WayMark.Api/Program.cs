using Microsoft.EntityFrameworkCore;
using WayMark.Api.Data;
using Microsoft.AspNetCore.Identity;
using Microsoft.OpenApi;
using WayMark.Api.Services;
using WayMark.Api.Services.Routing;
using WayMark.Api.Security;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddWayMarkSecurity(builder.Configuration);

// Add services to the container.
// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddControllers();
builder.Services.Configure<EmailTestOptions>(
    builder.Configuration.GetSection(EmailTestOptions.SectionName));
builder.Services.AddScoped<ISmtpEmailService, SmtpEmailService>();
builder.Services.AddSingleton<DijkstraRouter>();
builder.Services.AddScoped<IRoutePlanner, RoutePlanner>();

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
builder.Services.AddDbContext<WayMarkDbContext>(options =>
    options.UseSqlServer(
        builder.Configuration.GetConnectionString("WayMarkDatabase"),
        sqlServer => sqlServer.MigrationsHistoryTable("__EFMigrationsHistory")));

builder.Services.AddDbContext<AuthDbContext>(options =>
    options.UseSqlServer(
        builder.Configuration.GetConnectionString("WayMarkDatabase"),
        sqlServer => sqlServer.MigrationsHistoryTable("__AuthMigrationsHistory")));
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
    .AddEntityFrameworkStores<AuthDbContext>();
var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
if (app.Environment.IsDevelopment())
{
    app.UseCors("Development");
}

app.UseAuthentication();
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
