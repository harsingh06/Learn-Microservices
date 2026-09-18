namespace ApplicationService.Clients;

// This service's own view of a candidate — deliberately NOT a shared model with
// CandidateService. It only names the fields this service actually uses.
public record CandidateSummary(string Id, string FullName);

public interface ICandidateClient
{
    Task<CandidateSummary?> GetAsync(string id, CancellationToken ct = default);
}

public class CandidateClient(HttpClient http) : ICandidateClient
{
    public async Task<CandidateSummary?> GetAsync(string id, CancellationToken ct = default)
    {
        var response = await http.GetAsync($"/candidates/{id}", ct);
        if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
            return null;

        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<CandidateSummary>(ct);
    }
}
