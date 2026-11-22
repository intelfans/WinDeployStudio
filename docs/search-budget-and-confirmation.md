SEARCH: BUDGET, CONFIRMATION, AND THE GATEWAY ROUTE

1. HOURLY BUDGET

   lib/core/services/ai_search_budget.dart

   10 gateway searches per rolling hour, per installation. When the
   allowance is spent the client stops calling the gateway and falls back
   to the keyless sources (Bing RSS, then DuckDuckGo). Search still works;
   only the provider changes, so the operator stops paying.

   A slot is charged when the request is sent and refunded only when our
   worker answers 404 or 501 - both of which it replies before contacting
   the provider, so nothing was billed.

   The allowance is per installation. It is a cost guard, not licence
   enforcement. If billing risk grows, add a server-side counter in the
   worker with a KV namespace; that is the only place it cannot be reset.

2. CONFIRMATION DIALOG

   Shown immediately before any query leaves the device. It names the
   recipient and prints the exact text that will be sent.

   Refusing drops the search; it does not reroute, because every route
   transmits the same text.

   Wired as SearchConfirmationCallback:
     AiMessageService.sendMessage(confirmSearch: ...)
       -> ChatNotifier.setSearchConfirmation(handler)
         -> AiAssistantScreen._confirmSearchQuery()

   Null callback means no prompt. Tests and headless callers keep the old
   behaviour.

3. GATEWAY SEARCH ROUTE

   POST /v1/search  { query, max_results }
   Provider: Tavily, credential stays in the worker.
   Returns 501 when TAVILY_API_KEY is absent, and the client falls back.

DEPLOYMENT REMINDER

   Setting the secret is not enough: the worker code must be redeployed.
   While /v1/search answers 404, the deployed worker is the old build.
