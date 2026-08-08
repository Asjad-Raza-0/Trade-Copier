// Cloudflare Pages Function API Proxy
// Proxies requests from Cloudflare Pages (https://...) to Master VPS Relay Server (http://...)
// Handling HTTPS Mixed-Content and CORS transparently on the Cloudflare Edge network.

export async function onRequest(context) {
  const { request, env } = context;
  const url = new URL(request.url);

  // Extract path and query string after /api/
  const subPath = url.pathname.replace(/^\/api/, '');
  const queryString = url.search;

  // Master VPS Endpoint configuration (can be overridden via Cloudflare Environment Variable RELAY_SERVER_URL)
  const targetBase = (env.RELAY_SERVER_URL || "http://3.11.8.205:8765").replace(/\/+$/, '');
  
  // Forward request to Master VPS Relay Server
  let targetUrl = `${targetBase}/api${subPath}${queryString}`;
  if (subPath === '/slaves' || subPath === '/health' || subPath === '/events' || subPath === '/trade' || subPath === '/poll' || subPath === '/purge') {
    targetUrl = `${targetBase}${subPath}${queryString}`;
  }

  // Pre-flight CORS request handling
  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 200,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, X-API-Key, Authorization",
      },
    });
  }

  try {
    // Clone headers and attach RELAY_API_KEY from environment or request
    const newHeaders = new Headers(request.headers);
    if (!newHeaders.has("X-API-Key") && env.RELAY_API_KEY) {
      newHeaders.set("X-API-Key", env.RELAY_API_KEY);
    }
    newHeaders.set("Host", new URL(targetBase).host);

    const init = {
      method: request.method,
      headers: newHeaders,
    };

    if (["POST", "PUT", "PATCH"].includes(request.method)) {
      init.body = await request.text();
    }

    const response = await fetch(targetUrl, init);
    const responseData = await response.text();

    // Create CORS compliant response back to frontend
    const finalHeaders = new Headers(response.headers);
    finalHeaders.set("Access-Control-Allow-Origin", "*");
    finalHeaders.set("Access-Control-Allow-Headers", "Content-Type, X-API-Key, Authorization");
    finalHeaders.set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");

    return new Response(responseData, {
      status: response.status,
      headers: finalHeaders,
    });
  } catch (err) {
    return new Response(
      JSON.stringify({
        error: "Edge Proxy connection failed to Master VPS Relay",
        details: err.message,
        target_url: targetUrl
      }),
      {
        status: 502,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      }
    );
  }
}
