using ApplicationService.Models;

namespace ApplicationService.Data;

// The one abstraction this service needs: it lets unit tests run without Cosmos.
public interface IApplicationRepository
{
    Task<JobApplication?> GetAsync(string id, CancellationToken ct = default);
    Task<IReadOnlyList<JobApplication>> ListAsync(string? candidateId, string? jobId, CancellationToken ct = default);
    Task<JobApplication?> FindByCandidateAndJobAsync(string candidateId, string jobId, CancellationToken ct = default);
    Task AddAsync(JobApplication application, CancellationToken ct = default);
    Task UpdateAsync(JobApplication application, CancellationToken ct = default);
}
