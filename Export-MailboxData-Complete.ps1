# Updated message tracking section
$messageTraces = @()
$continuationToken = $null
$hasMoreMessages = $true

while ($hasMoreMessages) {
    $response = Get-MessageTraceV2 -PageSize 1000 -ContinuationToken $continuationToken
    $messageTraces += $response.MessageTraces
    $continuationToken = $response.ContinuationToken
    $hasMoreMessages = $continuationToken -ne $null
}

# Process message traces
foreach ($trace in $messageTraces) {
    # Process each message trace
}
