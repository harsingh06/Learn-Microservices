using JobService.Models;

namespace JobService.Data;

// The one abstraction this service needs: it lets unit tests run without Cosmos.
public interface IJobRepository
{
    Task<Job?> GetAsync(string id, CancellationToken ct = default);
    Task<IReadOnlyList<Job>> ListAsync(CancellationToken ct = default);
    Task AddAsync(Job job, CancellationToken ct = default);
    Task UpdateAsync(Job job, CancellationToken ct = default);
}
