<#
ShareGate OneDrive Migration Toolkit v8.3.5.4

What changed in v8.3.5
- Added Connection Profile menu and JSON profile support
- Added configurable Source/Destination root URLs and admin metadata
- Added cached session reuse within a single process/batch worker
- ParallelBatches still signs in once per batch worker, not once globally across all workers
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$CsvPath,
    [switch]$BrowseForCsv,
    [switch]$Menu,
    [ValidateSet("ValidateOnly","Migrate")][string]$Mode = "Migrate",
    [ValidateSet("Root","Subfolder")][string]$MigrationFolderMode = "Subfolder",
    [string]$DefaultSubFolder = "Migrated data",
    [string]$SourceLibraryName = "Documents",
    [string]$DestinationLibraryName = "Documents",
    [string]$ResultsRoot = ".\ShareGate-Results",
    [ValidateSet("Auto","Browser","ModernAuth")][string]$AuthMode = "Auto",
    [string]$SourceRootUrl,
    [string]$DestinationRootUrl,
    [string]$SourceAdminCenterUrl,
    [string]$DestinationAdminCenterUrl,
    [string]$SourceAdminUser,
    [string]$DestinationAdminUser,
    [string]$ConnectionProfilePath,
    [ValidateSet("ReuseAuthSerial","TrueParallel","ParallelBatches")][string]$ExecutionMode = "ReuseAuthSerial",
    [switch]$Incremental,
    [switch]$WhatIfOnly,
    [switch]$SkipCompletedFromPriorResults,
    [string]$PriorResultsCsvPath,
    [switch]$ReprocessSuccess,

    [switch]$ExecuteMigration,
    [int]$MaxRetryCount = 3,
    [int]$RetryDelaySeconds = 15,
    [switch]$ResumeInterrupted,
    [int]$ThrottleDelayMilliseconds = 0,
    [switch]$DetailedErrorReporting,
    [switch]$ShowProgress,
    [string]$VerificationReportPath,
    [switch]$SkipVerification,
    [switch]$NoPause,
    [ValidateRange(1,5)][int]$MaxParallelSessions = 1
)


if ($null -eq $script:PreAuthConnectionCache) { $script:PreAuthConnectionCache = @{} }
if ($null -eq $script:ConnectionCache) { $script:ConnectionCache = @{} }
if ($null -eq $script:PreAuthenticated) { $script:PreAuthenticated = $false }
if ($null -eq (Get-Variable -Name BatchScopedAuthReuse -Scope Script -ErrorAction SilentlyContinue)) { $script:BatchScopedAuthReuse = $false }
if ($null -eq $script:LogFile -or [string]::IsNullOrWhiteSpace([string]$script:LogFile)) {
    $script:LogFile = Join-Path $env:TEMP 'ShareGate-OneDrive-Migration-Toolkit-preconnect.log'
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:VerificationReportCache = @{}
$script:VerificationRowsByReportPath = @{}


function Merge-CsvIntoMaster {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )
    if ([string]::IsNullOrWhiteSpace($SourcePath) -or -not (Test-Path -LiteralPath $SourcePath)) { return }
    if ([string]::IsNullOrWhiteSpace($DestinationPath)) { return }
    $rows = @()
    try { $rows = @(Import-Csv -LiteralPath $SourcePath) } catch { $rows = @() }
    foreach ($r in $rows) {
        $r | Export-Csv -LiteralPath $DestinationPath -NoTypeInformation -Append
    }
}

function New-WorkerArgumentList {
    param(
        [string]$ScriptPath,
        [string]$WorkerCsvPath,
        [string]$WorkerResultsRoot,
        [string]$Mode,
        [string]$MigrationFolderMode,
        [string]$DefaultSubFolder,
        [string]$SourceLibraryName,
        [string]$DestinationLibraryName,
        [string]$AuthMode,
        [string]$ExecutionMode,
        [bool]$Incremental,
        [bool]$WhatIfOnly,
        [bool]$SkipCompletedFromPriorResults,
        [string]$PriorResultsCsvPath,
        [bool]$ReprocessSuccess,
        [int]$MaxParallelSessions,
        [bool]$ExecuteMigration,
        [int]$MaxRetryCount,
        [int]$RetryDelaySeconds,
        [bool]$ResumeInterrupted,
        [int]$ThrottleDelayMilliseconds,
        [bool]$DetailedErrorReporting,
        [bool]$ShowProgress,
        [string]$VerificationReportPath,
        [bool]$SkipVerification,
        [bool]$BatchScopedAuthReuse
    )
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $ScriptPath),'-CsvPath',('"{0}"' -f $WorkerCsvPath),'-Mode',$Mode,'-MigrationFolderMode',$MigrationFolderMode,'-DefaultSubFolder',('"{0}"' -f $DefaultSubFolder),'-SourceLibraryName',('"{0}"' -f $SourceLibraryName),'-DestinationLibraryName',('"{0}"' -f $DestinationLibraryName),'-ResultsRoot',('"{0}"' -f $WorkerResultsRoot),'-AuthMode',$AuthMode,'-MaxRetryCount',$MaxRetryCount,'-RetryDelaySeconds',$RetryDelaySeconds,'-ThrottleDelayMilliseconds',$ThrottleDelayMilliseconds,'-ExecutionMode','ReuseAuthSerial','-MaxParallelSessions','1','-NoPause')
    if ($Incremental) { $args += '-Incremental' }
    if ($WhatIfOnly) { $args += '-WhatIfOnly' }
    if ($SkipCompletedFromPriorResults) { $args += '-SkipCompletedFromPriorResults' }
    if (-not [string]::IsNullOrWhiteSpace($PriorResultsCsvPath)) { $args += @('-PriorResultsCsvPath',('"{0}"' -f $PriorResultsCsvPath)) }
    if ($ReprocessSuccess) { $args += '-ReprocessSuccess' }
    if ($ExecuteMigration) { $args += '-ExecuteMigration' }
    if ($ResumeInterrupted) { $args += '-ResumeInterrupted' }
    if ($DetailedErrorReporting) { $args += '-DetailedErrorReporting' }
    if ($ShowProgress) { $args += '-ShowProgress' }
    if (-not [string]::IsNullOrWhiteSpace($VerificationReportPath)) { $args += @('-VerificationReportPath',('"{0}"' -f $VerificationReportPath)) }
    if ($SkipVerification) { $args += '-SkipVerification' }
    return ($args -join ' ')
}

function Get-ParallelWorkerAuthMode {
    param([string]$AuthMode, [int]$MaxParallelSessions)
    if ($MaxParallelSessions -gt 1) {
        if ($AuthMode -in @('Auto','ModernAuth')) { return 'Browser' }
    }
    return $AuthMode
}

function Get-LatestWorkerRunFolder {
    param([string]$WorkerResultsRoot)
    if ([string]::IsNullOrWhiteSpace($WorkerResultsRoot) -or -not (Test-Path -LiteralPath $WorkerResultsRoot)) { return $null }
    return (Get-ChildItem -LiteralPath $WorkerResultsRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1)
}

function Wait-WorkerRootConnectionReady {
    param(
        [string]$WorkerResultsRoot,
        [int]$TimeoutSeconds = 120
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $childRun = Get-LatestWorkerRunFolder -WorkerResultsRoot $WorkerResultsRoot
        if ($childRun) {
            $logPath = Join-Path $childRun.FullName 'Migration.log'
            if (Test-Path -LiteralPath $logPath) {
                try {
                    $tail = Get-Content -LiteralPath $logPath -Tail 60 -ErrorAction Stop
                    if (($tail | Select-String -SimpleMatch 'Connected [DestinationRoot]' -Quiet) -or
                        ($tail | Select-String -SimpleMatch 'Connection failed [DestinationRoot]' -Quiet) -or
                        ($tail | Select-String -SimpleMatch 'Connection failed [SourceRoot]' -Quiet)) {
                        return $true
                    }
                }
                catch { }
            }
        }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Get-ParallelLaunchStaggerSeconds {
    param([int]$MaxParallelSessions)
    if ($MaxParallelSessions -ge 5) { return 35 }
    if ($MaxParallelSessions -eq 4) { return 30 }
    if ($MaxParallelSessions -eq 3) { return 25 }
    return 20
}

function Invoke-ParallelAuthWarmup {
    param(
        [object[]]$Rows,
        [string]$Mode,
        [string]$AuthMode
    )
    if (-not @($Rows) -or @($Rows).Count -eq 0) { return }
    $workerAuthMode = Get-ParallelWorkerAuthMode -AuthMode $AuthMode -MaxParallelSessions 2
    Write-Log -Level STEP -Message ('Parallel auth warm-up starting using [{0}] mode. Complete the browser sign-in once and keep the browser session open so worker processes can attempt reuse.' -f $workerAuthMode)
    $firstRow = @($Rows)[0]
    $roots = New-Object System.Collections.Generic.List[string]
    if ($Mode -in @('Migrate','ValidateOnly')) {
        $sourceRoot = Get-RootSiteUrl -PersonalSiteUrl $firstRow.SourceSite
        if (-not [string]::IsNullOrWhiteSpace($sourceRoot)) { [void]$roots.Add($sourceRoot) }
    }
    $destinationRoot = Get-RootSiteUrl -PersonalSiteUrl $firstRow.DestinationSite
    if (-not [string]::IsNullOrWhiteSpace($destinationRoot)) { [void]$roots.Add($destinationRoot) }
    $labelIndex = 0
    foreach ($root in @($roots | Select-Object -Unique)) {
        $labelIndex++
        try {
            [void](Connect-ShareGateSite -Url $root -Mode $workerAuthMode -Label ('ParallelWarmupRoot{0}' -f $labelIndex))
        }
        catch {
            Write-Log -Level WARN -Message ('Parallel auth warm-up failed for {0}: {1}' -f $root, $_.Exception.Message)
        }
    }
    Start-Sleep -Seconds 8
    Write-Log -Level INFO -Message 'Parallel auth warm-up completed. Browser session reuse window opened for parallel workers.'
}

function Split-RowsIntoBatches {
    param(
        [object[]]$Rows,
        [int]$BatchCount
    )

    $rowArray = @($Rows)
    if ($rowArray.Count -eq 0) { return @() }

    $hasBatchColumn = $false
    foreach ($row in $rowArray) {
        if ($row.PSObject.Properties.Name -contains 'Batch') {
            $hasBatchColumn = $true
            break
        }
    }

    if ($hasBatchColumn) {
        $manualRows = @($rowArray | Where-Object {
            $_.PSObject.Properties.Name -contains 'Batch' -and -not [string]::IsNullOrWhiteSpace([string]$_.Batch)
        })
        if ($manualRows.Count -gt 0) {
            $groups = $manualRows | Group-Object { ([string]$_.Batch).Trim() } | Sort-Object Name
            $result = @()
            foreach ($group in $groups) {
                $result += [pscustomobject]@{
                    Name = $group.Name
                    Rows = @($group.Group)
                    IsManual = $true
                }
            }

            $unassignedRows = @($rowArray | Where-Object {
                -not ($_.PSObject.Properties.Name -contains 'Batch') -or [string]::IsNullOrWhiteSpace([string]$_.Batch)
            })
            if ($unassignedRows.Count -gt 0) {
                $result += [pscustomobject]@{
                    Name = 'Batch-Unassigned'
                    Rows = $unassignedRows
                    IsManual = $false
                }
            }
            return $result
        }
    }

    $actualBatchCount = [Math]::Max(1, [Math]::Min($BatchCount, $rowArray.Count))
    $batches = @()
    for ($i = 0; $i -lt $actualBatchCount; $i++) {
        $batches += ,(New-Object System.Collections.Generic.List[object])
    }
    $cursor = 0
    foreach ($row in $rowArray) {
        $batches[$cursor].Add($row)
        $cursor = ($cursor + 1) % $actualBatchCount
    }

    $result = @()
    for ($i = 0; $i -lt $batches.Count; $i++) {
        $result += [pscustomobject]@{
            Name = ('Batch-{0:D2}' -f ($i + 1))
            Rows = @($batches[$i])
            IsManual = $false
        }
    }
    return $result
}

function Invoke-ParallelBatchProcessing {
    param(
        [object[]]$Rows,
        [string]$CsvPath,
        [int]$MaxParallelSessions,
        [string]$RunFolder,
        [string]$ScriptPath,
        [string]$Mode,
        [string]$MigrationFolderMode,
        [string]$DefaultSubFolder,
        [string]$SourceLibraryName,
        [string]$DestinationLibraryName,
        [string]$AuthMode,
        [string]$ExecutionMode,
        [string]$ConnectionProfileStatus,
        [bool]$Incremental,
        [bool]$WhatIfOnly,
        [bool]$SkipCompletedFromPriorResults,
        [string]$PriorResultsCsvPath,
        [bool]$ReprocessSuccess,
        [bool]$ExecuteMigration,
        [int]$MaxRetryCount,
        [int]$RetryDelaySeconds,
        [bool]$ResumeInterrupted,
        [int]$ThrottleDelayMilliseconds,
        [bool]$DetailedErrorReporting,
        [bool]$ShowProgress,
        [string]$VerificationReportPath,
        [bool]$SkipVerification,
        [bool]$BatchScopedAuthReuse
    )
    $workerRoot = Join-Path $RunFolder 'BatchWorkers'
    New-Item -ItemType Directory -Path $workerRoot -Force | Out-Null
    $requestedWorkerCount = [Math]::Max(1, [Math]::Min($MaxParallelSessions, @($Rows).Count))
    $batchGroups = @(Split-RowsIntoBatches -Rows $Rows -BatchCount $requestedWorkerCount)
    if ($batchGroups.Count -eq 0) {
        Write-Log -Level WARN -Message 'ParallelBatches dispatcher found no eligible rows to launch.'
        return
    }

    $workerAuthMode = Get-ParallelWorkerAuthMode -AuthMode $AuthMode -MaxParallelSessions $requestedWorkerCount
    $workerLaunchStaggerSeconds = Get-ParallelLaunchStaggerSeconds -MaxParallelSessions $requestedWorkerCount
    $active = @()
    $engine = 'powershell.exe'
    $nextBatchIndex = 0
    $manualBatchNames = @($batchGroups | Where-Object { $_.IsManual } | ForEach-Object { $_.Name })
    if ($manualBatchNames.Count -gt 0) {
        Write-Log -Level INFO -Message ("ParallelBatches detected manual batch grouping from CSV column [Batch]: {0}" -f ($manualBatchNames -join ', '))
    }
    Write-Log -Level INFO -Message ("ParallelBatches dispatcher starting with up to {0} concurrent worker(s) across {1} batch group(s) for {2} row(s). Worker auth mode = {3}. Launch stagger = {4} second(s)." -f $requestedWorkerCount, $batchGroups.Count, @($Rows).Count, $workerAuthMode, $workerLaunchStaggerSeconds)

    while ($nextBatchIndex -lt $batchGroups.Count -or $active.Count -gt 0) {
        while ($active.Count -lt $requestedWorkerCount -and $nextBatchIndex -lt $batchGroups.Count) {
            $batchGroup = $batchGroups[$nextBatchIndex]
            $batchRows = @($batchGroup.Rows)
            if ($batchRows.Count -eq 0) {
                $nextBatchIndex++
                continue
            }
            $safeBatchName = (($batchGroup.Name -replace '[^A-Za-z0-9._-]', '_').Trim('_'))
            if ([string]::IsNullOrWhiteSpace($safeBatchName)) {
                $safeBatchName = ('Batch-{0:D2}' -f ($nextBatchIndex + 1))
            }
            $batchFolder = Join-Path $workerRoot $safeBatchName
            New-Item -ItemType Directory -Path $batchFolder -Force | Out-Null
            $workerCsvPath = Join-Path $batchFolder 'WorkerInput.csv'
            $batchRows | Export-Csv -LiteralPath $workerCsvPath -NoTypeInformation
            $workerResultsRoot = Join-Path $batchFolder 'ResultsRoot'
            New-Item -ItemType Directory -Path $workerResultsRoot -Force | Out-Null
            $argList = New-WorkerArgumentList -ScriptPath $ScriptPath -WorkerCsvPath $workerCsvPath -WorkerResultsRoot $workerResultsRoot -Mode $Mode -MigrationFolderMode $MigrationFolderMode -DefaultSubFolder $DefaultSubFolder -SourceLibraryName $SourceLibraryName -DestinationLibraryName $DestinationLibraryName -AuthMode $workerAuthMode -Incremental:$Incremental -WhatIfOnly:$WhatIfOnly -SkipCompletedFromPriorResults:$SkipCompletedFromPriorResults -PriorResultsCsvPath $PriorResultsCsvPath -ReprocessSuccess:$ReprocessSuccess -ExecuteMigration:$ExecuteMigration -MaxRetryCount $MaxRetryCount -RetryDelaySeconds $RetryDelaySeconds -ResumeInterrupted:$ResumeInterrupted -ThrottleDelayMilliseconds $ThrottleDelayMilliseconds -DetailedErrorReporting:$DetailedErrorReporting -ShowProgress:$false -VerificationReportPath $VerificationReportPath -SkipVerification:$SkipVerification -BatchScopedAuthReuse:$BatchScopedAuthReuse
            $proc = Start-Process -FilePath $engine -ArgumentList $argList -PassThru -WindowStyle Normal
            Write-Log -Level INFO -Message ("Started batch worker [{0}] with PID {1} for {2} row(s)." -f $batchGroup.Name, $proc.Id, $batchRows.Count)
            $active += [pscustomobject]@{ Index = ($nextBatchIndex + 1); Name = $batchGroup.Name; WorkerResultsRoot = $workerResultsRoot; Process = $proc }
            $warmupReady = Wait-WorkerRootConnectionReady -WorkerResultsRoot $workerResultsRoot -TimeoutSeconds 180
            if ($warmupReady) {
                Write-Log -Level INFO -Message ("Batch worker [{0}] passed the root-connection gate; staggering next batch launch by {1} second(s)." -f $batchGroup.Name, $workerLaunchStaggerSeconds)
            }
            else {
                Write-Log -Level WARN -Message ("Batch worker [{0}] did not signal root-connection readiness within the timeout; continuing with conservative stagger of {1} second(s)." -f $batchGroup.Name, $workerLaunchStaggerSeconds)
            }
            $nextBatchIndex++
            if ($nextBatchIndex -lt $batchGroups.Count) {
                Start-Sleep -Seconds $workerLaunchStaggerSeconds
            }
        }

        if ($active.Count -gt 0) {
            Start-Sleep -Seconds 2
        }

        $remaining = @()
        foreach ($worker in $active) {
            if ($worker.Process.HasExited) {
                Write-Log -Level INFO -Message ("Batch worker [{0}] exited with code {1}." -f $worker.Name, $worker.Process.ExitCode)
                $childRun = Get-ChildItem -LiteralPath $worker.WorkerResultsRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
                if ($childRun) {
                    Merge-CsvIntoMaster -SourcePath (Join-Path $childRun.FullName 'Results.csv') -DestinationPath $script:ResultsCsv
                    Merge-CsvIntoMaster -SourcePath (Join-Path $childRun.FullName 'MigrationState.csv') -DestinationPath $script:StateCsv
                    Merge-CsvIntoMaster -SourcePath (Join-Path $childRun.FullName 'RootFileVerification.csv') -DestinationPath $script:VerificationCsv
                    Merge-CsvIntoMaster -SourcePath (Join-Path $childRun.FullName 'PerUserValidationSummary.csv') -DestinationPath $script:ValidationSummaryCsv
                    if ($DetailedErrorReporting) {
                        Merge-CsvIntoMaster -SourcePath (Join-Path $childRun.FullName 'Errors.csv') -DestinationPath $script:ErrorsCsv
                    }
                }
            }
            else {
                $remaining += $worker
            }
        }
        $active = @($remaining)
    }

    $resultsRows = @(); try { $resultsRows = @(Import-Csv -LiteralPath $script:ResultsCsv) } catch {}
    $successCount = @($resultsRows | Where-Object { $_.Status -eq 'Success' -or $_.Status -eq 'Completed' }).Count
    $failureCount = @($resultsRows | Where-Object { $_.Status -eq 'Failed' }).Count
    $skippedCount = @($resultsRows | Where-Object { $_.Status -eq 'Skipped' }).Count
    return [pscustomobject]@{ SuccessCount = $successCount; FailureCount = $failureCount; SkippedCount = $skippedCount }
}

function Invoke-ParallelRowProcessing {
    param(
        [object[]]$Rows,
        [string]$CsvPath,
        [int]$MaxParallelSessions,
        [string]$RunFolder,
        [string]$ScriptPath,
        [string]$Mode,
        [string]$MigrationFolderMode,
        [string]$DefaultSubFolder,
        [string]$SourceLibraryName,
        [string]$DestinationLibraryName,
        [string]$AuthMode,
        [bool]$Incremental,
        [bool]$WhatIfOnly,
        [bool]$SkipCompletedFromPriorResults,
        [string]$PriorResultsCsvPath,
        [bool]$ReprocessSuccess,
        [bool]$ExecuteMigration,
        [int]$MaxRetryCount,
        [int]$RetryDelaySeconds,
        [bool]$ResumeInterrupted,
        [int]$ThrottleDelayMilliseconds,
        [bool]$DetailedErrorReporting,
        [bool]$ShowProgress,
        [string]$VerificationReportPath,
        [bool]$SkipVerification
    )
    $workerRoot = Join-Path $RunFolder 'ParallelWorkers'
    New-Item -ItemType Directory -Path $workerRoot -Force | Out-Null
    $workerAuthMode = Get-ParallelWorkerAuthMode -AuthMode $AuthMode -MaxParallelSessions $MaxParallelSessions
    $workerLaunchStaggerSeconds = Get-ParallelLaunchStaggerSeconds -MaxParallelSessions $MaxParallelSessions
    $queue = New-Object System.Collections.Queue
    $rowIndex = 0
    foreach ($row in @($Rows)) {
        $rowIndex++
        $rowFolder = Join-Path $workerRoot ('Row-{0:D4}' -f $rowIndex)
        New-Item -ItemType Directory -Path $rowFolder -Force | Out-Null
        $workerCsvPath = Join-Path $rowFolder 'WorkerInput.csv'
        @($row) | Export-Csv -LiteralPath $workerCsvPath -NoTypeInformation
        $queue.Enqueue([pscustomobject]@{ Index = $rowIndex; RowFolder = $rowFolder; WorkerCsvPath = $workerCsvPath })
    }

    $active = @()
    $engine = 'powershell.exe'
    Write-Log -Level INFO -Message ("Parallel dispatcher starting with MaxParallelSessions={0} for {1} row(s). Worker auth mode = {2}. Launch stagger = {3} second(s)." -f $MaxParallelSessions, @($Rows).Count, $workerAuthMode, $workerLaunchStaggerSeconds)

    while ($queue.Count -gt 0 -or $active.Count -gt 0) {
        while ($queue.Count -gt 0 -and $active.Count -lt $MaxParallelSessions) {
            $item = $queue.Dequeue()
            $workerResultsRoot = Join-Path $item.RowFolder 'ResultsRoot'
            New-Item -ItemType Directory -Path $workerResultsRoot -Force | Out-Null
            $argList = New-WorkerArgumentList -ScriptPath $ScriptPath -WorkerCsvPath $item.WorkerCsvPath -WorkerResultsRoot $workerResultsRoot -Mode $Mode -MigrationFolderMode $MigrationFolderMode -DefaultSubFolder $DefaultSubFolder -SourceLibraryName $SourceLibraryName -DestinationLibraryName $DestinationLibraryName -AuthMode $AuthMode -Incremental:$Incremental -WhatIfOnly:$WhatIfOnly -SkipCompletedFromPriorResults:$SkipCompletedFromPriorResults -PriorResultsCsvPath $PriorResultsCsvPath -ReprocessSuccess:$ReprocessSuccess -ExecuteMigration:$ExecuteMigration -MaxRetryCount $MaxRetryCount -RetryDelaySeconds $RetryDelaySeconds -ResumeInterrupted:$ResumeInterrupted -ThrottleDelayMilliseconds $ThrottleDelayMilliseconds -DetailedErrorReporting:$DetailedErrorReporting -ShowProgress:$false -VerificationReportPath $VerificationReportPath -SkipVerification:$SkipVerification -BatchScopedAuthReuse:$BatchScopedAuthReuse
            $proc = Start-Process -FilePath $engine -ArgumentList $argList -PassThru -WindowStyle Normal
            Write-Log -Level INFO -Message ("Started worker for row {0} with PID {1}." -f $item.Index, $proc.Id)
            $active += [pscustomobject]@{ Index = $item.Index; RowFolder = $item.RowFolder; WorkerResultsRoot = $workerResultsRoot; Process = $proc }
            $warmupReady = Wait-WorkerRootConnectionReady -WorkerResultsRoot $workerResultsRoot -TimeoutSeconds 120
            if ($warmupReady) {
                Write-Log -Level INFO -Message ("Worker for row {0} passed the root-connection gate; staggering next worker launch by {1} second(s)." -f $item.Index, $workerLaunchStaggerSeconds)
            }
            else {
                Write-Log -Level WARN -Message ("Worker for row {0} did not signal root-connection readiness within the timeout; continuing with conservative stagger of {1} second(s)." -f $item.Index, $workerLaunchStaggerSeconds)
            }
            Start-Sleep -Seconds $workerLaunchStaggerSeconds
        }

        Start-Sleep -Seconds 2
        $remaining = @()
        foreach ($worker in $active) {
            if ($worker.Process.HasExited) {
                Write-Log -Level INFO -Message ("Worker for row {0} exited with code {1}." -f $worker.Index, $worker.Process.ExitCode)
                $childRun = Get-ChildItem -LiteralPath $worker.WorkerResultsRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
                if ($childRun) {
                    Merge-CsvIntoMaster -SourcePath (Join-Path $childRun.FullName 'Results.csv') -DestinationPath $script:ResultsCsv
                    Merge-CsvIntoMaster -SourcePath (Join-Path $childRun.FullName 'MigrationState.csv') -DestinationPath $script:StateCsv
                    Merge-CsvIntoMaster -SourcePath (Join-Path $childRun.FullName 'RootFileVerification.csv') -DestinationPath $script:VerificationCsv
                    if ($DetailedErrorReporting) {
                        Merge-CsvIntoMaster -SourcePath (Join-Path $childRun.FullName 'Errors.csv') -DestinationPath $script:ErrorsCsv
                    }
                }
            }
            else {
                $remaining += $worker
            }
        }
        $active = @($remaining)
    }

    $resultsRows = @(); try { $resultsRows = @(Import-Csv -LiteralPath $script:ResultsCsv) } catch {}
    $successCount = @($resultsRows | Where-Object { $_.Status -eq 'Success' -or $_.Status -eq 'Completed' }).Count
    $failureCount = @($resultsRows | Where-Object { $_.Status -eq 'Failed' }).Count
    $skippedCount = @($resultsRows | Where-Object { $_.Status -eq 'Skipped' }).Count
    return [pscustomobject]@{ SuccessCount = $successCount; FailureCount = $failureCount; SkippedCount = $skippedCount }
}

function Assert-Module {
    param([string]$Name)
    $module = Get-Module -ListAvailable -Name $Name | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $module) {
        throw "Module $Name not found"
    }
}

function New-RunFolder {
    param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root)) {
        New-Item -ItemType Directory -Path $Root -Force | Out-Null
    }
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $path = Join-Path $Root $ts
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Write-Log {
    param([ValidateSet('INFO','WARN','ERROR','SUCCESS','STEP')][string]$Level, [string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"
    $color = switch ($Level) {
        'SUCCESS' { 'Green' }
        'ERROR'   { 'Red' }
        'WARN'    { 'Yellow' }
        'STEP'    { 'Cyan' }
        default   { 'White' }
    }
    Write-Host $line -ForegroundColor $color
    if ($script:LogFile) {
        Add-Content -LiteralPath $script:LogFile -Value $line
    }
}

function Initialize-CsvFile {
    param(
        [string]$Path,
        [pscustomobject]$TemplateRow,
        [string]$Label
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or $null -eq $TemplateRow) { return }
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        $header = ($TemplateRow | ConvertTo-Csv -NoTypeInformation | Select-Object -First 1)
        Set-Content -LiteralPath $Path -Value $header -Encoding UTF8
        if (-not [string]::IsNullOrWhiteSpace($Label)) {
            Write-Log -Level INFO -Message "$Label initialized: $Path"
        }
    }
}

function Save-ResultRow {
    param([pscustomobject]$Row)
    $append = Test-Path -LiteralPath $script:ResultsCsv
    $Row | Export-Csv -LiteralPath $script:ResultsCsv -NoTypeInformation -Append:$append
}

function Save-ErrorRow {
    param([pscustomobject]$Row)
    if (-not $script:ErrorsCsv) { return }
    $append = Test-Path -LiteralPath $script:ErrorsCsv
    $Row | Export-Csv -LiteralPath $script:ErrorsCsv -NoTypeInformation -Append:$append
}

function Save-VerificationRow {
    param([pscustomobject]$Row)
    if (-not $script:VerificationCsv) { return }
    if ($null -eq $Row) { return }
    if (-not (Test-Path -LiteralPath $script:VerificationCsv)) {
        Initialize-CsvFile -Path $script:VerificationCsv -TemplateRow $Row -Label 'Verification CSV'
    }
    try {
        $Row | Export-Csv -LiteralPath $script:VerificationCsv -NoTypeInformation -Append
        Write-Log -Level INFO -Message ("Verification row saved: Row {0}; Status={1}" -f $Row.Index, $Row.VerificationStatus)
    }
    catch {
        Write-Log -Level ERROR -Message ("Failed to write verification row for Row {0}: {1}" -f $Row.Index, $_.Exception.Message)
        throw
    }
}

function Save-ValidationSummaryRow {
    param([pscustomobject]$Row)
    if (-not $script:ValidationSummaryCsv) { return }
    if ($null -eq $Row) { return }
    if (-not (Test-Path -LiteralPath $script:ValidationSummaryCsv)) {
        Initialize-CsvFile -Path $script:ValidationSummaryCsv -TemplateRow $Row -Label 'Validation summary CSV'
    }
    try {
        $Row | Export-Csv -LiteralPath $script:ValidationSummaryCsv -NoTypeInformation -Append
        Write-Log -Level INFO -Message ("Validation summary row saved: Row {0}; Classification={1}" -f $Row.Index, $Row.ValidationClassification)
    }
    catch {
        Write-Log -Level ERROR -Message ("Failed to write validation summary row for Row {0}: {1}" -f $Row.Index, $_.Exception.Message)
        throw
    }
}

function Save-StateRow {
    param([pscustomobject]$Row)
    if (-not $script:StateCsv) { return }

    $existing = @()
    if (Test-Path -LiteralPath $script:StateCsv) {
        try { $existing = @(Import-Csv -LiteralPath $script:StateCsv) } catch { $existing = @() }
    }

    $filtered = @($existing | Where-Object { $_.RowKey -ne $Row.RowKey })
    $filtered += $Row
    $filtered | Sort-Object RowIndex | Export-Csv -LiteralPath $script:StateCsv -NoTypeInformation
}

function Get-StateLookup {
    param([string]$Path)
    $lookup = @{}
    if ([string]::IsNullOrWhiteSpace($Path)) { return $lookup }
    if (-not (Test-Path -LiteralPath $Path)) { return $lookup }

    $rows = @(Import-Csv -LiteralPath $Path)
    foreach ($row in $rows) {
        if (-not [string]::IsNullOrWhiteSpace($row.RowKey)) {
            $lookup[$row.RowKey] = $row
        }
    }
    return $lookup
}

function Get-ExceptionText {
    param([System.Exception]$Exception)
    $list = @()
    $cur = $Exception
    while ($null -ne $cur) {
        $list += $cur.Message
        $cur = $cur.InnerException
    }
    return ($list -join ' | ')
}

function Get-RootSiteUrl {
    param([string]$PersonalSiteUrl)
    try {
        $uri = [System.Uri]$PersonalSiteUrl
        return ('{0}://{1}/' -f $uri.Scheme, $uri.Host)
    }
    catch {
        throw "Invalid URL: $PersonalSiteUrl"
    }
}

function Get-CsvPathInteractive {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = 'Select CSV file'
    $dialog.Filter = 'CSV files (*.csv)|*.csv'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    }
    throw 'CSV selection cancelled'
}

function Normalize-PathSegment {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return $Value.Trim().Trim('/').Trim('\\')
}

function Resolve-TargetSubFolder {
    param([psobject]$Row, [string]$FolderMode, [string]$DefaultFolder)
    $csvFolder = ''
    if ($Row -and $Row.PSObject.Properties.Name -contains 'SubFolder') {
        $csvFolder = Normalize-PathSegment -Value ([string]$Row.SubFolder)
    }
    switch ($FolderMode) {
        'Root' { return '' }
        'Subfolder' {
            if (-not [string]::IsNullOrWhiteSpace($csvFolder)) { return $csvFolder }
            return (Normalize-PathSegment -Value $DefaultFolder)
        }
        default {
            return (Normalize-PathSegment -Value $DefaultFolder)
        }
    }
}

function Get-RowValue {
    param([psobject]$Row, [string]$PropertyName)
    if ($null -eq $Row) { return '' }
    if ($Row.PSObject.Properties.Name -contains $PropertyName) {
        return [string]$Row.$PropertyName
    }
    return ''
}

function New-RowKey {
    param([int]$Index, [string]$SourceSite, [string]$DestinationSite, [string]$ResolvedSubFolder)
    return ('{0}|{1}|{2}|{3}' -f $Index, $SourceSite, $DestinationSite, $ResolvedSubFolder)
}

function Build-ResultRow {
    param(
        [string]$Operation,
        [datetime]$Started,
        [datetime]$Ended,
        [int]$Index,
        [string]$RowKey,
        [string]$UserPrincipalName,
        [string]$SourceSite,
        [string]$DestinationSite,
        [string]$SourceLibrary,
        [string]$DestinationLibrary,
        [string]$CsvSubFolder,
        [string]$ResolvedSubFolder,
        [string]$MigrationFolderMode,
        [string]$FolderAction,
        [string]$Status,
        [string]$TaskName,
        [string]$ErrorMessage,
        [string]$Note,
        [bool]$FolderExistsBefore,
        [bool]$FolderExistsAfter,
        [bool]$IncrementalEnabled,
        [bool]$WhatIfEnabled,
        [string]$AuthModeUsed,
        [int]$RetryAttempt,
        [string]$ExecutionMode
    )
    $duration = [math]::Round((New-TimeSpan -Start $Started -End $Ended).TotalSeconds, 2)
    return [pscustomobject]@{
        TimestampStart       = $Started.ToString('s')
        TimestampEnd         = $Ended.ToString('s')
        DurationSeconds      = $duration
        Index                = $Index
        RowKey               = $RowKey
        Operation            = $Operation
        Status               = $Status
        RetryAttempt         = $RetryAttempt
        ExecutionMode        = $ExecutionMode
        UserPrincipalName    = $UserPrincipalName
        SourceSite           = $SourceSite
        DestinationSite      = $DestinationSite
        SourceLibrary        = $SourceLibrary
        DestinationLibrary   = $DestinationLibrary
        CsvSubFolder         = $CsvSubFolder
        ResolvedSubFolder    = $ResolvedSubFolder
        MigrationFolderMode  = $MigrationFolderMode
        FolderAction         = $FolderAction
        FolderExistsBefore   = $FolderExistsBefore
        FolderExistsAfter    = $FolderExistsAfter
        TaskName             = $TaskName
        Incremental          = $IncrementalEnabled
        WhatIf               = $WhatIfEnabled
        AuthMode             = $AuthModeUsed
        ErrorMessage         = $ErrorMessage
        Note                 = $Note
    }
}

function Build-ErrorRow {
    param(
        [int]$Index,
        [string]$RowKey,
        [string]$Operation,
        [string]$SourceSite,
        [string]$DestinationSite,
        [string]$ResolvedSubFolder,
        [int]$RetryAttempt,
        [string]$ErrorMessage,
        [string]$ErrorType,
        [string]$StackTrace,
        [string]$UserPrincipalName,
        [string]$Note
    )
    [pscustomobject]@{
        Timestamp         = (Get-Date).ToString('s')
        Index             = $Index
        RowKey            = $RowKey
        Operation         = $Operation
        RetryAttempt      = $RetryAttempt
        UserPrincipalName = $UserPrincipalName
        SourceSite        = $SourceSite
        DestinationSite   = $DestinationSite
        ResolvedSubFolder = $ResolvedSubFolder
        ErrorType         = $ErrorType
        ErrorMessage      = $ErrorMessage
        StackTrace        = $StackTrace
        Note              = $Note
    }
}


function Build-VerificationRow {
    param(
        [int]$Index,
        [string]$RowKey,
        [string]$UserPrincipalName,
        [string]$SourceSite,
        [string]$DestinationSite,
        [string]$SourceLibrary,
        [string]$DestinationLibrary,
        [string]$ResolvedSubFolder,
        [string]$VerificationStatus,
        [int]$SourceRootFileCount,
        [int]$DestinationRootFileCount,
        [string[]]$MissingFileNames,
        [string[]]$ExtraFileNames,
        [string]$VerificationMessage
    )
    $missing = @($MissingFileNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $extra = @($ExtraFileNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    [pscustomobject]@{
        Timestamp                = (Get-Date).ToString('s')
        Index                    = $Index
        RowKey                   = $RowKey
        UserPrincipalName        = $UserPrincipalName
        SourceSite               = $SourceSite
        DestinationSite          = $DestinationSite
        SourceLibrary            = $SourceLibrary
        DestinationLibrary       = $DestinationLibrary
        ResolvedSubFolder        = $ResolvedSubFolder
        SourceRootFileCount      = $SourceRootFileCount
        DestinationRootFileCount = $DestinationRootFileCount
        MissingRootFileCount     = @($missing).Count
        ExtraRootFileCount       = @($extra).Count
        MissingRootFilesSample   = (@($missing) | Select-Object -First 20) -join '; '
        ExtraRootFilesSample     = (@($extra) | Select-Object -First 20) -join '; '
        VerificationStatus       = $VerificationStatus
        VerificationMessage      = $VerificationMessage
    }
}

function New-SkippedVerificationRow {
    param(
        [int]$Index,
        [string]$RowKey,
        [string]$UserPrincipalName,
        [string]$SourceSite,
        [string]$DestinationSite,
        [string]$SourceLibrary,
        [string]$DestinationLibrary,
        [string]$ResolvedSubFolder,
        [string]$Message
    )
    return (Build-VerificationRow -Index $Index -RowKey $RowKey -UserPrincipalName $UserPrincipalName -SourceSite $SourceSite -DestinationSite $DestinationSite -SourceLibrary $SourceLibrary -DestinationLibrary $DestinationLibrary -ResolvedSubFolder $ResolvedSubFolder -VerificationStatus 'Skipped' -SourceRootFileCount 0 -DestinationRootFileCount 0 -MissingFileNames @() -ExtraFileNames @() -VerificationMessage $Message)
}

function Build-ValidationSummaryRow {
    param(
        [pscustomobject]$ResultRow,
        [pscustomobject]$VerificationRow
    )

    $resultStatus = ''
    $sourceSite = ''
    $destinationSite = ''
    $sourceLibrary = ''
    $destinationLibrary = ''
    $resolvedSubFolder = ''
    $userPrincipalName = ''
    $index = 0
    $rowKey = ''
    $taskName = ''
    $durationSeconds = 0
    $errorMessage = ''
    $verificationStatus = 'NotRun'
    $verificationMessage = 'Verification did not run.'
    $sourceRootFileCount = 0
    $destinationRootFileCount = 0
    $missingRootFileCount = 0
    $extraRootFileCount = 0
    $missingSample = ''
    $extraSample = ''

    if ($ResultRow) {
        $resultStatus = [string]$ResultRow.Status
        $sourceSite = [string]$ResultRow.SourceSite
        $destinationSite = [string]$ResultRow.DestinationSite
        $sourceLibrary = [string]$ResultRow.SourceLibrary
        $destinationLibrary = [string]$ResultRow.DestinationLibrary
        $resolvedSubFolder = [string]$ResultRow.ResolvedSubFolder
        $userPrincipalName = [string]$ResultRow.UserPrincipalName
        $index = [int]$ResultRow.Index
        $rowKey = [string]$ResultRow.RowKey
        $taskName = [string]$ResultRow.TaskName
        $errorMessage = [string]$ResultRow.ErrorMessage
        try { $durationSeconds = [double]$ResultRow.DurationSeconds } catch { $durationSeconds = 0 }
    }

    if ($VerificationRow) {
        $verificationStatus = [string]$VerificationRow.VerificationStatus
        $verificationMessage = [string]$VerificationRow.VerificationMessage
        try { $sourceRootFileCount = [int]$VerificationRow.SourceRootFileCount } catch { $sourceRootFileCount = 0 }
        try { $destinationRootFileCount = [int]$VerificationRow.DestinationRootFileCount } catch { $destinationRootFileCount = 0 }
        try { $missingRootFileCount = [int]$VerificationRow.MissingRootFileCount } catch { $missingRootFileCount = 0 }
        try { $extraRootFileCount = [int]$VerificationRow.ExtraRootFileCount } catch { $extraRootFileCount = 0 }
        $missingSample = [string]$VerificationRow.MissingRootFilesSample
        $extraSample = [string]$VerificationRow.ExtraRootFilesSample
        if ([string]::IsNullOrWhiteSpace($resolvedSubFolder)) { $resolvedSubFolder = [string]$VerificationRow.ResolvedSubFolder }
    }

    $classification = 'Review'
    $summary = ''
    if ($resultStatus -eq 'Failed') {
        $classification = 'MigrationFailed'
        $summary = 'Migration failed before validation completed.'
    }
    elseif ($verificationStatus -eq 'Passed') {
        $classification = 'Validated'
        $summary = 'Root-file verification passed.'
    }
    elseif ($verificationStatus -eq 'Completed' -and $missingRootFileCount -gt 0) {
        $classification = 'PossibleMissingItems'
        $summary = 'Verification found root-file mismatches.'
    }
    elseif ($verificationStatus -eq 'Skipped' -and $sourceRootFileCount -eq 0 -and $destinationRootFileCount -eq 0) {
        $classification = 'NeedsManualReview'
        $summary = 'Verification was skipped or could not be completed. Review task report and compare counts.'
    }
    elseif ($verificationStatus -eq 'Completed') {
        $classification = 'ValidatedWithDifferences'
        $summary = 'Verification completed with differences that need review.'
    }
    else {
        $classification = 'NeedsManualReview'
        $summary = 'Validation summary generated; inspect migration report and counts.'
    }

    [pscustomobject]@{
        Timestamp                    = (Get-Date).ToString('s')
        Index                        = $index
        RowKey                       = $rowKey
        UserPrincipalName            = $userPrincipalName
        SourceSite                   = $sourceSite
        DestinationSite              = $destinationSite
        SourceLibrary                = $sourceLibrary
        DestinationLibrary           = $destinationLibrary
        ResolvedSubFolder            = $resolvedSubFolder
        MigrationStatus              = $resultStatus
        VerificationStatus           = $verificationStatus
        ValidationClassification     = $classification
        ValidationSummary            = $summary
        TaskName                     = $taskName
        DurationSeconds              = $durationSeconds
        SourceRootFileCount          = $sourceRootFileCount
        DestinationRootFileCount     = $destinationRootFileCount
        MissingRootFileCount         = $missingRootFileCount
        ExtraRootFileCount           = $extraRootFileCount
        MissingRootFilesSample       = $missingSample
        ExtraRootFilesSample         = $extraSample
        VerificationMessage          = $verificationMessage
        MigrationErrorMessage        = $errorMessage
    }
}

function ConvertTo-NormalizedServerRelativePath {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $normalized = ([string]$Value).Trim() -replace '\\','/'
    if ($normalized -match '^[a-z]+://') {
        try {
            $u = [System.Uri]$normalized
            $normalized = $u.AbsolutePath
        }
        catch { }
    }
    if (-not $normalized.StartsWith('/')) { $normalized = '/' + $normalized }
    $normalized = $normalized.TrimEnd('/')
    return $normalized
}

function Get-ChildPathSegment {
    param([string]$ParentPath, [string]$ChildPath)
    if ([string]::IsNullOrWhiteSpace($ChildPath)) { return '' }
    $parent = ConvertTo-NormalizedServerRelativePath -Value $ParentPath
    $child = ConvertTo-NormalizedServerRelativePath -Value $ChildPath
    if ([string]::IsNullOrWhiteSpace($parent)) { return $child.Trim('/') }
    if ($child.StartsWith($parent + '/')) {
        return $child.Substring($parent.Length + 1)
    }
    return ''
}

function Get-ItemPathValue {
    param([object]$Item)
    if ($null -eq $Item) { return '' }
    foreach ($name in @('ServerRelativeUrl','ServerRelativePath','Path','Url','FileRef')) {
        if ($Item.PSObject.Properties.Name -contains $name -and -not [string]::IsNullOrWhiteSpace([string]$Item.$name)) {
            return [string]$Item.$name
        }
    }
    return ''
}

function Get-ItemNameValue {
    param([object]$Item)
    if ($null -eq $Item) { return '' }
    foreach ($name in @('Name','Title','LeafName','FileLeafRef')) {
        if ($Item.PSObject.Properties.Name -contains $name -and -not [string]::IsNullOrWhiteSpace([string]$Item.$name)) {
            return [string]$Item.$name
        }
    }
    $path = Get-ItemPathValue -Item $Item
    if (-not [string]::IsNullOrWhiteSpace($path)) {
        return [System.IO.Path]::GetFileName($path)
    }
    return ''
}

function Test-ItemIsFolder {
    param([object]$Item)
    if ($null -eq $Item) { return $false }
    foreach ($name in @('IsFolder','Folder','FSObjType')) {
        if ($Item.PSObject.Properties.Name -contains $name) {
            $value = $Item.$name
            if ($name -eq 'FSObjType') { return ([int]$value -eq 1) }
            if ($value -is [bool]) { return [bool]$value }
            if ($null -ne $value) {
                $str = ([string]$value).Trim().ToLowerInvariant()
                if ($str -in @('true','folder','1')) { return $true }
                if ($str -in @('false','file','0')) { return $false }
            }
        }
    }
    $path = Get-ItemPathValue -Item $Item
    if ($path.EndsWith('/')) { return $true }
    return $false
}

function Get-RootFileNamesFromListObject {
    param([object]$List, [string]$RootFolderPath)
    $rootFolderPath = ConvertTo-NormalizedServerRelativePath -Value $RootFolderPath
    if ($null -eq $List) { return @() }
    $candidateCollections = @()
    foreach ($prop in @('Files','Items')) {
        if ($List.PSObject.Properties.Name -contains $prop -and $null -ne $List.$prop) {
            $candidateCollections += ,@($List.$prop)
        }
    }
    if ($candidateCollections.Count -eq 0) { return @() }

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($collection in $candidateCollections) {
        foreach ($item in @($collection)) {
            if (Test-ItemIsFolder -Item $item) { continue }
            $path = Get-ItemPathValue -Item $item
            $relative = Get-ChildPathSegment -ParentPath $rootFolderPath -ChildPath $path
            if (-not [string]::IsNullOrWhiteSpace($relative) -and $relative -notmatch '/') {
                $names.Add((Get-ItemNameValue -Item $item))
            }
        }
    }
    return @($names | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
}


function Get-RelativePathUnderLibrary {
    param([string]$Path, [string]$LibraryName)

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($LibraryName)) { return '' }
    $normalized = (($Path -replace '\\','/') -replace '/+','/').Trim()
    $normalized = $normalized.Trim('/')
    if ([string]::IsNullOrWhiteSpace($normalized)) { return '' }

    $segments = @($normalized -split '/')
    $libraryIndex = -1
    for ($i = 0; $i -lt $segments.Count; $i++) {
        if ($segments[$i].Trim().ToLowerInvariant() -eq $LibraryName.Trim('/').ToLowerInvariant()) {
            $libraryIndex = $i
            break
        }
    }
    if ($libraryIndex -lt 0) { return '' }
    if (($libraryIndex + 1) -ge $segments.Count) { return '' }
    return (($segments[($libraryIndex + 1)..($segments.Count - 1)]) -join '/')
}

function Get-ReportColumnValue {
    param([object]$Row, [string[]]$CandidateNames)

    if ($null -eq $Row) { return $null }
    foreach ($candidate in @($CandidateNames)) {
        foreach ($prop in @($Row.PSObject.Properties.Name)) {
            if ($prop.Trim().ToLowerInvariant() -eq $candidate.Trim().ToLowerInvariant()) {
                return $Row.$prop
            }
        }
    }
    return $null
}

function Import-VerificationReportRows {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        throw "Verification report not found: $Path"
    }

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($extension) {
        '.csv' {
            return @(Import-Csv -LiteralPath $Path)
        }
        '.xlsx' {
            $excel = $null
            $workbook = $null
            try {
                $excel = New-Object -ComObject Excel.Application
                $excel.Visible = $false
                $excel.DisplayAlerts = $false
                $workbook = $excel.Workbooks.Open($Path, $null, $true)
                $worksheet = $workbook.Worksheets.Item(1)
                $usedRange = $worksheet.UsedRange
                $rowCount = [int]$usedRange.Rows.Count
                $columnCount = [int]$usedRange.Columns.Count
                if ($rowCount -lt 2 -or $columnCount -lt 1) { return @() }

                $headers = @()
                for ($c = 1; $c -le $columnCount; $c++) {
                    $header = [string]$worksheet.Cells.Item(1, $c).Text
                    if ([string]::IsNullOrWhiteSpace($header)) { $header = "Column$c" }
                    $headers += $header
                }

                $rows = New-Object System.Collections.Generic.List[object]
                for ($r = 2; $r -le $rowCount; $r++) {
                    $map = [ordered]@{}
                    $hasValue = $false
                    for ($c = 1; $c -le $columnCount; $c++) {
                        $value = $worksheet.Cells.Item($r, $c).Text
                        if (-not [string]::IsNullOrWhiteSpace([string]$value)) { $hasValue = $true }
                        $map[$headers[$c - 1]] = [string]$value
                    }
                    if ($hasValue) {
                        $rows.Add([pscustomobject]$map)
                    }
                }
                return @($rows)
            }
            finally {
                if ($workbook) { $workbook.Close($false) | Out-Null }
                if ($excel) { $excel.Quit() | Out-Null }
                foreach ($obj in @($usedRange, $worksheet, $workbook, $excel)) {
                    if ($null -ne $obj) {
                        try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($obj) } catch {}
                    }
                }
                [gc]::Collect()
                [gc]::WaitForPendingFinalizers()
            }
        }
        default {
            throw "Unsupported verification report type: $extension"
        }
    }
}


function Get-CachedVerificationReportRows {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return @() }

    $resolvedPath = $Path
    try {
        if (Test-Path -LiteralPath $Path) {
            $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
        }
    }
    catch { }

    if ($script:VerificationReportCache.ContainsKey($resolvedPath)) {
        return @($script:VerificationReportCache[$resolvedPath])
    }

    $rows = @(Import-VerificationReportRows -Path $resolvedPath)
    $script:VerificationReportCache[$resolvedPath] = $rows
    return $rows
}

function Get-FilteredVerificationReportRows {
    param(
        [object[]]$Rows,
        [string]$SourceSiteUrl,
        [string]$DestinationSiteUrl
    )

    $filtered = New-Object System.Collections.Generic.List[object]
    foreach ($row in @($Rows)) {
        $sourceSite = [string](Get-ReportColumnValue -Row $row -CandidateNames @('SourceSite','Source Site','Source site'))
        $destinationSite = [string](Get-ReportColumnValue -Row $row -CandidateNames @('DestinationSite','Destination Site','Destination site','Target Site','TargetSite'))
        $sourcePath = [string](Get-ReportColumnValue -Row $row -CandidateNames @('Source path','Source Path','Path','Item path'))
        $destinationPath = [string](Get-ReportColumnValue -Row $row -CandidateNames @('Destination path','Destination Path','Target path','Target Path'))

        $sourceMatches = $true
        $destinationMatches = $true

        if (-not [string]::IsNullOrWhiteSpace($SourceSiteUrl)) {
            $normalizedSourceSiteUrl = $SourceSiteUrl.TrimEnd('/').ToLowerInvariant()
            if (-not [string]::IsNullOrWhiteSpace($sourceSite)) {
                $sourceMatches = ($sourceSite.TrimEnd('/').ToLowerInvariant() -eq $normalizedSourceSiteUrl)
            }
            else {
                $sourceMatches = (-not [string]::IsNullOrWhiteSpace($sourcePath) -and $sourcePath.ToLowerInvariant().StartsWith($normalizedSourceSiteUrl))
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($DestinationSiteUrl)) {
            $normalizedDestinationSiteUrl = $DestinationSiteUrl.TrimEnd('/').ToLowerInvariant()
            if (-not [string]::IsNullOrWhiteSpace($destinationSite)) {
                $destinationMatches = ($destinationSite.TrimEnd('/').ToLowerInvariant() -eq $normalizedDestinationSiteUrl)
            }
            else {
                $destinationMatches = (-not [string]::IsNullOrWhiteSpace($destinationPath) -and $destinationPath.ToLowerInvariant().StartsWith($normalizedDestinationSiteUrl))
            }
        }

        if ($sourceMatches -and $destinationMatches) {
            [void]$filtered.Add($row)
        }
    }

    return @($filtered)
}

function Resolve-VerificationReportPath {
    param(
        [string]$ExplicitPath,
        [string]$TaskName,
        [string]$RunFolder,
        [datetime]$StartedAt
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath) -and (Test-Path -LiteralPath $ExplicitPath)) {
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    $searchRoots = @()
    foreach ($candidate in @($RunFolder, (Get-Location).Path, $PSScriptRoot, (Join-Path $env:USERPROFILE 'Downloads'))) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            $searchRoots += $candidate
        }
    }
    $searchRoots = @($searchRoots | Select-Object -Unique)

    $patterns = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($TaskName)) {
        $patterns.Add("*$TaskName*.csv")
        $patterns.Add("*$TaskName*.xlsx")
    }
    $patterns.Add('CopyContent-*.csv')
    $patterns.Add('CopyContent-*.xlsx')
    $patterns.Add('*Migration*.csv')
    $patterns.Add('*Migration*.xlsx')

    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($root in $searchRoots) {
        foreach ($pattern in $patterns) {
            try {
                Get-ChildItem -LiteralPath $root -Filter $pattern -File -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -ge $StartedAt.AddMinutes(-5) } |
                    ForEach-Object { [void]$candidates.Add($_) }
            }
            catch { }
        }
    }

    $picked = @($candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    if ($picked.Count -gt 0) {
        return $picked[0].FullName
    }
    return $null
}

function Try-Export-VerificationReport {
    param(
        [object]$TaskObject,
        [string]$TaskName,
        [string]$RunFolder
    )

    if ($null -eq $TaskObject) { return $null }

    $cmd = Get-ShareGateCommand -Names @('Export-TaskReport','Export-Report','Export-ResultReport')
    if (-not $cmd) { return $null }

    $baseName = if ([string]::IsNullOrWhiteSpace($TaskName)) { 'CopyContent-Report' } else { $TaskName }
    $targetPath = Join-Path $RunFolder ($baseName + '.csv')
    $supported = @($cmd.Parameters.Keys)
    $params = @{}
    $hasTaskBinding = $false

    if ('Task' -in $supported) {
        $params['Task'] = $TaskObject
        $hasTaskBinding = $true
    }
    elseif ('Result' -in $supported) {
        $params['Result'] = $TaskObject
        $hasTaskBinding = $true
    }
    elseif ('CopyResult' -in $supported) {
        $params['CopyResult'] = $TaskObject
        $hasTaskBinding = $true
    }

    if (-not $hasTaskBinding) {
        Write-Log -Level WARN -Message ('Best-effort report export skipped: {0} requires an unsupported task/result parameter set.' -f $cmd.Name)
        return $null
    }

    if ('Path' -in $supported) { $params['Path'] = $targetPath }
    elseif ('FilePath' -in $supported) { $params['FilePath'] = $targetPath }
    elseif ('ReportPath' -in $supported) { $params['ReportPath'] = $targetPath }
    elseif ('Destination' -in $supported) { $params['Destination'] = $targetPath }
    if ('Format' -in $supported) { $params['Format'] = 'Csv' }

    try {
        & $cmd.Name @params | Out-Null
        if (Test-Path -LiteralPath $targetPath) { return $targetPath }
    }
    catch {
        Write-Log -Level WARN -Message ("Best-effort report export failed: {0}" -f $_.Exception.Message)
    }
    return $null
}

function Test-ReportRowRepresentsFile {
    param([object]$Row)

    $folderSignals = @('folder','directory')
    $fileSignals = @('file','document','item')

    $typeValue = [string](Get-ReportColumnValue -Row $Row -CandidateNames @('Item type','Type','Object type','Content type'))
    if (-not [string]::IsNullOrWhiteSpace($typeValue)) {
        $normalized = $typeValue.Trim().ToLowerInvariant()
        if ($normalized -in $folderSignals) { return $false }
        if ($normalized -in $fileSignals) { return $true }
    }

    $sourcePath = [string](Get-ReportColumnValue -Row $Row -CandidateNames @('Source path','Source Path','Path','Item path'))
    if ($sourcePath -match '\.[^/\\]+$') { return $true }

    return $true
}

function Get-ReportStatusCategory {
    param([object]$Row)

    $statusText = [string](Get-ReportColumnValue -Row $Row -CandidateNames @('Status','Result','Migration status'))
    if ([string]::IsNullOrWhiteSpace($statusText)) { return 'Unknown' }
    $normalized = $statusText.Trim().ToLowerInvariant()
    if ($normalized -match 'success|completed|copied|migrated') { return 'Success' }
    if ($normalized -match 'warn|warning') { return 'Warning' }
    if ($normalized -match 'fail|error') { return 'Failed' }
    if ($normalized -match 'skip') { return 'Skipped' }
    return 'Unknown'
}

function Get-RootFileVerificationFromReportRows {
    param(
        [object[]]$Rows,
        [string]$SourceLibraryName,
        [string]$DestinationLibraryName,
        [string]$ResolvedSubFolder
    )

    $expected = New-Object 'System.Collections.Generic.Dictionary[string,string]'
    $migrated = New-Object 'System.Collections.Generic.HashSet[string]'
    $subfolderNormalized = Normalize-PathSegment -Value $ResolvedSubFolder

    foreach ($row in @($Rows)) {
        if (-not (Test-ReportRowRepresentsFile -Row $row)) { continue }

        $sourcePath = [string](Get-ReportColumnValue -Row $Row -CandidateNames @('Source path','Source Path','Path','Item path'))
        $destinationPath = [string](Get-ReportColumnValue -Row $Row -CandidateNames @('Destination path','Destination Path','Target path','Target Path'))
        $sourceRelative = Get-RelativePathUnderLibrary -Path $sourcePath -LibraryName $SourceLibraryName
        if ([string]::IsNullOrWhiteSpace($sourceRelative) -or $sourceRelative -match '/') { continue }

        $fileName = [System.IO.Path]::GetFileName($sourceRelative)
        if ([string]::IsNullOrWhiteSpace($fileName)) { continue }

        $status = Get-ReportStatusCategory -Row $row
        if (-not $expected.ContainsKey($fileName)) {
            $expected[$fileName] = $status
        }
        elseif ($status -eq 'Success') {
            $expected[$fileName] = $status
        }

        $destinationMatches = $true
        if (-not [string]::IsNullOrWhiteSpace($destinationPath)) {
            $destRelative = Get-RelativePathUnderLibrary -Path $destinationPath -LibraryName $DestinationLibraryName
            if ([string]::IsNullOrWhiteSpace($subfolderNormalized)) {
                $destinationMatches = (-not [string]::IsNullOrWhiteSpace($destRelative) -and $destRelative -notmatch '/')
            }
            else {
                $expectedPrefix = ($subfolderNormalized -replace '\\','/').Trim('/') + '/'
                $destinationMatches = ($destRelative.ToLowerInvariant().StartsWith($expectedPrefix.ToLowerInvariant()) -and (($destRelative.Substring($expectedPrefix.Length)) -notmatch '/'))
            }
        }

        if ($status -eq 'Success' -and $destinationMatches) {
            [void]$migrated.Add($fileName)
        }
    }

    $sourceNames = @($expected.Keys | Sort-Object)
    $destNames = @($migrated.ToArray() | Sort-Object)
    return (Compare-RootFileSets -SourceNames $sourceNames -DestinationNames $destNames)
}

function Invoke-RootFileVerification {
    param(
        [string]$VerificationReportPath,
        [string]$TaskName,
        [object]$TaskObject,
        [string]$RunFolder,
        [datetime]$CopyStartedAt,
        [string]$SourceLibraryName,
        [string]$DestinationLibraryName,
        [string]$ResolvedSubFolder,
        [int]$Index,
        [string]$RowKey,
        [string]$UserPrincipalName,
        [string]$SourceSiteUrl,
        [string]$DestinationSiteUrl
    )
    Write-Log -Level INFO -Message "Row ${Index}: ResolvedSubFolder = $(if ([string]::IsNullOrWhiteSpace($ResolvedSubFolder)) { '<root>' } else { $ResolvedSubFolder })"
    try {
        $exportedReport = Try-Export-VerificationReport -TaskObject $TaskObject -TaskName $TaskName -RunFolder $RunFolder
        $reportPath = Resolve-VerificationReportPath -ExplicitPath $(if ($exportedReport) { $exportedReport } else { $VerificationReportPath }) -TaskName $TaskName -RunFolder $RunFolder -StartedAt $CopyStartedAt
        if ([string]::IsNullOrWhiteSpace($reportPath)) {
            throw 'No verification report file was found. Provide -VerificationReportPath or export the ShareGate task report to CSV/XLSX.'
        }

        Write-Log -Level INFO -Message "Row ${Index}: Verification report = $reportPath"
        $allRows = @(Get-CachedVerificationReportRows -Path $reportPath)
        if ($allRows.Count -eq 0) {
            throw "Verification report is empty: $reportPath"
        }

        $cacheKey = ('{0}|{1}|{2}' -f $reportPath.ToLowerInvariant(), $SourceSiteUrl.TrimEnd('/').ToLowerInvariant(), $DestinationSiteUrl.TrimEnd('/').ToLowerInvariant())
        if ($script:VerificationRowsByReportPath.ContainsKey($cacheKey)) {
            $rows = @($script:VerificationRowsByReportPath[$cacheKey])
        }
        else {
            $rows = @(Get-FilteredVerificationReportRows -Rows $allRows -SourceSiteUrl $SourceSiteUrl -DestinationSiteUrl $DestinationSiteUrl)
            $script:VerificationRowsByReportPath[$cacheKey] = $rows
        }
        if ($rows.Count -eq 0) {
            throw "No matching report rows were found for the current source/destination site pair in: $reportPath"
        }

        $comparison = Get-RootFileVerificationFromReportRows -Rows $rows -SourceLibraryName $SourceLibraryName -DestinationLibraryName $DestinationLibraryName -ResolvedSubFolder $ResolvedSubFolder
        $status = if ($comparison.Passed) { 'Passed' } else { 'Failed' }
        $message = "Report-based verification from $(Split-Path -Leaf $reportPath); Expected root files in source = $($comparison.SourceCount); Observed migrated root files in destination$(if ([string]::IsNullOrWhiteSpace($ResolvedSubFolder)) { '' } else { '/' + $ResolvedSubFolder }) = $($comparison.DestinationCount); Verification = $status"
        Write-Log -Level INFO -Message "Row ${Index}: Expected root files in source report = $($comparison.SourceCount)"
        Write-Log -Level INFO -Message "Row ${Index}: Observed migrated root files in destination$(if ([string]::IsNullOrWhiteSpace($ResolvedSubFolder)) { '' } else { '/' + $ResolvedSubFolder }) = $($comparison.DestinationCount)"
        if ($status -eq 'Passed') {
            Write-Log -Level SUCCESS -Message "Row ${Index}: Verification = Passed"
        }
        else {
            Write-Log -Level WARN -Message "Row ${Index}: Verification = Failed | Missing sample: $((@($comparison.MissingNames) | Select-Object -First 10) -join '; ')"
        }

        return (Build-VerificationRow -Index $Index -RowKey $RowKey -UserPrincipalName $UserPrincipalName -SourceSite $SourceSiteUrl -DestinationSite $DestinationSiteUrl -SourceLibrary $SourceLibraryName -DestinationLibrary $DestinationLibraryName -ResolvedSubFolder $ResolvedSubFolder -VerificationStatus $status -SourceRootFileCount $comparison.SourceCount -DestinationRootFileCount $comparison.DestinationCount -MissingFileNames $comparison.MissingNames -ExtraFileNames $comparison.ExtraNames -VerificationMessage $message)
    }
    catch {
        $message = "Verification skipped: $($_.Exception.Message)"
        Write-Log -Level WARN -Message "Row ${Index}: $message"
        return (New-SkippedVerificationRow -Index $Index -RowKey $RowKey -UserPrincipalName $UserPrincipalName -SourceSite $SourceSiteUrl -DestinationSite $DestinationSiteUrl -SourceLibrary $SourceLibraryName -DestinationLibrary $DestinationLibraryName -ResolvedSubFolder $ResolvedSubFolder -Message $message)
    }
}

function Connect-ShareGateSite {
    param([string]$Url, [object]$UseCredentialsFrom, [string]$Mode, [string]$Label)
    $lastError = $null

    if ($null -ne $UseCredentialsFrom) {
        try {
            Write-Log -Level INFO -Message "Connecting [$Label] with [UseCredentialsFrom]: $Url"
            $conn = Connect-Site -Url $Url -UseCredentialsFrom $UseCredentialsFrom
            Write-Log -Level SUCCESS -Message "Connected [$Label]"
            return $conn
        }
        catch {
            $lastError = $_
            Write-Log -Level WARN -Message "Connection failed [$Label] with [UseCredentialsFrom]: $($_.Exception.Message)"
            if ($script:BatchScopedAuthReuse) {
                throw $lastError.Exception
            }
        }
    }

    $attempts = if ($Mode -eq 'Browser') { @('Browser') } elseif ($Mode -eq 'ModernAuth') { @('ModernAuth') } else { @('ModernAuth','Browser') }
    foreach ($attempt in $attempts) {
        try {
            Write-Log -Level INFO -Message "Connecting [$Label] with [$attempt]: $Url"
            $params = @{ Url = $Url }
            if ($attempt -eq 'Browser') {
                $params['Browser'] = $true
            }
            else {
                $params['ModernAuth'] = $true
            }
            $conn = Connect-Site @params
            Write-Log -Level SUCCESS -Message "Connected [$Label]"
            return $conn
        }
        catch {
            $lastError = $_
            Write-Log -Level WARN -Message "Connection failed [$Label] with [$attempt]: $($_.Exception.Message)"
        }
    }
    throw $lastError.Exception
}

function Get-ShareGateCommand {
    param([string[]]$Names)
    foreach ($name in $Names) {
        $cmd = Get-Command -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd }
    }
    return $null
}


function Get-ShareGateList {
    param(
        [object]$Site,
        [string]$LibraryName
    )

    $cmd = Get-ShareGateCommand -Names @('Get-List','Get-Library')
    if (-not $cmd) {
        throw 'Get-List/Get-Library cmdlet not found. Cannot resolve ShareGate list/library object.'
    }

    try {
        if ($cmd.Name -eq 'Get-List' -or $cmd.Name -eq 'Get-Library') {
            return (& $cmd.Name -Site $Site -Name $LibraryName)
        }
        throw "Unsupported command resolved for ShareGate list lookup: $($cmd.Name)"
    }
    catch {
        throw "Failed to resolve library/list [$LibraryName]: $($_.Exception.Message)"
    }
}

function Test-TargetFolderExists {
    param([object]$DestinationSite, [string]$LibraryName, [string]$SubFolder)
    if ([string]::IsNullOrWhiteSpace($SubFolder)) { return $true }

    $cmd = Get-ShareGateCommand -Names @('Get-List','Get-Library')
    if (-not $cmd) {
        Write-Log -Level WARN -Message 'Folder existence check skipped because Get-List/Get-Library cmdlet was not found.'
        return $false
    }

    try {
        $list = & $cmd.Name -Site $DestinationSite -Name $LibraryName
        $folderPath = $SubFolder -replace '\\','/'

        if ($list.PSObject.Properties.Name -contains 'Folders') {
            $match = @($list.Folders | Where-Object { $_.Path -eq $folderPath -or $_.Name -eq (Split-Path -Path $folderPath -Leaf) })
            return (@($match).Count -gt 0)
        }
    }
    catch {
        Write-Log -Level WARN -Message "Folder existence probe failed: $($_.Exception.Message)"
    }

    return $false
}

function Invoke-CopyContent {
    param(
        [object]$SourceSite,
        [object]$DestinationSite,
        [string]$SourceSiteUrl,
        [string]$DestinationSiteUrl,
        [string]$SourceLibraryName,
        [string]$DestinationLibraryName,
        [string]$ResolvedSubFolder,
        [switch]$Incremental,
        [switch]$ExecuteMigration,
        [switch]$WhatIfOnly
    )

    if (-not $ExecuteMigration -or $WhatIfOnly) {
        return [pscustomobject]@{ TaskName = ''; FolderAction = 'PlannedCopy'; ExecutionMode = 'DryRun' }
    }

    $copyCmd = Get-ShareGateCommand -Names @('Copy-Content')
    if (-not $copyCmd) {
        throw 'Copy-Content cmdlet not found. Migration cannot be executed.'
    }

    $sourceList = Get-ShareGateList -Site $SourceSite -LibraryName $SourceLibraryName
    $destinationList = Get-ShareGateList -Site $DestinationSite -LibraryName $DestinationLibraryName

    $params = @{
        SourceList      = $sourceList
        DestinationList = $destinationList
        TaskName        = "CopyContent-$([DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss_fff'))"
    }

    if (-not [string]::IsNullOrWhiteSpace($ResolvedSubFolder)) {
        $params['DestinationFolder'] = $ResolvedSubFolder
    }
    if ($Incremental) {
        # ShareGate incremental behavior is controlled through CopySettings in many scenarios.
        # Keep current compatibility by trying the switch only when available.
        $params['IncrementalUpdate'] = $true
    }

    # Remove unsupported parameters dynamically so the cmdlet invocation stays compatible.
    $supported = @($copyCmd.Parameters.Keys)
    foreach ($k in @($params.Keys)) {
        if ($k -notin $supported) {
            $params.Remove($k)
        }
    }

    $task = & $copyCmd.Name @params
    $resolvedTaskName = [string]$(if ($task -and $task.PSObject.Properties.Name -contains 'Name') { $task.Name } elseif ($params.ContainsKey('TaskName')) { $params['TaskName'] } else { '' })
    return [pscustomobject]@{
        TaskName      = $resolvedTaskName
        FolderAction  = 'Copied'
        ExecutionMode = 'Executed'
        RawTask       = $task
    }
}

function Get-ConnectionFromCacheOrConnect {
    param(
        [hashtable]$Cache,
        [string]$Url,
        [object]$UseCredentialsFrom,
        [string]$Mode,
        [string]$Label,
        [int]$MaxRetryCount,
        [int]$RetryDelaySeconds,
        [int]$RowIndex,
        [string]$RowKey,
        [string]$OperationLabel
    )

    if ($null -eq $Cache) { $Cache = @{} }

    if (-not [string]::IsNullOrWhiteSpace($Url) -and $Cache.ContainsKey($Url) -and $null -ne $Cache[$Url]) {
        Write-Log -Level INFO -Message "Row $RowIndex [$RowKey] - Reusing cached connection for $Url"
        return [pscustomobject]@{ Success = $true; Attempt = 1; Result = $Cache[$Url]; ErrorRecord = $null; FromCache = $true }
    }

    if (-not [string]::IsNullOrWhiteSpace($Url) -and $script:ConnectionCache.ContainsKey($Url) -and $null -ne $script:ConnectionCache[$Url]) {
        $Cache[$Url] = $script:ConnectionCache[$Url]
        Write-Log -Level INFO -Message "Row $RowIndex [$RowKey] - Reusing script-scoped cached connection for $Url"
        return [pscustomobject]@{ Success = $true; Attempt = 1; Result = $Cache[$Url]; ErrorRecord = $null; FromCache = $true }
    }

    if (-not [string]::IsNullOrWhiteSpace($Url) -and $script:PreAuthConnectionCache.ContainsKey($Url) -and $null -ne $script:PreAuthConnectionCache[$Url]) {
        $Cache[$Url] = $script:PreAuthConnectionCache[$Url]
        Write-Log -Level INFO -Message "Row $RowIndex [$RowKey] - Reusing pre-auth cached connection for $Url"
        return [pscustomobject]@{ Success = $true; Attempt = 1; Result = $Cache[$Url]; ErrorRecord = $null; FromCache = $true }
    }

    $result = Invoke-WithRetry -ScriptBlock {
        Connect-ShareGateSite -Url $Url -UseCredentialsFrom $UseCredentialsFrom -Mode $Mode -Label $Label
    } -MaxRetryCount $MaxRetryCount -RetryDelaySeconds $RetryDelaySeconds -OperationLabel $OperationLabel -RowIndex $RowIndex -RowKey $RowKey

    if ($result.Success -and -not [string]::IsNullOrWhiteSpace($Url)) {
        $Cache[$Url] = $result.Result
        $script:ConnectionCache[$Url] = $result.Result
    }

    return $result
}

function Invoke-WithRetry {
    param(
        [scriptblock]$ScriptBlock,
        [int]$MaxRetryCount,
        [int]$RetryDelaySeconds,
        [string]$OperationLabel,
        [int]$RowIndex,
        [string]$RowKey
    )

    $attempt = 0
    while ($attempt -lt $MaxRetryCount) {
        $attempt++
        try {
            Write-Log -Level INFO -Message "Row $RowIndex [$RowKey] - $OperationLabel attempt $attempt of $MaxRetryCount"
            $result = & $ScriptBlock
            return [pscustomobject]@{ Success = $true; Attempt = $attempt; Result = $result; ErrorRecord = $null }
        }
        catch {
            $err = $_
            Write-Log -Level WARN -Message "Row $RowIndex [$RowKey] - $OperationLabel attempt $attempt failed: $($err.Exception.Message)"
            if ($attempt -ge $MaxRetryCount) {
                return [pscustomobject]@{ Success = $false; Attempt = $attempt; Result = $null; ErrorRecord = $err }
            }
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
}

function Show-Header {
    param([string]$Title)
    Clear-Host
    Write-Host '========================================================' -ForegroundColor Cyan
    Write-Host '  ShareGate OneDrive Migration Toolkit v8.3.5.4' -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host '========================================================' -ForegroundColor Cyan
    Write-Host ''
}


function Get-DefaultConnectionProfilePath {
    $scriptDir = Split-Path -Parent $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = (Get-Location).Path }
    return (Join-Path $scriptDir 'ShareGate-ConnectionProfile.json')
}

function Import-ConnectionProfile {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    }
    catch {
        Write-Host "  WARNING: Failed to read connection profile: $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

function Export-ConnectionProfile {
    param(
        [string]$Path,
        [string]$SourceRootUrl,
        [string]$DestinationRootUrl,
        [string]$SourceAdminCenterUrl,
        [string]$DestinationAdminCenterUrl,
        [string]$SourceAdminUser,
        [string]$DestinationAdminUser,
        [string]$AuthMode
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $profile = [pscustomobject]@{
        SourceRootUrl            = $SourceRootUrl
        DestinationRootUrl       = $DestinationRootUrl
        SourceAdminCenterUrl     = $SourceAdminCenterUrl
        DestinationAdminCenterUrl= $DestinationAdminCenterUrl
        SourceAdminUser          = $SourceAdminUser
        DestinationAdminUser     = $DestinationAdminUser
        AuthMode                 = $AuthMode
        SavedAt                  = (Get-Date).ToString('s')
    }
    $profile | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-ConnectionProfileStatus {
    param(
        [string]$SourceRootUrl,
        [string]$DestinationRootUrl,
        [string]$SourceAdminUser,
        [string]$DestinationAdminUser
    )
    if (-not [string]::IsNullOrWhiteSpace($SourceRootUrl) -and -not [string]::IsNullOrWhiteSpace($DestinationRootUrl)) {
        if (-not [string]::IsNullOrWhiteSpace($SourceAdminUser) -or -not [string]::IsNullOrWhiteSpace($DestinationAdminUser)) {
            return 'Configured'
        }
        return 'Roots set'
    }
    return 'Not configured'
}

function Show-ConnectionProfileMenu {
    param(
        [string]$ProfilePath,
        [string]$SourceRootUrl,
        [string]$DestinationRootUrl,
        [string]$SourceAdminCenterUrl,
        [string]$DestinationAdminCenterUrl,
        [string]$SourceAdminUser,
        [string]$DestinationAdminUser,
        [string]$AuthMode
    )
    $state = [ordered]@{
        ProfilePath = $(if ([string]::IsNullOrWhiteSpace($ProfilePath)) { Get-DefaultConnectionProfilePath } else { $ProfilePath })
        SourceRootUrl = $SourceRootUrl
        DestinationRootUrl = $DestinationRootUrl
        SourceAdminCenterUrl = $SourceAdminCenterUrl
        DestinationAdminCenterUrl = $DestinationAdminCenterUrl
        SourceAdminUser = $SourceAdminUser
        DestinationAdminUser = $DestinationAdminUser
        AuthMode = $AuthMode
    }
    while ($true) {
        Show-Header 'Connection Profile'
        Write-Host "  1. Profile Path: $($state.ProfilePath)"
        Write-Host "  2. Source Root URL (use -my): $($state.SourceRootUrl)"
        Write-Host "  3. Destination Root URL (use -my): $($state.DestinationRootUrl)"
        Write-Host "  4. Source Admin Center URL: $($state.SourceAdminCenterUrl)"
        Write-Host "  5. Destination Admin Center URL: $($state.DestinationAdminCenterUrl)"
        Write-Host "  6. Source Admin User: $($state.SourceAdminUser)"
        Write-Host "  7. Destination Admin User: $($state.DestinationAdminUser)"
        Write-Host '  8. Load profile from disk'
        Write-Host '  9. Save profile to disk'
        Write-Host '  10. Clear current values'
        Write-Host '  11. Connect Once Now'
        Write-Host '  12. Back'
        Write-Host ''
        $choice = Read-Host '  Enter choice'
        switch ($choice) {
            '1' { $v = Read-Host '  Enter profile path'; if ($v) { $state.ProfilePath = $v } }
            '2' { $v = Read-Host '  Enter source root URL'; if ($v -ne $null) { $state.SourceRootUrl = $v } }
            '3' { $v = Read-Host '  Enter destination root URL'; if ($v -ne $null) { $state.DestinationRootUrl = $v } }
            '4' { $v = Read-Host '  Enter source admin center URL'; if ($v -ne $null) { $state.SourceAdminCenterUrl = $v } }
            '5' { $v = Read-Host '  Enter destination admin center URL'; if ($v -ne $null) { $state.DestinationAdminCenterUrl = $v } }
            '6' { $v = Read-Host '  Enter source admin user'; if ($v -ne $null) { $state.SourceAdminUser = $v } }
            '7' { $v = Read-Host '  Enter destination admin user'; if ($v -ne $null) { $state.DestinationAdminUser = $v } }
            '8' {
                $loaded = Import-ConnectionProfile -Path $state.ProfilePath
                if ($loaded) {
                    foreach ($name in 'SourceRootUrl','DestinationRootUrl','SourceAdminCenterUrl','DestinationAdminCenterUrl','SourceAdminUser','DestinationAdminUser','AuthMode') {
                        if ($loaded.PSObject.Properties.Name -contains $name -and -not [string]::IsNullOrWhiteSpace([string]$loaded.$name)) { $state[$name] = [string]$loaded.$name }
                    }
                    Write-Host '  Profile loaded.' -ForegroundColor Green
                }
            }
            '9' {
                Export-ConnectionProfile -Path $state.ProfilePath -SourceRootUrl $state.SourceRootUrl -DestinationRootUrl $state.DestinationRootUrl -SourceAdminCenterUrl $state.SourceAdminCenterUrl -DestinationAdminCenterUrl $state.DestinationAdminCenterUrl -SourceAdminUser $state.SourceAdminUser -DestinationAdminUser $state.DestinationAdminUser -AuthMode $state.AuthMode
                Write-Host '  Profile saved.' -ForegroundColor Green
            }
            '10' {
                $state.SourceRootUrl='';$state.DestinationRootUrl='';$state.SourceAdminCenterUrl='';$state.DestinationAdminCenterUrl='';$state.SourceAdminUser='';$state.DestinationAdminUser=''
            }
            '11' {
                $script:ConnectionProfile = [ordered]@{
                    ProfilePath = $state.ProfilePath
                    SourceRootUrl = $state.SourceRootUrl
                    DestinationRootUrl = $state.DestinationRootUrl
                    SourceAdminCenterUrl = $state.SourceAdminCenterUrl
                    DestinationAdminCenterUrl = $state.DestinationAdminCenterUrl
                    SourceAdminUser = $state.SourceAdminUser
                    DestinationAdminUser = $state.DestinationAdminUser
                    AuthMode = $state.AuthMode
                }
                try {
                    Connect-OnceNowFromProfile
                }
                catch {
                    Write-Log -Level ERROR -Message "Connection Profile connect-once failed: $($_.Exception.Message)"
                    Write-Host "  Connect Once Now failed: $($_.Exception.Message)" -ForegroundColor Red
                    Pause
                }
            }
            '12' { return [pscustomobject]$state }
            '0' { return [pscustomobject]$state }
        }
    }
}



function Test-ConnectionProfileRootUrl {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$Label
    )
    if ([string]::IsNullOrWhiteSpace($Url)) { return }
    $normalized = $Url.Trim()
    if ($normalized -match '-admin\.sharepoint\.com/?$') {
        throw "$Label must be the tenant root/my URL, not the admin center URL. Example: https://<tenant>-my.sharepoint.com"
    }
}

function Connect-OnceNowFromProfile {
    [CmdletBinding()]
    param()

    if (-not $script:ConnectionProfile) {
        throw 'Connection profile is not initialized.'
    }

    if ($null -eq $script:PreAuthConnectionCache) { $script:PreAuthConnectionCache = @{} }
    if ($null -eq $script:ConnectionCache) { $script:ConnectionCache = @{} }
    if ($null -eq $script:LogFile -or [string]::IsNullOrWhiteSpace([string]$script:LogFile)) {
        $script:LogFile = Join-Path $env:TEMP 'ShareGate-OneDrive-Migration-Toolkit-preconnect.log'
    }

    $sourceRootUrl        = [string]$script:ConnectionProfile.SourceRootUrl
    $destinationRootUrl   = [string]$script:ConnectionProfile.DestinationRootUrl
    $sourceAdminUser      = [string]$script:ConnectionProfile.SourceAdminUser
    $destinationAdminUser = [string]$script:ConnectionProfile.DestinationAdminUser
    $authMode             = [string]$(if (-not [string]::IsNullOrWhiteSpace([string]$script:ConnectionProfile.AuthMode)) { $script:ConnectionProfile.AuthMode } elseif (-not [string]::IsNullOrWhiteSpace([string]$script:AuthMethod)) { $script:AuthMethod } else { 'Auto' })

    if ([string]::IsNullOrWhiteSpace($sourceRootUrl)) {
        throw 'SourceRootUrl is not configured in Connection Profile.'
    }
    if ([string]::IsNullOrWhiteSpace($destinationRootUrl)) {
        throw 'DestinationRootUrl is not configured in Connection Profile.'
    }

    Test-ConnectionProfileRootUrl -Url $sourceRootUrl -Label 'SourceRootUrl'
    Test-ConnectionProfileRootUrl -Url $destinationRootUrl -Label 'DestinationRootUrl'

    Write-Log -Level INFO -Message 'Connection Profile: Connect Once Now started.'

    $sourceConn = Connect-ShareGateSite -Url $sourceRootUrl -Mode $authMode -Label 'SourceRootProfile'
    if ($null -eq $sourceConn) { throw 'Failed to connect source root using the connection profile.' }
    $script:PreAuthConnectionCache[$sourceRootUrl] = $sourceConn
    $script:ConnectionCache[$sourceRootUrl] = $sourceConn
    $script:SourceRootConnection = $sourceConn
    $script:SourceRootUrl = $sourceRootUrl

    $destinationConn = Connect-ShareGateSite -Url $destinationRootUrl -Mode $authMode -Label 'DestinationRootProfile'
    if ($null -eq $destinationConn) { throw 'Failed to connect destination root using the connection profile.' }
    $script:PreAuthConnectionCache[$destinationRootUrl] = $destinationConn
    $script:ConnectionCache[$destinationRootUrl] = $destinationConn
    $script:DestinationRootConnection = $destinationConn
    $script:DestinationRootUrl = $destinationRootUrl

    $script:PreAuthenticated = $true

    Write-Log -Level SUCCESS -Message 'Connection Profile: Connect Once Now succeeded for source and destination roots.'
    Write-Host ''
    Write-Host '  Connected successfully.' -ForegroundColor Green
    Write-Host '  Cached root connections will be reused in this PowerShell session when possible.' -ForegroundColor Green
    Write-Host ''
    Pause
}

function Show-MainMenu {
    param(
        [string]$CsvPath,
        [string]$Mode,
        [string]$FolderMode,
        [string]$DefaultSubFolder,
        [string]$AuthMode,
        [string]$ExecutionMode,
        [string]$ConnectionProfileStatus,
        [bool]$Incremental,
        [bool]$WhatIfOnly,
        [bool]$SkipCompleted,
        [string]$PriorResults,
        [bool]$ReprocessSuccess,
        [int]$MaxParallelSessions,
        [bool]$ExecuteMigration,
        [int]$MaxRetryCount,
        [int]$RetryDelaySeconds,
        [bool]$ResumeInterrupted,
        [int]$ThrottleDelayMilliseconds,
        [bool]$ShowProgress,
        [bool]$DetailedErrorReporting
    )

    $csvStatus = if ([string]::IsNullOrWhiteSpace($CsvPath)) { 'NOT SELECTED' } else { Split-Path -Leaf $CsvPath }
    $csvColor = if ([string]::IsNullOrWhiteSpace($CsvPath)) { 'Red' } else { 'Green' }

    Show-Header 'Main Menu'
    Write-Host ''
    Write-Host "  CSV File: $csvStatus" -ForegroundColor $csvColor
    Write-Host ''
    Write-Host '  OPERATION SETTINGS' -ForegroundColor Yellow
    Write-Host "  1. Connection Config: $ConnectionProfileStatus"
    Write-Host '  2. Select CSV File'
    Write-Host "  3. Operation Mode: $Mode"
    Write-Host "  4. Migration Target: $FolderMode"
    Write-Host "  5. Subfolder Name: $DefaultSubFolder"
    Write-Host "  6. Auth Method: $AuthMode"
    Write-Host "  7. Execution Mode: $ExecutionMode"
    Write-Host ''
    Write-Host '  EXECUTION SAFETY' -ForegroundColor Yellow
    Write-Host "  8. Execute Migration: $(if ($ExecuteMigration) { 'ON' } else { 'OFF (DRY RUN)' })"
    Write-Host "  9. WhatIf Mode: $(if ($WhatIfOnly) { 'ON' } else { 'OFF' })"
    Write-Host ''
    Write-Host '  MIGRATION OPTIONS' -ForegroundColor Yellow
    Write-Host "  10. Incremental: $(if ($Incremental) { 'ON' } else { 'OFF' })"
    Write-Host "  11. Show Progress: $(if ($ShowProgress) { 'ON' } else { 'OFF' })"
    Write-Host ''
    Write-Host '  RESILIENCE OPTIONS' -ForegroundColor Yellow
    Write-Host "  12. Resume Interrupted: $(if ($ResumeInterrupted) { 'ON' } else { 'OFF' })"
    Write-Host "  13. Max Retries: $MaxRetryCount"
    Write-Host "  14. Retry Delay (sec): $RetryDelaySeconds"
    Write-Host "  15. Throttle Delay (ms): $ThrottleDelayMilliseconds"
    Write-Host "  16. Detailed Error Reporting: $(if ($DetailedErrorReporting) { 'ON' } else { 'OFF' })"
    Write-Host ''
    Write-Host '  ADVANCED OPTIONS' -ForegroundColor Yellow
    Write-Host "  17. Skip Prior Success: $(if ($SkipCompleted) { 'ON' } else { 'OFF' })"
    Write-Host '  18. Set Prior Results CSV'
    Write-Host "  19. Reprocess Success: $(if ($ReprocessSuccess) { 'ON' } else { 'OFF' })"
    Write-Host "  20. Parallel Sessions: $MaxParallelSessions"
    Write-Host ''
    Write-Host '  EXECUTION' -ForegroundColor Yellow
    Write-Host '  22. View Configuration'
    Write-Host '  23. RUN'
    Write-Host '  24. Exit'
    Write-Host ''
}

function Select-Mode {
    Show-Header 'Select Operation Mode'
    Write-Host '  1. Migrate - Copy content to destination'
    Write-Host '  2. ValidateOnly - Validate connections only'
    Write-Host ''
    $choice = Read-Host '  Enter choice (1-2)'
    switch ($choice) {
        '1' { return 'Migrate' }
        '2' { return 'ValidateOnly' }
        default { return 'Migrate' }
    }
}

function Select-FolderMode {
    Show-Header 'Select Migration Target'
    Write-Host '  1. Subfolder - Migrate into a subfolder'
    Write-Host '  2. Root - Migrate to the OneDrive root'
    Write-Host ''
    $choice = Read-Host '  Enter choice (1-2)'
    switch ($choice) {
        '1' { return 'Subfolder' }
        '2' { return 'Root' }
        default { return 'Subfolder' }
    }
}

function Select-AuthMode {
    Show-Header 'Select Authentication'
    Write-Host '  1. Auto - ModernAuth then Browser (RECOMMENDED)'
    Write-Host '  2. Browser - Browser only'
    Write-Host '  3. ModernAuth - OAuth only'
    Write-Host ''
    $choice = Read-Host '  Enter choice (1-3)'
    switch ($choice) {
        '1' { return 'Auto' }
        '2' { return 'Browser' }
        '3' { return 'ModernAuth' }
        default { return 'Auto' }
    }
}

function Select-ExecutionMode {
    Show-Header 'Select Execution Mode'
    Write-Host '  1. ReuseAuthSerial - Login once, reuse one session, process queued rows serially (MOST STABLE)'
    Write-Host '  2. TrueParallel - Launch 1-5 isolated worker sessions for concurrent migrations (may prompt for auth per user)'
    Write-Host '  3. ParallelBatches - Launch 1-5 batch workers; each batch signs in once and processes multiple users serially (BEST BALANCE)'
    Write-Host ''
    $choice = Read-Host '  Enter choice (1-3)'
    switch ($choice) {
        '1' { return 'ReuseAuthSerial' }
        '2' { return 'TrueParallel' }
        '3' { return 'ParallelBatches' }
        default { return 'ReuseAuthSerial' }
    }
}

function Start-InteractiveMenu {
    $menuCsvPath = $CsvPath
    $menuMode = if ($Mode -in @('ValidateOnly','Migrate')) { $Mode } else { 'Migrate' }
    $menuFolderMode = if ($MigrationFolderMode -in @('Root','Subfolder')) { $MigrationFolderMode } else { 'Subfolder' }
    $menuDefaultSubFolder = $DefaultSubFolder
    $menuAuthMode = $AuthMode
    $menuConnectionProfilePath = if ([string]::IsNullOrWhiteSpace($ConnectionProfilePath)) { Get-DefaultConnectionProfilePath } else { $ConnectionProfilePath }
    $loadedProfile = Import-ConnectionProfile -Path $menuConnectionProfilePath
    $menuSourceRootUrl = if (-not [string]::IsNullOrWhiteSpace($SourceRootUrl)) { $SourceRootUrl } elseif ($loadedProfile -and $loadedProfile.PSObject.Properties.Name -contains 'SourceRootUrl') { [string]$loadedProfile.SourceRootUrl } else { '' }
    $menuDestinationRootUrl = if (-not [string]::IsNullOrWhiteSpace($DestinationRootUrl)) { $DestinationRootUrl } elseif ($loadedProfile -and $loadedProfile.PSObject.Properties.Name -contains 'DestinationRootUrl') { [string]$loadedProfile.DestinationRootUrl } else { '' }
    $menuSourceAdminCenterUrl = if (-not [string]::IsNullOrWhiteSpace($SourceAdminCenterUrl)) { $SourceAdminCenterUrl } elseif ($loadedProfile -and $loadedProfile.PSObject.Properties.Name -contains 'SourceAdminCenterUrl') { [string]$loadedProfile.SourceAdminCenterUrl } else { '' }
    $menuDestinationAdminCenterUrl = if (-not [string]::IsNullOrWhiteSpace($DestinationAdminCenterUrl)) { $DestinationAdminCenterUrl } elseif ($loadedProfile -and $loadedProfile.PSObject.Properties.Name -contains 'DestinationAdminCenterUrl') { [string]$loadedProfile.DestinationAdminCenterUrl } else { '' }
    $menuSourceAdminUser = if (-not [string]::IsNullOrWhiteSpace($SourceAdminUser)) { $SourceAdminUser } elseif ($loadedProfile -and $loadedProfile.PSObject.Properties.Name -contains 'SourceAdminUser') { [string]$loadedProfile.SourceAdminUser } else { '' }
    $menuDestinationAdminUser = if (-not [string]::IsNullOrWhiteSpace($DestinationAdminUser)) { $DestinationAdminUser } elseif ($loadedProfile -and $loadedProfile.PSObject.Properties.Name -contains 'DestinationAdminUser') { [string]$loadedProfile.DestinationAdminUser } else { '' }
    $menuExecutionMode = if ($ExecutionMode -in @('ReuseAuthSerial','TrueParallel','ParallelBatches')) { $ExecutionMode } else { 'ReuseAuthSerial' }
    $menuIncremental = [bool]$Incremental
    $menuWhatIfOnly = [bool]$WhatIfOnly
    $menuSkipCompleted = [bool]$SkipCompletedFromPriorResults
    $menuPriorResults = $PriorResultsCsvPath
    $menuReprocessSuccess = [bool]$ReprocessSuccess
    $menuMaxParallelSessions = if ($MaxParallelSessions -ge 1 -and $MaxParallelSessions -le 5) { [int]$MaxParallelSessions } else { 1 }
    $menuExecuteMigration = [bool]$ExecuteMigration
    $menuMaxRetryCount = $MaxRetryCount
    $menuRetryDelaySeconds = $RetryDelaySeconds
    $menuResumeInterrupted = [bool]$ResumeInterrupted
    $menuThrottleDelayMilliseconds = $ThrottleDelayMilliseconds
    $menuShowProgress = [bool]$ShowProgress
    $menuDetailedErrorReporting = [bool]$DetailedErrorReporting

    while ($true) {
        $connectionProfileStatus = Get-ConnectionProfileStatus -SourceRootUrl $menuSourceRootUrl -DestinationRootUrl $menuDestinationRootUrl -SourceAdminUser $menuSourceAdminUser -DestinationAdminUser $menuDestinationAdminUser
        Show-MainMenu -CsvPath $menuCsvPath -Mode $menuMode -FolderMode $menuFolderMode -DefaultSubFolder $menuDefaultSubFolder -AuthMode $menuAuthMode -ExecutionMode $menuExecutionMode -ConnectionProfileStatus $connectionProfileStatus -Incremental $menuIncremental -WhatIfOnly $menuWhatIfOnly -SkipCompleted $menuSkipCompleted -PriorResults $menuPriorResults -ReprocessSuccess $menuReprocessSuccess -MaxParallelSessions $menuMaxParallelSessions -ExecuteMigration $menuExecuteMigration -MaxRetryCount $menuMaxRetryCount -RetryDelaySeconds $menuRetryDelaySeconds -ResumeInterrupted $menuResumeInterrupted -ThrottleDelayMilliseconds $menuThrottleDelayMilliseconds -ShowProgress $menuShowProgress -DetailedErrorReporting $menuDetailedErrorReporting

        $choice = Read-Host '  Enter choice'
        switch ($choice) {
            '1'  { $cp = Show-ConnectionProfileMenu -ProfilePath $menuConnectionProfilePath -SourceRootUrl $menuSourceRootUrl -DestinationRootUrl $menuDestinationRootUrl -SourceAdminCenterUrl $menuSourceAdminCenterUrl -DestinationAdminCenterUrl $menuDestinationAdminCenterUrl -SourceAdminUser $menuSourceAdminUser -DestinationAdminUser $menuDestinationAdminUser -AuthMode $menuAuthMode; if ($cp) { $menuConnectionProfilePath = $cp.ProfilePath; $menuSourceRootUrl = $cp.SourceRootUrl; $menuDestinationRootUrl = $cp.DestinationRootUrl; $menuSourceAdminCenterUrl = $cp.SourceAdminCenterUrl; $menuDestinationAdminCenterUrl = $cp.DestinationAdminCenterUrl; $menuSourceAdminUser = $cp.SourceAdminUser; $menuDestinationAdminUser = $cp.DestinationAdminUser } }
            '2'  { try { $menuCsvPath = Get-CsvPathInteractive } catch {} }
            '3'  { $menuMode = Select-Mode }
            '4'  { $menuFolderMode = Select-FolderMode }
            '5'  { $input = Read-Host '  Enter folder name'; if ($input) { $menuDefaultSubFolder = $input } }
            '6'  { $menuAuthMode = Select-AuthMode }
            '7'  { $menuExecutionMode = Select-ExecutionMode }
            '8'  { $menuExecuteMigration = -not $menuExecuteMigration }
            '9'  { $menuWhatIfOnly = -not $menuWhatIfOnly }
            '10' { $menuIncremental = -not $menuIncremental }
            '11' { $menuShowProgress = -not $menuShowProgress }
            '12' { $menuResumeInterrupted = -not $menuResumeInterrupted }
            '13' { $v = Read-Host '  Enter max retries'; if ($v -match '^\d+$') { $menuMaxRetryCount = [int]$v } }
            '14' { $v = Read-Host '  Enter retry delay seconds'; if ($v -match '^\d+$') { $menuRetryDelaySeconds = [int]$v } }
            '15' { $v = Read-Host '  Enter throttle delay ms'; if ($v -match '^\d+$') { $menuThrottleDelayMilliseconds = [int]$v } }
            '16' { $menuDetailedErrorReporting = -not $menuDetailedErrorReporting }
            '17' { $menuSkipCompleted = -not $menuSkipCompleted }
            '18' { try { $menuPriorResults = Get-CsvPathInteractive } catch {} }
            '19' { $menuReprocessSuccess = -not $menuReprocessSuccess }
            '20' {
                $value = Read-Host '  Enter parallel sessions (1-5)'
                if ($value -match '^[1-5]$') { $menuMaxParallelSessions = [int]$value }
                else { Write-Host '  Invalid value. Use 1 to 5.' -ForegroundColor Red }
            }
            '22' {
                Show-Header 'Configuration'
                Write-Host "  Connection Profile Status: $connectionProfileStatus"
                Write-Host "  CSV: $menuCsvPath"
                Write-Host "  Mode: $menuMode"
                Write-Host "  Migration Target: $menuFolderMode"
                Write-Host "  Subfolder Name: $menuDefaultSubFolder"
                Write-Host "  Auth Mode: $menuAuthMode"
                Write-Host "  Execution Mode: $menuExecutionMode"
                Write-Host "  Connection Profile: $menuConnectionProfilePath"
                Write-Host "  Source Root URL: $menuSourceRootUrl"
                Write-Host "  Destination Root URL: $menuDestinationRootUrl"
                Write-Host "  Source Admin Center URL: $menuSourceAdminCenterUrl"
                Write-Host "  Destination Admin Center URL: $menuDestinationAdminCenterUrl"
                Write-Host "  Source Admin User: $menuSourceAdminUser"
                Write-Host "  Destination Admin User: $menuDestinationAdminUser"
                Write-Host "  Execute Migration: $menuExecuteMigration"
                Write-Host "  WhatIf: $menuWhatIfOnly"
                Write-Host "  Incremental: $menuIncremental"
                Write-Host "  ResumeInterrupted: $menuResumeInterrupted"
                Write-Host "  MaxRetryCount: $menuMaxRetryCount"
                Write-Host "  RetryDelaySeconds: $menuRetryDelaySeconds"
                Write-Host "  ThrottleDelayMilliseconds: $menuThrottleDelayMilliseconds"
                Write-Host "  DetailedErrorReporting: $menuDetailedErrorReporting"
                Write-Host "  MaxParallelSessions: $menuMaxParallelSessions"
                Write-Host ''
                $null = Read-Host '  Press Enter'
            }
            '23' {
                if ([string]::IsNullOrWhiteSpace($menuCsvPath)) {
                    Write-Host '  ERROR: Select CSV first' -ForegroundColor Red
                }
                else {
                    if ((-not $script:PreAuthenticated) -and -not [string]::IsNullOrWhiteSpace($menuSourceRootUrl) -and -not [string]::IsNullOrWhiteSpace($menuDestinationRootUrl) -and $menuExecutionMode -in @('ReuseAuthSerial','ParallelBatches')) {
                        $script:ConnectionProfile = [ordered]@{
                            ProfilePath = $menuConnectionProfilePath
                            SourceRootUrl = $menuSourceRootUrl
                            DestinationRootUrl = $menuDestinationRootUrl
                            SourceAdminCenterUrl = $menuSourceAdminCenterUrl
                            DestinationAdminCenterUrl = $menuDestinationAdminCenterUrl
                            SourceAdminUser = $menuSourceAdminUser
                            DestinationAdminUser = $menuDestinationAdminUser
                            AuthMode = $menuAuthMode
                        }
                        try {
                            Write-Host '  Connection profile is configured. Connecting now before run...' -ForegroundColor Cyan
                            Connect-OnceNowFromProfile
                        }
                        catch {
                            Write-Host "  Auto-connect before run failed: $($_.Exception.Message)" -ForegroundColor Red
                            $continueChoice = Read-Host '  Continue to RUN anyway? (Y/N)'
                            if ($continueChoice -notin @('Y','y')) { continue }
                        }
                    }
                    $script:MenuResolved = [pscustomobject]@{
                        CsvPath                          = $menuCsvPath
                        Mode                             = $menuMode
                        MigrationFolderMode              = $menuFolderMode
                        DefaultSubFolder                 = $menuDefaultSubFolder
                        AuthMode                         = $menuAuthMode
                        ConnectionProfilePath            = $menuConnectionProfilePath
                        SourceRootUrl                    = $menuSourceRootUrl
                        DestinationRootUrl               = $menuDestinationRootUrl
                        SourceAdminCenterUrl             = $menuSourceAdminCenterUrl
                        DestinationAdminCenterUrl        = $menuDestinationAdminCenterUrl
                        SourceAdminUser                  = $menuSourceAdminUser
                        DestinationAdminUser             = $menuDestinationAdminUser
                        ExecutionMode                    = $menuExecutionMode
                        Incremental                      = $menuIncremental
                        WhatIfOnly                       = $menuWhatIfOnly
                        SkipCompletedFromPriorResults    = $menuSkipCompleted
                        PriorResultsCsvPath              = $menuPriorResults
                        ReprocessSuccess                 = $menuReprocessSuccess
                        MaxParallelSessions              = $menuMaxParallelSessions
                        ExecuteMigration                 = $menuExecuteMigration
                        MaxRetryCount                    = $menuMaxRetryCount
                        RetryDelaySeconds                = $menuRetryDelaySeconds
                        ResumeInterrupted                = $menuResumeInterrupted
                        ThrottleDelayMilliseconds        = $menuThrottleDelayMilliseconds
                        ShowProgress                     = $menuShowProgress
                        DetailedErrorReporting           = $menuDetailedErrorReporting
                    }
                    return
                }
            }
            '24' { exit 0 }
        }
    }
}

Assert-Module -Name 'Sharegate'

if ($Menu) {
    Start-InteractiveMenu
    if ($script:MenuResolved) {
        $CsvPath = $script:MenuResolved.CsvPath
        $Mode = $script:MenuResolved.Mode
        $MigrationFolderMode = $script:MenuResolved.MigrationFolderMode
        $DefaultSubFolder = $script:MenuResolved.DefaultSubFolder
        $AuthMode = $script:MenuResolved.AuthMode
        $ConnectionProfilePath = $script:MenuResolved.ConnectionProfilePath
        $SourceRootUrl = $script:MenuResolved.SourceRootUrl
        $DestinationRootUrl = $script:MenuResolved.DestinationRootUrl
        $SourceAdminCenterUrl = $script:MenuResolved.SourceAdminCenterUrl
        $DestinationAdminCenterUrl = $script:MenuResolved.DestinationAdminCenterUrl
        $SourceAdminUser = $script:MenuResolved.SourceAdminUser
        $DestinationAdminUser = $script:MenuResolved.DestinationAdminUser
        $ExecutionMode = $script:MenuResolved.ExecutionMode
        $Incremental = [bool]$script:MenuResolved.Incremental
        $WhatIfOnly = [bool]$script:MenuResolved.WhatIfOnly
        $SkipCompletedFromPriorResults = [bool]$script:MenuResolved.SkipCompletedFromPriorResults
        $PriorResultsCsvPath = $script:MenuResolved.PriorResultsCsvPath
        $ReprocessSuccess = [bool]$script:MenuResolved.ReprocessSuccess
        $MaxParallelSessions = [int]$script:MenuResolved.MaxParallelSessions
        $ExecuteMigration = [bool]$script:MenuResolved.ExecuteMigration
        $MaxRetryCount = [int]$script:MenuResolved.MaxRetryCount
        $RetryDelaySeconds = [int]$script:MenuResolved.RetryDelaySeconds
        $ResumeInterrupted = [bool]$script:MenuResolved.ResumeInterrupted
        $ThrottleDelayMilliseconds = [int]$script:MenuResolved.ThrottleDelayMilliseconds
        $ShowProgress = [bool]$script:MenuResolved.ShowProgress
        $DetailedErrorReporting = [bool]$script:MenuResolved.DetailedErrorReporting
    }
}


if ([string]::IsNullOrWhiteSpace($ConnectionProfilePath)) {
    $ConnectionProfilePath = Get-DefaultConnectionProfilePath
}
$loadedConnectionProfile = Import-ConnectionProfile -Path $ConnectionProfilePath
if ($loadedConnectionProfile) {
    foreach ($name in 'SourceRootUrl','DestinationRootUrl','SourceAdminCenterUrl','DestinationAdminCenterUrl','SourceAdminUser','DestinationAdminUser','AuthMode') {
        if ([string]::IsNullOrWhiteSpace((Get-Variable -Name $name -ValueOnly -ErrorAction SilentlyContinue)) -and $loadedConnectionProfile.PSObject.Properties.Name -contains $name -and -not [string]::IsNullOrWhiteSpace([string]$loadedConnectionProfile.$name)) {
            Set-Variable -Name $name -Value ([string]$loadedConnectionProfile.$name)
        }
    }
}

if ($BrowseForCsv -or [string]::IsNullOrWhiteSpace($CsvPath)) {
    $CsvPath = Get-CsvPathInteractive
}

if (-not (Test-Path -LiteralPath $CsvPath)) {
    throw 'CSV not found'
}

$runFolder = New-RunFolder -Root $ResultsRoot
$script:LogFile = Join-Path $runFolder 'Migration.log'
$script:ResultsCsv = Join-Path $runFolder 'Results.csv'
$script:StateCsv = Join-Path $runFolder 'MigrationState.csv'
$script:ErrorsCsv = Join-Path $runFolder 'Errors.csv'
$script:VerificationCsv = Join-Path $runFolder 'RootFileVerification.csv'
$script:ValidationSummaryCsv = Join-Path $runFolder 'PerUserValidationSummary.csv'

$resultsTemplateRow = Build-ResultRow -Operation '' -Started (Get-Date) -Ended (Get-Date) -Index 0 -RowKey '' -UserPrincipalName '' -SourceSite '' -DestinationSite '' -SourceLibrary '' -DestinationLibrary '' -CsvSubFolder '' -ResolvedSubFolder '' -MigrationFolderMode '' -FolderAction '' -Status '' -TaskName '' -ErrorMessage '' -Note '' -FolderExistsBefore $false -FolderExistsAfter $false -IncrementalEnabled $false -WhatIfEnabled $false -AuthModeUsed '' -RetryAttempt 0 -ExecutionMode ''
$stateTemplateRow = [pscustomobject]@{ RowIndex = 0; RowKey = ''; Status = ''; LastAttempt = 0; LastError = ''; Timestamp = ''; SourceSite = ''; DestinationSite = ''; ResolvedSubFolder = '' }
$verificationTemplateRow = New-SkippedVerificationRow -Index 0 -RowKey '' -UserPrincipalName '' -SourceSite '' -DestinationSite '' -SourceLibrary '' -DestinationLibrary '' -ResolvedSubFolder '' -Message 'Template'
Initialize-CsvFile -Path $script:ResultsCsv -TemplateRow $resultsTemplateRow -Label 'Results CSV'
Initialize-CsvFile -Path $script:StateCsv -TemplateRow $stateTemplateRow -Label 'State CSV'
Initialize-CsvFile -Path $script:VerificationCsv -TemplateRow $verificationTemplateRow -Label 'Verification CSV'
$validationSummaryTemplateRow = Build-ValidationSummaryRow -ResultRow $resultsTemplateRow -VerificationRow $verificationTemplateRow
Initialize-CsvFile -Path $script:ValidationSummaryCsv -TemplateRow $validationSummaryTemplateRow -Label 'Validation summary CSV'
if ($DetailedErrorReporting) {
    $errorTemplateRow = Build-ErrorRow -Index 0 -RowKey '' -Operation '' -SourceSite '' -DestinationSite '' -ResolvedSubFolder '' -RetryAttempt 0 -ErrorMessage '' -ErrorType '' -StackTrace '' -UserPrincipalName '' -Note ''
    Initialize-CsvFile -Path $script:ErrorsCsv -TemplateRow $errorTemplateRow -Label 'Errors CSV'
}
$transcriptFile = Join-Path $runFolder 'Transcript.txt'
$effectiveResumePath = if ($ResumeInterrupted -and -not [string]::IsNullOrWhiteSpace($PriorResultsCsvPath)) { $PriorResultsCsvPath } else { '' }

Start-Transcript -LiteralPath $transcriptFile -Force | Out-Null

try {
    if ($Mode -notin @('ValidateOnly','Migrate')) { $Mode = 'Migrate' }
if ($MigrationFolderMode -notin @('Root','Subfolder')) { $MigrationFolderMode = 'Subfolder' }
Write-Log -Level INFO -Message '==================================================='
    Write-Log -Level INFO -Message 'ShareGate OneDrive Migration Toolkit v8.3.5.4'
    Write-Log -Level INFO -Message '==================================================='
    Write-Log -Level INFO -Message "Run folder: $runFolder"
    Write-Log -Level INFO -Message "CSV path: $CsvPath"
    Write-Log -Level INFO -Message "Mode: $Mode"
    Write-Log -Level INFO -Message "Folder mode: $MigrationFolderMode"
    Write-Log -Level INFO -Message "ExecuteMigration: $ExecuteMigration"
    Write-Log -Level INFO -Message "WhatIfOnly: $WhatIfOnly"
    Write-Log -Level INFO -Message "ResumeInterrupted: $ResumeInterrupted"
    Write-Log -Level INFO -Message "ThrottleDelayMilliseconds: $ThrottleDelayMilliseconds"
    Write-Log -Level INFO -Message "ExecutionMode: $ExecutionMode"
    Write-Log -Level INFO -Message "VerificationReportPath: $(if ([string]::IsNullOrWhiteSpace($VerificationReportPath)) { '<auto-discover>' } else { $VerificationReportPath })"
    Write-Log -Level INFO -Message "ValidationSummary: $script:ValidationSummaryCsv"
    Write-Log -Level INFO -Message "SkipVerification: $([bool]$SkipVerification)"
    Write-Log -Level INFO -Message "MaxParallelSessions: $MaxParallelSessions"

$script:ConnectionProfile = [ordered]@{
    ProfilePath = $ConnectionProfilePath
    SourceRootUrl = $SourceRootUrl
    DestinationRootUrl = $DestinationRootUrl
    SourceAdminCenterUrl = $SourceAdminCenterUrl
    DestinationAdminCenterUrl = $DestinationAdminCenterUrl
    SourceAdminUser = $SourceAdminUser
    DestinationAdminUser = $DestinationAdminUser
    AuthMode = $AuthMode
}
if ($null -eq $script:PreAuthConnectionCache) { $script:PreAuthConnectionCache = @{} }
if ($null -eq (Get-Variable -Name PreAuthenticated -Scope Script -ErrorAction SilentlyContinue)) { $script:PreAuthenticated = $false }
$script:BatchScopedAuthReuse = [bool]$BatchScopedAuthReuse
if ($null -eq (Get-Variable -Name SourceRootConnection -Scope Script -ErrorAction SilentlyContinue)) { $script:SourceRootConnection = $null }
if ($null -eq (Get-Variable -Name DestinationRootConnection -Scope Script -ErrorAction SilentlyContinue)) { $script:DestinationRootConnection = $null }
Write-Log -Level INFO -Message "ConnectionProfilePath: $ConnectionProfilePath"
Write-Log -Level INFO -Message "ConfiguredSourceRootUrl: $(if ([string]::IsNullOrWhiteSpace($SourceRootUrl)) { '<derived>' } else { $SourceRootUrl })"
Write-Log -Level INFO -Message "ConfiguredDestinationRootUrl: $(if ([string]::IsNullOrWhiteSpace($DestinationRootUrl)) { '<derived>' } else { $DestinationRootUrl })"
Write-Log -Level INFO -Message "SourceAdminUser: $(if ([string]::IsNullOrWhiteSpace($SourceAdminUser)) { '<not set>' } else { $SourceAdminUser })"
Write-Log -Level INFO -Message "DestinationAdminUser: $(if ([string]::IsNullOrWhiteSpace($DestinationAdminUser)) { '<not set>' } else { $DestinationAdminUser })"
    Write-Log -Level INFO -Message '==================================================='

    $table = @(Import-Csv -LiteralPath $CsvPath)
    $rowCount = @($table).Count
    if (-not $table -or $rowCount -eq 0) {
        throw 'CSV has no data rows'
    }

    $requiredColumns = @('SourceSite','DestinationSite')
    $firstRow = $table | Select-Object -First 1
    foreach ($requiredColumn in $requiredColumns) {
        if ($firstRow.PSObject.Properties.Name -notcontains $requiredColumn) {
            throw "CSV missing required column: $requiredColumn"
        }
    }

    Write-Log -Level INFO -Message "CSV loaded: $rowCount rows"


    if ($ExecutionMode -eq 'ReuseAuthSerial' -and $MaxParallelSessions -gt 1 -and $rowCount -gt 1) {
        Write-Log -Level WARN -Message ("ReuseAuthSerial mode enabled. MaxParallelSessions={0} is acting as queue guidance only; active migration concurrency remains 1 so the authenticated ShareGate session and connection cache can be reused across queued rows without repeated worker sign-ins." -f $MaxParallelSessions)
    }
    elseif ($ExecutionMode -eq 'TrueParallel' -and $MaxParallelSessions -gt 1 -and $rowCount -gt 1) {
        Write-Log -Level WARN -Message ("TrueParallel mode enabled. Up to {0} worker session(s) will be launched. Browser auth optimization, warm-up reuse, and staggered starts are enabled, but some tenants may still prompt for source/destination auth per worker." -f $MaxParallelSessions)
        Invoke-ParallelAuthWarmup -Rows $table -Mode $Mode -AuthMode $AuthMode
        Invoke-ParallelRowProcessing -Rows $table -CsvPath $CsvPath -MaxParallelSessions $MaxParallelSessions -RunFolder $runFolder -ScriptPath $PSCommandPath -Mode $Mode -MigrationFolderMode $MigrationFolderMode -DefaultSubFolder $DefaultSubFolder -SourceLibraryName $SourceLibraryName -DestinationLibraryName $DestinationLibraryName -AuthMode $AuthMode -Incremental:$Incremental -WhatIfOnly:$WhatIfOnly -SkipCompletedFromPriorResults:$SkipCompletedFromPriorResults -PriorResultsCsvPath $PriorResultsCsvPath -ReprocessSuccess:$ReprocessSuccess -ExecuteMigration:$ExecuteMigration -MaxRetryCount $MaxRetryCount -RetryDelaySeconds $RetryDelaySeconds -ResumeInterrupted:$ResumeInterrupted -ThrottleDelayMilliseconds $ThrottleDelayMilliseconds -DetailedErrorReporting:$DetailedErrorReporting -ShowProgress:$false -VerificationReportPath $VerificationReportPath -SkipVerification:$SkipVerification -BatchScopedAuthReuse:$BatchScopedAuthReuse
        return
    }
    elseif ($ExecutionMode -eq 'ParallelBatches' -and $MaxParallelSessions -gt 1 -and $rowCount -gt 1) {
        Write-Log -Level WARN -Message ("ParallelBatches mode enabled. Up to {0} batch worker session(s) will be launched. Each batch worker signs in once and then processes its assigned users serially." -f $MaxParallelSessions)
        Write-Log -Level INFO -Message 'ParallelBatches mode: skipping parent auth warm-up. Each batch worker will authenticate once and then reuse its own session for its assigned users.'
        Invoke-ParallelBatchProcessing -Rows $table -BatchScopedAuthReuse:$true -CsvPath $CsvPath -MaxParallelSessions $MaxParallelSessions -RunFolder $runFolder -ScriptPath $PSCommandPath -Mode $Mode -MigrationFolderMode $MigrationFolderMode -DefaultSubFolder $DefaultSubFolder -SourceLibraryName $SourceLibraryName -DestinationLibraryName $DestinationLibraryName -AuthMode $AuthMode -Incremental:$Incremental -WhatIfOnly:$WhatIfOnly -SkipCompletedFromPriorResults:$SkipCompletedFromPriorResults -PriorResultsCsvPath $PriorResultsCsvPath -ReprocessSuccess:$ReprocessSuccess -ExecuteMigration:$ExecuteMigration -MaxRetryCount $MaxRetryCount -RetryDelaySeconds $RetryDelaySeconds -ResumeInterrupted:$ResumeInterrupted -ThrottleDelayMilliseconds $ThrottleDelayMilliseconds -DetailedErrorReporting:$DetailedErrorReporting -ShowProgress:$false -VerificationReportPath $VerificationReportPath -SkipVerification:$SkipVerification
        return
    }

    $sourceRoot = if (-not [string]::IsNullOrWhiteSpace($SourceRootUrl)) { $SourceRootUrl } else { Get-RootSiteUrl -PersonalSiteUrl $firstRow.SourceSite }
    $destinationRoot = if (-not [string]::IsNullOrWhiteSpace($DestinationRootUrl)) { $DestinationRootUrl } else { Get-RootSiteUrl -PersonalSiteUrl $firstRow.DestinationSite }

    $needsSource = $Mode -in @('Migrate','ValidateOnly')
    $srcRootConnection = $null
    $dstRootConnection = $null

    if ($script:PreAuthenticated -and $script:SourceRootConnection -and $script:DestinationRootConnection -and [string]$script:SourceRootUrl -eq [string]$sourceRoot -and [string]$script:DestinationRootUrl -eq [string]$destinationRoot) {
        Write-Log -Level INFO -Message 'Using pre-authenticated cached root connections from Connection Profile.'
        if ($needsSource) { $srcRootConnection = $script:SourceRootConnection }
        $dstRootConnection = $script:DestinationRootConnection
    }
    else {
        Write-Log -Level STEP -Message 'Establishing root connections...'
        if ($needsSource) {
            $srcRootConnection = Connect-ShareGateSite -Url $sourceRoot -Mode $AuthMode -Label 'SourceRoot'
        }
        $dstRootConnection = Connect-ShareGateSite -Url $destinationRoot -Mode $AuthMode -Label 'DestinationRoot'
        if ($needsSource -and $srcRootConnection) { $script:SourceRootConnection = $srcRootConnection; $script:SourceRootUrl = $sourceRoot }
        if ($dstRootConnection) { $script:DestinationRootConnection = $dstRootConnection; $script:DestinationRootUrl = $destinationRoot }
        $script:PreAuthenticated = ($null -ne $srcRootConnection -or -not $needsSource) -and ($null -ne $dstRootConnection)
        if ($needsSource -and $srcRootConnection) { $script:PreAuthConnectionCache[$sourceRoot] = $srcRootConnection }
        if ($dstRootConnection) { $script:PreAuthConnectionCache[$destinationRoot] = $dstRootConnection }
    }

    $priorLookup = @{}
    if ($SkipCompletedFromPriorResults -and -not [string]::IsNullOrWhiteSpace($PriorResultsCsvPath) -and (Test-Path -LiteralPath $PriorResultsCsvPath)) {
        Write-Log -Level INFO -Message "Loading prior results from: $PriorResultsCsvPath"
        foreach ($prior in @(Import-Csv -LiteralPath $PriorResultsCsvPath)) {
            $k = ''
            if ($prior.PSObject.Properties.Name -contains 'RowKey' -and -not [string]::IsNullOrWhiteSpace($prior.RowKey)) {
                $k = $prior.RowKey
            }
            elseif ($prior.PSObject.Properties.Name -contains 'Index' -and $prior.PSObject.Properties.Name -contains 'SourceSite' -and $prior.PSObject.Properties.Name -contains 'DestinationSite' -and $prior.PSObject.Properties.Name -contains 'ResolvedSubFolder') {
                $k = ('{0}|{1}|{2}|{3}' -f $prior.Index, $prior.SourceSite, $prior.DestinationSite, $prior.ResolvedSubFolder)
            }
            if (-not [string]::IsNullOrWhiteSpace($k)) {
                $priorLookup[$k] = $prior
            }
        }
    }

    $resumeLookup = Get-StateLookup -Path $effectiveResumePath
    if ($ResumeInterrupted -and $resumeLookup.Count -gt 0) {
        Write-Log -Level INFO -Message "Resume state loaded: $($resumeLookup.Count) row entries from $effectiveResumePath"
    }

    $sourceConnectionCache = @{}
    $destinationConnectionCache = @{}
    if ($srcRootConnection -and -not [string]::IsNullOrWhiteSpace($sourceRoot)) { $sourceConnectionCache[$sourceRoot] = $srcRootConnection; $script:ConnectionCache[$sourceRoot] = $srcRootConnection }
    if ($dstRootConnection -and -not [string]::IsNullOrWhiteSpace($destinationRoot)) { $destinationConnectionCache[$destinationRoot] = $dstRootConnection; $script:ConnectionCache[$destinationRoot] = $dstRootConnection }
    if ($ExecutionMode -eq 'ParallelBatches' -or $script:BatchScopedAuthReuse) { Write-Log -Level INFO -Message 'Batch-scoped auth reuse is enabled for this worker. Per-user interactive auth fallback is suppressed when root credential reuse is available.' }

    Write-Log -Level STEP -Message 'Processing migration rows...'
    $successCount = 0
    $failureCount = 0
    $skippedCount = 0

    for ($i = 0; $i -lt $table.Count; $i++) {
        $row = $table[$i]
        $index = $i + 1
        $started = Get-Date

        $sourceSiteUrl = [string]$row.SourceSite
        $destinationSiteUrl = [string]$row.DestinationSite
        $csvSubFolder = Get-RowValue -Row $row -PropertyName 'SubFolder'
        $resolvedSubFolder = Resolve-TargetSubFolder -Row $row -FolderMode $MigrationFolderMode -DefaultFolder $DefaultSubFolder
        $userPrincipalName = Get-RowValue -Row $row -PropertyName 'UserPrincipalName'
        $note = Get-RowValue -Row $row -PropertyName 'Note'
        $rowKey = New-RowKey -Index $index -SourceSite $sourceSiteUrl -DestinationSite $destinationSiteUrl -ResolvedSubFolder $resolvedSubFolder
        $percentComplete = [math]::Round(($index / $table.Count) * 100, 0)
        $executionModeLabel = if ($ExecuteMigration -and -not $WhatIfOnly) { 'Execute' } else { 'DryRun' }

        if ($ShowProgress) {
            Write-Progress -Id 1 -Activity 'ShareGate OneDrive Migration' -Status "Row $index of $($table.Count)" -PercentComplete $percentComplete
        }

        Write-Log -Level INFO -Message "Row ${index}: begin $Mode; User=$userPrincipalName; Source=$sourceSiteUrl; Destination=$destinationSiteUrl; SourceFolder=$csvSubFolder; ResolvedSubFolder=$resolvedSubFolder"

        if ($SkipCompletedFromPriorResults -and $priorLookup.ContainsKey($rowKey)) {
            $prior = $priorLookup[$rowKey]
            if (($prior.Status -eq 'Success' -or $prior.Status -eq 'Completed') -and -not $ReprocessSuccess) {
                $ended = Get-Date
                Write-Log -Level WARN -Message "Row $index skipped due to prior successful result."
                $result = Build-ResultRow -Operation $Mode -Started $started -Ended $ended -Index $index -RowKey $rowKey -UserPrincipalName $userPrincipalName -SourceSite $sourceSiteUrl -DestinationSite $destinationSiteUrl -SourceLibrary $SourceLibraryName -DestinationLibrary $DestinationLibraryName -CsvSubFolder $csvSubFolder -ResolvedSubFolder $resolvedSubFolder -MigrationFolderMode $MigrationFolderMode -FolderAction 'SkippedPriorSuccess' -Status 'Skipped' -TaskName '' -ErrorMessage '' -Note $note -FolderExistsBefore $false -FolderExistsAfter $false -IncrementalEnabled ([bool]$Incremental) -WhatIfEnabled ([bool]$WhatIfOnly) -AuthModeUsed $AuthMode -RetryAttempt 0 -ExecutionMode $executionModeLabel
                Save-ResultRow -Row $result
                $validationSummaryRow = Build-ValidationSummaryRow -ResultRow $result -VerificationRow $null
                Save-ValidationSummaryRow -Row $validationSummaryRow
                Save-StateRow -Row ([pscustomobject]@{ RowIndex = $index; RowKey = $rowKey; Status = 'Skipped'; LastAttempt = 0; LastError = ''; Timestamp = (Get-Date).ToString('s'); SourceSite = $sourceSiteUrl; DestinationSite = $destinationSiteUrl; ResolvedSubFolder = $resolvedSubFolder })
                $skippedCount++
                continue
            }
        }

        if ($ResumeInterrupted -and $resumeLookup.ContainsKey($rowKey)) {
            $resume = $resumeLookup[$rowKey]
            if (($resume.Status -eq 'Success' -or $resume.Status -eq 'Completed' -or $resume.Status -eq 'Skipped') -and -not $ReprocessSuccess) {
                $ended = Get-Date
                Write-Log -Level WARN -Message "Row $index skipped due to resume state status [$($resume.Status)]."
                $result = Build-ResultRow -Operation $Mode -Started $started -Ended $ended -Index $index -RowKey $rowKey -UserPrincipalName $userPrincipalName -SourceSite $sourceSiteUrl -DestinationSite $destinationSiteUrl -SourceLibrary $SourceLibraryName -DestinationLibrary $DestinationLibraryName -CsvSubFolder $csvSubFolder -ResolvedSubFolder $resolvedSubFolder -MigrationFolderMode $MigrationFolderMode -FolderAction 'SkippedResumeState' -Status 'Skipped' -TaskName '' -ErrorMessage '' -Note $note -FolderExistsBefore $false -FolderExistsAfter $false -IncrementalEnabled ([bool]$Incremental) -WhatIfEnabled ([bool]$WhatIfOnly) -AuthModeUsed $AuthMode -RetryAttempt 0 -ExecutionMode $executionModeLabel
                Save-ResultRow -Row $result
                $validationSummaryRow = Build-ValidationSummaryRow -ResultRow $result -VerificationRow $null
                Save-ValidationSummaryRow -Row $validationSummaryRow
                Save-StateRow -Row ([pscustomobject]@{ RowIndex = $index; RowKey = $rowKey; Status = 'Skipped'; LastAttempt = 0; LastError = ''; Timestamp = (Get-Date).ToString('s'); SourceSite = $sourceSiteUrl; DestinationSite = $destinationSiteUrl; ResolvedSubFolder = $resolvedSubFolder })
                $skippedCount++
                continue
            }
        }

        try {
            $sourceConn = $null
            $destConn = $null

            $sourceConnectResult = $null
            $destConnectResult = $null

            if ($needsSource) {
                $sourceConnectResult = Get-ConnectionFromCacheOrConnect -Cache $sourceConnectionCache -Url $sourceSiteUrl -UseCredentialsFrom $srcRootConnection -Mode $AuthMode -Label "SourceRow$index" -MaxRetryCount $MaxRetryCount -RetryDelaySeconds $RetryDelaySeconds -RowIndex $index -RowKey $rowKey -OperationLabel 'Connect source site'

                if (-not $sourceConnectResult.Success) { throw $sourceConnectResult.ErrorRecord }
                $sourceConn = $sourceConnectResult.Result
            }

            $destConnectResult = Get-ConnectionFromCacheOrConnect -Cache $destinationConnectionCache -Url $destinationSiteUrl -UseCredentialsFrom $dstRootConnection -Mode $AuthMode -Label "DestinationRow$index" -MaxRetryCount $MaxRetryCount -RetryDelaySeconds $RetryDelaySeconds -RowIndex $index -RowKey $rowKey -OperationLabel 'Connect destination site'

            if (-not $destConnectResult.Success) { throw $destConnectResult.ErrorRecord }
            $destConn = $destConnectResult.Result

            $folderExistsBefore = $false
            $folderExistsAfter = $false
            $taskName = ''
            $folderAction = ''
            $status = 'Success'
            $copySucceeded = $false
            $copyFailureMessage = ''
            $finalAttempt = [Math]::Max($(if ($sourceConnectResult) { $sourceConnectResult.Attempt } else { 1 }), $destConnectResult.Attempt)
            if ($Mode -eq 'ValidateOnly') {
                $folderExistsBefore = if ([string]::IsNullOrWhiteSpace($resolvedSubFolder)) { $true } else { Test-TargetFolderExists -DestinationSite $destConn -LibraryName $DestinationLibraryName -SubFolder $resolvedSubFolder }
                $folderExistsAfter = $folderExistsBefore
                $folderAction = 'Validated'
            }
            else {
                $copyStartedAt = Get-Date
                try {
                    Write-Log -Level INFO -Message "Row ${index}: Starting copy operation..."
                    $copyOp = Invoke-WithRetry -ScriptBlock {
                        Invoke-CopyContent -SourceSite $sourceConn -DestinationSite $destConn -SourceSiteUrl $sourceSiteUrl -DestinationSiteUrl $destinationSiteUrl -SourceLibraryName $SourceLibraryName -DestinationLibraryName $DestinationLibraryName -ResolvedSubFolder $resolvedSubFolder -Incremental:$Incremental -ExecuteMigration:$ExecuteMigration -WhatIfOnly:$WhatIfOnly
                    } -MaxRetryCount $MaxRetryCount -RetryDelaySeconds $RetryDelaySeconds -OperationLabel 'Copy content' -RowIndex $index -RowKey $rowKey

                    if (-not $copyOp.Success) { throw $copyOp.ErrorRecord }
                    if ($copyOp.Result.PSObject.Properties.Name -contains 'TaskName' -and -not [string]::IsNullOrWhiteSpace($copyOp.Result.TaskName)) {
                        $taskName = [string]$copyOp.Result.TaskName
                    }
                    $folderAction = [string]$(if ($copyOp.Result.PSObject.Properties.Name -contains 'FolderAction') { $copyOp.Result.FolderAction } else { 'Copied' })
                    $folderExistsAfter = $true
                    $finalAttempt = [Math]::Max($finalAttempt, $copyOp.Attempt)
                    $copySucceeded = $true
                    Write-Log -Level SUCCESS -Message "Row ${index}: Copy operation completed"
                }
                catch {
                    $copySucceeded = $false
                    $copyFailureMessage = Get-ExceptionText -Exception $_.Exception
                    Write-Log -Level ERROR -Message "Row ${index}: Copy operation failed: $copyFailureMessage"
                    throw
                }
            }

            $ended = Get-Date
            $result = Build-ResultRow -Operation $Mode -Started $started -Ended $ended -Index $index -RowKey $rowKey -UserPrincipalName $userPrincipalName -SourceSite $sourceSiteUrl -DestinationSite $destinationSiteUrl -SourceLibrary $SourceLibraryName -DestinationLibrary $DestinationLibraryName -CsvSubFolder $csvSubFolder -ResolvedSubFolder $resolvedSubFolder -MigrationFolderMode $MigrationFolderMode -FolderAction $folderAction -Status $status -TaskName $taskName -ErrorMessage '' -Note $note -FolderExistsBefore $folderExistsBefore -FolderExistsAfter $folderExistsAfter -IncrementalEnabled ([bool]$Incremental) -WhatIfEnabled ([bool]$WhatIfOnly) -AuthModeUsed $AuthMode -RetryAttempt $finalAttempt -ExecutionMode $executionModeLabel
            Save-ResultRow -Row $result
            if (-not ($Mode -eq 'Migrate' -and $ExecuteMigration -and -not $WhatIfOnly)) {
                $validationSummaryRow = Build-ValidationSummaryRow -ResultRow $result -VerificationRow $null
                Save-ValidationSummaryRow -Row $validationSummaryRow
            }

            if ($Mode -eq 'Migrate' -and $ExecuteMigration -and -not $WhatIfOnly) {
                try {
                    if ($SkipVerification) {
                        $verificationRow = New-SkippedVerificationRow -Index $index -RowKey $rowKey -UserPrincipalName $userPrincipalName -SourceSite $sourceSiteUrl -DestinationSite $destinationSiteUrl -SourceLibrary $SourceLibraryName -DestinationLibrary $DestinationLibraryName -ResolvedSubFolder $resolvedSubFolder -Message 'Verification skipped by operator request (-SkipVerification).'
                    }
                    else {
                        Write-Log -Level INFO -Message "Row ${index}: Starting root file verification..."
                        $taskNameForVerification = ''
                        $taskObjectForVerification = $null
                        if ($copyOp -and $copyOp.Result) {
                            if ($copyOp.Result.PSObject.Properties.Name -contains 'TaskName' -and -not [string]::IsNullOrWhiteSpace($copyOp.Result.TaskName)) {
                                $taskNameForVerification = [string]$copyOp.Result.TaskName
                            }
                            if ($copyOp.Result.PSObject.Properties.Name -contains 'RawTask') {
                                $taskObjectForVerification = $copyOp.Result.RawTask
                            }
                        }
                        $verificationRow = Invoke-RootFileVerification -VerificationReportPath $VerificationReportPath -TaskName $taskNameForVerification -TaskObject $taskObjectForVerification -RunFolder $runFolder -CopyStartedAt $copyStartedAt -SourceLibraryName $SourceLibraryName -DestinationLibraryName $DestinationLibraryName -ResolvedSubFolder $resolvedSubFolder -Index $index -RowKey $rowKey -UserPrincipalName $userPrincipalName -SourceSiteUrl $sourceSiteUrl -DestinationSiteUrl $destinationSiteUrl
                        if (-not $verificationRow) {
                            $verificationRow = New-SkippedVerificationRow -Index $index -RowKey $rowKey -UserPrincipalName $userPrincipalName -SourceSite $sourceSiteUrl -DestinationSite $destinationSiteUrl -SourceLibrary $SourceLibraryName -DestinationLibrary $DestinationLibraryName -ResolvedSubFolder $resolvedSubFolder -Message 'Verification returned no row.'
                        }
                    }
                    Save-VerificationRow -Row $verificationRow
                    $validationSummaryRow = Build-ValidationSummaryRow -ResultRow $result -VerificationRow $verificationRow
                    Save-ValidationSummaryRow -Row $validationSummaryRow
                }
                catch {
                    $verificationError = Get-ExceptionText -Exception $_.Exception
                    Write-Log -Level ERROR -Message "Row ${index}: Verification FAILED: $verificationError"
                    $verificationRow = New-SkippedVerificationRow -Index $index -RowKey $rowKey -UserPrincipalName $userPrincipalName -SourceSite $sourceSiteUrl -DestinationSite $destinationSiteUrl -SourceLibrary $SourceLibraryName -DestinationLibrary $DestinationLibraryName -ResolvedSubFolder $resolvedSubFolder -Message ("Verification failed after copy completion: {0}" -f $verificationError)
                    Save-VerificationRow -Row $verificationRow
                    $validationSummaryRow = Build-ValidationSummaryRow -ResultRow $result -VerificationRow $verificationRow
                    Save-ValidationSummaryRow -Row $validationSummaryRow
                }
            }

            Save-StateRow -Row ([pscustomobject]@{ RowIndex = $index; RowKey = $rowKey; Status = 'Success'; LastAttempt = $finalAttempt; LastError = ''; Timestamp = (Get-Date).ToString('s'); SourceSite = $sourceSiteUrl; DestinationSite = $destinationSiteUrl; ResolvedSubFolder = $resolvedSubFolder })
            Write-Log -Level SUCCESS -Message "Row ${index}: $sourceSiteUrl -> $destinationSiteUrl [Success]"
            $successCount++
        }
        catch {
            $ended = Get-Date
            $errText = Get-ExceptionText -Exception $_.Exception
            $stack = if ($_.ScriptStackTrace) { [string]$_.ScriptStackTrace } else { '' }
            $errorType = if ($_.Exception) { $_.Exception.GetType().FullName } else { 'UnknownError' }

            $result = Build-ResultRow -Operation $Mode -Started $started -Ended $ended -Index $index -RowKey $rowKey -UserPrincipalName $userPrincipalName -SourceSite $sourceSiteUrl -DestinationSite $destinationSiteUrl -SourceLibrary $SourceLibraryName -DestinationLibrary $DestinationLibraryName -CsvSubFolder $csvSubFolder -ResolvedSubFolder $resolvedSubFolder -MigrationFolderMode $MigrationFolderMode -FolderAction 'Failed' -Status 'Failed' -TaskName '' -ErrorMessage $errText -Note $note -FolderExistsBefore $false -FolderExistsAfter $false -IncrementalEnabled ([bool]$Incremental) -WhatIfEnabled ([bool]$WhatIfOnly) -AuthModeUsed $AuthMode -RetryAttempt $MaxRetryCount -ExecutionMode $executionModeLabel
            Save-ResultRow -Row $result
            Save-StateRow -Row ([pscustomobject]@{ RowIndex = $index; RowKey = $rowKey; Status = 'Failed'; LastAttempt = $MaxRetryCount; LastError = $errText; Timestamp = (Get-Date).ToString('s'); SourceSite = $sourceSiteUrl; DestinationSite = $destinationSiteUrl; ResolvedSubFolder = $resolvedSubFolder })

            if ($DetailedErrorReporting) {
                $errorRow = Build-ErrorRow -Index $index -RowKey $rowKey -Operation $Mode -SourceSite $sourceSiteUrl -DestinationSite $destinationSiteUrl -ResolvedSubFolder $resolvedSubFolder -RetryAttempt $MaxRetryCount -ErrorMessage $errText -ErrorType $errorType -StackTrace $stack -UserPrincipalName $userPrincipalName -Note $note
                Save-ErrorRow -Row $errorRow
            }

            if ($Mode -eq 'Migrate' -and $ExecuteMigration -and -not $WhatIfOnly) {
                $failedVerificationRow = New-SkippedVerificationRow -Index $index -RowKey $rowKey -UserPrincipalName $userPrincipalName -SourceSite $sourceSiteUrl -DestinationSite $destinationSiteUrl -SourceLibrary $SourceLibraryName -DestinationLibrary $DestinationLibraryName -ResolvedSubFolder $resolvedSubFolder -Message ("Verification unavailable because row failed before verification completed: {0}" -f $errText)
                Save-VerificationRow -Row $failedVerificationRow
                $validationSummaryRow = Build-ValidationSummaryRow -ResultRow $result -VerificationRow $failedVerificationRow
                Save-ValidationSummaryRow -Row $validationSummaryRow
            }

            Write-Log -Level ERROR -Message "Row $index failed: $errText"
            $failureCount++
        }
        finally {
            if ($ThrottleDelayMilliseconds -gt 0 -and $index -lt $table.Count) {
                Start-Sleep -Milliseconds $ThrottleDelayMilliseconds
            }
        }
    }

    if ($ShowProgress) {
        Write-Progress -Id 1 -Activity 'ShareGate OneDrive Migration' -Completed
    }

    Write-Log -Level SUCCESS -Message "Complete: $successCount success, $failureCount failed, $skippedCount skipped"
    Write-Log -Level INFO -Message "Results: $script:ResultsCsv"
    Write-Log -Level INFO -Message "State: $script:StateCsv"
    Write-Log -Level INFO -Message ("Verification CSV exists: {0}" -f (Test-Path -LiteralPath $script:VerificationCsv))
    if ($DetailedErrorReporting) {
        Write-Log -Level INFO -Message "Errors: $script:ErrorsCsv"
    }
    Write-Log -Level INFO -Message "Verification: $script:VerificationCsv"
    Write-Log -Level INFO -Message ("Verification CSV exists: {0}" -f (Test-Path -LiteralPath $script:VerificationCsv))
}
catch {
    $err = Get-ExceptionText -Exception $_.Exception
    Write-Log -Level ERROR -Message "FATAL: $err"
    Write-Host "ERROR: $err" -ForegroundColor Red
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
    Write-Host ''
    Write-Host "Run folder: $runFolder" -ForegroundColor Cyan
    if (-not $NoPause -and -not $Menu) {
        $null = Read-Host 'Press Enter to exit'
    }
}
