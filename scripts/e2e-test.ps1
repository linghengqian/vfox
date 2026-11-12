#!/usr/bin/env pwsh
# Scratch branch only: the fork's e2e job runs this file on windows-latest.
# It now runs the vfox#732 probe.
param([switch]$Verbose = $false)

& "$PSScriptRoot\probe732\run.ps1"
exit $LASTEXITCODE
