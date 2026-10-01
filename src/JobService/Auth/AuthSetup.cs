using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.Identity.Web;

namespace JobService.Auth;

// Who may call this API and what they may do (see AUTH.md). Every service owns
// its own copy of this — no shared library, same as the rest of the code.
public static class AtsRoles
{
    public const string Recruiter = "Recruiter";
    public const string HiringManager = "HiringManager";
}

public static class AtsPolicies
{
    public const string Read = "Read";
    public const string ManageJobs = "ManageJobs";
}

public static class AuthSetup
{
    // Every token for this API must carry this delegated scope: the web app's
    // tokens and ApplicationService's On-Behalf-Of tokens both do.
    public const string RequiredScope = "access_as_user";

    // Validates Entra ID access tokens issued for THIS API: signature (Entra's
    // published keys), issuer (our tenant), audience (this API's client ID), lifetime.
    public static IServiceCollection AddAtsAuthentication(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
            .AddMicrosoftIdentityWebApi(configuration.GetSection("AzureAd"));

        // Keep claims exactly as Entra issues them ("roles", "scp", "name") instead
        // of .NET's legacy long URI names — what you see in the token is what the
        // policies check.
        services.PostConfigure<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme, options =>
        {
            options.MapInboundClaims = false;
            options.TokenValidationParameters.RoleClaimType = "roles";
            options.TokenValidationParameters.NameClaimType = "name";
        });

        return services;
    }

    // Policies, deliberately independent of HOW the caller was authenticated, so
    // tests can exercise them with a fake authentication scheme.
    public static IServiceCollection AddAtsAuthorization(this IServiceCollection services)
    {
        services.AddRequiredScopeAuthorization(); // Microsoft.Identity.Web's scope check

        services.AddAuthorization(options =>
        {
            options.AddPolicy(AtsPolicies.Read, Policy(AtsRoles.Recruiter, AtsRoles.HiringManager));
            options.AddPolicy(AtsPolicies.ManageJobs, Policy(AtsRoles.Recruiter));

            // Secure by default: any endpoint WITHOUT an explicit policy still
            // needs a valid token with the scope. Opt out with .AllowAnonymous().
            options.FallbackPolicy = new AuthorizationPolicyBuilder()
                .RequireAuthenticatedUser()
                .RequireScope(RequiredScope)
                .Build();
        });

        return services;
    }

    private static AuthorizationPolicy Policy(params string[] roles) =>
        new AuthorizationPolicyBuilder()
            .RequireAuthenticatedUser()
            .RequireScope(RequiredScope)
            .RequireRole(roles)
            .Build();
}
