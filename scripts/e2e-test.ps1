[CmdletBinding()]
param()
# Scratch branch only: the fork's e2e job runs this file on windows-latest. It now runs the vfox#335 probe.
& "$PSScriptRoot\probe335\run.ps1"
exit 0
