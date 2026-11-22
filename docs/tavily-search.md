TAVILY SEARCH ON THE GATEWAY

WHY

  The desktop client used to scrape two public endpoints: Bing's RSS feed
  and DuckDuckGo's instant-answer API. Both are unstructured fallbacks. A
  structured provider gives better results and, more importantly, keeps
  the credential on the server instead of shipping it in the client.

HOW IT WORKS

  Client asks the gateway:  POST  /v1/search
  Body:                     { query, max_results }
  Gateway calls Tavily:     https://api.tavily.com/search
  Gateway returns:          { provider, query, results[], notice }

  The client only uses this route when the configured endpoint is the
  built-in one. A user's private provider has no such route, so the two
  keyless sources remain the fallback there.

DEPLOY

  1. Get a key at https://tavily.com
  2. In the Cloudflare dashboard: Worker -> Settings -> Variables and
     Secrets -> add TAVILY_API_KEY as a Secret (type: Secret).
  3. Redeploy the worker.

  Without the secret, /v1/search answers 501 and the client silently
  falls back to Bing and DuckDuckGo. Nothing breaks.

COST

  Tavily bills per search. Each user question that triggers search costs
  one request. The gateway caps max_results at 8 and query length at 400
  characters to bound the payload.
