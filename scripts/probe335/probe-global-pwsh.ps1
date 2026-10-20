# vfox#335 probe, scenario P: PowerShell 7 started with the registry environment, then a session `use`.
# Usage: pwsh -NoProfile -File probe-global-pwsh.ps1 <majorB>
param([Parameter(Mandatory = $true)][string]$B)
$ErrorActionPreference = 'Continue'

function Show([string]$label) {
    Write-Host ''
    Write-Host "--- $label"
    Write-Host "JAVA_HOME=[$env:JAVA_HOME]"
    Write-Host 'Get-Command java -All (first 3):'
    Get-Command java -All -ErrorAction SilentlyContinue | Select-Object -First 3 | ForEach-Object { Write-Host "  $($_.Source)" }
    $line = (& java -version 2>&1 | ForEach-Object { "$_" } | Select-Object -First 1)
    Write-Host "java -version: $line"
    $line = (& "$env:JAVA_HOME\bin\java.exe" -version 2>&1 | ForEach-Object { "$_" } | Select-Object -First 1)
    Write-Host "`$env:JAVA_HOME\bin\java -version: $line"
    Write-Host 'PATH entries that mention java/jdk/vfox (position: entry):'
    $i = 0
    ($env:Path -split ';') | ForEach-Object { $i++; if ($_ -match 'java|jdk|temurin|hostedtoolcache|\.vfox|\.version-fox') { '{0,4}: {1}' -f $i, $_ } } | Select-Object -First 20
}

& vfox --version
Write-Host "inherited JAVA_HOME=[$env:JAVA_HOME]"
Write-Host ('java before activation: ' + (Get-Command java -ErrorAction SilentlyContinue).Source)

Write-Host ''
Write-Host '########## activate (what $PROFILE does)'
Invoke-Expression (& vfox activate pwsh | Out-String)
prompt | Out-Null
Show 'P0: new pwsh, global choice only'

Write-Host ''
Write-Host "########## vfox use java@$B (session) + prompt"
& vfox use "java@$B"
prompt | Out-Null
Show "P1: session $B on top of the global choice"
