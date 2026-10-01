using System.Net;
using System.Net.Http.Json;
using ApplicationService.Auth;
using ApplicationService.Clients;
using ApplicationService.Data;
using ApplicationService.Endpoints;
using ApplicationService.Models;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;

namespace ApplicationService.Tests.Auth;

// Who may call what: the REAL routes (MapApplicationEndpoints) and the REAL
// policies (AddAtsAuthorization), with Entra replaced by TestAuthHandler and the
// downstream clients substituted (On-Behalf-Of is exercised end-to-end, not here).
public sealed class AuthorizationTests : IAsyncDisposable
{
    private const string Recruiter = AtsRoles.Recruiter;
    private const string HiringManager = AtsRoles.HiringManager;
    private const string NoRole = "";

    private readonly IApplicationRepository _repository = Substitute.For<IApplicationRepository>();
    private readonly ICandidateClient _candidates = Substitute.For<ICandidateClient>();
    private readonly IJobClient _jobs = Substitute.For<IJobClient>();
    private WebApplication? _app;

    public AuthorizationTests()
    {
        _repository.ListAsync(default, default).ReturnsForAnyArgs(new List<JobApplication>());
        _repository.GetAsync("a-1").ReturnsForAnyArgs(new JobApplication { Id = "a-1", CandidateId = "c-1", JobId = "j-1" });
        _repository.FindByCandidateAndJobAsync(default!, default!).ReturnsForAnyArgs((JobApplication?)null);
        _candidates.GetAsync(default!).ReturnsForAnyArgs(new CandidateSummary("c-1", "Ada"));
        _jobs.GetAsync(default!).ReturnsForAnyArgs(new JobSummary("j-1", "Engineer"));
    }

    [Theory]
    [InlineData(Recruiter, HttpStatusCode.OK)]
    [InlineData(HiringManager, HttpStatusCode.OK)]
    [InlineData(NoRole, HttpStatusCode.Forbidden)]
    public async Task Listing_applications_needs_either_role(string role, HttpStatusCode expected)
    {
        var response = await SendAsync(HttpMethod.Get, "/applications", role);
        Assert.Equal(expected, response.StatusCode);
    }

    [Theory]
    [InlineData(Recruiter, HttpStatusCode.OK)]
    [InlineData(HiringManager, HttpStatusCode.OK)]
    public async Task Reading_one_application_needs_either_role(string role, HttpStatusCode expected)
    {
        var response = await SendAsync(HttpMethod.Get, "/applications/a-1", role);
        Assert.Equal(expected, response.StatusCode);
    }

    [Theory]
    [InlineData(Recruiter, HttpStatusCode.Created)]
    [InlineData(HiringManager, HttpStatusCode.Forbidden)]
    public async Task Only_recruiters_submit_applications(string role, HttpStatusCode expected)
    {
        var response = await SendAsync(HttpMethod.Post, "/applications", role,
            body: new SubmitApplicationRequest("c-1", "j-1"));
        Assert.Equal(expected, response.StatusCode);
    }

    [Fact]
    public async Task A_forbidden_submit_never_reaches_the_other_services()
    {
        await SendAsync(HttpMethod.Post, "/applications", HiringManager, body: new SubmitApplicationRequest("c-1", "j-1"));

        await _candidates.DidNotReceiveWithAnyArgs().GetAsync(default!);
        await _repository.DidNotReceiveWithAnyArgs().AddAsync(default!);
    }

    [Theory]
    [InlineData(HiringManager, HttpStatusCode.OK)]
    [InlineData(Recruiter, HttpStatusCode.Forbidden)]
    public async Task Only_hiring_managers_review_applications(string role, HttpStatusCode expected)
    {
        var response = await SendAsync(HttpMethod.Put, "/applications/a-1/status", role,
            body: new UpdateStatusRequest("InReview"));
        Assert.Equal(expected, response.StatusCode);
    }

    [Fact]
    public async Task No_token_is_401()
    {
        var response = await SendAsync(HttpMethod.Get, "/applications", role: null);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Right_role_without_the_api_scope_is_403()
    {
        var response = await SendAsync(HttpMethod.Get, "/applications", Recruiter, withScope: false);
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
            builder.Services.AddSingleton(_candidates);
            builder.Services.AddSingleton(_jobs);
            builder.Services.AddAuthentication(TestAuthHandler.SchemeName)
                .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>(TestAuthHandler.SchemeName, _ => { });
            builder.Services.AddAtsAuthorization(); // the real policies

            _app = builder.Build();
            _app.UseAuthentication();
            _app.UseAuthorization();
            _app.MapApplicationEndpoints(); // the real routes
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
