param(
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$PluginTag,
    [Parameter(Mandatory = $true)][string]$PluginZip,
    [Parameter(Mandatory = $true)][string]$PluginSha256
)
# Installs vfox <Version> into C:\probe\vfox-<Version> and downloads the java plugin zip to C:\probe\dl.
# Only public release URLs are used; every download is checked against a published or pinned SHA-256.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$dl = 'C:\probe\dl'
$dest = "C:\probe\vfox-$Version"
New-Item -ItemType Directory -Force $dl, $dest, "C:\probe\x-$Version" | Out-Null

$asset = "vfox_${Version}_windows_x86_64.zip"
$base = "https://github.com/version-fox/vfox/releases/download/v$Version"
Invoke-WebRequest -Uri "$base/checksums.txt" -OutFile "$dl\checksums-$Version.txt"
Invoke-WebRequest -Uri "$base/$asset" -OutFile "$dl\$asset"
$line = Select-String -Path "$dl\checksums-$Version.txt" -Pattern ([regex]::Escape($asset)) | Select-Object -First 1
$expected = ($line.Line -split '\s+')[0].ToLower()
$actual = (Get-FileHash "$dl\$asset" -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $expected) { throw "vfox checksum mismatch: $actual vs $expected" }
Expand-Archive "$dl\$asset" -DestinationPath "C:\probe\x-$Version" -Force
$exe = Get-ChildItem "C:\probe\x-$Version" -Recurse -Filter vfox.exe | Select-Object -First 1
Copy-Item $exe.FullName "$dest\vfox.exe"

if (-not (Test-Path "$dl\$PluginZip")) {
    Invoke-WebRequest -Uri "https://github.com/version-fox/vfox-java/releases/download/$PluginTag/$PluginZip" -OutFile "$dl\$PluginZip"
}
$actual = (Get-FileHash "$dl\$PluginZip" -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $PluginSha256) { throw "plugin checksum mismatch: $actual" }

& "$dest\vfox.exe" --version
& "$env:ProgramFiles\Git\bin\bash.exe" --version | Select-Object -First 1
[Environment]::OSVersion.VersionString
