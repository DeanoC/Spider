$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$script:E2EDir = $PSScriptRoot
$script:RepoRoot = Split-Path -Parent $PSScriptRoot

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Pass {
    param([string]$Message)
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

function Require-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "missing required command: $Name"
    }
}

function New-RunDirectory {
    param([string]$Prefix)
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    return Join-Path $script:RepoRoot ("e2e/out/{0}-{1}-{2}" -f $Prefix, $stamp, $PID)
}

function Ensure-RunDirectoryUnderRepo {
    param([string]$Path)

    $repo = [System.IO.Path]::GetFullPath($script:RepoRoot).TrimEnd("\")
    $full = [System.IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($repo + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "OUTPUT_DIR must live under $repo so WSL can access the shared checkout"
    }
    return $full
}

function Get-RunDirectoryRelative {
    param([string]$Path)

    $repo = [System.IO.Path]::GetFullPath($script:RepoRoot).TrimEnd("\")
    $full = [System.IO.Path]::GetFullPath($Path)
    return $full.Substring($repo.Length + 1).Replace("\", "/")
}

function Wait-ForFile {
    param(
        [string]$Path,
        [int]$Attempts = 180,
        [int]$DelayMs = 200
    )

    for ($i = 0; $i -lt $Attempts; $i += 1) {
        if (Test-Path -LiteralPath $Path) {
            return $true
        }
        Start-Sleep -Milliseconds $DelayMs
    }
    return $false
}

function Read-JsonField {
    param(
        [string]$Path,
        [string]$Field
    )

    $payload = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $value = $payload.$Field
    if ($null -eq $value) {
        return ""
    }
    return [string]$value
}

function ConvertTo-BashSingleQuoted {
    param([string]$Text)
    return "'" + $Text.Replace("'", "'""'""'") + "'"
}

function Get-WslDistro {
    if ($env:SPIDER_WSL_DISTRO) {
        return $env:SPIDER_WSL_DISTRO
    }

    $raw = & wsl.exe -l -q 2>$null
    $names = @()
    foreach ($line in $raw) {
        $clean = ($line -replace "`0", "").Trim()
        if ($clean.Length -gt 0) {
            $names += $clean
        }
    }
    if ($names.Count -eq 0) {
        throw "no WSL distro found"
    }
    return $names[0]
}

function Get-WslRepoRoot {
    $resolved = (Resolve-Path -LiteralPath $script:RepoRoot).Path
    $normalized = $resolved.Replace("\", "/")
    $path = (& wsl.exe wslpath -a $normalized).Trim()
    if (-not $path) {
        throw "failed to resolve WSL path for $resolved"
    }
    return $path
}

function ConvertTo-WslPath {
    param([string]$WindowsPath)
    $resolved = [System.IO.Path]::GetFullPath($WindowsPath)
    $normalized = $resolved.Replace("\", "/")
    $path = (& wsl.exe wslpath -a $normalized).Trim()
    if (-not $path) {
        throw "failed to resolve WSL path for $resolved"
    }
    return $path
}

function Invoke-WslBash {
    param(
        [string]$Command,
        [hashtable]$Environment = @{}
    )

    $wslDistro = Get-WslDistro
    $wslRoot = Get-WslRepoRoot
    $envPrefix = ""
    if ($Environment.Count -gt 0) {
        $pairs = foreach ($entry in $Environment.GetEnumerator() | Sort-Object Name) {
            "export {0}={1}" -f $entry.Key, (ConvertTo-BashSingleQuoted ([string]$entry.Value))
        }
        $envPrefix = ($pairs -join "; ") + "; "
    }

    $fullCommand = "cd {0} && {1}{2}" -f (ConvertTo-BashSingleQuoted $wslRoot), $envPrefix, $Command
    & wsl.exe -d $wslDistro bash -lc $fullCommand
    if ($LASTEXITCODE -ne 0) {
        throw "WSL command failed: $Command"
    }
}

function Invoke-WslHelper {
    param(
        [string]$Action,
        [hashtable]$Environment = @{}
    )

    $wslDistro = Get-WslDistro
    $wslRoot = Get-WslRepoRoot
    $helper = "{0}/e2e/run_linux_spiderweb_host.sh" -f $wslRoot
    $tempScript = "/tmp/spider-e2e-{0}-{1}-{2}.sh" -f $PID, (Get-Date -Format "yyyyMMddHHmmssfff"), $Action
    $command = "rm -f {2}; tr -d '\r' < {0} > {2}; chmod +x {2}; bash {2} {1}" -f `
        (ConvertTo-BashSingleQuoted $helper), `
        (ConvertTo-BashSingleQuoted $Action), `
        (ConvertTo-BashSingleQuoted $tempScript)
    $helperEnvironment = @{}
    foreach ($entry in $Environment.GetEnumerator()) {
        $helperEnvironment[$entry.Key] = [string]$entry.Value
    }
    if (-not $helperEnvironment.ContainsKey("SPIDER_E2E_ROOT_DIR")) {
        $helperEnvironment["SPIDER_E2E_ROOT_DIR"] = $wslRoot
    }

    try {
        Invoke-WslBash -Command $command -Environment $helperEnvironment
    } finally {
        & wsl.exe -d $wslDistro rm -f $tempScript *> $null
    }
}

function Test-WslCommand {
    param([string]$Name)
    & wsl.exe sh -lc ("command -v {0} >/dev/null 2>&1" -f $Name)
    return $LASTEXITCODE -eq 0
}

function Get-WslPrimaryIp {
    $raw = (& wsl.exe hostname -I).Trim()
    if (-not $raw) {
        throw "failed to determine WSL IP"
    }
    $parts = $raw -split "\s+"
    return $parts[0]
}

function Get-WindowsSourceIpForTarget {
    param([string]$TargetIp)

    $client = New-Object System.Net.Sockets.UdpClient
    try {
        $client.Connect($TargetIp, 80)
        return $client.Client.LocalEndPoint.Address.ToString()
    } finally {
        $client.Dispose()
    }
}

function Resolve-BuiltBinary {
    param(
        [string]$PrefixDir,
        [string]$BaseName
    )

    $candidates = @(
        (Join-Path $PrefixDir ("bin\{0}.exe" -f $BaseName)),
        (Join-Path $PrefixDir ("bin\{0}" -f $BaseName))
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    throw "missing built binary for $BaseName under $PrefixDir"
}

function Start-LoggedProcess {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$StdoutPath,
        [string]$StderrPath,
        [string]$WorkingDirectory
    )

    return Start-Process `
        -FilePath $FilePath `
        -ArgumentList $ArgumentList `
        -WorkingDirectory $WorkingDirectory `
        -NoNewWindow `
        -PassThru `
        -RedirectStandardOutput $StdoutPath `
        -RedirectStandardError $StderrPath
}
