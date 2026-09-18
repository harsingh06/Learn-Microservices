using ApplicationService.Models;
using Microsoft.Azure.Cosmos;

namespace ApplicationService.Data;

public class CosmosApplicationRepository(Container container) : IApplicationRepository
{
    public async Task<JobApplication?> GetAsync(string id, CancellationToken ct = default)
    {
        try
        {
            var response = await container.ReadItemAsync<JobApplication>(id, new PartitionKey(id), cancellationToken: ct);
            return response.Resource;
        }
        catch (CosmosException ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public async Task<IReadOnlyList<JobApplication>> ListAsync(string? candidateId, string? jobId, CancellationToken ct = default)
    {
        // Property names in Cosmos SQL match the stored JSON, which is camelCase.
        var sql = "SELECT * FROM c WHERE 1=1";
        if (!string.IsNullOrWhiteSpace(candidateId)) sql += " AND c.candidateId = @candidateId";
        if (!string.IsNullOrWhiteSpace(jobId)) sql += " AND c.jobId = @jobId";
        sql += " ORDER BY c.submittedAtUtc DESC";

        var query = new QueryDefinition(sql);
        if (!string.IsNullOrWhiteSpace(candidateId)) query = query.WithParameter("@candidateId", candidateId);
        if (!string.IsNullOrWhiteSpace(jobId)) query = query.WithParameter("@jobId", jobId);

        return await QueryAsync(query, ct);
    }

    public async Task<JobApplication?> FindByCandidateAndJobAsync(string candidateId, string jobId, CancellationToken ct = default)
    {
        var query = new QueryDefinition("SELECT * FROM c WHERE c.candidateId = @candidateId AND c.jobId = @jobId")
            .WithParameter("@candidateId", candidateId)
            .WithParameter("@jobId", jobId);

        var matches = await QueryAsync(query, ct);
        return matches.FirstOrDefault();
    }

    public async Task AddAsync(JobApplication application, CancellationToken ct = default)
    {
        await container.CreateItemAsync(application, new PartitionKey(application.Id), cancellationToken: ct);
    }

    public async Task UpdateAsync(JobApplication application, CancellationToken ct = default)
    {
        await container.ReplaceItemAsync(application, application.Id, new PartitionKey(application.Id), cancellationToken: ct);
    }

    private async Task<IReadOnlyList<JobApplication>> QueryAsync(QueryDefinition query, CancellationToken ct)
    {
        var results = new List<JobApplication>();
        using var iterator = container.GetItemQueryIterator<JobApplication>(query);
        while (iterator.HasMoreResults)
        {
            results.AddRange(await iterator.ReadNextAsync(ct));
        }
        return results;
    }
}
