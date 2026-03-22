$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "windows-e2e-common.ps1")

$RootDir = $script:RepoRoot
$RemoteFixtureDir = Join-Path $RootDir "e2e/fixtures/remote-smoke"
$LinuxHelper = Join-Path $RootDir "e2e/run_linux_spiderweb_host.sh"

$OutputDir = if ($env:OUTPUT_DIR) { $env:OUTPUT_DIR } else { New-RunDirectory "cross-platform-node-workspace-windows" }
$OutputDir = Ensure-RunDirectoryUnderRepo $OutputDir
$RunDirRel = Get-RunDirectoryRelative $OutputDir
$LogDir = Join-Path $OutputDir "logs"
$StateDir = Join-Path $OutputDir "state"
$ArtifactDir = Join-Path $OutputDir "artifacts"
$BuildDir = Join-Path $OutputDir "build/windows"

$SpiderNodePrefix = Join-Path $BuildDir "spidernode-prefix"
$SpiderNodeLocalCache = Join-Path $BuildDir "spidernode-local-cache"
$SpiderNodeGlobalCache = Join-Path $BuildDir "spidernode-global-cache"
$LocalNodeBin = $null

$SpiderwebPort = if ($env:SPIDERWEB_PORT) { $env:SPIDERWEB_PORT } else { "28790" }
$LocalWorkspaceNodePort = if ($env:LOCAL_WORKSPACE_NODE_PORT) { $env:LOCAL_WORKSPACE_NODE_PORT } else { "28911" }
$RemoteNodePort = if ($env:REMOTE_NODE_PORT) { $env:REMOTE_NODE_PORT } else { "28912" }
$RemoteNodeName = if ($env:REMOTE_NODE_NAME) { $env:REMOTE_NODE_NAME } else { "cross-windows-remote-node" }
$RemoteExportName = if ($env:REMOTE_EXPORT_NAME) { $env:REMOTE_EXPORT_NAME } else { "remote-smoke" }

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

try {
    if ($env:OS -ne "Windows_NT") {
        throw "the Windows parity lane must run on Windows"
    }

    Require-Command "wsl"
    Require-Command "python"
    Require-Command "zig"

    if (-not (Test-Path -LiteralPath (Join-Path $RemoteFixtureDir "run_remote_smoke.py"))) {
        throw "missing remote smoke fixture at $RemoteFixtureDir"
    }

    New-Item -ItemType Directory -Force -Path $OutputDir, $LogDir, $StateDir, $ArtifactDir, $BuildDir | Out-Null

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
        "--export", ("{0}={1}:rw" -f $RemoteExportName, $RemoteFixtureDir),
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

    Write-Info "Finishing cross-platform workspace scenario in WSL ..."
    Invoke-WslHelper -Action "finish_scenario" -Environment $helperEnv

    $resultFile = Join-Path $ArtifactDir "workspace_result.json"
    $remoteSmokeFile = Join-Path $ArtifactDir "remote_smoke_result.json"
    if (-not (Test-Path -LiteralPath $resultFile) -or -not (Test-Path -LiteralPath $remoteSmokeFile)) {
        throw "scenario completed without the expected result artifacts"
    }

    Write-Pass "Cross-platform node workspace smoke completed"
    Write-Info "Artifacts:"
    Write-Host "  $handoffFile"
    Write-Host "  $resultFile"
    Write-Host "  $remoteSmokeFile"
} finally {
    Cleanup
}
