namespace ApplicationService.Clients;

// This service's own view of a job — deliberately NOT a shared model with JobService.
public record JobSummary(string Id, string Title);

public interface IJobClient
{
    Task<JobSummary?> GetAsync(string id, CancellationToken ct = default);
}

public class JobClient(HttpClient http) : IJobClient
{
    public async Task<JobSummary?> GetAsync(string id, CancellationToken ct = default)
    {
        var response = await http.GetAsync($"/jobs/{id}", ct);
        if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
            return null;

        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<JobSummary>(ct);
    }
}
