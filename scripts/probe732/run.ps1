#!/usr/bin/env pwsh
# GitHub Actions probe for version-fox/vfox#732 on windows-latest.
# Scratch branch only; scripts/e2e-test.ps1 calls this file.
#
# It builds vfox from the checked-out source, installs the java plugin and two
# Temurin JDKs, then reproduces the report: a global `vfox use -g java@11`,
# a new shell that carries the machine PATH (with the image's JDK 17) followed
# by the user PATH, and a session `vfox use java@21`. The default path.mode
# (baseline) must make `java` report 21; switching to legacy must bring the
# system 17 back, which shows the probe catches the bug.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$bash = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
$pwshExe = (Get-Process -Id $PID).Path
$work = 'C:\probe732'
$dl = Join-Path $work 'dl'
$vfox = Join-Path $work 'vfox.exe'
$pluginZip = Join-Path $dl 'vfox-java-0.6.6.zip'
$pluginSha = 'e97be71f03509fe04bdc1f0929e168d68fd4255ab4e02b5122c1d3bbc702f2a3'
$upstreamMain = '1446db12dc9cfa8a2080d0d286c07279f592783b'
$primaryFailures = New-Object System.Collections.Generic.List[string]

New-Item -ItemType Directory -Force $work, $dl | Out-Null

# The e2e job sets VFOX_HOME to a directory on D:; a user's plugin and cache
# live in the default user root.
Remove-Item Env:VFOX_HOME -ErrorAction SilentlyContinue

function Section([string]$title) {
    Write-Host ''
    Write-Host ('=' * 100)
    Write-Host "##### $title"
    Write-Host ('=' * 100)
}

function Use-RegistryEnv {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$m;$u;$work"
    $jh = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User')
    if (-not $jh) { $jh = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine') }
    if ($jh) { $env:JAVA_HOME = $jh } else { Remove-Item Env:JAVA_HOME -ErrorAction SilentlyContinue }
    foreach ($n in '__VFOX_SHELL', '__VFOX_PID', '__VFOX_CURTMPPATH', '__VFOX_INITIALIZED', '__VFOX_ORIG_PATH') {
        Remove-Item "env:$n" -ErrorAction SilentlyContinue
    }
}

function Reset-ProcessEnv([string]$basePath, [string]$baseJavaHome) {
    $env:Path = $basePath
    if ($baseJavaHome) { $env:JAVA_HOME = $baseJavaHome } else { Remove-Item Env:JAVA_HOME -ErrorAction SilentlyContinue }
    foreach ($n in '__VFOX_SHELL', '__VFOX_PID', '__VFOX_CURTMPPATH', '__VFOX_INITIALIZED', '__VFOX_ORIG_PATH') {
        Remove-Item "env:$n" -ErrorAction SilentlyContinue
    }
}

function Record([string]$name, [bool]$ok) {
    if ($ok) {
        Write-Host "PROBE SUMMARY: PASS - $name"
    } else {
        Write-Host "PROBE SUMMARY: FAIL - $name"
        $script:primaryFailures.Add($name)
    }
}

function Bash([string]$script, [string[]]$scriptArgs = @()) {
    & $bash --login "$PSScriptRoot\$script" @scriptArgs
    return $LASTEXITCODE
}

# Windows checkouts may turn LF into CRLF; bash would then choke on the scripts.
Get-ChildItem $PSScriptRoot -Filter *.sh | ForEach-Object {
    $t = [IO.File]::ReadAllText($_.FullName)
    if ($t.Contains("`r`n")) {
        [IO.File]::WriteAllText($_.FullName, $t.Replace("`r`n", "`n"))
        Write-Host "normalized line endings: $($_.Name)"
    }
}

Section 'runner'
[Environment]::OSVersion.VersionString
& $bash --version | Select-Object -First 1
Write-Host "USERPROFILE=$env:USERPROFILE"
Write-Host "JAVA_HOME=$env:JAVA_HOME"
Write-Host "JAVA_HOME_11_X64=$env:JAVA_HOME_11_X64"
Write-Host "JAVA_HOME_17_X64=$env:JAVA_HOME_17_X64"
Write-Host "JAVA_HOME_21_X64=$env:JAVA_HOME_21_X64"
Write-Host 'Machine PATH entries that mention java:'
([Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';') | Where-Object { $_ -match 'java|jdk|temurin|hostedtoolcache' }
Write-Host 'User PATH entries that mention java:'
([Environment]::GetEnvironmentVariable('Path', 'User') -split ';') | Where-Object { $_ -match 'java|jdk|temurin|hostedtoolcache|vfox' }

Section 'source under test'
Push-Location $repo
& git rev-parse HEAD
& git log -1 --format='%H %s'
Write-Host "go source changes against $upstreamMain (should be empty):"
& git diff --stat $upstreamMain -- '*.go' 'go.mod' 'go.sum'
Pop-Location

$basePath = $env:Path
$baseJavaHome = $env:JAVA_HOME
$saved = @{}
foreach ($n in 'Path', 'JAVA_HOME', 'VERSION_FOX_PATH') {
    $saved[$n] = [Environment]::GetEnvironmentVariable($n, 'User')
}

try {
    Section 'build vfox from the checked-out source'
    Push-Location $repo
    & go build -o $vfox .
    $buildExit = $LASTEXITCODE
    Pop-Location
    if ($buildExit -ne 0) { throw "go build failed with exit $buildExit" }
    & $vfox --version
    Write-Host "path.mode out of the box: $(& $vfox config path.mode)"

    Section 'install the java plugin and Temurin 11 and 21'
    if (-not (Test-Path $pluginZip)) {
        Invoke-WebRequest -Uri 'https://github.com/version-fox/vfox-java/releases/download/v0.6.6/vfox-java-0.6.6.zip' -OutFile $pluginZip
    }
    $actual = (Get-FileHash $pluginZip -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $pluginSha) { throw "plugin checksum mismatch: $actual vs $pluginSha" }
    & $vfox add --source $pluginZip java
    if ($LASTEXITCODE -ne 0) { throw 'vfox add java failed' }
    foreach ($v in '11', '21') {
        & $vfox install "java@$v-tem"
        if ($LASTEXITCODE -ne 0) { throw "vfox install java@$v-tem failed" }
    }
    & $vfox list java

    Section 'system java in a new shell (registry PATH)'
    Use-RegistryEnv
    $sysLine = (& $bash --login -c 'java -version 2>&1 | head -1' | Select-Object -First 1)
    Write-Host "system java: $sysLine"
    $sysMajor = if ($sysLine -match '"([0-9]+)') { $matches[1] } else { '17' }
    Write-Host "system java major: $sysMajor"
    Reset-ProcessEnv $basePath $baseJavaHome

    Section 'default mode: vfox use -g java@11'
    Use-RegistryEnv
    $rc = Bash 'global.sh' @('11')
    Write-Host "[global.sh exit code: $rc]"
    if ($rc -ne 0) { Record 'global choice in a new bash (java 11)' $false } else { Record 'global choice in a new bash (java 11)' $true }

    Section 'default mode: new bash, global 11, then session use java@21'
    Use-RegistryEnv
    $rc = Bash 'session.sh' @('21', '11')
    Write-Host "[session.sh exit code: $rc]"
    if ($rc -ne 0) { Record 'session java@21 on top of global 11 in bash' $false } else { Record 'session java@21 on top of global 11 in bash' $true }

    Section 'default mode: new pwsh, global 11, then session use java@21'
    Use-RegistryEnv
    & $pwshExe -NoProfile -File "$PSScriptRoot\probe-pwsh.ps1" 21 11
    $rc = $LASTEXITCODE
    Write-Host "[probe-pwsh.ps1 exit code: $rc]"
    if ($rc -ne 0) { Record 'session java@21 on top of global 11 in pwsh' $false } else { Record 'session java@21 on top of global 11 in pwsh' $true }

    Section 'control: path.mode legacy must fail the same way'
    & $vfox config path.mode legacy
    Use-RegistryEnv
    $rc = Bash 'legacy-session.sh' @('21', $sysMajor)
    Write-Host "[legacy-session.sh exit code: $rc]"
    if ($rc -eq 0) {
        Write-Host "PROBE CONTROL: legacy mode still puts the system java first (java $sysMajor), as reported"
    } else {
        Write-Host "PROBE CONTROL: legacy mode did NOT reproduce the report (expected system java $sysMajor); the probe or the behavior changed"
    }
    & $vfox config --unset path.mode
    Write-Host "path.mode after unset: $(& $vfox config path.mode)"
} finally {
    foreach ($n in $saved.Keys) {
        [Environment]::SetEnvironmentVariable($n, $saved[$n], 'User')
    }
    Reset-ProcessEnv $basePath $baseJavaHome
    Get-Process -Name java -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

Section 'result'
Write-Host "vfox code under test: $upstreamMain"
Write-Host "default path.mode: baseline"
if ($primaryFailures.Count -eq 0) {
    Write-Host 'PROBE RESULT: PASS - #732 does not reproduce on the latest main'
    exit 0
}
Write-Host "PROBE RESULT: FAIL - $($primaryFailures.Count) check(s) failed:"
foreach ($f in $primaryFailures) { Write-Host "  - $f" }
exit 1
