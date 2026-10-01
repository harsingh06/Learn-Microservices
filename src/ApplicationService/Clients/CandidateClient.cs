namespace ApplicationService.Clients;

// This service's own view of a candidate — deliberately NOT a shared model with
// CandidateService. It only names the fields this service actually uses.
public record CandidateSummary(string Id, string FullName);

public interface ICandidateClient
{
    // null when the candidate doesn't exist; throws DependencyUnavailableException
    // when CandidateService can't answer.
    Task<CandidateSummary?> GetAsync(string id, CancellationToken ct = default);
}

// The HttpClient arrives with the resilience pipeline already in its handler
// chain (Program.cs), so every call here gets the bulkhead, retries, circuit
// breaker and timeouts without this class knowing about them.
public class CandidateClient(HttpClient http) : ICandidateClient
{
    public Task<CandidateSummary?> GetAsync(string id, CancellationToken ct = default) =>
        DependencyCall.GetOrNullAsync<CandidateSummary>(http, "CandidateService", $"/candidates/{id}", ct);
}
