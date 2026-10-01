using System.Net;
using System.Net.Http.Json;
using JobService.Auth;
using JobService.Data;
using JobService.Endpoints;
using JobService.Models;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;

namespace JobService.Tests.Auth;

// Who may call what: the REAL routes (MapJobEndpoints) and the REAL
// policies (AddAtsAuthorization), with Entra replaced by TestAuthHandler. Token
// validation itself is Microsoft.Identity.Web's job; these tests pin OUR rules.
public sealed class AuthorizationTests : IAsyncDisposable
{
    private const string Recruiter = AtsRoles.Recruiter;
    private const string HiringManager = AtsRoles.HiringManager;
    private const string NoRole = "";

    private readonly IJobRepository _repository = Substitute.For<IJobRepository>();
    private WebApplication? _app;

    public AuthorizationTests()
    {
        _repository.ListAsync(default).ReturnsForAnyArgs(new List<Job>());
        _repository.GetAsync("j-1").ReturnsForAnyArgs(new Job { Id = "j-1", Title = "Engineer", Description = "Builds", Location = "Remote" });
    }

    [Theory]
    [InlineData(Recruiter, HttpStatusCode.OK)]
    [InlineData(HiringManager, HttpStatusCode.OK)]
    [InlineData(NoRole, HttpStatusCode.Forbidden)]
    public async Task Listing_jobs_needs_either_role(string role, HttpStatusCode expected)
    {
        var response = await SendAsync(HttpMethod.Get, "/jobs", role);
        Assert.Equal(expected, response.StatusCode);
    }

    [Theory]
    [InlineData(Recruiter, HttpStatusCode.OK)]
    [InlineData(HiringManager, HttpStatusCode.OK)]
    public async Task Reading_one_job_needs_either_role(string role, HttpStatusCode expected)
    {
        var response = await SendAsync(HttpMethod.Get, "/jobs/j-1", role);
        Assert.Equal(expected, response.StatusCode);
    }

    [Theory]
    [InlineData(Recruiter, HttpStatusCode.Created)]
    [InlineData(HiringManager, HttpStatusCode.Forbidden)]
    public async Task Only_recruiters_create_jobs(string role, HttpStatusCode expected)
    {
        var response = await SendAsync(HttpMethod.Post, "/jobs", role,
            body: new CreateJobRequest("Tester", "Tests things", "Remote"));
        Assert.Equal(expected, response.StatusCode);
    }

    [Theory]
    [InlineData(Recruiter, HttpStatusCode.OK)]
    [InlineData(HiringManager, HttpStatusCode.Forbidden)]
    public async Task Only_recruiters_update_jobs(string role, HttpStatusCode expected)
    {
        var response = await SendAsync(HttpMethod.Put, "/jobs/j-1", role,
            body: new UpdateJobRequest("Senior Engineer", "Builds", "Remote"));
        Assert.Equal(expected, response.StatusCode);
    }

    [Fact]
    public async Task No_token_is_401()
    {
        var response = await SendAsync(HttpMethod.Get, "/jobs", role: null);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Right_role_without_the_api_scope_is_403()
    {
        var response = await SendAsync(HttpMethod.Get, "/jobs", Recruiter, withScope: false);
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    // The fallback policy: an endpoint someone forgets to give a policy is still
    // closed to anonymous callers and tokens without the scope.
    [Theory]
    [InlineData(null, true, HttpStatusCode.Unauthorized)]
    [InlineData(NoRole, false, HttpStatusCode.Forbidden)]
    [InlineData(NoRole, true, HttpStatusCode.OK)]
    public async Task Endpoints_without_a_policy_are_protected_by_default(string? role, bool withScope, HttpStatusCode expected)
    {
        var response = await SendAsync(HttpMethod.Get, "/no-explicit-policy", role, withScope);
        Assert.Equal(expected, response.StatusCode);
    }

    // role == null -> anonymous; "" -> signed in without a role.
    private async Task<HttpResponseMessage> SendAsync(
        HttpMethod method, string path, string? role, bool withScope = true, object? body = null)
    {
        var client = await ClientAsync();
        var request = new HttpRequestMessage(method, path);
        if (role is not null)
        {
            request.Headers.Add("X-Test-User", "test-user");
            request.Headers.Add("X-Test-Roles", role);
            if (withScope)
                request.Headers.Add("X-Test-Scopes", AuthSetup.RequiredScope);
        }
        if (body is not null)
            request.Content = JsonContent.Create(body);
        return await client.SendAsync(request);
    }

    private async Task<HttpClient> ClientAsync()
    {
        if (_app is null)
        {
            var builder = WebApplication.CreateBuilder();
            builder.WebHost.UseTestServer();
            builder.Services.AddSingleton(_repository);
            builder.Services.AddAuthentication(TestAuthHandler.SchemeName)
                .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>(TestAuthHandler.SchemeName, _ => { });
            builder.Services.AddAtsAuthorization(); // the real policies

            _app = builder.Build();
            _app.UseAuthentication();
            _app.UseAuthorization();
            _app.MapJobEndpoints(); // the real routes
            _app.MapGet("/no-explicit-policy", () => "ok");
            await _app.StartAsync();
        }
        return _app.GetTestClient();
    }

    public async ValueTask DisposeAsync()
    {
        if (_app is not null)
            await _app.DisposeAsync();
    }
}
