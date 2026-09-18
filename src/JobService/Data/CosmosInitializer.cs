using Microsoft.Azure.Cosmos;

namespace JobService.Data;

public static class CosmosInitializer
{
    // Creates the database/container on startup so local dev needs no manual setup.
    // Retries because the Cosmos emulator takes a while to boot under docker-compose.
    public static async Task EnsureCreatedAsync(CosmosClient client, string databaseName, string containerName, ILogger logger)
    {
        const int maxAttempts = 12;
        for (var attempt = 1; ; attempt++)
        {
            try
            {
                var database = (await client.CreateDatabaseIfNotExistsAsync(databaseName)).Database;
                await database.CreateContainerIfNotExistsAsync(containerName, "/id");
                logger.LogInformation("Cosmos ready: {Database}/{Container}", databaseName, containerName);
                return;
            }
            catch (Exception ex) when (attempt < maxAttempts)
            {
                logger.LogWarning("Cosmos not ready (attempt {Attempt}/{Max}): {Message}", attempt, maxAttempts, ex.Message);
                await Task.Delay(TimeSpan.FromSeconds(5));
            }
        }
    }
}
