using ApplicationService.Clients;
using ApplicationService.Data;
using ApplicationService.Models;
using Microsoft.AspNetCore.Http.HttpResults;

namespace ApplicationService.Endpoints;

// Handlers are public static methods so unit tests can call them directly
// with mocked dependencies — no web host needed.
public static class ApplicationEndpoints
{
    public static void MapApplicationEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/applications").WithTags("Applications");
        group.MapGet("/", List);
        group.MapGet("/{id}", GetById);
        group.MapPost("/", Submit);
        group.MapPut("/{id}/status", UpdateStatus);
    }

    public static async Task<Ok<IReadOnlyList<JobApplication>>> List(
        string? candidateId, string? jobId, IApplicationRepository repository)
    {
        return TypedResults.Ok(await repository.ListAsync(candidateId, jobId));
    }

    public static async Task<Results<Ok<JobApplication>, NotFound>> GetById(
        string id, IApplicationRepository repository)
    {
        var application = await repository.GetAsync(id);
        return application is null ? TypedResults.NotFound() : TypedResults.Ok(application);
    }

    public static async Task<Results<Created<JobApplication>, BadRequest<string>, Conflict<string>, ProblemHttpResult>> Submit(
        SubmitApplicationRequest request,
        IApplicationRepository repository,
        ICandidateClient candidateClient,
        IJobClient jobClient)
    {
        if (string.IsNullOrWhiteSpace(request.CandidateId))
            return TypedResults.BadRequest("CandidateId is required.");
        if (string.IsNullOrWhiteSpace(request.JobId))
            return TypedResults.BadRequest("JobId is required.");

        // Synchronous existence checks against the owning services. This couples
        // availability (can't apply if CandidateService is down) — accepted for Phase 1;
        // the alternative is an event-fed local read model, tracked in the backlog.
        // The clients' resilience pipelines absorb blips; what's left is either "doesn't
        // exist" (400) or "couldn't be checked right now" (503 — retrying can succeed).
        CandidateSummary? candidate;
        JobSummary? job;
        try
        {
            candidate = await candidateClient.GetAsync(request.CandidateId);
            if (candidate is null)
                return TypedResults.BadRequest($"Candidate '{request.CandidateId}' does not exist.");

            job = await jobClient.GetAsync(request.JobId);
            if (job is null)
                return TypedResults.BadRequest($"Job '{request.JobId}' does not exist.");
        }
        catch (DependencyUnavailableException ex)
        {
            return TypedResults.Problem(
                statusCode: StatusCodes.Status503ServiceUnavailable,
                title: $"{ex.Dependency} is temporarily unavailable",
                detail: "The application wasn't submitted. Please retry in a few seconds.");
        }

        var existing = await repository.FindByCandidateAndJobAsync(request.CandidateId, request.JobId);
        if (existing is not null)
            return TypedResults.Conflict("This candidate has already applied to this job.");

        var application = new JobApplication
        {
            CandidateId = candidate.Id,
            JobId = job.Id,
            CandidateName = candidate.FullName,
            JobTitle = job.Title
        };
        await repository.AddAsync(application);
        return TypedResults.Created($"/applications/{application.Id}", application);
    }

    public static async Task<Results<Ok<JobApplication>, NotFound, BadRequest<string>>> UpdateStatus(
        string id, UpdateStatusRequest request, IApplicationRepository repository)
    {
        if (!Enum.TryParse<ApplicationStatus>(request.Status, ignoreCase: true, out var newStatus))
            return TypedResults.BadRequest(
                $"Unknown status '{request.Status}'. Valid values: {string.Join(", ", Enum.GetNames<ApplicationStatus>())}.");

        var application = await repository.GetAsync(id);
        if (application is null)
            return TypedResults.NotFound();

        if (!StatusTransitions.IsAllowed(application.Status, newStatus))
            return TypedResults.BadRequest($"Cannot change status from {application.Status} to {newStatus}.");

        application.Status = newStatus;
        await repository.UpdateAsync(application);
        return TypedResults.Ok(application);
    }
}
