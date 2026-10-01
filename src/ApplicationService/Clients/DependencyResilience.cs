using Microsoft.Extensions.Http.Resilience;

namespace ApplicationService.Clients;

// Resilience policy for calls to the services this one depends on. Applied per
// typed client in Program.cs, so each dependency gets its OWN pipeline — its own
// bulkhead and its own circuit breaker (a failing CandidateService can't stop
// calls to JobService). The pipeline runs, outermost first:
//
//   bulkhead -> total timeout -> retry -> circuit breaker -> attempt timeout -> HTTP
//
// The library defaults suit high-traffic services; the values below are tuned
// for this app's low traffic and scale-to-zero cold starts.
public static class DependencyResilience
{
    public static void Configure(HttpStandardResilienceOptions options)
    {
        // Bulkhead: at most 20 calls in flight to this dependency; the 21st is
        // rejected at once (no queue) instead of piling up behind a slow service.
        options.RateLimiter.DefaultRateLimiterOptions.PermitLimit = 20;
        options.RateLimiter.DefaultRateLimiterOptions.QueueLimit = 0;

        // Per attempt: long enough for a cold start (apps scale to zero; the first
        // request can take ~20 s). Tighter would turn every cold start into a failure.
        options.AttemptTimeout.Timeout = TimeSpan.FromSeconds(25);

        // Whole call, retries included — the most a user ever waits on a dependency.
        options.TotalRequestTimeout.Timeout = TimeSpan.FromSeconds(60);

        // Retry (defaults kept): 3 retries, exponential backoff with jitter, only
        // on transient failures (5xx, 408, 429, connection errors, timeouts). Safe
        // here because every call through these clients is a GET.

        // Circuit breaker: trip when half the calls in the last 60 s failed — once
        // at least 5 were made (the default of 100 would never trip at our traffic).
        // While open, calls fail instantly for 15 s; then one trial call decides.
        // (The library requires SamplingDuration >= 2 x AttemptTimeout.)
        options.CircuitBreaker.FailureRatio = 0.5;
        options.CircuitBreaker.MinimumThroughput = 5;
        options.CircuitBreaker.SamplingDuration = TimeSpan.FromSeconds(60);
        options.CircuitBreaker.BreakDuration = TimeSpan.FromSeconds(15);
    }
}
