namespace JobService.Models;

// Cosmos document. Serialized camelCase, so Id becomes the "id" Cosmos requires.
public class Job
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Title { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string Location { get; set; } = string.Empty;
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}

public record CreateJobRequest(string Title, string Description, string? Location);

public record UpdateJobRequest(string Title, string Description, string? Location);
