namespace ApplicationService.Clients;

// This service's own view of a job — deliberately NOT a shared model with JobService.
public record JobSummary(string Id, string Title);

public interface IJobClient
{
    // null when the job doesn't exist; throws DependencyUnavailableException
    // when JobService can't answer.
    Task<JobSummary?> GetAsync(string id, CancellationToken ct = default);
}

// Resilience comes from the HttpClient's pipeline (Program.cs) — see CandidateClient.
public class JobClient(HttpClient http) : IJobClient
{
    public Task<JobSummary?> GetAsync(string id, CancellationToken ct = default) =>
        DependencyCall.GetOrNullAsync<JobSummary>(http, "JobService", $"/jobs/{id}", ct);
}
