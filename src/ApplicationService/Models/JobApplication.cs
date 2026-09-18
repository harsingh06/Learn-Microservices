using System.Text.Json.Serialization;

namespace ApplicationService.Models;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum ApplicationStatus
{
    Submitted,
    InReview,
    Accepted,
    Rejected
}

// Cosmos document. CandidateName/JobTitle are snapshots taken at apply time so that
// listing applications never requires calling the other services (deliberate duplication).
public class JobApplication
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string CandidateId { get; set; } = string.Empty;
    public string JobId { get; set; } = string.Empty;
    public string CandidateName { get; set; } = string.Empty;
    public string JobTitle { get; set; } = string.Empty;
    public ApplicationStatus Status { get; set; } = ApplicationStatus.Submitted;
    public DateTime SubmittedAtUtc { get; set; } = DateTime.UtcNow;
}

public record SubmitApplicationRequest(string CandidateId, string JobId);

public record UpdateStatusRequest(string Status);

// The status workflow lives entirely inside this service.
public static class StatusTransitions
{
    private static readonly Dictionary<ApplicationStatus, ApplicationStatus[]> Allowed = new()
    {
        [ApplicationStatus.Submitted] = [ApplicationStatus.InReview, ApplicationStatus.Rejected],
        [ApplicationStatus.InReview] = [ApplicationStatus.Accepted, ApplicationStatus.Rejected],
        [ApplicationStatus.Accepted] = [],
        [ApplicationStatus.Rejected] = []
    };

    public static bool IsAllowed(ApplicationStatus from, ApplicationStatus to) =>
        Allowed[from].Contains(to);
}
