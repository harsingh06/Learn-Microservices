using JobService.Data;
using JobService.Endpoints;
using JobService.Models;
using Microsoft.AspNetCore.Http.HttpResults;
using NSubstitute;

namespace JobService.Tests;

public class JobEndpointsTests
{
    private readonly IJobRepository _repository = Substitute.For<IJobRepository>();

    [Fact]
    public async Task Create_WithValidRequest_SavesAndReturnsCreated()
    {
        var request = new CreateJobRequest("Engineer", "Build things.", "Remote");

        var result = await JobEndpoints.Create(request, _repository);

        var created = Assert.IsType<Created<Job>>(result.Result);
        Assert.Equal("Engineer", created.Value!.Title);
        Assert.Equal("Remote", created.Value.Location);
        await _repository.Received(1).AddAsync(Arg.Any<Job>());
    }

    [Fact]
    public async Task Create_WithoutLocation_DefaultsToEmpty()
    {
        var result = await JobEndpoints.Create(new CreateJobRequest("Engineer", "Build things.", null), _repository);

        var created = Assert.IsType<Created<Job>>(result.Result);
        Assert.Equal(string.Empty, created.Value!.Location);
    }

    [Theory]
    [InlineData("", "Build things.")]
    [InlineData("Engineer", "")]
    [InlineData("  ", "Build things.")]
    public async Task Create_WithMissingFields_ReturnsBadRequest(string title, string description)
    {
        var result = await JobEndpoints.Create(new CreateJobRequest(title, description, null), _repository);

        Assert.IsType<BadRequest<string>>(result.Result);
        await _repository.DidNotReceive().AddAsync(Arg.Any<Job>());
    }

    [Fact]
    public async Task GetById_WhenJobExists_ReturnsJob()
    {
        _repository.GetAsync("j1").Returns(new Job { Id = "j1", Title = "Engineer" });

        var result = await JobEndpoints.GetById("j1", _repository);

        var ok = Assert.IsType<Ok<Job>>(result.Result);
        Assert.Equal("Engineer", ok.Value!.Title);
    }

    [Fact]
    public async Task GetById_WhenJobMissing_ReturnsNotFound()
    {
        _repository.GetAsync("missing").Returns((Job?)null);

        var result = await JobEndpoints.GetById("missing", _repository);

        Assert.IsType<NotFound>(result.Result);
    }

    [Fact]
    public async Task Update_WhenJobExists_PersistsChanges()
    {
        var job = new Job { Id = "j1", Title = "Engineer", Description = "Old." };
        _repository.GetAsync("j1").Returns(job);

        var result = await JobEndpoints.Update("j1", new UpdateJobRequest("Staff Engineer", "New.", "Hybrid"), _repository);

        var ok = Assert.IsType<Ok<Job>>(result.Result);
        Assert.Equal("Staff Engineer", ok.Value!.Title);
        Assert.Equal("New.", ok.Value.Description);
        Assert.Equal("Hybrid", ok.Value.Location);
        await _repository.Received(1).UpdateAsync(job);
    }

    [Fact]
    public async Task Update_WhenJobMissing_ReturnsNotFound()
    {
        _repository.GetAsync("missing").Returns((Job?)null);

        var result = await JobEndpoints.Update("missing", new UpdateJobRequest("T", "D", null), _repository);

        Assert.IsType<NotFound>(result.Result);
        await _repository.DidNotReceive().UpdateAsync(Arg.Any<Job>());
    }

    [Fact]
    public async Task List_ReturnsAllJobs()
    {
        _repository.ListAsync().Returns([new Job { Title = "A" }, new Job { Title = "B" }]);

        var result = await JobEndpoints.List(_repository);

        Assert.Equal(2, result.Value!.Count);
    }
}
