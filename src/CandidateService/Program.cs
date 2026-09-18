using CandidateService.Data;
using CandidateService.Endpoints;
using Microsoft.Azure.Cosmos;
using Scalar.AspNetCore;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenApi();

// The React app (a different origin) calls this API directly in Phase 1 — no gateway yet.
builder.Services.AddCors(options => options.AddDefaultPolicy(policy =>
    policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));

// One CosmosClient per process (SDK guidance). Gateway mode lets it talk plain HTTP
// to the local emulator; the same code works against real Cosmos over HTTPS.
builder.Services.AddSingleton(_ =>
{
    var cosmos = builder.Configuration.GetSection("Cosmos");
    return new CosmosClient(cosmos["Endpoint"], cosmos["Key"], new CosmosClientOptions
    {
        ConnectionMode = ConnectionMode.Gateway,
        LimitToEndpoint = true,
        UseSystemTextJsonSerializerWithOptions = new(System.Text.Json.JsonSerializerDefaults.Web)
    });
});
builder.Services.AddSingleton(sp =>
{
    var cosmos = builder.Configuration.GetSection("Cosmos");
    return sp.GetRequiredService<CosmosClient>().GetContainer(cosmos["Database"], cosmos["Container"]);
});
builder.Services.AddSingleton<ICandidateRepository, CosmosCandidateRepository>();

var app = builder.Build();

app.UseCors();
app.MapOpenApi();
app.MapScalarApiReference(); // interactive API docs at /scalar/v1
app.MapCandidateEndpoints();
app.MapGet("/health", () => Results.Ok(new { status = "ok", service = "candidate-service" }));

await CosmosInitializer.EnsureCreatedAsync(
    app.Services.GetRequiredService<CosmosClient>(),
    app.Configuration["Cosmos:Database"]!,
    app.Configuration["Cosmos:Container"]!,
    app.Logger);

app.Run();
