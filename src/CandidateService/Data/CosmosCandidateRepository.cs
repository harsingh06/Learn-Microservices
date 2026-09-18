using CandidateService.Models;
using Microsoft.Azure.Cosmos;

namespace CandidateService.Data;

public class CosmosCandidateRepository(Container container) : ICandidateRepository
{
    public async Task<Candidate?> GetAsync(string id, CancellationToken ct = default)
    {
        try
        {
            var response = await container.ReadItemAsync<Candidate>(id, new PartitionKey(id), cancellationToken: ct);
            return response.Resource;
        }
        catch (CosmosException ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public async Task<IReadOnlyList<Candidate>> SearchAsync(string? search, CancellationToken ct = default)
    {
        // Property names in Cosmos SQL match the stored JSON, which is camelCase.
        var query = string.IsNullOrWhiteSpace(search)
            ? new QueryDefinition("SELECT * FROM c ORDER BY c.createdAtUtc DESC")
            : new QueryDefinition("SELECT * FROM c WHERE CONTAINS(LOWER(c.fullName), @search)")
                .WithParameter("@search", search.Trim().ToLowerInvariant());

        var results = new List<Candidate>();
        using var iterator = container.GetItemQueryIterator<Candidate>(query);
        while (iterator.HasMoreResults)
        {
            results.AddRange(await iterator.ReadNextAsync(ct));
        }
        return results;
    }

    public async Task AddAsync(Candidate candidate, CancellationToken ct = default)
    {
        await container.CreateItemAsync(candidate, new PartitionKey(candidate.Id), cancellationToken: ct);
    }

    public async Task UpdateAsync(Candidate candidate, CancellationToken ct = default)
    {
        await container.ReplaceItemAsync(candidate, candidate.Id, new PartitionKey(candidate.Id), cancellationToken: ct);
    }
}
