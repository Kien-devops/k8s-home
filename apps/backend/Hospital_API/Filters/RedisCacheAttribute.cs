using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Extensions.Caching.Distributed;

namespace Hospital_API.Filters;

[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method)]
public sealed class RedisCacheAttribute : Attribute, IAsyncActionFilter
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    private readonly string _prefix;
    private readonly int _ttlSeconds;

    public RedisCacheAttribute(string prefix, int ttlSeconds = 300)
    {
        _prefix = prefix;
        _ttlSeconds = ttlSeconds;
    }

    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        if (!HttpMethods.IsGet(context.HttpContext.Request.Method))
        {
            await next();
            return;
        }

        var cache = context.HttpContext.RequestServices.GetRequiredService<IDistributedCache>();
        var version = await GetCacheVersionAsync(cache, context.HttpContext.RequestAborted);
        var request = context.HttpContext.Request;
        var cacheKey = $"response-cache:{_prefix}:{version}:{request.Path}{request.QueryString}";
        var cachedJson = await cache.GetStringAsync(cacheKey, context.HttpContext.RequestAborted);

        if (!string.IsNullOrWhiteSpace(cachedJson))
        {
            context.HttpContext.Response.Headers["X-Cache"] = "HIT";
            context.Result = new ContentResult
            {
                Content = cachedJson,
                ContentType = "application/json",
                StatusCode = StatusCodes.Status200OK
            };
            return;
        }

        var executedContext = await next();
        if (executedContext.Result is ObjectResult { StatusCode: null or StatusCodes.Status200OK } objectResult)
        {
            var json = JsonSerializer.Serialize(objectResult.Value, JsonOptions);
            await cache.SetStringAsync(
                cacheKey,
                json,
                new DistributedCacheEntryOptions
                {
                    AbsoluteExpirationRelativeToNow = TimeSpan.FromSeconds(_ttlSeconds)
                },
                context.HttpContext.RequestAborted);

            context.HttpContext.Response.Headers["X-Cache"] = "MISS";
        }
    }

    private async Task<string> GetCacheVersionAsync(IDistributedCache cache, CancellationToken cancellationToken)
    {
        var versionKey = GetVersionKey(_prefix);
        var version = await cache.GetStringAsync(versionKey, cancellationToken);
        if (!string.IsNullOrWhiteSpace(version))
        {
            return version;
        }

        version = "v1";
        await cache.SetStringAsync(versionKey, version, cancellationToken);
        return version;
    }

    internal static string GetVersionKey(string prefix) => $"response-cache-version:{prefix}";
}

