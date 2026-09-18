using JobService.Models;
using Microsoft.Azure.Cosmos;

namespace JobService.Data;

public class CosmosJobRepository(Container container) : IJobRepository
{
    public async Task<Job?> GetAsync(string id, CancellationToken ct = default)
    {
        try
        {
            var response = await container.ReadItemAsync<Job>(id, new PartitionKey(id), cancellationToken: ct);
            return response.Resource;
        }
        catch (CosmosException ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public async Task<IReadOnlyList<Job>> ListAsync(CancellationToken ct = default)
    {
        var query = new QueryDefinition("SELECT * FROM c ORDER BY c.createdAtUtc DESC");
        var results = new List<Job>();
        using var iterator = container.GetItemQueryIterator<Job>(query);
        while (iterator.HasMoreResults)
        {
            results.AddRange(await iterator.ReadNextAsync(ct));
        }
        return results;
    }

    public async Task AddAsync(Job job, CancellationToken ct = default)
    {
        await container.CreateItemAsync(job, new PartitionKey(job.Id), cancellationToken: ct);
    }

    public async Task UpdateAsync(Job job, CancellationToken ct = default)
    {
        await container.ReplaceItemAsync(job, job.Id, new PartitionKey(job.Id), cancellationToken: ct);
    }
}
