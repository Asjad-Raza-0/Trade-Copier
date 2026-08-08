export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Proxy all /api/* requests to the Master VPS relay
    if (url.pathname.startsWith('/api')) {
      return handleApiProxy(request, env, url);
    }

    // Serve static HTML/JS/CSS files via Workers Assets binding
    return env.ASSETS.fetch(request);
  }
};

async function handleApiProxy(request, env, url) {
  if (request.method === 'OPTIONS') {
    return new Response(null, {
      status: 200,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, X-API-Key, Authorization',
      }
    });
  }

  const targetBase = (env.RELAY_SERVER_URL || 'http://3.11.8.205:8765').replace(/\/+$/, '');
  const subPath = url.pathname.replace(/^\/api/, '');
  const queryString = url.search;

  // Direct routes (no /api prefix on the relay server)
  let targetUrl;
  if (['/slaves', '/health', '/events', '/trade', '/poll', '/purge'].includes(subPath)) {
    targetUrl = `${targetBase}${subPath}${queryString}`;
  } else {
    // Dashboard routes: /api/dashboard-summary, /api/command, etc.
    targetUrl = `${targetBase}/api${subPath}${queryString}`;
  }

  const newHeaders = new Headers(request.headers);
  if (!newHeaders.has('X-API-Key')) {
    const key = env.RELAY_API_KEY || 'ahgcjhbckjhsafkhkfuablhfkakkscknalkn7jhg3gd';
    newHeaders.set('X-API-Key', key);
  }
  newHeaders.delete('Host');
  newHeaders.delete('host');

  const init = { method: request.method, headers: newHeaders };
  if (['POST', 'PUT', 'PATCH'].includes(request.method)) {
    init.body = await request.text();
  }

  try {
    const response = await fetch(targetUrl, init);
    const body = await response.text();

    const outHeaders = new Headers(response.headers);
    outHeaders.set('Access-Control-Allow-Origin', '*');
    outHeaders.set('Access-Control-Allow-Headers', 'Content-Type, X-API-Key, Authorization');
    outHeaders.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');

    return new Response(body, { status: response.status, headers: outHeaders });
  } catch (err) {
    return new Response(
      JSON.stringify({
        error: 'Worker proxy failed to reach Master VPS Relay',
        details: err.message,
        target_url: targetUrl
      }),
      {
        status: 502,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        }
      }
    );
  }
}
