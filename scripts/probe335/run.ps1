# vfox#335 probe driver. Lives on a scratch branch of a fork only; scripts/e2e-test.ps1 calls it.
# 1. control: a Gradle daemon and a JAVA_HOME junction that is re-pointed, no vfox involved
# 2. vfox 0.5.4 + java plugin 0.4.3 (what the reporter ran) under Git Bash
# 3. vfox 1.0.13 + java plugin 0.6.2 (current) under Git Bash
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$probe = $PSScriptRoot
$bash = "$env:ProgramFiles\Git\bin\bash.exe"

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

Section 'runner'
[Environment]::OSVersion.VersionString
& "$env:ProgramFiles\Git\bin\git.exe" --version
& $bash --version | Select-Object -First 1
Write-Host "USERPROFILE=$env:USERPROFILE"
Write-Host "JAVA_HOME=$env:JAVA_HOME"
Write-Host "JAVA_HOME_11_X64=$env:JAVA_HOME_11_X64"
Write-Host "JAVA_HOME_21_X64=$env:JAVA_HOME_21_X64"

Section 'CONTROL: Gradle daemon and a re-pointed junction, no vfox'
try {
    & "$probe\install-gradle.ps1"
    Bash 'gradle-control.sh' @($env:JAVA_HOME_11_X64, $env:JAVA_HOME_21_X64)
} catch {
    Write-Host "control failed: $_"
}

function Run-Flavor([string]$Vfox, [string]$PluginTag, [string]$PluginZip, [string]$PluginSha256) {
    Section "FLAVOR: vfox $Vfox + java plugin $PluginTag"
    # vfox's global `use` writes these user-level variables; put them back afterwards.
    $saved = @{}
    foreach ($n in 'Path', 'JAVA_HOME', 'VERSION_FOX_PATH') { $saved[$n] = [Environment]::GetEnvironmentVariable($n, 'User') }
    try {
        & "$probe\install-vfox.ps1" -Version $Vfox -PluginTag $PluginTag -PluginZip $PluginZip -PluginSha256 $PluginSha256
        if (-not $?) { throw 'install-vfox.ps1 failed' }
        $env:Path = "C:\probe\vfox-$Vfox;$basePath"
        $env:JAVA_HOME = $baseJavaHome

        Bash 'install-jdks.sh' @($PluginZip)

        Section "vfox $Vfox, scenario S: session scope in a fresh Git Bash"
        Bash 'probe-session.sh' @('11', '21')

        Section "vfox $Vfox, scenario G part 1: vfox use -g java@11"
        Bash 'probe-global-1.sh' @('11')

        Section "vfox $Vfox, scenario G part 2: a new Git Bash that carries the global choice, then session java@21"
        Write-Host 'user-level environment in the registry after the global use:'
        Get-ItemProperty HKCU:\Environment | Select-Object Path, JAVA_HOME, VERSION_FOX_PATH | Format-List | Out-String -Width 4000
        # What a newly opened Git Bash gets from Explorer: Machine then User values (vfox.exe is not in them).
        $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $u = [Environment]::GetEnvironmentVariable('Path', 'User')
        $env:Path = "$m;$u;C:\probe\vfox-$Vfox"
        $jh = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User')
        if (-not $jh) { $jh = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine') }
        $env:JAVA_HOME = $jh
        foreach ($n in '__VFOX_SHELL', '__VFOX_PID', '__VFOX_CURTMPPATH') { Remove-Item "env:$n" -ErrorAction SilentlyContinue }
        Bash 'probe-global-2.sh' @('21')
    } catch {
        Write-Host "flavor $Vfox failed: $_"
    } finally {
        foreach ($n in $saved.Keys) { [Environment]::SetEnvironmentVariable($n, $saved[$n], 'User') }
        $env:Path = $basePath
        $env:JAVA_HOME = $baseJavaHome
        Get-Process -Name java -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

Run-Flavor '0.5.4' 'v0.4.3' 'vfox-java-0.4.3.zip' 'a9007600ecf40d6a0c08f1f519e8a55f6b214afe87c6398995323bb68d697dfa'
Run-Flavor '1.0.13' 'v0.6.2' 'vfox-java-0.6.2.zip' 'ce352b2eb78478b66858b9b0b731ccb0968b48704a5d1735e989c84fb2b20d84'

Section 'PROBE FINISHED'
exit 0
