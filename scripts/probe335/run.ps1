# vfox#335 probe driver, run 2. Lives on a scratch branch of a fork only; scripts/e2e-test.ps1 calls it.
# 1. control: a Gradle daemon and a JAVA_HOME junction that is re-pointed, no vfox involved
# 2. vfox 1.0.13 + java plugin 0.6.2 (current) under Git Bash and PowerShell; it runs first because 1.0.x keeps using an
#    existing ~/.version-fox, which the 0.5.4 run below creates
# 3. vfox 0.5.4 + java plugin 0.4.3 (what the reporter ran) under Git Bash
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$probe = $PSScriptRoot
$bash = "$env:ProgramFiles\Git\bin\bash.exe"
$pwshExe = (Get-Process -Id $PID).Path

function Section([string]$title) {
    Write-Host ''
    Write-Host ('=' * 100)
    Write-Host "##### $title"
    Write-Host ('=' * 100)
}

function Bash([string]$script, [string[]]$scriptArgs = @()) {
    & $bash --login "$probe\$script" @scriptArgs
    Write-Host "[$script exit code: $LASTEXITCODE]"
}

function Pwsh7([string]$script, [string[]]$scriptArgs = @()) {
    & $pwshExe -NoProfile -File "$probe\$script" @scriptArgs
    Write-Host "[$script exit code: $LASTEXITCODE]"
}

# Windows checkouts may turn LF into CRLF; bash would then choke on the scripts.
Get-ChildItem $probe -Filter *.sh | ForEach-Object {
    $t = [IO.File]::ReadAllText($_.FullName)
    if ($t.Contains("`r`n")) {
        [IO.File]::WriteAllText($_.FullName, $t.Replace("`r`n", "`n"))
        Write-Host "normalized line endings: $($_.Name)"
    }
}

# The e2e job sets VFOX_HOME to a folder on D:; a user has the default home on C:.
Remove-Item Env:VFOX_HOME -ErrorAction SilentlyContinue
$env:CHERE_INVOKING = '1'
$env:GRADLE = '/c/probe/gradle/gradle-8.9/bin/gradle'
$env:GRADLE_PROJECT = '/c/probe/gp'
$basePath = $env:Path
$baseJavaHome = $env:JAVA_HOME

# What a newly opened shell gets from Explorer: the Machine PATH, then the User PATH (and the user-level JAVA_HOME).
function Use-RegistryEnv([string]$VfoxDir) {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$m;$u;$VfoxDir"
    $jh = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User')
    if (-not $jh) { $jh = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine') }
    $env:JAVA_HOME = $jh
    foreach ($n in '__VFOX_SHELL', '__VFOX_PID', '__VFOX_CURTMPPATH', '__VFOX_INITIALIZED') { Remove-Item "env:$n" -ErrorAction SilentlyContinue }
}

function Reset-ProcessEnv {
    $env:Path = $basePath
    $env:JAVA_HOME = $baseJavaHome
    foreach ($n in '__VFOX_SHELL', '__VFOX_PID', '__VFOX_CURTMPPATH', '__VFOX_INITIALIZED') { Remove-Item "env:$n" -ErrorAction SilentlyContinue }
}

function Show-Registry([string]$why) {
    Write-Host "user-level environment in the registry ($why):"
    Get-ItemProperty HKCU:\Environment | Select-Object Path, JAVA_HOME, VERSION_FOX_PATH | Format-List | Out-String -Width 4000
}

Section 'runner'
[Environment]::OSVersion.VersionString
& $bash --version | Select-Object -First 1
Write-Host "USERPROFILE=$env:USERPROFILE"
Write-Host "JAVA_HOME=$env:JAVA_HOME"
Write-Host "JAVA_HOME_11_X64=$env:JAVA_HOME_11_X64"
Write-Host "JAVA_HOME_21_X64=$env:JAVA_HOME_21_X64"
Write-Host 'Machine PATH entries that mention java:'
([Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';') | Where-Object { $_ -match 'java|jdk|temurin|hostedtoolcache' }
Write-Host 'User PATH entries that mention java:'
([Environment]::GetEnvironmentVariable('Path', 'User') -split ';') | Where-Object { $_ -match 'java|jdk|temurin|hostedtoolcache' }

Section 'CONTROL: Gradle daemon and a re-pointed junction, no vfox'
try {
    & "$probe\install-gradle.ps1"
    Bash 'gradle-control.sh' @($env:JAVA_HOME_11_X64, $env:JAVA_HOME_21_X64)
} catch {
    Write-Host "control failed: $_"
}

function Run-Flavor13 {
    $Vfox = '1.0.13'
    Section "FLAVOR: vfox $Vfox + java plugin v0.6.2"
    $saved = @{}
    foreach ($n in 'Path', 'JAVA_HOME', 'VERSION_FOX_PATH') { $saved[$n] = [Environment]::GetEnvironmentVariable($n, 'User') }
    $vdir = "C:\probe\vfox-$Vfox"
    try {
        & "$probe\install-vfox.ps1" -Version $Vfox -PluginTag 'v0.6.2' -PluginZip 'vfox-java-0.6.2.zip' -PluginSha256 'ce352b2eb78478b66858b9b0b731ccb0968b48704a5d1735e989c84fb2b20d84'
        if (-not $?) { throw 'install-vfox.ps1 failed' }
        $env:Path = "$vdir;$basePath"
        Bash 'install-jdks.sh' @('vfox-java-0.6.2.zip')

        Section "vfox $Vfox, scenario S: session scope in a fresh Git Bash, nothing vfox-related in the incoming PATH"
        Bash 'probe-session.sh' @('11', '21')

        Section "vfox $Vfox, scenario G part 1: vfox use -g java@11"
        Bash 'probe-global-1.sh' @('11')
        Show-Registry 'after the global use'

        Section "vfox $Vfox, scenario G part 2: a new Git Bash that carries the global choice, then session java@21"
        Use-RegistryEnv $vdir
        Bash 'probe-global-2.sh' @('21')

        Section "vfox $Vfox, scenario G part 3: the same, but .bashrc first drops vfox entries from PATH"
        Use-RegistryEnv $vdir
        Bash 'probe-global-3.sh' @('21')

        Section "vfox $Vfox, scenario P: the same in PowerShell 7"
        Use-RegistryEnv $vdir
        Pwsh7 'probe-global-pwsh.ps1' @('21')

        Section "vfox $Vfox, reset: drop the global java and the registry entries"
        Reset-ProcessEnv
        $env:Path = "$vdir;$basePath"
        Bash 'probe-unuse.sh'
        foreach ($n in $saved.Keys) { [Environment]::SetEnvironmentVariable($n, $saved[$n], 'User') }
        Show-Registry 'restored to the baseline'

        Section "vfox $Vfox, scenario X: no global java, only an unrelated vfox directory in the Windows PATH"
        [Environment]::SetEnvironmentVariable('Path', "C:\Users\runneradmin\.vfox\sdks\nodejs\bin;$($saved['Path'])", 'User')
        Show-Registry 'with an unrelated vfox directory in the User PATH'
        Use-RegistryEnv $vdir
        Bash 'probe-fakedir.sh' @('21')
    } catch {
        Write-Host "flavor $Vfox failed: $_"
    } finally {
        foreach ($n in $saved.Keys) { [Environment]::SetEnvironmentVariable($n, $saved[$n], 'User') }
        Reset-ProcessEnv
        Get-Process -Name java -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

function Run-Flavor054 {
    $Vfox = '0.5.4'
    Section "FLAVOR: vfox $Vfox + java plugin v0.4.3"
    $saved = @{}
    foreach ($n in 'Path', 'JAVA_HOME', 'VERSION_FOX_PATH') { $saved[$n] = [Environment]::GetEnvironmentVariable($n, 'User') }
    $vdir = "C:\probe\vfox-$Vfox"
    try {
        & "$probe\install-vfox.ps1" -Version $Vfox -PluginTag 'v0.4.3' -PluginZip 'vfox-java-0.4.3.zip' -PluginSha256 'a9007600ecf40d6a0c08f1f519e8a55f6b214afe87c6398995323bb68d697dfa'
        if (-not $?) { throw 'install-vfox.ps1 failed' }
        $env:Path = "$vdir;$basePath"
        Bash 'install-jdks.sh' @('vfox-java-0.4.3.zip')

        Section "vfox $Vfox, scenario S: session scope in a fresh Git Bash"
        Bash 'probe-session.sh' @('11', '21')

        Section "vfox $Vfox, scenario G part 1: vfox use -g java@11"
        Bash 'probe-global-1.sh' @('11')
        Show-Registry 'after the global use'

        Section "vfox $Vfox, scenario G part 2: a new Git Bash that carries the global choice, then session java@21"
        Use-RegistryEnv $vdir
        Bash 'probe-global-2.sh' @('21')
    } catch {
        Write-Host "flavor $Vfox failed: $_"
    } finally {
        foreach ($n in $saved.Keys) { [Environment]::SetEnvironmentVariable($n, $saved[$n], 'User') }
        Reset-ProcessEnv
        Get-Process -Name java -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

Run-Flavor13
Run-Flavor054

Section 'PROBE FINISHED'
exit 0
