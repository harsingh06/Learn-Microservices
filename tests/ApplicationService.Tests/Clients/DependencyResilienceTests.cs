using System.Net;
using System.Net.Http.Json;
using ApplicationService.Clients;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Http.Resilience;
using Polly.CircuitBreaker;
using Polly.RateLimiting;

namespace ApplicationService.Tests.Clients;

// The clients as Program.cs wires them — DependencyResilience.Configure on a
// real IHttpClientFactory pipeline — with only the network swapped for a stub.
// Retry delays are zeroed so the tests don't sit through real backoff.
public class DependencyResilienceTests
{
    private readonly StubHandler _candidateApi = new();
    private readonly StubHandler _jobApi = new();

    private ServiceProvider Build(Action<HttpStandardResilienceOptions>? tweak = null)
    {
        void Configure(HttpStandardResilienceOptions o)
        {
            DependencyResilience.Configure(o);
            o.Retry.Delay = TimeSpan.Zero;
            tweak?.Invoke(o);
        }

        var services = new ServiceCollection();
        services.AddHttpClient<ICandidateClient, CandidateClient>(c => c.BaseAddress = new Uri("http://candidate"))
            .ConfigurePrimaryHttpMessageHandler(() => _candidateApi)
            .AddStandardResilienceHandler(Configure);
        services.AddHttpClient<IJobClient, JobClient>(c => c.BaseAddress = new Uri("http://job"))
            .ConfigurePrimaryHttpMessageHandler(() => _jobApi)
            .AddStandardResilienceHandler(Configure);
        return services.BuildServiceProvider();
    }

    [Fact]
    public async Task Retry_absorbs_a_transient_failure()
    {
        _candidateApi.Respond = (call, _) => Task.FromResult(call == 1 ? Status(HttpStatusCode.ServiceUnavailable) : Candidate());
        using var sp = Build();

        var candidate = await sp.GetRequiredService<ICandidateClient>().GetAsync("c-1");

        Assert.Equal("Ada Lovelace", candidate!.FullName);
        Assert.Equal(2, _candidateApi.Calls);
    }

    [Fact]
    public async Task Still_failing_after_retries_is_unavailable_not_missing()
    {
        _candidateApi.Respond = (_, _) => Task.FromResult(Status(HttpStatusCode.ServiceUnavailable));
        using var sp = Build();

        var ex = await Assert.ThrowsAsync<DependencyUnavailableException>(
            () => sp.GetRequiredService<ICandidateClient>().GetAsync("c-1"));

        Assert.Equal("CandidateService", ex.Dependency);
        Assert.Equal(4, _candidateApi.Calls); // 1 attempt + 3 retries
    }

    [Fact]
    public async Task Missing_candidate_is_null_and_not_retried()
    {
        _candidateApi.Respond = (_, _) => Task.FromResult(Status(HttpStatusCode.NotFound));
        using var sp = Build();

        Assert.Null(await sp.GetRequiredService<ICandidateClient>().GetAsync("c-404"));
        Assert.Equal(1, _candidateApi.Calls);
    }

    [Fact]
    public async Task Other_client_errors_are_bugs_not_outages()
    {
        _candidateApi.Respond = (_, _) => Task.FromResult(Status(HttpStatusCode.BadRequest));
        using var sp = Build();

        var ex = await Assert.ThrowsAsync<HttpRequestException>(
            () => sp.GetRequiredService<ICandidateClient>().GetAsync("c-1"));

        Assert.Equal(HttpStatusCode.BadRequest, ex.StatusCode);
        Assert.Equal(1, _candidateApi.Calls); // 400 is not transient: no retry
    }

    [Fact]
    public async Task Circuit_opens_fails_fast_then_recovers()
    {
        var healthy = false;
        _candidateApi.Respond = (_, _) => Task.FromResult(healthy ? Candidate() : Status(HttpStatusCode.InternalServerError));
        using var sp = Build(o => o.CircuitBreaker.BreakDuration = TimeSpan.FromSeconds(1));
        var client = sp.GetRequiredService<ICandidateClient>();

        // Failures pile up past the threshold (5 calls, 50% failing) and the circuit opens.
        await Assert.ThrowsAsync<DependencyUnavailableException>(() => client.GetAsync("c-1"));
        await Assert.ThrowsAsync<DependencyUnavailableException>(() => client.GetAsync("c-1"));

        // OPEN: rejected at once, without touching the network.
        var callsBefore = _candidateApi.Calls;
        var ex = await Assert.ThrowsAsync<DependencyUnavailableException>(() => client.GetAsync("c-1"));
        Assert.IsType<BrokenCircuitException>(ex.InnerException);
        Assert.Equal(callsBefore, _candidateApi.Calls);

        // After the break the service is back: the HALF-OPEN trial call succeeds and closes the circuit.
        healthy = true;
        await Task.Delay(TimeSpan.FromSeconds(1.2));
        Assert.NotNull(await client.GetAsync("c-1"));
        Assert.NotNull(await client.GetAsync("c-1"));
    }

    [Fact]
    public async Task Bulkhead_rejects_the_21st_concurrent_call_and_isolates_other_dependencies()
    {
        var gate = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        _candidateApi.Respond = async (_, ct) =>
        {
            await gate.Task.WaitAsync(ct); // CandidateService "hangs"
            return Candidate();
        };
        _jobApi.Respond = (_, _) => Task.FromResult(Job());
        using var sp = Build();

        // Fill the candidate compartment: 20 calls stuck in flight.
        var stuck = Enumerable.Range(0, 20)
            .Select(_ => sp.GetRequiredService<ICandidateClient>().GetAsync("c-1"))
            .ToList();
        await WaitUntil(() => _candidateApi.Calls == 20);

        // The 21st is rejected immediately instead of queueing behind them…
        var ex = await Assert.ThrowsAsync<DependencyUnavailableException>(
            () => sp.GetRequiredService<ICandidateClient>().GetAsync("c-1"));
        Assert.IsType<RateLimiterRejectedException>(ex.InnerException);

        // …while JobService, in its own compartment, is unaffected.
        Assert.NotNull(await sp.GetRequiredService<IJobClient>().GetAsync("j-1"));

        gate.SetResult();
        Assert.All(await Task.WhenAll(stuck), Assert.NotNull);
    }

    [Fact]
    public async Task Caller_cancellation_is_not_reported_as_an_outage()
    {
        _candidateApi.Respond = async (_, ct) =>
        {
            await Task.Delay(Timeout.Infinite, ct);
            return Candidate();
        };
        using var sp = Build();
        using var cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(100));

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => sp.GetRequiredService<ICandidateClient>().GetAsync("c-1", cts.Token));
    }

    private static HttpResponseMessage Status(HttpStatusCode code) => new(code);

    private static HttpResponseMessage Candidate() =>
        new(HttpStatusCode.OK) { Content = JsonContent.Create(new { id = "c-1", fullName = "Ada Lovelace" }) };

    private static HttpResponseMessage Job() =>
        new(HttpStatusCode.OK) { Content = JsonContent.Create(new { id = "j-1", title = "Engineer" }) };

    private static async Task WaitUntil(Func<bool> condition)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        while (!condition())
            await Task.Delay(10, timeout.Token);
    }

    // Stands in for the network: counts calls and answers via Respond(callNumber, ct).
    // A new response per call — the pipeline disposes the ones it retries.
    private sealed class StubHandler : HttpMessageHandler
    {
        private int _calls;

        public int Calls => Volatile.Read(ref _calls);

        public Func<int, CancellationToken, Task<HttpResponseMessage>> Respond { get; set; } =
            (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK));

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct) =>
            Respond(Interlocked.Increment(ref _calls), ct);
    }
}
