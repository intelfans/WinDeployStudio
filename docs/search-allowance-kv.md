SEARCH ALLOWANCE: KV-SIDE

WHY BOTH LAYERS

  The client keeps a local allowance so a normal user never notices the
  limit. That counter is lost when app data is cleared, so it cannot be the
  only guard. The worker keeps its own counters in KV: those survive a
  reinstall, and the optional global cap bounds total spend regardless of
  how many installations exist.

KEYS

  search:i:<install-id>:<hour>      per installation, 1 hour TTL
  search:global:<day>               optional total, 25 hour TTL

  The installation id is a random UUID the client creates once and stores.
  It contains no user or machine information. When the header is missing the
  worker falls back to a SHA-256 hash of the connecting IP, so an anonymous
  caller cannot escape the limit entirely without the address being stored.

SETUP

  1. Dashboard -> Workers & Pages -> KV -> Create a namespace.
     Name it anything, for example windeploy-search-budget.
  2. Your Worker -> Settings -> Bindings -> Add binding -> KV Namespace.
       Variable name: SEARCH_BUDGET
       Namespace:     the one you just created
  3. Redeploy.

  Optional plain-text variables under Settings -> Variables:
       SEARCH_INSTALL_HOURLY  default 10
       SEARCH_GLOBAL_DAILY    default 400, set 0 to disable

LIMITS OF THIS DESIGN

  KV has no atomic increment. Two simultaneous requests can read the same
  counter and both pass, so under heavy concurrency the effective limit is
  slightly higher than configured. That is acceptable for a cost guard; an
  exact limiter needs a Durable Object.

  Every counted search costs two KV writes (one per counter). The free tier
  allows 1000 writes per day, which sustains roughly 500 searches per day.
  Raising SEARCH_GLOBAL_DAILY past that on a free plan will exhaust writes
  before the budget.

RESPONSE CONTRACT

  200  normal, with X-WDS-Search-Remaining and X-WDS-Search-Limit
  429  allowance exhausted, with Retry-After; the client refunds its local
       slot and falls back to Bing / DuckDuckGo
