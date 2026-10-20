# vfox#335 probe driver, run 4. Lives on a scratch branch of a fork only; scripts/e2e-test.ps1 calls it.
# The same scenarios as runs 2 and 3, under the Git Bash of the report's time: PortableGit 2.46.0 (2024-07-29), which still
# ships mingw64 and starts as MSYSTEM=MINGW64 (the runner's Git for Windows 2.56 only has ucrt64 and ignores MSYSTEM=MINGW64).
# vfox 1.0.13 + java plugin 0.6.2 runs first because 1.0.x keeps using an existing ~/.version-fox, which the 0.5.4 run creates.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$probe = $PSScriptRoot
$gitBash = "$env:ProgramFiles\Git\bin\bash.exe"

function Section([string]$title) {
    Write-Host ''
    Write-Host ('=' * 100)
    Write-Host "##### $title"
    Write-Host ('=' * 100)
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
Remove-Item Env:GRADLE -ErrorAction SilentlyContinue
Remove-Item Env:GRADLE_PROJECT -ErrorAction SilentlyContinue
$env:CHERE_INVOKING = '1'
$basePath = $env:Path
$baseJavaHome = $env:JAVA_HOME

$default = @{ Name = 'gitbash-default'; Exe = $gitBash; Env = @{}; Cygwin = $false }
$flavours = @(
    @{ Name = 'portablegit-2.46.0-MINGW64'; Exe = 'C:\pgit\bin\bash.exe'; Env = @{ MSYSTEM = 'MINGW64' }; Cygwin = $false }
)

function Invoke-Flavour([hashtable]$fl, [string]$script, [string[]]$scriptArgs = @()) {
    if (-not (Test-Path $fl.Exe)) { Write-Host "[$($fl.Name): $($fl.Exe) is missing, skipped $script]"; return }
    $saved = @{}
    foreach ($k in $fl.Env.Keys) {
        $saved[$k] = [Environment]::GetEnvironmentVariable($k, 'Process')
        [Environment]::SetEnvironmentVariable($k, $fl.Env[$k], 'Process')
    }
    try {
        $path = "$probe\$script"
        if ($fl.Cygwin) { $path = (& 'C:\cygwin64\bin\cygpath.exe' -u $path) }
        & $fl.Exe --login $path @scriptArgs
        Write-Host "[$($fl.Name): $script exit code: $LASTEXITCODE]"
    } finally {
        foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k], 'Process') }
    }
}

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

function Install-Cygwin {
    if (Test-Path 'C:\cygwin64\bin\bash.exe') { return }
    $setup = 'C:\probe\dl\cygwin-setup-x86_64.exe'
    try {
        New-Item -ItemType Directory -Force C:\probe\dl | Out-Null
        Invoke-WebRequest -Uri 'https://www.cygwin.com/setup-x86_64.exe' -OutFile $setup
        Write-Host ('setup-x86_64.exe: ' + (Get-FileHash $setup -Algorithm SHA256).Hash.ToLower() + ', signature ' + (Get-AuthenticodeSignature $setup).Status)
    } catch {
        Write-Host "cygwin: could not download setup: $_"
        return
    }
    foreach ($site in 'https://mirrors.kernel.org/sourceware/cygwin/', 'https://cygwin.mirror.constant.com') {
        $a = @('--quiet-mode', '--no-shortcuts', '--no-startmenu', '--no-desktop', '--only-site', '--site', $site, '--root', 'C:\cygwin64', '--local-package-dir', 'C:\probe\dl\cygwin-pkgs')
        $p = Start-Process -FilePath $setup -ArgumentList $a -Wait -PassThru
        Write-Host "cygwin setup via $site exit code: $($p.ExitCode)"
        if (Test-Path 'C:\cygwin64\bin\bash.exe') { break }
    }
}

Section 'runner'
[Environment]::OSVersion.VersionString
Write-Host "USERPROFILE=$env:USERPROFILE"
Write-Host "JAVA_HOME=$env:JAVA_HOME"
Write-Host ('Git install folders: ' + ((Get-ChildItem $env:ProgramFiles\Git -Directory | Select-Object -ExpandProperty Name) -join ', '))
Write-Host "Git has mingw64: $(Test-Path $env:ProgramFiles\Git\mingw64)   Git has ucrt64: $(Test-Path $env:ProgramFiles\Git\ucrt64)"
Write-Host "C:\msys64 present: $(Test-Path C:\msys64\usr\bin\bash.exe)"
& $gitBash --version | Select-Object -First 1
if (Test-Path C:\msys64\usr\bin\bash.exe) { & C:\msys64\usr\bin\bash.exe --version | Select-Object -First 1 }

Section 'install PortableGit 2.46.0'
function Install-PortableGit {
    if (Test-Path 'C:\pgit\bin\bash.exe') { return }
    $exe = 'C:\probe\dl\PortableGit-2.46.0-64-bit.7z.exe'
    New-Item -ItemType Directory -Force C:\probe\dl | Out-Null
    Invoke-WebRequest -Uri 'https://github.com/git-for-windows/git/releases/download/v2.46.0.windows.1/PortableGit-2.46.0-64-bit.7z.exe' -OutFile $exe
    $actual = (Get-FileHash $exe -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne 'dedae83f4d0851bcbf473c516701e2da6a5d7c574d694d5eceec46d1307132ea') { throw "PortableGit checksum mismatch: $actual" }
    $p = Start-Process -FilePath $exe -ArgumentList '-oC:\pgit', '-y' -Wait -PassThru
    Write-Host "PortableGit extraction exit code: $($p.ExitCode)"
}
try { Install-PortableGit } catch { Write-Host "PortableGit install failed: $_" }
if (Test-Path 'C:\pgit\bin\bash.exe') {
    & 'C:\pgit\bin\bash.exe' --version | Select-Object -First 1
    Write-Host ('PortableGit folders: ' + ((Get-ChildItem C:\pgit -Directory | Select-Object -ExpandProperty Name) -join ', '))
} else { Write-Host 'PortableGit is not available' }

function Run-Version([string]$Vfox, [string]$PluginTag, [string]$PluginZip, [string]$PluginSha256, [bool]$HasUnuse) {
    Section "VERSION: vfox $Vfox + java plugin $PluginTag"
    $saved = @{}
    foreach ($n in 'Path', 'JAVA_HOME', 'VERSION_FOX_PATH') { $saved[$n] = [Environment]::GetEnvironmentVariable($n, 'User') }
    $vdir = "C:\probe\vfox-$Vfox"
    try {
        & "$probe\install-vfox.ps1" -Version $Vfox -PluginTag $PluginTag -PluginZip $PluginZip -PluginSha256 $PluginSha256
        if (-not $?) { throw 'install-vfox.ps1 failed' }
        $env:Path = "$vdir;$basePath"
        Invoke-Flavour $default 'install-jdks.sh' @("C:\probe\dl\$PluginZip")

        foreach ($fl in $flavours) {
            if (-not (Test-Path $fl.Exe)) { Write-Host "skipping $($fl.Name): $($fl.Exe) is missing"; continue }

            Section "$($fl.Name), vfox ${Vfox}, scenario S: session scope, nothing vfox-related in the incoming PATH"
            Reset-ProcessEnv
            $env:Path = "$vdir;$basePath"
            Invoke-Flavour $fl 'probe-session.sh' @('11', '21')

            Section "$($fl.Name), vfox ${Vfox}, scenario G part 1: vfox use -g java@11"
            Invoke-Flavour $fl 'probe-global-1.sh' @('11')
            Show-Registry 'after the global use'

            Section "$($fl.Name), vfox ${Vfox}, scenario G part 2: a new shell that carries the global choice, then session java@21"
            Use-RegistryEnv $vdir
            Invoke-Flavour $fl 'probe-global-2.sh' @('21')

            # give the next scenario a clean start: no global java, registry back to the baseline
            Reset-ProcessEnv
            $env:Path = "$vdir;$basePath"
            if ($HasUnuse) { Invoke-Flavour $default 'probe-unuse.sh' } else { Remove-Item "$env:USERPROFILE\.version-fox\.tool-versions" -ErrorAction SilentlyContinue }
            foreach ($n in $saved.Keys) { [Environment]::SetEnvironmentVariable($n, $saved[$n], 'User') }
        }
    } catch {
        Write-Host "version $Vfox failed: $_"
    } finally {
        foreach ($n in $saved.Keys) { [Environment]::SetEnvironmentVariable($n, $saved[$n], 'User') }
        Reset-ProcessEnv
        Get-Process -Name java -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

Run-Version '1.0.13' 'v0.6.2' 'vfox-java-0.6.2.zip' 'ce352b2eb78478b66858b9b0b731ccb0968b48704a5d1735e989c84fb2b20d84' $true
Run-Version '0.5.4' 'v0.4.3' 'vfox-java-0.4.3.zip' 'a9007600ecf40d6a0c08f1f519e8a55f6b214afe87c6398995323bb68d697dfa' $false

Section 'PROBE FINISHED'
exit 0
