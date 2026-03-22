$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "windows-e2e-common.ps1")

$RootDir = $script:RepoRoot
$LinuxHelper = Join-Path $RootDir "e2e/run_linux_spiderweb_host.sh"
$RemoteTemplateDir = Join-Path $RootDir "e2e/fixtures/agent-relay"
$LinuxWorkerPrompt = Join-Path $RootDir "e2e/prompts/agent-relay-linux-worker.txt"
$WindowsReviewerPrompt = Join-Path $RootDir "e2e/prompts/agent-relay-windows-reviewer.txt"
$Validator = Join-Path $RootDir "e2e/validate_agent_relay.py"
$RelayRunner = Join-Path $RootDir "e2e/agent_relay_runner.py"

$OutputDir = if ($env:OUTPUT_DIR) { $env:OUTPUT_DIR } else { New-RunDirectory "cross-platform-agent-relay-windows" }
$OutputDir = Ensure-RunDirectoryUnderRepo $OutputDir
$RunDirRel = Get-RunDirectoryRelative $OutputDir
$RunName = Split-Path -Leaf $OutputDir
$LogDir = Join-Path $OutputDir "logs"
$StateDir = Join-Path $OutputDir "state"
$ArtifactDir = Join-Path $OutputDir "artifacts"
$BuildDir = Join-Path $OutputDir "build/windows"
$RemoteExportCopy = Join-Path $StateDir "windows-remote-export"

$SpiderNodePrefix = Join-Path $BuildDir "spidernode-prefix"
$SpiderNodeLocalCache = Join-Path $BuildDir "spidernode-local-cache"
$SpiderNodeGlobalCache = Join-Path $BuildDir "spidernode-global-cache"
$LocalNodeBin = $null

$SpiderwebPort = if ($env:SPIDERWEB_PORT) { $env:SPIDERWEB_PORT } else { "28796" }
$LocalWorkspaceNodePort = if ($env:LOCAL_WORKSPACE_NODE_PORT) { $env:LOCAL_WORKSPACE_NODE_PORT } else { "28951" }
$RemoteNodePort = if ($env:REMOTE_NODE_PORT) { $env:REMOTE_NODE_PORT } else { "28952" }
$RemoteNodeName = if ($env:REMOTE_NODE_NAME) { $env:REMOTE_NODE_NAME } else { "cross-windows-review-node" }
$RemoteExportName = if ($env:REMOTE_EXPORT_NAME) { $env:REMOTE_EXPORT_NAME } else { "remote-smoke" }
$RemoteBindPath = "/remote"

$LinuxWorkerJsonl = Join-Path $LogDir "linux-worker-runner.jsonl"
$LinuxWorkerStderr = Join-Path $LogDir "linux-worker-runner.stderr.log"
$LinuxWorkerLast = Join-Path $ArtifactDir "linux_worker_last_message.txt"
$WindowsReviewerJsonl = Join-Path $LogDir "windows-reviewer-runner.jsonl"
$WindowsReviewerStderr = Join-Path $LogDir "windows-reviewer-runner.stderr.log"
$WindowsReviewerLast = Join-Path $ArtifactDir "windows_reviewer_last_message.txt"
$RelayValidationJson = Join-Path $ArtifactDir "agent_relay_validation.json"

$LocalRemoteNodeLog = Join-Path $LogDir "windows-remote-node.log"
$LocalRemoteNodeErrLog = Join-Path $LogDir "windows-remote-node.stderr.log"
$LocalRemoteNode = $null
$script:HelperEnv = $null

function Cleanup {
    if ($null -ne $script:LocalRemoteNode -and -not $script:LocalRemoteNode.HasExited) {
        try {
            Stop-Process -Id $script:LocalRemoteNode.Id -Force
        } catch {
        }
    }
    if (Test-Path -LiteralPath $LinuxHelper) {
        try {
            if ($null -ne $script:HelperEnv) {
                Invoke-WslHelper -Action "cleanup" -Environment $script:HelperEnv
            }
        } catch {
        }
    }
}

function Copy-RemoteTemplate {
    if (Test-Path -LiteralPath $RemoteExportCopy) {
        Remove-Item -LiteralPath $RemoteExportCopy -Recurse -Force
    }
    Copy-Item -LiteralPath $RemoteTemplateDir -Destination $RemoteExportCopy -Recurse
}

function Wait-ForNonEmptyFile {
    param(
        [string]$Path,
        [int]$Attempts = 150,
        [int]$DelayMs = 200
    )

    for ($i = 0; $i -lt $Attempts; $i += 1) {
        if (Test-Path -LiteralPath $Path) {
            $item = Get-Item -LiteralPath $Path
            if ($item.Length -gt 0) {
                return $true
            }
        }
        Start-Sleep -Milliseconds $DelayMs
    }
    return $false
}

function Invoke-LinuxWorker {
    param([hashtable]$HelperEnv)

    $linuxMount = "/tmp/$RunName/mountpoint"
    $runnerMode = if ($env:SPIDER_E2E_LINUX_WORKER_RUNNER) { $env:SPIDER_E2E_LINUX_WORKER_RUNNER } else { "auto" }
    $useCodex = $runnerMode -eq "codex" -or ($runnerMode -eq "auto" -and (Test-WslCommand -Name "codex"))

    $artifactDirWsl = ConvertTo-WslPath $ArtifactDir
    $logDirWsl = ConvertTo-WslPath $LogDir
    $runnerWsl = ConvertTo-WslPath $RelayRunner
    $promptWsl = ConvertTo-WslPath $LinuxWorkerPrompt
    $lastWsl = ConvertTo-WslPath $LinuxWorkerLast
    $jsonlWsl = ConvertTo-WslPath $LinuxWorkerJsonl
    $stderrWsl = ConvertTo-WslPath $LinuxWorkerStderr

    if ($useCodex) {
        Write-Info "Running Linux worker Codex in WSL ..."
        $cmd = @"
set -euo pipefail
mkdir -p $(ConvertTo-BashSingleQuoted $artifactDirWsl) $(ConvertTo-BashSingleQuoted $logDirWsl)
cat $(ConvertTo-BashSingleQuoted $promptWsl) | \
codex exec \
  --json \
  --skip-git-repo-check \
  --dangerously-bypass-approvals-and-sandbox \
  --ephemeral \
  --color never \
  --add-dir $(ConvertTo-BashSingleQuoted $artifactDirWsl) \
  -C $(ConvertTo-BashSingleQuoted $linuxMount) \
  -o $(ConvertTo-BashSingleQuoted $lastWsl) \
  - \
  >$(ConvertTo-BashSingleQuoted $jsonlWsl) \
  2>$(ConvertTo-BashSingleQuoted $stderrWsl)
"@
        Invoke-WslBash -Command $cmd -Environment $HelperEnv
        return
    }

    Write-Info "Running Linux worker fallback runner in WSL ..."
    $cmd = @"
set -euo pipefail
mkdir -p $(ConvertTo-BashSingleQuoted $artifactDirWsl) $(ConvertTo-BashSingleQuoted $logDirWsl)
python3 $(ConvertTo-BashSingleQuoted $runnerWsl) \
  --mode worker \
  --root $(ConvertTo-BashSingleQuoted ($linuxMount + "/remote")) \
  --worker-platform linux \
  --remote-bind-path $(ConvertTo-BashSingleQuoted $RemoteBindPath) \
  --output-last-message $(ConvertTo-BashSingleQuoted $lastWsl) \
  >$(ConvertTo-BashSingleQuoted $jsonlWsl) \
  2>$(ConvertTo-BashSingleQuoted $stderrWsl)
"@
    Invoke-WslBash -Command $cmd -Environment $HelperEnv
}

function Invoke-WindowsReviewer {
    $runnerMode = if ($env:SPIDER_E2E_WINDOWS_REVIEWER_RUNNER) { $env:SPIDER_E2E_WINDOWS_REVIEWER_RUNNER } else { "auto" }
    $hasCodex = $null -ne (Get-Command codex -ErrorAction SilentlyContinue)
    $useCodex = $runnerMode -eq "codex" -or ($runnerMode -eq "auto" -and $hasCodex)

    if ($useCodex) {
        Write-Info "Running Windows reviewer Codex ..."
        $cmdLine = 'type "{0}" | codex exec --json --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox --ephemeral --color never --add-dir "{1}" -C "{2}" -o "{3}" - 1>"{4}" 2>"{5}"' -f `
            $WindowsReviewerPrompt, `
            $ArtifactDir, `
            $RemoteExportCopy, `
            $WindowsReviewerLast, `
            $WindowsReviewerJsonl, `
            $WindowsReviewerStderr
        & cmd.exe /d /c $cmdLine
        if ($LASTEXITCODE -ne 0) {
            throw "Windows reviewer Codex failed"
        }
        return
    }

    Write-Info "Running Windows reviewer fallback runner ..."
    & python $RelayRunner `
        --mode reviewer `
        --root $RemoteExportCopy `
        --reviewer-platform windows `
        --output-last-message $WindowsReviewerLast `
        >$WindowsReviewerJsonl 2>$WindowsReviewerStderr
    if ($LASTEXITCODE -ne 0) {
        throw "Windows reviewer fallback runner failed"
    }
}

try {
    if ($env:OS -ne "Windows_NT") {
        throw "the Windows parity lane must run on Windows"
    }

    Require-Command "wsl"
    Require-Command "python"
    Require-Command "zig"

    New-Item -ItemType Directory -Force -Path $OutputDir, $LogDir, $StateDir, $ArtifactDir, $BuildDir | Out-Null
    Copy-RemoteTemplate

    $wslIp = Get-WslPrimaryIp
    $windowsHostIp = Get-WindowsSourceIpForTarget $wslIp

    Write-Info "Building Windows SpiderNode binary into isolated prefix ..."
    Push-Location (Join-Path $RootDir "SpiderNode")
    try {
        & zig build `
            --prefix $SpiderNodePrefix `
            --cache-dir $SpiderNodeLocalCache `
            --global-cache-dir $SpiderNodeGlobalCache
        if ($LASTEXITCODE -ne 0) {
            throw "zig build failed for Windows SpiderNode"
        }
    } finally {
        Pop-Location
    }
    $LocalNodeBin = Resolve-BuiltBinary -PrefixDir $SpiderNodePrefix -BaseName "spiderweb-fs-node"

    $helperEnv = @{
        RUN_DIR_REL = $RunDirRel
        SPIDERWEB_HOST_IP = $wslIp
        SPIDERWEB_PORT = $SpiderwebPort
        LOCAL_WORKSPACE_NODE_PORT = $LocalWorkspaceNodePort
        REMOTE_NODE_NAME = $RemoteNodeName
        REMOTE_EXPORT_NAME = $RemoteExportName
        REMOTE_BIND_PATH = $RemoteBindPath
    }
    $script:HelperEnv = $helperEnv

    Write-Info "Building Linux Spiderweb/SpiderNode side in WSL ..."
    Invoke-WslHelper -Action "build" -Environment $helperEnv

    Write-Info "Starting Linux Spiderweb host stack in WSL ..."
    Invoke-WslHelper -Action "start_host_stack" -Environment $helperEnv

    $handoffFile = Join-Path $ArtifactDir "control_handoff.json"
    if (-not (Wait-ForFile -Path $handoffFile)) {
        throw "Linux host stack did not write a handoff file"
    }

    $controlUrl = Read-JsonField -Path $handoffFile -Field "control_url"
    $controlAuthToken = Read-JsonField -Path $handoffFile -Field "control_auth_token"
    $remoteInviteToken = Read-JsonField -Path $handoffFile -Field "remote_invite_token"
    if (-not $controlUrl -or -not $controlAuthToken -or -not $remoteInviteToken) {
        throw "handoff file is missing required control credentials"
    }

    Write-Info "Starting Windows remote export node on $windowsHostIp`:$RemoteNodePort ..."
    $nodeArgs = @(
        "--bind", $windowsHostIp,
        "--port", $RemoteNodePort,
        "--export", ("{0}={1}:rw" -f $RemoteExportName, $RemoteExportCopy),
        "--control-url", $controlUrl,
        "--control-auth-token", $controlAuthToken,
        "--pair-mode", "invite",
        "--invite-token", $remoteInviteToken,
        "--node-name", $RemoteNodeName,
        "--state-file", (Join-Path $StateDir "windows-remote-node-state.json")
    )
    $LocalRemoteNode = Start-LoggedProcess `
        -FilePath $LocalNodeBin `
        -ArgumentList $nodeArgs `
        -StdoutPath $LocalRemoteNodeLog `
        -StderrPath $LocalRemoteNodeErrLog `
        -WorkingDirectory $RootDir

    Write-Info "Preparing mounted workspace in WSL ..."
    Invoke-WslHelper -Action "finish_scenario" -Environment $helperEnv

    Invoke-LinuxWorker -HelperEnv $helperEnv
    $workerReport = Join-Path $RemoteExportCopy "worker_report.md"
    $workerSummary = Join-Path $RemoteExportCopy "worker_summary.json"
    if (-not (Wait-ForNonEmptyFile -Path $workerReport) -or -not (Wait-ForNonEmptyFile -Path $workerSummary)) {
        throw "Linux worker did not produce the expected remote outputs"
    }
    Write-Pass "Linux worker wrote results through Spiderweb into the remote export"

    Invoke-WindowsReviewer
    $reviewFile = Join-Path $RemoteExportCopy "review.md"
    $reviewSummary = Join-Path $RemoteExportCopy "review_summary.json"
    if (-not (Wait-ForNonEmptyFile -Path $reviewFile) -or -not (Wait-ForNonEmptyFile -Path $reviewSummary)) {
        throw "Windows reviewer did not produce the expected review outputs"
    }

    Write-Info "Validating cross-platform relay outputs ..."
    & python $Validator `
        --remote-root $RemoteExportCopy `
        --reviewer-platform windows `
        --output $RelayValidationJson
    if ($LASTEXITCODE -ne 0) {
        throw "relay validation failed"
    }

    Write-Pass "Cross-platform agent relay smoke completed"
    Write-Info "Artifacts:"
    Write-Host "  $handoffFile"
    Write-Host "  $(Join-Path $ArtifactDir 'workspace_result.json')"
    Write-Host "  $(Join-Path $ArtifactDir 'remote_smoke_result.json')"
    Write-Host "  $RelayValidationJson"
    Write-Host "  $LinuxWorkerLast"
    Write-Host "  $WindowsReviewerLast"
} finally {
    Cleanup
}
