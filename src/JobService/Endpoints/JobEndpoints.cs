using JobService.Data;
using JobService.Models;
using Microsoft.AspNetCore.Http.HttpResults;

namespace JobService.Endpoints;

// Handlers are public static methods so unit tests can call them directly
// with a mocked repository — no web host needed.
public static class JobEndpoints
{
    public static void MapJobEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/jobs").WithTags("Jobs");
        group.MapGet("/", List);
        group.MapGet("/{id}", GetById);
        group.MapPost("/", Create);
        group.MapPut("/{id}", Update);
    }

    public static async Task<Ok<IReadOnlyList<Job>>> List(IJobRepository repository)
    {
        return TypedResults.Ok(await repository.ListAsync());
    }

    public static async Task<Results<Ok<Job>, NotFound>> GetById(string id, IJobRepository repository)
    {
        var job = await repository.GetAsync(id);
        return job is null ? TypedResults.NotFound() : TypedResults.Ok(job);
    }

    public static async Task<Results<Created<Job>, BadRequest<string>>> Create(
        CreateJobRequest request, IJobRepository repository)
    {
        if (string.IsNullOrWhiteSpace(request.Title))
            return TypedResults.BadRequest("Title is required.");
        if (string.IsNullOrWhiteSpace(request.Description))
            return TypedResults.BadRequest("Description is required.");

        var job = new Job
        {
            Title = request.Title.Trim(),
            Description = request.Description.Trim(),
            Location = request.Location?.Trim() ?? string.Empty
        };
        await repository.AddAsync(job);
        return TypedResults.Created($"/jobs/{job.Id}", job);
    }

    public static async Task<Results<Ok<Job>, NotFound, BadRequest<string>>> Update(
        string id, UpdateJobRequest request, IJobRepository repository)
    {
        if (string.IsNullOrWhiteSpace(request.Title))
            return TypedResults.BadRequest("Title is required.");
        if (string.IsNullOrWhiteSpace(request.Description))
            return TypedResults.BadRequest("Description is required.");

        var job = await repository.GetAsync(id);
        if (job is null)
            return TypedResults.NotFound();

        job.Title = request.Title.Trim();
        job.Description = request.Description.Trim();
        job.Location = request.Location?.Trim() ?? string.Empty;
        await repository.UpdateAsync(job);
        return TypedResults.Ok(job);
    }
}
