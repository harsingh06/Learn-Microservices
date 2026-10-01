namespace ApplicationService.Clients;

// "The dependency couldn't answer" — deliberately NOT the same as "the thing
// doesn't exist" (a null result). Mapped to 503 by the endpoints: retrying
// later can succeed.
public class DependencyUnavailableException(string dependency, Exception inner)
    : Exception($"{dependency} is temporarily unavailable.", inner)
{
    public string Dependency { get; } = dependency;
}
