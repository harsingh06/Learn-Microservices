using CandidateService.Data;
using CandidateService.Models;
using Microsoft.AspNetCore.Http.HttpResults;

namespace CandidateService.Endpoints;

// Handlers are public static methods so unit tests can call them directly
// with a mocked repository — no web host needed.
public static class CandidateEndpoints
{
    public static void MapCandidateEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/candidates").WithTags("Candidates");
        group.MapGet("/", List);
        group.MapGet("/{id}", GetById);
        group.MapPost("/", Create);
        group.MapPut("/{id}", Update);
    }

    public static async Task<Ok<IReadOnlyList<Candidate>>> List(string? search, ICandidateRepository repository)
    {
        return TypedResults.Ok(await repository.SearchAsync(search));
    }

    public static async Task<Results<Ok<Candidate>, NotFound>> GetById(string id, ICandidateRepository repository)
    {
        var candidate = await repository.GetAsync(id);
        return candidate is null ? TypedResults.NotFound() : TypedResults.Ok(candidate);
    }

    public static async Task<Results<Created<Candidate>, BadRequest<string>>> Create(
        CreateCandidateRequest request, ICandidateRepository repository)
    {
        if (string.IsNullOrWhiteSpace(request.FullName))
            return TypedResults.BadRequest("FullName is required.");
        if (string.IsNullOrWhiteSpace(request.Email))
            return TypedResults.BadRequest("Email is required.");

        var candidate = new Candidate
        {
            FullName = request.FullName.Trim(),
            Email = request.Email.Trim()
        };
        await repository.AddAsync(candidate);
        return TypedResults.Created($"/candidates/{candidate.Id}", candidate);
    }

    public static async Task<Results<Ok<Candidate>, NotFound, BadRequest<string>>> Update(
        string id, UpdateCandidateRequest request, ICandidateRepository repository)
    {
        if (string.IsNullOrWhiteSpace(request.FullName))
            return TypedResults.BadRequest("FullName is required.");
        if (string.IsNullOrWhiteSpace(request.Email))
            return TypedResults.BadRequest("Email is required.");

        var candidate = await repository.GetAsync(id);
        if (candidate is null)
            return TypedResults.NotFound();

        candidate.FullName = request.FullName.Trim();
        candidate.Email = request.Email.Trim();
        await repository.UpdateAsync(candidate);
        return TypedResults.Ok(candidate);
    }
}
