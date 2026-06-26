using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Extensions.Caching.Distributed;

namespace Hospital_API.Filters;

[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method)]
public sealed class RedisCacheEvictAttribute : Attribute, IAsyncActionFilter
{
    private readonly string[] _prefixes;

    public RedisCacheEvictAttribute(params string[] prefixes)
    {
        _prefixes = prefixes;
    }

    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        if (HttpMethods.IsGet(context.HttpContext.Request.Method))
        {
            await next();
            return;
        }

        var executedContext = await next();
        var statusCode = executedContext.HttpContext.Response.StatusCode;
        if (statusCode < StatusCodes.Status200OK || statusCode >= StatusCodes.Status300MultipleChoices)
        {
            return;
        }

        var cache = context.HttpContext.RequestServices.GetRequiredService<IDistributedCache>();
        foreach (var prefix in _prefixes)
        {
            await cache.SetStringAsync(
                RedisCacheAttribute.GetVersionKey(prefix),
                Guid.NewGuid().ToString("N"),
                context.HttpContext.RequestAborted);
        }
    }
}
