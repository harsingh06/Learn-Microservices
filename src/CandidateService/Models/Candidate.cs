namespace CandidateService.Models;

// Cosmos document. Serialized camelCase, so Id becomes the "id" Cosmos requires.
public class Candidate
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string FullName { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}

public record CreateCandidateRequest(string FullName, string Email);

public record UpdateCandidateRequest(string FullName, string Email);
