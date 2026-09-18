using CandidateService.Data;
using CandidateService.Endpoints;
using CandidateService.Models;
using Microsoft.AspNetCore.Http.HttpResults;
using NSubstitute;

namespace CandidateService.Tests;

public class CandidateEndpointsTests
{
    private readonly ICandidateRepository _repository = Substitute.For<ICandidateRepository>();

    [Fact]
    public async Task Create_WithValidRequest_SavesAndReturnsCreated()
    {
        var request = new CreateCandidateRequest("Ada Lovelace", "ada@example.com");

        var result = await CandidateEndpoints.Create(request, _repository);

        var created = Assert.IsType<Created<Candidate>>(result.Result);
        Assert.Equal("Ada Lovelace", created.Value!.FullName);
        Assert.Equal("ada@example.com", created.Value.Email);
        Assert.Equal($"/candidates/{created.Value.Id}", created.Location);
        await _repository.Received(1).AddAsync(Arg.Any<Candidate>());
    }

    [Theory]
    [InlineData("", "ada@example.com")]
    [InlineData("  ", "ada@example.com")]
    [InlineData("Ada Lovelace", "")]
    public async Task Create_WithMissingFields_ReturnsBadRequest(string fullName, string email)
    {
        var request = new CreateCandidateRequest(fullName, email);

        var result = await CandidateEndpoints.Create(request, _repository);

        Assert.IsType<BadRequest<string>>(result.Result);
        await _repository.DidNotReceive().AddAsync(Arg.Any<Candidate>());
    }

    [Fact]
    public async Task GetById_WhenCandidateExists_ReturnsCandidate()
    {
        var candidate = new Candidate { Id = "c1", FullName = "Ada", Email = "ada@example.com" };
        _repository.GetAsync("c1").Returns(candidate);

        var result = await CandidateEndpoints.GetById("c1", _repository);

        var ok = Assert.IsType<Ok<Candidate>>(result.Result);
        Assert.Equal("Ada", ok.Value!.FullName);
    }

    [Fact]
    public async Task GetById_WhenCandidateMissing_ReturnsNotFound()
    {
        _repository.GetAsync("missing").Returns((Candidate?)null);

        var result = await CandidateEndpoints.GetById("missing", _repository);

        Assert.IsType<NotFound>(result.Result);
    }

    [Fact]
    public async Task Update_WhenCandidateExists_PersistsChanges()
    {
        var candidate = new Candidate { Id = "c1", FullName = "Ada", Email = "old@example.com" };
        _repository.GetAsync("c1").Returns(candidate);

        var result = await CandidateEndpoints.Update("c1", new UpdateCandidateRequest("Ada King", "new@example.com"), _repository);

        var ok = Assert.IsType<Ok<Candidate>>(result.Result);
        Assert.Equal("Ada King", ok.Value!.FullName);
        Assert.Equal("new@example.com", ok.Value.Email);
        await _repository.Received(1).UpdateAsync(candidate);
    }

    [Fact]
    public async Task Update_WhenCandidateMissing_ReturnsNotFound()
    {
        _repository.GetAsync("missing").Returns((Candidate?)null);

        var result = await CandidateEndpoints.Update("missing", new UpdateCandidateRequest("Ada", "ada@example.com"), _repository);

        Assert.IsType<NotFound>(result.Result);
        await _repository.DidNotReceive().UpdateAsync(Arg.Any<Candidate>());
    }

    [Fact]
    public async Task List_PassesSearchTermToRepository()
    {
        _repository.SearchAsync("ada").Returns([new Candidate { FullName = "Ada" }]);

        var result = await CandidateEndpoints.List("ada", _repository);

        Assert.Single(result.Value!);
        await _repository.Received(1).SearchAsync("ada");
    }
}
