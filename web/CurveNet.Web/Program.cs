using System.Text.Json;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.RateLimiting;

var builder = WebApplication.CreateBuilder(args);

// Защита Kestrel: лимит тела запроса и сокрытие заголовка сервера
builder.WebHost.ConfigureKestrel(options =>
{
    options.Limits.MaxRequestBodySize = 512 * 1024; // 512 КБ
    options.AddServerHeader = false;
});

builder.Services.AddCors(o => o.AddDefaultPolicy(p =>
    p.AllowAnyOrigin().WithMethods("GET", "POST").WithHeaders("Content-Type")));

// Ограничение частоты запросов (Rate Limiting)
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy("predict", context =>
        RateLimitPartition.GetFixedWindowLimiter(
            context.Connection.RemoteIpAddress?.ToString() ?? "anon",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 15,
                Window = TimeSpan.FromSeconds(10),
                QueueLimit = 2
            }));
    options.AddPolicy("save_sample", context =>
        RateLimitPartition.GetFixedWindowLimiter(
            context.Connection.RemoteIpAddress?.ToString() ?? "anon",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 5,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0
            }));
});

// Регистрация сервисов инференса через Dependency Injection
builder.Services.AddSingleton<IModelRunner, OnnxModelRunner>();
builder.Services.AddSingleton<CurvePredictService>();

var app = builder.Build();

app.UseCors();

// Базовые заголовки безопасности HTTP
app.Use(async (context, next) =>
{
    var headers = context.Response.Headers;
    headers.XContentTypeOptions = "nosniff";
    headers.XFrameOptions = "SAMEORIGIN";
    headers["Referrer-Policy"] = "strict-origin-when-cross-origin";
    headers.ContentSecurityPolicy =
        "default-src 'self'; " +
        "script-src 'self' https://cdn.jsdelivr.net; " +
        "style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; " +
        "font-src 'self' https://cdn.jsdelivr.net; " +
        "img-src 'self' data:; " +
        "connect-src 'self';";

    await next();
});

app.UseRateLimiter();
app.UseDefaultFiles();
app.UseStaticFiles();

app.MapGet("/api/classes", () =>
    CurveConfig.AllClasses.Select(c => new
    {
        key = c.Key,
        name = c.Name,
        isCurve = c.IsCurve,
        closed = c.Closed,
        nStrokes = c.NStrokes
    }));

app.MapPost("/api/predict", async (PredictRequestDto req, CurvePredictService svc, CancellationToken ct) =>
{
    try
    {
        var res = await svc.PredictAsync(req, ct);
        return Results.Ok(res);
    }
    catch (OperationCanceledException)
    {
        return Results.StatusCode(499);
    }
    catch (Exception ex)
    {
        return Results.BadRequest(new { ok = false, message = ex.Message });
    }
}).RequireRateLimiting("predict");

app.MapPost("/api/save-sample", (SaveSampleRequestDto req, CurvePredictService svc) =>
{
    if (req.Strokes == null || req.Strokes.Length == 0 || req.Strokes.Length > 200)
        return Results.BadRequest(new { ok = false, message = "Некорректные данные холста." });

    try
    {
        var cls = CurveConfig.GetClass(req.ClassKey);
        var (fileName, total) = svc.SaveSample(req);
        return Results.Ok(new
        {
            ok = true,
            fileName,
            className = cls.Name,
            total
        });
    }
    catch (Exception ex)
    {
        return Results.BadRequest(new { ok = false, message = ex.Message });
    }
}).RequireRateLimiting("save_sample");

// Режим быстрой проверки совпадения C# и MATLAB по контрольному примеру (--verify)
if (args.Contains("--verify"))
{
    using var scope = app.Services.CreateScope();
    var svc = scope.ServiceProvider.GetRequiredService<CurvePredictService>();
    string verPath = Path.Combine(app.Environment.ContentRootPath, "Models", "verification.json");
    using var doc = JsonDocument.Parse(File.ReadAllText(verPath));
    var root = doc.RootElement;

    var strokes = JsonSerializer.Deserialize<double[][][]>(root.GetProperty("strokes").GetRawText())!;
    double span = root.GetProperty("canvasSpan").GetDouble();

    var r = svc.Predict(new PredictRequestDto(strokes, span));
    Console.WriteLine($"=== Сверка C# vs MATLAB ===");
    Console.WriteLine($"MATLAB class:      {root.GetProperty("predClass").GetString()}");
    Console.WriteLine($"C#     class:      {r.Class}");
    Console.WriteLine($"MATLAB confidence: {root.GetProperty("confidence").GetDouble():F6}");
    Console.WriteLine($"C#     confidence: {r.Confidence:F6}");
    Console.WriteLine($"MATLAB residual:   {root.GetProperty("residual").GetDouble():F6}");
    Console.WriteLine($"C#     residual:   {r.Residual:F6}");
    Console.WriteLine($"MATLAB equation:   {root.GetProperty("equation").GetString()}");
    Console.WriteLine($"C#     equation:   {r.Equation}");
    return;
}

app.Run();
