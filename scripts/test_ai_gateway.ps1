# WinDeploy Studio - AI gateway smoke test
#
#   .\scripts\test_ai_gateway.ps1
#   .\scripts\test_ai_gateway.ps1 -BaseUrl https://ai.xueyanzhang.top -Model mimo-v2.5-pro

[CmdletBinding()]
param(
    [string] $BaseUrl = 'https://ai.xueyanzhang.top',
    [string] $Model = 'mimo-v2.5-pro',
    [string] $ApiKey = ''
)

$ErrorActionPreference = 'Stop'
$BaseUrl = $BaseUrl.TrimEnd('/')

function Explain([int] $Code) {
    switch ($Code) {
        0   { return 'no HTTP response (DNS/TLS/network)' }
        401 { return 'auth rejected - check the upstream key' }
        404 { return 'route missing - worker not deployed at this path' }
        405 { return 'wrong HTTP method' }
        429 { return 'rate limited upstream' }
        500 { return 'worker misconfigured - secret MIMO_API_KEY missing?' }
        502 { return 'upstream unreachable' }
        504 { return 'upstream timed out' }
        default { return "HTTP $Code" }
    }
}

function StatusOf($ErrorRecord) {
    if ($ErrorRecord.Exception.Response) {
        return [int] $ErrorRecord.Exception.Response.StatusCode
    }
    return 0
}

Write-Host ''
Write-Host "Gateway : $BaseUrl" -ForegroundColor Cyan
Write-Host "Model   : $Model" -ForegroundColor Cyan
Write-Host ''

# 1 - model list
Write-Host '[1/4] GET /v1/models' -ForegroundColor Yellow
try {
    $headers = @{ Accept = 'application/json' }
    if ($ApiKey) { $headers['Authorization'] = "Bearer $ApiKey" }
    $models = Invoke-RestMethod -Uri "$BaseUrl/v1/models" -Method Get -Headers $headers -TimeoutSec 30
    $count = @($models.data).Count
    Write-Host "      PASS - $count model(s)" -ForegroundColor Green
    @($models.data) | Select-Object -First 5 | ForEach-Object { Write-Host "        - $($_.id)" }
}
catch {
    Write-Host "      FAIL - $(Explain (StatusOf $_))" -ForegroundColor Red
    if ($_.ErrorDetails.Message) { Write-Host "      body: $($_.ErrorDetails.Message)" }
}

# 2 - non-streaming completion
Write-Host "[2/4] POST /v1/chat/completions  model=$Model" -ForegroundColor Yellow
$body = @{
    model    = $Model
    messages = @(@{ role = 'user'; content = 'Reply with the single word: pong' })
    stream   = $false
} | ConvertTo-Json -Depth 6 -Compress

try {
    $resp = Invoke-WebRequest -Uri "$BaseUrl/v1/chat/completions" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 120 -UseBasicParsing
    $served = $resp.Headers['X-WDS-Model']
    $from = $resp.Headers['X-WDS-Model-Migrated']
    Write-Host "      PASS - HTTP $($resp.StatusCode)" -ForegroundColor Green
    Write-Host "      served model : $served"
    if ($from) {
        Write-Host "      migrated from: $from"
        Write-Host '      -> retired ID rewritten at the gateway' -ForegroundColor Green
    }
    $parsed = $resp.Content | ConvertFrom-Json
    if ($parsed.choices[0].message.content) { Write-Host "      reply        : $($parsed.choices[0].message.content)" }
}
catch {
    Write-Host "      FAIL - $(Explain (StatusOf $_))" -ForegroundColor Red
    if ($_.ErrorDetails.Message) { Write-Host "      body: $($_.ErrorDetails.Message)" }
}

# 3 - streaming
Write-Host '[3/4] POST /v1/chat/completions  stream=true' -ForegroundColor Yellow
$streamBody = @{
    model    = $Model
    messages = @(@{ role = 'user'; content = 'Count from 1 to 5.' })
    stream   = $true
} | ConvertTo-Json -Depth 6 -Compress

try {
    $resp = Invoke-WebRequest -Uri "$BaseUrl/v1/chat/completions" -Method Post -ContentType 'application/json' -Body $streamBody -TimeoutSec 120 -UseBasicParsing
    $events = ([regex]::Matches($resp.Content, '(?m)^data: ')).Count
    Write-Host "      PASS - HTTP $($resp.StatusCode)  content-type: $($resp.Headers['Content-Type'])" -ForegroundColor Green
    Write-Host "      SSE data events: $events"
    if ($resp.Content -match '\[DONE\]') { Write-Host '      stream terminated with [DONE]' }
}
catch {
    Write-Host "      FAIL - $(Explain (StatusOf $_))" -ForegroundColor Red
    if ($_.ErrorDetails.Message) { Write-Host "      body: $($_.ErrorDetails.Message)" }
}

Write-Host ''

# 4 - Tavily search through the gateway
Write-Host '[4/4] POST /v1/search' -ForegroundColor Yellow
$searchBody = @{ query = 'Windows To Go deployment'; max_results = 3 } | ConvertTo-Json -Compress
try {
    $resp = Invoke-WebRequest -Uri "$BaseUrl/v1/search" -Method Post -ContentType 'application/json' -Body $searchBody -TimeoutSec 60 -UseBasicParsing
    $data = $resp.Content | ConvertFrom-Json
    $n = @($data.results).Count
    Write-Host "      PASS - HTTP $($resp.StatusCode), provider=$($data.provider), results=$n" -ForegroundColor Green
    @($data.results) | Select-Object -First 3 | ForEach-Object { Write-Host "        - $($_.title)" }
}
catch {
    $code = 0
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    Write-Host "      FAIL - $(Explain (StatusOf $_))" -ForegroundColor Red
    if ($code -eq 501) {
        Write-Host '      -> TAVILY_API_KEY is not set on the worker, or the worker still runs the old code.' -ForegroundColor DarkYellow
    }
    if ($code -eq 404) {
        Write-Host '      -> The deployed worker does not have the /search route. Paste the new worker.js and Deploy.' -ForegroundColor DarkYellow
    }
    if ($_.ErrorDetails.Message) { Write-Host "      body: $($_.ErrorDetails.Message)" }
}

Write-Host 'Note: a 405 on a plain GET is correct - /chat/completions accepts POST only.' -ForegroundColor DarkGray
