// API Gateway: the single origin the browser talks to for all API calls.
// Pure configuration — routing lives in appsettings.json ("ReverseProxy" section),
// overridable per environment via standard .NET config environment variables.
// Future cross-cutting concerns (auth, rate limiting, resiliency) belong here,
// not in the individual services.
var builder = WebApplication.CreateBuilder(args);

// CORS is enforced once, at the edge, instead of in every service.
builder.Services.AddCors(options => options.AddDefaultPolicy(policy =>
    policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));

builder.Services.AddReverseProxy()
    .LoadFromConfig(builder.Configuration.GetSection("ReverseProxy"));

var app = builder.Build();

app.UseCors();
app.MapGet("/health", () => Results.Ok(new { status = "ok", service = "api-gateway" }));
app.MapReverseProxy();

app.Run();
