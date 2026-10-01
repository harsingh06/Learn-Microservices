using System.Net;
using Polly.CircuitBreaker;
using Polly.RateLimiting;
using Polly.Timeout;

namespace ApplicationService.Clients;

// What a result from a dependency MEANS — the resilience POLICY (retries,
// breaker, bulkhead, timeouts) lives in the HttpClient's pipeline instead
// (DependencyResilience, wired in Program.cs).
internal static class DependencyCall
{
    // null           -> the resource doesn't exist (404)
    // throws DependencyUnavailableException -> the dependency couldn't answer
    // throws anything else -> a bug on our side (surfaces as a 500)
    public static async Task<T?> GetOrNullAsync<T>(
        HttpClient http, string dependency, string path, CancellationToken ct) where T : class
    {
        HttpResponseMessage response;
        try
        {
            response = await http.GetAsync(path, ct);
        }
        // The caller giving up isn't an outage: let their cancellation through.
        catch (Exception ex) when (IsUnavailable(ex) && !ct.IsCancellationRequested)
        {
            throw new DependencyUnavailableException(dependency, ex);
        }

        if (response.StatusCode == HttpStatusCode.NotFound)
            return null;

        // Still failing after the retries: the dependency is unhealthy.
        if (IsTransient(response.StatusCode))
            throw new DependencyUnavailableException(
                dependency, new HttpRequestException($"{dependency} returned {(int)response.StatusCode}.", null, response.StatusCode));

        // Any other 4xx means OUR request is wrong — a bug, so a 500 is honest.
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<T>(ct);
    }

    private static bool IsUnavailable(Exception ex) => ex is
        BrokenCircuitException            // circuit open: failed instantly, no network call
        or RateLimiterRejectedException   // bulkhead full: too many calls already in flight
        or TimeoutRejectedException       // attempt or total timeout
        or HttpRequestException;          // connection refused / reset / DNS

    private static bool IsTransient(HttpStatusCode status) =>
        (int)status >= 500 || status is HttpStatusCode.RequestTimeout or HttpStatusCode.TooManyRequests;
}
