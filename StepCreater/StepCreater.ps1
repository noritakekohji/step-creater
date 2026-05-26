<#
.SYNOPSIS
  StepCreater entry point. Phase 1: CLI for workfolder operations (no GUI yet).
.PARAMETER WorkFolder
  Path to a workfolder.
.PARAMETER Mode
  Initial mode (Edit | Execute | Capture). Default: Edit.
.PARAMETER Init
  Create a new workfolder at WorkFolder with the given Title.
.PARAMETER Title
  Title for the new procedure (used with -Init).
.EXAMPLE
  .\StepCreater.ps1 -Init -WorkFolder C:\temp\proc1 -Title "Server Build"
.EXAMPLE
  .\StepCreater.ps1 -WorkFolder C:\temp\proc1
#>
[CmdletBinding()]
param(
    [Parameter()] [string]$WorkFolder,
    [Parameter()] [ValidateSet('Edit', 'Execute', 'Capture')] [string]$Mode = 'Edit',
    [Parameter()] [switch]$Init,
    [Parameter()] [string]$Title
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/StepCreater.psd1" -Force

if ($Init) {
    if (-not $WorkFolder) { throw '-WorkFolder is required with -Init.' }
    if (-not $Title)      { throw '-Title is required with -Init.' }
    $path = New-StepCreaterWorkfolder -Path $WorkFolder -Title $Title
    Write-Host "Created workfolder: $path"
    return
}

if (-not $WorkFolder) {
    Write-Host 'Usage: StepCreater.ps1 -WorkFolder <path> [-Mode Edit|Execute|Capture]'
    Write-Host '       StepCreater.ps1 -Init -WorkFolder <path> -Title "<title>"'
    return
}

$session = Open-StepCreaterWorkfolder -Path $WorkFolder
$session.Mode = $Mode

Write-Host "Opened: $($session.WorkFolderPath)"
Write-Host "Title : $($session.Procedure.Title)"
Write-Host "Steps : $($session.Procedure.Steps.Count)"
Write-Host "Mode  : $($session.Mode)"
foreach ($step in $session.Procedure.Steps) {
    Write-Host ("  [{0}] {1}: {2}" -f $step.Status, $step.Id, $step.Title)
}
