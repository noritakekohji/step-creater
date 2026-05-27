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
    Add-Type -AssemblyName PresentationFramework
    $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dlg.Description = 'ワークフォルダを選択（キャンセルで終了）'
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host 'キャンセルされました。'
        return
    }
    $WorkFolder = $dlg.SelectedPath
}

try {
    Add-Type -AssemblyName PresentationFramework

    $mdPath = Join-Path $WorkFolder 'procedure.md'
    if (-not (Test-Path -LiteralPath $mdPath)) {
        # 既存ワークフォルダではない → 新規作成するか確認
        $existing = if (Test-Path -LiteralPath $WorkFolder) {
            Get-ChildItem -LiteralPath $WorkFolder -Force | Select-Object -First 1
        } else { $null }

        $msg = if ($existing) {
            "選択されたフォルダはStepCreaterのワークフォルダではありません:`n$WorkFolder`n`n新規ワークフォルダとして作成しますか？`n（既存ファイルは残りますが、procedure.md が新規生成されます）"
        } else {
            "選択されたフォルダは空です:`n$WorkFolder`n`n新規ワークフォルダとして作成しますか？"
        }
        $r = [System.Windows.MessageBox]::Show($msg, 'StepCreater', 'YesNo', 'Question')
        if ($r -ne 'Yes') {
            Write-Host '中止しました。'
            return
        }

        Add-Type -AssemblyName Microsoft.VisualBasic
        $title = [Microsoft.VisualBasic.Interaction]::InputBox(
            '手順書のタイトルを入力してください', '新規ワークフォルダ', '新規手順書')
        if ([string]::IsNullOrWhiteSpace($title)) {
            Write-Host 'タイトル未入力のため中止しました。'
            return
        }

        New-StepCreaterWorkfolder -Path $WorkFolder -Title $title -Force | Out-Null
    }

    $session = Open-StepCreaterWorkfolder -Path $WorkFolder
    $session.Mode = $Mode
    Show-StepCreaterMainWindow -Session $session
}
catch {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        "起動に失敗しました:`n`n$($_.Exception.Message)`n`n$($_.ScriptStackTrace)",
        'StepCreater - エラー', 'OK', 'Error') | Out-Null
    Write-Error $_
}
