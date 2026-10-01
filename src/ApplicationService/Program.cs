using ApplicationService.Auth;
using ApplicationService.Clients;
using ApplicationService.Data;
using ApplicationService.Endpoints;
using Microsoft.Azure.Cosmos;
using Microsoft.Identity.Web;
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

// Every request needs an Entra ID access token for this API; endpoints add role
// policies on top (Auth/AuthSetup.cs, AUTH.md).
builder.Services.AddAtsAuthentication(builder.Configuration);
builder.Services.AddAtsAuthorization();

// Typed HTTP clients for the sync existence checks against the owning services.
// Each carries an On-Behalf-Of handler: before every call it exchanges the
// signed-in user's token for one whose audience is THAT service (scopes in
// DownstreamApis:*), so CandidateService / JobService authenticate the call —
// and see the same user and roles. The client classes don't change.
builder.Services.AddHttpClient<ICandidateClient, CandidateClient>(client =>
        client.BaseAddress = new Uri(builder.Configuration["Services:CandidateApi"]!))
    .AddMicrosoftIdentityUserAuthenticationHandler(
        "CandidateApi", builder.Configuration.GetSection("DownstreamApis:CandidateApi"));
builder.Services.AddHttpClient<IJobClient, JobClient>(client =>
        client.BaseAddress = new Uri(builder.Configuration["Services:JobApi"]!))
    .AddMicrosoftIdentityUserAuthenticationHandler(
        "JobApi", builder.Configuration.GetSection("DownstreamApis:JobApi"));

var app = builder.Build();

// CORS first, so browser preflight requests (which never carry a token) get answered.
app.UseCors();
app.UseAuthentication();
app.UseAuthorization();

// Docs and the health probe stay public; everything else is protected (fallback policy).
app.MapOpenApi().AllowAnonymous();
app.MapScalarApiReference().AllowAnonymous(); // interactive API docs at /scalar/v1
app.MapApplicationEndpoints();
app.MapGet("/health", () => Results.Ok(new { status = "ok", service = "application-service" })).AllowAnonymous();

await CosmosInitializer.EnsureCreatedAsync(
    app.Services.GetRequiredService<CosmosClient>(),
    app.Configuration["Cosmos:Database"]!,
    app.Configuration["Cosmos:Container"]!,
    app.Logger);

app.Run();
