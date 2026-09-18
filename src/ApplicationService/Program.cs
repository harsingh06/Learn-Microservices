using ApplicationService.Clients;
using ApplicationService.Data;
using ApplicationService.Endpoints;
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
builder.Services.AddSingleton<IApplicationRepository, CosmosApplicationRepository>();

// Typed HTTP clients for the sync existence checks against the owning services.
builder.Services.AddHttpClient<ICandidateClient, CandidateClient>(client =>
    client.BaseAddress = new Uri(builder.Configuration["Services:CandidateApi"]!));
builder.Services.AddHttpClient<IJobClient, JobClient>(client =>
    client.BaseAddress = new Uri(builder.Configuration["Services:JobApi"]!));

var app = builder.Build();

app.UseCors();
app.MapOpenApi();
app.MapScalarApiReference(); // interactive API docs at /scalar/v1
app.MapApplicationEndpoints();
app.MapGet("/health", () => Results.Ok(new { status = "ok", service = "application-service" }));

await CosmosInitializer.EnsureCreatedAsync(
    app.Services.GetRequiredService<CosmosClient>(),
    app.Configuration["Cosmos:Database"]!,
    app.Configuration["Cosmos:Container"]!,
    app.Logger);

app.Run();
