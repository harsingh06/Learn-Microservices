using ApplicationService.Clients;
using ApplicationService.Data;
using ApplicationService.Endpoints;
using ApplicationService.Models;
using Microsoft.AspNetCore.Http.HttpResults;
using NSubstitute;

namespace ApplicationService.Tests;

public class ApplicationEndpointsTests
{
    private readonly IApplicationRepository _repository = Substitute.For<IApplicationRepository>();
    private readonly ICandidateClient _candidateClient = Substitute.For<ICandidateClient>();
    private readonly IJobClient _jobClient = Substitute.For<IJobClient>();

    private Task<Results<Created<JobApplication>, BadRequest<string>, Conflict<string>>> Submit(
        string candidateId = "c1", string jobId = "j1") =>
        ApplicationEndpoints.Submit(new SubmitApplicationRequest(candidateId, jobId), _repository, _candidateClient, _jobClient);

    [Fact]
    public async Task Submit_WithValidRequest_SnapshotsNamesAndReturnsCreated()
    {
        _candidateClient.GetAsync("c1").Returns(new CandidateSummary("c1", "Ada Lovelace"));
        _jobClient.GetAsync("j1").Returns(new JobSummary("j1", "Engineer"));
        _repository.FindByCandidateAndJobAsync("c1", "j1").Returns((JobApplication?)null);

        var result = await Submit();

        var created = Assert.IsType<Created<JobApplication>>(result.Result);
        Assert.Equal("Ada Lovelace", created.Value!.CandidateName);
        Assert.Equal("Engineer", created.Value.JobTitle);
        Assert.Equal(ApplicationStatus.Submitted, created.Value.Status);
        await _repository.Received(1).AddAsync(Arg.Any<JobApplication>());
    }

    [Fact]
    public async Task Submit_WhenCandidateDoesNotExist_ReturnsBadRequest()
    {
        _candidateClient.GetAsync("c1").Returns((CandidateSummary?)null);

        var result = await Submit();

        var badRequest = Assert.IsType<BadRequest<string>>(result.Result);
        Assert.Contains("Candidate", badRequest.Value);
        await _repository.DidNotReceive().AddAsync(Arg.Any<JobApplication>());
    }

    [Fact]
    public async Task Submit_WhenJobDoesNotExist_ReturnsBadRequest()
    {
        _candidateClient.GetAsync("c1").Returns(new CandidateSummary("c1", "Ada"));
        _jobClient.GetAsync("j1").Returns((JobSummary?)null);

        var result = await Submit();

        var badRequest = Assert.IsType<BadRequest<string>>(result.Result);
        Assert.Contains("Job", badRequest.Value);
        await _repository.DidNotReceive().AddAsync(Arg.Any<JobApplication>());
    }

    [Fact]
    public async Task Submit_WhenAlreadyApplied_ReturnsConflict()
    {
        _candidateClient.GetAsync("c1").Returns(new CandidateSummary("c1", "Ada"));
        _jobClient.GetAsync("j1").Returns(new JobSummary("j1", "Engineer"));
        _repository.FindByCandidateAndJobAsync("c1", "j1").Returns(new JobApplication { CandidateId = "c1", JobId = "j1" });

        var result = await Submit();

        Assert.IsType<Conflict<string>>(result.Result);
        await _repository.DidNotReceive().AddAsync(Arg.Any<JobApplication>());
    }

    [Theory]
    [InlineData("", "j1")]
    [InlineData("c1", "")]
    public async Task Submit_WithMissingIds_ReturnsBadRequest(string candidateId, string jobId)
    {
        var result = await Submit(candidateId, jobId);

        Assert.IsType<BadRequest<string>>(result.Result);
    }

    [Fact]
    public async Task UpdateStatus_WithAllowedTransition_PersistsNewStatus()
    {
        var application = new JobApplication { Id = "a1", Status = ApplicationStatus.Submitted };
        _repository.GetAsync("a1").Returns(application);

        var result = await ApplicationEndpoints.UpdateStatus("a1", new UpdateStatusRequest("InReview"), _repository);

        var ok = Assert.IsType<Ok<JobApplication>>(result.Result);
        Assert.Equal(ApplicationStatus.InReview, ok.Value!.Status);
        await _repository.Received(1).UpdateAsync(application);
    }

    [Fact]
    public async Task UpdateStatus_WithDisallowedTransition_ReturnsBadRequest()
    {
        // Submitted must go through InReview before Accepted.
        _repository.GetAsync("a1").Returns(new JobApplication { Id = "a1", Status = ApplicationStatus.Submitted });

        var result = await ApplicationEndpoints.UpdateStatus("a1", new UpdateStatusRequest("Accepted"), _repository);

        Assert.IsType<BadRequest<string>>(result.Result);
        await _repository.DidNotReceive().UpdateAsync(Arg.Any<JobApplication>());
    }

    [Fact]
    public async Task UpdateStatus_WithUnknownStatus_ReturnsBadRequest()
    {
        var result = await ApplicationEndpoints.UpdateStatus("a1", new UpdateStatusRequest("Hired"), _repository);

        var badRequest = Assert.IsType<BadRequest<string>>(result.Result);
        Assert.Contains("Unknown status", badRequest.Value);
    }

    [Fact]
    public async Task UpdateStatus_WhenApplicationMissing_ReturnsNotFound()
    {
        _repository.GetAsync("missing").Returns((JobApplication?)null);

        var result = await ApplicationEndpoints.UpdateStatus("missing", new UpdateStatusRequest("InReview"), _repository);

        Assert.IsType<NotFound>(result.Result);
    }

    [Theory]
    [InlineData(ApplicationStatus.Submitted, ApplicationStatus.InReview, true)]
    [InlineData(ApplicationStatus.Submitted, ApplicationStatus.Rejected, true)]
    [InlineData(ApplicationStatus.Submitted, ApplicationStatus.Accepted, false)]
    [InlineData(ApplicationStatus.InReview, ApplicationStatus.Accepted, true)]
    [InlineData(ApplicationStatus.InReview, ApplicationStatus.Rejected, true)]
    [InlineData(ApplicationStatus.Accepted, ApplicationStatus.Rejected, false)]
    [InlineData(ApplicationStatus.Rejected, ApplicationStatus.InReview, false)]
    public void StatusTransitions_EnforceTheWorkflow(ApplicationStatus from, ApplicationStatus to, bool allowed)
    {
        Assert.Equal(allowed, StatusTransitions.IsAllowed(from, to));
    }
}
