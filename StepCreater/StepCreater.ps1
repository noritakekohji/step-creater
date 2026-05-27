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
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dlg.Description = 'ワークフォルダを選択（キャンセルで終了）'
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host 'キャンセルされました。'
        return
    }
    $WorkFolder = $dlg.SelectedPath
}

$session = Open-StepCreaterWorkfolder -Path $WorkFolder
$session.Mode = $Mode
Show-StepCreaterMainWindow -Session $session
