using CandidateService.Models;

namespace CandidateService.Data;

// The one abstraction this service needs: it lets unit tests run without Cosmos.
public interface ICandidateRepository
{
    Task<Candidate?> GetAsync(string id, CancellationToken ct = default);
    Task<IReadOnlyList<Candidate>> SearchAsync(string? search, CancellationToken ct = default);
    Task AddAsync(Candidate candidate, CancellationToken ct = default);
    Task UpdateAsync(Candidate candidate, CancellationToken ct = default);
}
