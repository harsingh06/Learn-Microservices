using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace ApplicationService.Tests.Auth;

// Stands in for Entra ID in tests: the caller is described by request headers
// instead of a signed token. Claims use the same names as real Entra tokens
// ("roles", "scp", "name"), so the REAL policies evaluate them unchanged.
//
//   (no X-Test-User)        -> anonymous
//   X-Test-User: ada        -> authenticated as "ada"
//   X-Test-Roles: a,b       -> roles a and b
//   X-Test-Scopes: s1 s2    -> delegated scopes s1 and s2
public sealed class TestAuthHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string SchemeName = "Test";

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue("X-Test-User", out var user))
            return Task.FromResult(AuthenticateResult.NoResult());

        var claims = new List<Claim> { new("name", user.ToString()) };
        claims.AddRange(Request.Headers["X-Test-Roles"].ToString()
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(role => new Claim("roles", role)));
        var scopes = Request.Headers["X-Test-Scopes"].ToString();
        if (scopes.Length > 0)
            claims.Add(new Claim("scp", scopes));

        var identity = new ClaimsIdentity(claims, SchemeName, nameType: "name", roleType: "roles");
        return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identity), SchemeName)));
    }
}
