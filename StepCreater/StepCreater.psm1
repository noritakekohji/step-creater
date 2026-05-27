Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

class ScreenshotRef {
    [string]   $FileName
    [datetime] $CapturedAt
    [string]   $Kind                # full | window | rect
    [bool]     $MaskedFromOriginal

    ScreenshotRef([string]$fileName, [datetime]$capturedAt, [string]$kind) {
        if ($kind -notin 'full', 'window', 'rect') {
            throw "Invalid Kind '$kind'. Expected: full | window | rect."
        }
        $this.FileName            = $fileName
        $this.CapturedAt          = $capturedAt
        $this.Kind                = $kind
        $this.MaskedFromOriginal  = $false
    }
}

class Step {
    [string] $Id
    [string] $Title
    [string] $BodyMarkdown
    [string] $Command
    [string] $ExpectedResult
    [string] $Status
    [Nullable[datetime]] $Started
    [Nullable[datetime]] $Finished
    [string] $Note
    [System.Collections.Generic.List[ScreenshotRef]] $Evidence
    [hashtable] $UnknownSectionsRaw

    Step([string]$id, [string]$title) {
        $this.Id                  = $id
        $this.Title               = $title
        $this.BodyMarkdown        = ''
        $this.Command             = ''
        $this.ExpectedResult      = ''
        $this.Status              = 'pending'
        $this.Note                = ''
        $this.Evidence            = [System.Collections.Generic.List[ScreenshotRef]]::new()
        $this.UnknownSectionsRaw  = @{}
    }
}

class ProcedureDoc {
    [string]   $Title
    [string]   $Author
    [Nullable[datetime]] $Created
    [Nullable[datetime]] $Updated
    [System.Collections.Generic.List[Step]] $Steps

    ProcedureDoc([string]$title) {
        $this.Title  = $title
        $this.Author = ''
        $this.Steps  = [System.Collections.Generic.List[Step]]::new()
    }

    [Step] AddStep([string]$title) {
        $nextNum = $this.Steps.Count + 1
        $id = '{0:D2}' -f $nextNum
        $step = [Step]::new($id, $title)
        $this.Steps.Add($step) | Out-Null
        return $step
    }
}

function Write-Procedure {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ProcedureDoc]$Procedure
    )

    $sb = [System.Text.StringBuilder]::new()
    $nl = "`n"

    # YAML front matter
    [void]$sb.Append("---$nl")
    [void]$sb.Append("title: $($Procedure.Title)$nl")
    if ($Procedure.Author)  { [void]$sb.Append("author: $($Procedure.Author)$nl") }
    if ($Procedure.Created) { [void]$sb.Append("created: $($Procedure.Created.ToString('yyyy-MM-dd'))$nl") }
    if ($Procedure.Updated) { [void]$sb.Append("updated: $($Procedure.Updated.ToString('s'))$nl") }
    [void]$sb.Append("---$nl$nl")

    # H1 title
    [void]$sb.Append("# $($Procedure.Title)$nl$nl")

    # Steps
    $i = 0
    foreach ($step in $Procedure.Steps) {
        $i++
        [void]$sb.Append("## Step $i`: $($step.Title)$nl")
        [void]$sb.Append("<!-- step-id: $($step.Id) -->$nl")
        [void]$sb.Append("- status: $($step.Status)$nl")
        if ($step.Started)  { [void]$sb.Append("- started: $($step.Started.ToString('s'))$nl") }
        if ($step.Finished) { [void]$sb.Append("- finished: $($step.Finished.ToString('s'))$nl") }
        [void]$sb.Append($nl)

        if ($step.BodyMarkdown) {
            [void]$sb.Append("### 手順$nl")
            [void]$sb.Append($step.BodyMarkdown.TrimEnd())
            [void]$sb.Append("$nl$nl")
        }

        if ($step.Command) {
            [void]$sb.Append("### 実行コマンド$nl")
            [void]$sb.Append('```powershell' + $nl)
            [void]$sb.Append($step.Command.TrimEnd() + $nl)
            [void]$sb.Append('```' + $nl + $nl)
        }

        if ($step.ExpectedResult) {
            [void]$sb.Append("### 想定結果$nl")
            [void]$sb.Append($step.ExpectedResult.TrimEnd())
            [void]$sb.Append("$nl$nl")
        }

        if ($step.Evidence.Count -gt 0) {
            [void]$sb.Append("### エビデンス$nl")
            foreach ($ev in $step.Evidence) {
                [void]$sb.Append("![]($($ev.FileName))$nl")
            }
            [void]$sb.Append($nl)
        }

        if ($step.Note) {
            [void]$sb.Append("### 備考$nl")
            [void]$sb.Append($step.Note.TrimEnd())
            [void]$sb.Append("$nl$nl")
        }

        foreach ($key in $step.UnknownSectionsRaw.Keys) {
            [void]$sb.Append("$key$nl")
            [void]$sb.Append($step.UnknownSectionsRaw[$key].TrimEnd())
            [void]$sb.Append("$nl$nl")
        }
    }

    return $sb.ToString()
}

function Read-Procedure {
    [CmdletBinding()]
    [OutputType([ProcedureDoc])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "File not found: $Path"
    }

    $text  = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $lines = $text -split "`r?`n"

    # Parse YAML front matter
    $i = 0
    $fm = @{}
    if ($lines.Count -gt 0 -and $lines[0] -eq '---') {
        $i = 1
        while ($i -lt $lines.Count -and $lines[$i] -ne '---') {
            if ($lines[$i] -match '^(\w+):\s*(.+?)\s*$') {
                $fm[$matches[1]] = $matches[2]
            }
            $i++
        }
        $i++
    }

    $title = if ($fm.ContainsKey('title')) { $fm['title'] } else { '' }
    $doc = [ProcedureDoc]::new($title)
    if ($fm.ContainsKey('author'))  { $doc.Author  = $fm['author'] }
    if ($fm.ContainsKey('created')) { $doc.Created = [datetime]::Parse($fm['created']) }
    if ($fm.ContainsKey('updated')) { $doc.Updated = [datetime]::Parse($fm['updated']) }

    # Split remainder by step headings ("## Step N: Title")
    $rest = ($lines[$i..($lines.Count - 1)]) -join "`n"
    $stepBlocks = [regex]::Split($rest, '(?m)^(?=## Step \d+:)')

    foreach ($block in $stepBlocks) {
        if ($block -notmatch '^## Step (\d+):\s*(.+?)\r?\n') { continue }
        $stepTitle = $matches[2].Trim()

        if ($block -match '<!-- step-id:\s*(\S+)\s*-->') { $id = $matches[1] }
        else { $id = '{0:D2}' -f [int]$matches[1] }

        $step = [Step]::new($id, $stepTitle)

        if ($block -match '(?m)^- status:\s*(\S+)\s*$')   { $step.Status   = $matches[1] }
        if ($block -match '(?m)^- started:\s*(\S+)\s*$')  { $step.Started  = [datetime]::Parse($matches[1]) }
        if ($block -match '(?m)^- finished:\s*(\S+)\s*$') { $step.Finished = [datetime]::Parse($matches[1]) }

        $sectionMatches = [regex]::Matches($block, '(?m)^### (.+?)\r?\n')
        for ($s = 0; $s -lt $sectionMatches.Count; $s++) {
            $heading = '### ' + $sectionMatches[$s].Groups[1].Value.Trim()
            $start   = $sectionMatches[$s].Index + $sectionMatches[$s].Length
            $end     = if ($s + 1 -lt $sectionMatches.Count) { $sectionMatches[$s + 1].Index } else { $block.Length }
            $content = $block.Substring($start, $end - $start).Trim()

            switch ($heading) {
                '### 手順'         { $step.BodyMarkdown   = $content }
                '### 実行コマンド' {
                    if ($content -match '(?ms)^```\w*\r?\n(.*?)\r?\n```') { $step.Command = $matches[1].Trim() }
                    else { $step.Command = $content }
                }
                '### 想定結果'     { $step.ExpectedResult = $content }
                '### エビデンス'   {
                    foreach ($m in [regex]::Matches($content, '!\[[^\]]*\]\(([^)]+)\)')) {
                        $step.Evidence.Add(
                            [ScreenshotRef]::new($m.Groups[1].Value, [datetime]::MinValue, 'full')
                        ) | Out-Null
                    }
                }
                '### 備考'         { $step.Note = $content }
                default            { $step.UnknownSectionsRaw[$heading] = $content }
            }
        }

        $doc.Steps.Add($step) | Out-Null
    }

    return $doc
}

class WorkSession {
    [string]       $WorkFolderPath
    [ProcedureDoc] $Procedure
    [int]          $CurrentStepIndex
    [string]       $Mode
    [System.Collections.Generic.List[ScreenshotRef]] $UnassignedScreenshots

    WorkSession([string]$path, [ProcedureDoc]$doc) {
        $this.WorkFolderPath        = $path
        $this.Procedure             = $doc
        $this.CurrentStepIndex      = 0
        $this.Mode                  = 'Edit'
        $this.UnassignedScreenshots = [System.Collections.Generic.List[ScreenshotRef]]::new()
    }
}

function New-StepCreaterWorkfolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Title,
        [switch]$Force
    )

    if (Test-Path -LiteralPath $Path) {
        $existing = Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1
        if ($existing -and -not $Force) {
            throw "Folder '$Path' is not empty. Use -Force to override."
        }
    } else {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    New-Item -ItemType Directory -Path (Join-Path $Path 'images')       -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Path 'attachments')  -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Path '.stepcreater') -Force | Out-Null

    $doc = [ProcedureDoc]::new($Title)
    $doc.Created = [datetime]::Today
    $md = Write-Procedure -Procedure $doc
    Set-Content -LiteralPath (Join-Path $Path 'procedure.md') -Value $md -Encoding UTF8

    $state = @{ currentStepIndex = 0; mode = 'Edit' } | ConvertTo-Json
    Set-Content -LiteralPath (Join-Path $Path '.stepcreater/state.json') -Value $state -Encoding UTF8

    return (Resolve-Path $Path).Path
}

function Open-StepCreaterWorkfolder {
    [CmdletBinding()]
    [OutputType([WorkSession])]
    param([Parameter(Mandatory)] [string]$Path)

    $resolved = (Resolve-Path $Path).Path
    $mdPath = Join-Path $resolved 'procedure.md'
    if (-not (Test-Path -LiteralPath $mdPath)) {
        throw "Not a StepCreater workfolder (procedure.md missing): $resolved"
    }

    $doc = Read-Procedure -Path $mdPath
    $session = [WorkSession]::new($resolved, $doc)

    $statePath = Join-Path $resolved '.stepcreater/state.json'
    if (-not (Test-Path -LiteralPath $statePath)) {
        New-Item -ItemType Directory -Path (Split-Path $statePath -Parent) -Force | Out-Null
        $defaultState = @{ currentStepIndex = 0; mode = 'Edit' } | ConvertTo-Json
        Set-Content -LiteralPath $statePath -Value $defaultState -Encoding UTF8
    } else {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if ($state.PSObject.Properties.Name -contains 'currentStepIndex') {
            $session.CurrentStepIndex = [int]$state.currentStepIndex
        }
        if ($state.PSObject.Properties.Name -contains 'mode') {
            $session.Mode = [string]$state.mode
        }
    }

    return $session
}

function Get-StepCreaterConfigPath {
    $dir = if ($env:STEPCREATER_CONFIG_DIR) { $env:STEPCREATER_CONFIG_DIR }
           else { Join-Path $env:APPDATA 'StepCreater' }
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return (Join-Path $dir 'config.json')
}

function Get-StepCreaterConfig {
    [CmdletBinding()]
    param()

    $path = Get-StepCreaterConfigPath
    if (-not (Test-Path -LiteralPath $path)) {
        $default = [pscustomobject]@{
            hotkeys = [pscustomobject]@{
                fullScreen = 'Ctrl+F12'
                window     = 'Ctrl+F11'
                rect       = 'Ctrl+Shift+F12'
            }
            annotationEnabled  = $true
            recentWorkfolders  = @()
        }
        return $default
    }
    return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

function Set-StepCreaterConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Config)

    $path = Get-StepCreaterConfigPath
    $json = $Config | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8
}

function Get-StepTemplates {
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[object]])]
    param()

    $dir = Join-Path $PSScriptRoot 'ui/templates'
    $list = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $dir)) { return $list }

    Get-ChildItem -LiteralPath $dir -Filter '*.psd1' | ForEach-Object {
        $data = Import-PowerShellDataFile -LiteralPath $_.FullName
        $list.Add([pscustomobject]$data) | Out-Null
    }
    return $list
}

function Add-ProcedureStepAt {
    [CmdletBinding()]
    [OutputType([Step])]
    param(
        [Parameter(Mandatory)] [ProcedureDoc]$Procedure,
        [Parameter(Mandatory)] [int]$Index,
        [Parameter(Mandatory)] [string]$Title
    )
    $step = [Step]::new('', $Title)
    $Procedure.Steps.Insert($Index, $step) | Out-Null
    Update-ProcedureStepIds -Procedure $Procedure
    return $step
}

function Remove-ProcedureStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ProcedureDoc]$Procedure,
        [Parameter(Mandatory)] [int]$Index
    )
    $Procedure.Steps.RemoveAt($Index) | Out-Null
    Update-ProcedureStepIds -Procedure $Procedure
}

function Move-ProcedureStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ProcedureDoc]$Procedure,
        [Parameter(Mandatory)] [int]$Index,
        [Parameter(Mandatory)] [ValidateSet('Up','Down')] [string]$Direction
    )
    $target = if ($Direction -eq 'Up') { $Index - 1 } else { $Index + 1 }
    if ($target -lt 0 -or $target -ge $Procedure.Steps.Count) { return }
    $step = $Procedure.Steps[$Index]
    $Procedure.Steps.RemoveAt($Index) | Out-Null
    $Procedure.Steps.Insert($target, $step) | Out-Null
    Update-ProcedureStepIds -Procedure $Procedure
}

function Update-ProcedureStepIds {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [ProcedureDoc]$Procedure)
    for ($i = 0; $i -lt $Procedure.Steps.Count; $i++) {
        $Procedure.Steps[$i].Id = '{0:D2}' -f ($i + 1)
    }
}

function Get-ProcedureHash {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [ProcedureDoc]$Procedure)
    $md = Write-Procedure -Procedure $Procedure
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($md)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($bytes)
    return [System.BitConverter]::ToString($hash) -replace '-', ''
}

function Show-StepCreaterMainWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [WorkSession]$Session,
        [switch]$NoShow
    )

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $xamlPath = Join-Path $PSScriptRoot 'ui/MainWindow.xaml'
    $xml = [xml](Get-Content -LiteralPath $xamlPath -Raw)
    $reader = [System.Xml.XmlNodeReader]::new($xml)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $c = @{}
    foreach ($name in @(
        'MenuNew','MenuOpen','MenuSave','MenuExit','MenuTemplates',
        'StatusText','DirtyText',
        'TabEdit','TabExecute','TabCapture',
        'WorkfolderPath','BtnSave',
        'StepList','BtnAdd','BtnDelete','BtnUp','BtnDown',
        'TxtTitle','CboStatus','TxtBody','TxtCommand','TxtExpected','TxtNote',
        'UnassignedTray',
        'EditPanel','ExecutePanel',
        'ProgressLabel','ExecChecklist',
        'ExecStepTitle','ExecBody','ExecCommand','BtnCopyCommand','ExecExpected',
        'ExecEvidenceTray','BtnComplete','BtnNg','BtnSkip'
    )) { $c[$name] = $window.FindName($name) }

    $c.WorkfolderPath.Text = $Session.WorkFolderPath
    $window.Title          = "StepCreater - $($Session.Procedure.Title)"
    Update-StepListUI -Session $Session -ListBox $c.StepList

    # Editor sync state
    $editorState = [pscustomobject]@{
        CurrentStepIndex = -1
        SuppressEdit     = $false
    }

    $loadStep = {
        param($idx)
        if ($idx -lt 0 -or $idx -ge $Session.Procedure.Steps.Count) {
            $editorState.SuppressEdit = $true
            $c.TxtTitle.Text    = ''
            $c.TxtBody.Text     = ''
            $c.TxtCommand.Text  = ''
            $c.TxtExpected.Text = ''
            $c.TxtNote.Text     = ''
            $c.CboStatus.SelectedIndex = -1
            $editorState.SuppressEdit = $false
            $editorState.CurrentStepIndex = -1
            return
        }
        $step = $Session.Procedure.Steps[$idx]
        $editorState.SuppressEdit = $true
        $c.TxtTitle.Text    = $step.Title
        $c.TxtBody.Text     = $step.BodyMarkdown
        $c.TxtCommand.Text  = $step.Command
        $c.TxtExpected.Text = $step.ExpectedResult
        $c.TxtNote.Text     = $step.Note
        $c.CboStatus.SelectedIndex = @('pending','done','ng','skipped').IndexOf($step.Status)
        $editorState.SuppressEdit = $false
        $editorState.CurrentStepIndex = $idx
    }.GetNewClosure()

    $saveEdits = {
        if ($editorState.SuppressEdit) { return }
        if ($editorState.CurrentStepIndex -lt 0) { return }
        $step = $Session.Procedure.Steps[$editorState.CurrentStepIndex]
        $step.Title          = $c.TxtTitle.Text
        $step.BodyMarkdown   = $c.TxtBody.Text
        $step.Command        = $c.TxtCommand.Text
        $step.ExpectedResult = $c.TxtExpected.Text
        $step.Note           = $c.TxtNote.Text
        if ($c.CboStatus.SelectedIndex -ge 0) {
            $step.Status = @('pending','done','ng','skipped')[$c.CboStatus.SelectedIndex]
        }
        $savedIdx = $editorState.CurrentStepIndex
        Update-StepListUI -Session $Session -ListBox $c.StepList
        $editorState.SuppressEdit = $true
        $c.StepList.SelectedIndex = $savedIdx
        $editorState.SuppressEdit = $false
        $editorState.CurrentStepIndex = $savedIdx
        Update-DirtyIndicator -Window $window
    }.GetNewClosure()

    $c.StepList.Add_SelectionChanged({ & $loadStep $c.StepList.SelectedIndex }.GetNewClosure())

    foreach ($tb in @($c.TxtTitle, $c.TxtBody, $c.TxtCommand, $c.TxtExpected, $c.TxtNote)) {
        $tb.Add_LostFocus($saveEdits)
    }
    $c.CboStatus.Add_SelectionChanged($saveEdits)

    $c.BtnAdd.Add_Click({
        $idx = if ($c.StepList.SelectedIndex -ge 0) { $c.StepList.SelectedIndex + 1 } else { $Session.Procedure.Steps.Count }
        Add-ProcedureStepAt -Procedure $Session.Procedure -Index $idx -Title '新しい手順' | Out-Null
        Update-StepListUI -Session $Session -ListBox $c.StepList
        $c.StepList.SelectedIndex = $idx
        Save-WorkSession -Session $Session
        $window.Tag.Baseline = Get-ProcedureHash -Procedure $Session.Procedure
        Update-DirtyIndicator -Window $window
    }.GetNewClosure())

    $c.BtnDelete.Add_Click({
        $idx = $c.StepList.SelectedIndex
        if ($idx -lt 0) { return }
        $confirm = [System.Windows.MessageBox]::Show(
            "Step $($Session.Procedure.Steps[$idx].Id) を削除しますか？",
            '確認', 'YesNo', 'Question')
        if ($confirm -ne 'Yes') { return }
        Remove-ProcedureStep -Procedure $Session.Procedure -Index $idx
        Update-StepListUI -Session $Session -ListBox $c.StepList
        if ($Session.Procedure.Steps.Count -gt 0) {
            $c.StepList.SelectedIndex = [Math]::Min($idx, $Session.Procedure.Steps.Count - 1)
        }
        Save-WorkSession -Session $Session
        $window.Tag.Baseline = Get-ProcedureHash -Procedure $Session.Procedure
        Update-DirtyIndicator -Window $window
    }.GetNewClosure())

    $c.BtnUp.Add_Click({
        $idx = $c.StepList.SelectedIndex
        if ($idx -lt 1) { return }
        Move-ProcedureStep -Procedure $Session.Procedure -Index $idx -Direction Up
        Update-StepListUI -Session $Session -ListBox $c.StepList
        $c.StepList.SelectedIndex = $idx - 1
        Save-WorkSession -Session $Session
        $window.Tag.Baseline = Get-ProcedureHash -Procedure $Session.Procedure
        Update-DirtyIndicator -Window $window
    }.GetNewClosure())

    $c.BtnDown.Add_Click({
        $idx = $c.StepList.SelectedIndex
        if ($idx -lt 0 -or $idx -ge $Session.Procedure.Steps.Count - 1) { return }
        Move-ProcedureStep -Procedure $Session.Procedure -Index $idx -Direction Down
        Update-StepListUI -Session $Session -ListBox $c.StepList
        $c.StepList.SelectedIndex = $idx + 1
        Save-WorkSession -Session $Session
        $window.Tag.Baseline = Get-ProcedureHash -Procedure $Session.Procedure
        Update-DirtyIndicator -Window $window
    }.GetNewClosure())

    $doSave = {
        Save-WorkSession -Session $Session
        $window.Tag.Baseline = Get-ProcedureHash -Procedure $Session.Procedure
        Update-DirtyIndicator -Window $window
        $c.StatusText.Text = "保存しました ($(Get-Date -Format HH:mm:ss))"
    }
    $c.BtnSave.Add_Click($doSave.GetNewClosure())
    $c.MenuSave.Add_Click($doSave.GetNewClosure())
    $c.MenuExit.Add_Click({ $window.Close() }.GetNewClosure())

    # Ctrl+S keyboard shortcut
    $saveCommand = [System.Windows.Input.RoutedCommand]::new()
    $cmdBinding  = [System.Windows.Input.CommandBinding]::new($saveCommand, { & $doSave }.GetNewClosure())
    $window.CommandBindings.Add($cmdBinding) | Out-Null
    $kb = [System.Windows.Input.KeyBinding]::new(
        $saveCommand,
        [System.Windows.Input.Key]::S,
        [System.Windows.Input.ModifierKeys]::Control
    )
    $window.InputBindings.Add($kb) | Out-Null

    $window.Tag = [pscustomobject]@{
        Session  = $Session
        Controls = $c
        Baseline = (Get-ProcedureHash -Procedure $Session.Procedure)
    }

    $assignToCurrent = {
        param($ref)
        $idx = $c.StepList.SelectedIndex
        if ($idx -lt 0) {
            [System.Windows.MessageBox]::Show('割当先のStepを先に選択してください。', '情報', 'OK', 'Information') | Out-Null
            return
        }
        $Session.UnassignedScreenshots.Remove($ref) | Out-Null
        $Session.Procedure.Steps[$idx].Evidence.Add($ref) | Out-Null
        Update-UnassignedTrayUI -Session $Session -TrayPanel $c.UnassignedTray -OnAssign $assignToCurrent
        Save-WorkSession -Session $Session
        $window.Tag.Baseline = Get-ProcedureHash -Procedure $Session.Procedure
        Update-DirtyIndicator -Window $window
    }.GetNewClosure()
    Update-UnassignedTrayUI -Session $Session -TrayPanel $c.UnassignedTray -OnAssign $assignToCurrent

    # ---- Execute mode helpers ----
    $loadExecStep = {
        param($idx)
        if ($idx -lt 0 -or $idx -ge $Session.Procedure.Steps.Count) {
            $c.ExecStepTitle.Text = ''
            $c.ExecBody.Text      = ''
            $c.ExecCommand.Text   = ''
            $c.ExecExpected.Text  = ''
            $c.ExecEvidenceTray.Children.Clear()
            return
        }
        $step = $Session.Procedure.Steps[$idx]
        $c.ExecStepTitle.Text = "Step $($step.Id): $($step.Title)"
        $c.ExecBody.Text      = $step.BodyMarkdown
        $c.ExecCommand.Text   = $step.Command
        $c.ExecExpected.Text  = $step.ExpectedResult

        $c.ExecEvidenceTray.Children.Clear()
        foreach ($ev in $step.Evidence) {
            $path = Join-Path $Session.WorkFolderPath ("images/" + $ev.FileName)
            if (-not (Test-Path -LiteralPath $path)) { continue }
            $img = New-Object System.Windows.Controls.Image
            $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
            $bmp.BeginInit(); $bmp.CacheOption = 'OnLoad'
            $bmp.UriSource = (New-Object System.Uri $path)
            $bmp.DecodePixelWidth = 200
            $bmp.EndInit()
            $img.Source = $bmp; $img.Stretch = 'Uniform'; $img.Width = 100; $img.Height = 70; $img.Margin = '2'
            $img.ToolTip = $ev.FileName
            $c.ExecEvidenceTray.Children.Add($img) | Out-Null
        }
    }.GetNewClosure()

    $applyMode = {
        param($mode)
        $Session.Mode = $mode
        if ($mode -eq 'Edit') {
            $c.EditPanel.Visibility    = 'Visible'
            $c.ExecutePanel.Visibility = 'Collapsed'
        } else {
            $c.EditPanel.Visibility    = 'Collapsed'
            $c.ExecutePanel.Visibility = 'Visible'
            Update-ExecChecklistUI -Session $Session -ListBox $c.ExecChecklist -ProgressLabel $c.ProgressLabel
            $idx = if ($c.ExecChecklist.SelectedIndex -ge 0) { $c.ExecChecklist.SelectedIndex } else { 0 }
            $c.ExecChecklist.SelectedIndex = $idx
            & $loadExecStep $idx
        }
    }.GetNewClosure()

    $c.TabEdit.Add_Checked({    & $applyMode 'Edit'    }.GetNewClosure())
    $c.TabExecute.Add_Checked({ & $applyMode 'Execute' }.GetNewClosure())

    $c.ExecChecklist.Add_SelectionChanged({
        & $loadExecStep $c.ExecChecklist.SelectedIndex
    }.GetNewClosure())

    & $applyMode $Session.Mode

    $confirmDiscard = {
        $current = Get-ProcedureHash -Procedure $Session.Procedure
        if ($current -eq $window.Tag.Baseline) { return $true }
        $r = [System.Windows.MessageBox]::Show(
            '未保存の変更があります。終了しますか？',
            '確認', 'OKCancel', 'Warning')
        return ($r -eq 'OK')
    }.GetNewClosure()
    $window.Tag | Add-Member -NotePropertyName ConfirmDiscard -NotePropertyValue $confirmDiscard

    Add-Type -AssemblyName System.Windows.Forms

    $c.MenuOpen.Add_Click({
        $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dlg.Description = 'ワークフォルダを選択'
        if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        if (-not (& $confirmDiscard)) { return }
        try {
            $newSession = Open-StepCreaterWorkfolder -Path $dlg.SelectedPath
        } catch {
            [System.Windows.MessageBox]::Show("開けませんでした: $($_.Exception.Message)", 'エラー', 'OK', 'Error') | Out-Null
            return
        }
        $window.Close()
        Show-StepCreaterMainWindow -Session $newSession
    }.GetNewClosure())

    $c.MenuNew.Add_Click({
        $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dlg.Description = '新規ワークフォルダの作成先を選択'
        if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

        Add-Type -AssemblyName Microsoft.VisualBasic
        $title = [Microsoft.VisualBasic.Interaction]::InputBox('手順書のタイトル', '新規作成', '新規手順書')
        if ([string]::IsNullOrWhiteSpace($title)) { return }
        if (-not (& $confirmDiscard)) { return }

        try {
            New-StepCreaterWorkfolder -Path $dlg.SelectedPath -Title $title | Out-Null
            $newSession = Open-StepCreaterWorkfolder -Path $dlg.SelectedPath
        } catch {
            [System.Windows.MessageBox]::Show("作成に失敗: $($_.Exception.Message)", 'エラー', 'OK', 'Error') | Out-Null
            return
        }
        $window.Close()
        Show-StepCreaterMainWindow -Session $newSession
    }.GetNewClosure())

    foreach ($tpl in (Get-StepTemplates)) {
        $mi = [System.Windows.Controls.MenuItem]::new()
        $mi.Header = $tpl.Name
        $tplLocal = $tpl
        $mi.Add_Click({
            $idx = if ($c.StepList.SelectedIndex -ge 0) { $c.StepList.SelectedIndex + 1 } else { $Session.Procedure.Steps.Count }
            $newStep = Add-ProcedureStepAt -Procedure $Session.Procedure -Index $idx -Title $tplLocal.Title
            $newStep.BodyMarkdown   = [string]$tplLocal.BodyMarkdown
            $newStep.Command        = [string]$tplLocal.Command
            $newStep.ExpectedResult = [string]$tplLocal.ExpectedResult
            $newStep.Note           = [string]$tplLocal.Note
            Update-StepListUI -Session $Session -ListBox $c.StepList
            $c.StepList.SelectedIndex = $idx
            Save-WorkSession -Session $Session
            $window.Tag.Baseline = Get-ProcedureHash -Procedure $Session.Procedure
            Update-DirtyIndicator -Window $window
        }.GetNewClosure())
        $c.MenuTemplates.Items.Add($mi) | Out-Null
    }

    $window.Add_Closing({
        $e = $args[1]
        if (-not (& $confirmDiscard)) { $e.Cancel = $true }
    }.GetNewClosure())

    $window.Add_KeyDown({
        $e = $args[1]
        if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
            $window.Close()
        }
    }.GetNewClosure())

    $window.Add_Loaded({
        $cfg = Get-StepCreaterConfig
        $captureHandler = {
            param($kind)
            try {
                Save-StepCreaterCapture -Session $Session -Kind $kind -StepId '' | Out-Null
                Update-UnassignedTrayUI -Session $Session -TrayPanel $c.UnassignedTray -OnAssign $assignToCurrent
                Save-WorkSession -Session $Session
                $window.Tag.Baseline = Get-ProcedureHash -Procedure $Session.Procedure
                Update-DirtyIndicator -Window $window
                $c.StatusText.Text = "キャプチャ保存 ($(Get-Date -Format HH:mm:ss))"
            } catch {
                $c.StatusText.Text = "キャプチャ失敗: $($_.Exception.Message)"
            }
        }.GetNewClosure()

        $hk = Register-StepCreaterHotkeys -Window $window -Combos @{
            full   = $cfg.hotkeys.fullScreen
            window = $cfg.hotkeys.window
            rect   = $cfg.hotkeys.rect
        } -OnFull   { & $captureHandler 'full'   } `
           -OnWindow { & $captureHandler 'window' } `
           -OnRect   { & $captureHandler 'rect'   }
        $window.Tag | Add-Member -NotePropertyName HotkeyHandle -NotePropertyValue $hk -Force
    }.GetNewClosure())

    $window.Add_Closed({
        if ($window.Tag.PSObject.Properties['HotkeyHandle'] -and $window.Tag.HotkeyHandle) {
            Unregister-StepCreaterHotkeys -Handle $window.Tag.HotkeyHandle
        }
    }.GetNewClosure())

    if ($NoShow) { return $window }
    [void]$window.ShowDialog()
    return $window
}

function Update-StepListUI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [WorkSession]$Session,
        [Parameter(Mandatory)] $ListBox
    )
    $ListBox.Items.Clear()
    foreach ($step in $Session.Procedure.Steps) {
        $item = "[{0}] {1}: {2}" -f $step.Status, $step.Id, $step.Title
        [void]$ListBox.Items.Add($item)
    }
}

function Update-DirtyIndicator {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Window)
    $tag = $Window.Tag
    if (-not $tag) { return }
    $current = Get-ProcedureHash -Procedure $tag.Session.Procedure
    $isDirty = ($current -ne $tag.Baseline)
    $tag.Controls.DirtyText.Text = if ($isDirty) { '● 未保存' } else { '' }
}

function Save-WorkSession {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [WorkSession]$Session)
    $Session.Procedure.Updated = Get-Date
    $md = Write-Procedure -Procedure $Session.Procedure
    $mdPath = Join-Path $Session.WorkFolderPath 'procedure.md'
    Set-Content -LiteralPath $mdPath -Value $md -Encoding UTF8
}

function Initialize-StepCreaterWin32 {
    [CmdletBinding()]
    param()

    if ('StepCreater.Win32' -as [type]) { return }

    $signature = @'
using System;
using System.Runtime.InteropServices;

namespace StepCreater {
    public static class Win32 {
        [DllImport("user32.dll")]
        public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll")]
        public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern IntPtr GetDesktopWindow();

        [DllImport("dwmapi.dll")]
        public static extern int DwmGetWindowAttribute(IntPtr hWnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT {
            public int Left; public int Top; public int Right; public int Bottom;
            public int Width  { get { return Right - Left; } }
            public int Height { get { return Bottom - Top; } }
        }

        public const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
        public const uint MOD_ALT     = 0x1;
        public const uint MOD_CONTROL = 0x2;
        public const uint MOD_SHIFT   = 0x4;
        public const uint MOD_WIN     = 0x8;
        public const int  WM_HOTKEY   = 0x0312;
    }
}
'@

    Add-Type -TypeDefinition $signature -ReferencedAssemblies System.Windows.Forms
}

function Get-CaptureFileName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [ValidateSet('full','window','rect')] [string]$Kind,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$StepId,
        [Parameter()] [datetime]$Timestamp = (Get-Date)
    )
    $stamp  = $Timestamp.ToString('yyyy-MM-dd_HHmmss')
    $suffix = if ([string]::IsNullOrEmpty($StepId)) { 'unassigned' } else { 'step' + $StepId }
    $kindTag = switch ($Kind) { 'full' { '' } 'window' { '_win' } 'rect' { '_rect' } }
    return "${stamp}_${suffix}${kindTag}.png"
}

function Invoke-FullScreenCapture {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$OutputPath)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    } finally {
        $g.Dispose()
    }
    $dir = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    return $OutputPath
}

function Invoke-ActiveWindowCapture {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$OutputPath)

    Initialize-StepCreaterWin32
    Add-Type -AssemblyName System.Drawing

    $hwnd = [StepCreater.Win32]::GetForegroundWindow()
    if ($hwnd -eq [IntPtr]::Zero) { throw 'No foreground window.' }

    $rect = New-Object StepCreater.Win32+RECT
    $rectSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type]([StepCreater.Win32+RECT]))
    $hr = [StepCreater.Win32]::DwmGetWindowAttribute(
        $hwnd,
        [StepCreater.Win32]::DWMWA_EXTENDED_FRAME_BOUNDS,
        [ref]$rect,
        $rectSize
    )
    if ($hr -ne 0) {
        [StepCreater.Win32]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
    }

    $w = $rect.Width; $h = $rect.Height
    if ($w -le 0 -or $h -le 0) { throw "Invalid window rect ($w x $h)." }

    $bitmap = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $g.CopyFromScreen(
            (New-Object System.Drawing.Point $rect.Left, $rect.Top),
            [System.Drawing.Point]::Empty,
            (New-Object System.Drawing.Size $w, $h)
        )
    } finally {
        $g.Dispose()
    }
    $dir = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    return $OutputPath
}
function ConvertTo-HotkeySpec {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string]$Combo)

    $tokens = $Combo -split '\+' | ForEach-Object { $_.Trim().ToLowerInvariant() }
    $mods = 0
    $keyToken = $null
    foreach ($t in $tokens) {
        switch ($t) {
            'ctrl'    { $mods = $mods -bor 0x2 }
            'control' { $mods = $mods -bor 0x2 }
            'shift'   { $mods = $mods -bor 0x4 }
            'alt'     { $mods = $mods -bor 0x1 }
            'win'     { $mods = $mods -bor 0x8 }
            default   { $keyToken = $t }
        }
    }
    if (-not $keyToken) { throw "No key in combo '$Combo'." }

    $vk = switch -Regex ($keyToken) {
        '^f([1-9]|1[0-2])$' { 0x6F + [int]$matches[1] }
        '^[a-z]$'           { [int][char]([string]$keyToken).ToUpperInvariant() }
        '^[0-9]$'           { [int][char][string]$keyToken }
        default             { throw "Unknown key '$keyToken' in combo '$Combo'." }
    }
    return [pscustomobject]@{ Modifiers = $mods; VKey = $vk }
}

function Register-StepCreaterHotkeys {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] $Window,
        [Parameter(Mandatory)] [hashtable]$Combos,
        [Parameter(Mandatory)] [scriptblock]$OnFull,
        [Parameter(Mandatory)] [scriptblock]$OnWindow,
        [Parameter(Mandatory)] [scriptblock]$OnRect
    )
    Initialize-StepCreaterWin32

    $helper = [System.Windows.Interop.WindowInteropHelper]::new($Window)
    $hwnd = $helper.Handle
    if ($hwnd -eq [IntPtr]::Zero) {
        throw 'Window has no HWND yet. Call after Window is loaded (e.g. inside Window.Loaded handler).'
    }
    $src = [System.Windows.Interop.HwndSource]::FromHwnd($hwnd)

    # Referenced inside $hook closure; touch here to satisfy PSReviewUnusedParameter
    $null = $OnFull, $OnWindow, $OnRect

    $registrations = @{}
    $idCounter = 1000
    foreach ($kind in 'full','window','rect') {
        $combo = $Combos[$kind]
        if (-not $combo) { continue }
        $spec = ConvertTo-HotkeySpec -Combo $combo
        $id = $idCounter++
        $ok = [StepCreater.Win32]::RegisterHotKey($hwnd, $id, [uint32]$spec.Modifiers, [uint32]$spec.VKey)
        if (-not $ok) {
            Write-Warning "Hotkey '$combo' could not be registered (already in use?)."
            continue
        }
        $registrations[$id] = @{ Kind = $kind; Combo = $combo }
    }

    $hook = {
        param($hwndArg, $msg, $wparam, $lparam, $handled)
        $null = $hwndArg, $lparam  # required by HwndSourceHook signature; not used
        if ($msg -ne [StepCreater.Win32]::WM_HOTKEY) { return [IntPtr]::Zero }
        $id = [int]$wparam
        $reg = $registrations[$id]
        if (-not $reg) { return [IntPtr]::Zero }
        switch ($reg.Kind) {
            'full'   { & $OnFull   }
            'window' { & $OnWindow }
            'rect'   { & $OnRect   }
        }
        $handled.Value = $true
        return [IntPtr]::Zero
    }.GetNewClosure()

    $src.AddHook($hook)

    return [pscustomobject]@{
        Hwnd          = $hwnd
        Registrations = $registrations
        Source        = $src
        Hook          = $hook
    }
}

function Unregister-StepCreaterHotkeys {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Handle)
    Initialize-StepCreaterWin32
    foreach ($id in $Handle.Registrations.Keys) {
        [StepCreater.Win32]::UnregisterHotKey($Handle.Hwnd, [int]$id) | Out-Null
    }
    if ($Handle.Source -and $Handle.Hook) {
        $Handle.Source.RemoveHook($Handle.Hook)
    }
}

function Add-CaptureAnnotation {
    [CmdletBinding()]
    [OutputType([System.Drawing.Bitmap])]
    param(
        [Parameter(Mandatory)] [System.Drawing.Bitmap]$SourceBitmap,
        [Parameter(Mandatory)] [System.Drawing.Point]$MousePosition,
        [Parameter()] [string]$Caption     = '',
        [Parameter()] [int]$CaptionHeight  = 24,
        [Parameter()] [int]$CircleRadius   = 20
    )
    Add-Type -AssemblyName System.Drawing

    $newH = $SourceBitmap.Height + $CaptionHeight
    $out = New-Object System.Drawing.Bitmap $SourceBitmap.Width, $newH
    $g = [System.Drawing.Graphics]::FromImage($out)
    try {
        $g.DrawImage($SourceBitmap, 0, 0, $SourceBitmap.Width, $SourceBitmap.Height)

        if ($MousePosition.X -ge 0 -and $MousePosition.Y -ge 0 `
            -and $MousePosition.X -le $SourceBitmap.Width `
            -and $MousePosition.Y -le $SourceBitmap.Height) {
            $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(180, 220, 0, 0)), 3
            try {
                $r = $CircleRadius
                $g.DrawEllipse($pen, $MousePosition.X - $r, $MousePosition.Y - $r, $r * 2, $r * 2)
            } finally { $pen.Dispose() }
        }

        if ($CaptionHeight -gt 0 -and -not [string]::IsNullOrEmpty($Caption)) {
            $bgBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(220, 0, 0, 0))
            $fgBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
            $font    = New-Object System.Drawing.Font 'Consolas', 10, ([System.Drawing.FontStyle]::Regular)
            try {
                $g.FillRectangle($bgBrush, 0, $SourceBitmap.Height, $SourceBitmap.Width, $CaptionHeight)
                $g.DrawString($Caption, $font, $fgBrush, 8, $SourceBitmap.Height + 4)
            } finally {
                $bgBrush.Dispose(); $fgBrush.Dispose(); $font.Dispose()
            }
        }
    } finally {
        $g.Dispose()
    }
    return $out
}

function Invoke-RectSelectionCapture {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$OutputPath)

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms

    $xamlPath = Join-Path $PSScriptRoot 'ui/RectSelector.xaml'
    $xml = [xml](Get-Content -LiteralPath $xamlPath -Raw)
    $reader = [System.Xml.XmlNodeReader]::new($xml)
    $win = [Windows.Markup.XamlReader]::Load($reader)

    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $win.Left   = $bounds.Left
    $win.Top    = $bounds.Top
    $win.Width  = $bounds.Width
    $win.Height = $bounds.Height

    $rect = $win.FindName('SelRect')

    $state = [pscustomobject]@{ Down = $false; StartX = 0; StartY = 0; Cancelled = $false }

    $win.Add_MouseLeftButtonDown({
        $p = $_.GetPosition($win)
        $state.Down = $true
        $state.StartX = $p.X; $state.StartY = $p.Y
        [System.Windows.Controls.Canvas]::SetLeft($rect, $p.X)
        [System.Windows.Controls.Canvas]::SetTop($rect, $p.Y)
        $rect.Width = 0; $rect.Height = 0
        $rect.Visibility = 'Visible'
    }.GetNewClosure())

    $win.Add_MouseMove({
        if (-not $state.Down) { return }
        $p = $_.GetPosition($win)
        $x = [Math]::Min($state.StartX, $p.X); $y = [Math]::Min($state.StartY, $p.Y)
        [System.Windows.Controls.Canvas]::SetLeft($rect, $x)
        [System.Windows.Controls.Canvas]::SetTop($rect, $y)
        $rect.Width  = [Math]::Abs($p.X - $state.StartX)
        $rect.Height = [Math]::Abs($p.Y - $state.StartY)
    }.GetNewClosure())

    $win.Add_MouseLeftButtonUp({
        if (-not $state.Down) { return }
        $state.Down = $false
        $win.Close()
    }.GetNewClosure())

    $win.Add_KeyDown({
        if ($_.Key -eq [System.Windows.Input.Key]::Escape) {
            $state.Cancelled = $true
            $win.Close()
        }
    }.GetNewClosure())

    [void]$win.ShowDialog()

    if ($state.Cancelled -or $rect.Width -lt 4 -or $rect.Height -lt 4) {
        return $null
    }

    $x = [int]([System.Windows.Controls.Canvas]::GetLeft($rect)) + $bounds.Left
    $y = [int]([System.Windows.Controls.Canvas]::GetTop($rect))  + $bounds.Top
    $w = [int]$rect.Width
    $h = [int]$rect.Height

    $bitmap = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $g.CopyFromScreen(
            (New-Object System.Drawing.Point $x, $y),
            [System.Drawing.Point]::Empty,
            (New-Object System.Drawing.Size $w, $h)
        )
    } finally { $g.Dispose() }
    $dir = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    return $OutputPath
}

function Save-StepCreaterCapture {
    [CmdletBinding()]
    [OutputType([ScreenshotRef])]
    param(
        [Parameter(Mandatory)] [WorkSession]$Session,
        [Parameter(Mandatory)] [ValidateSet('full','window','rect')] [string]$Kind,
        [Parameter()] [string]$StepId = ''
    )
    Initialize-StepCreaterWin32
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms

    $cfg = Get-StepCreaterConfig
    $now = Get-Date
    $name = Get-CaptureFileName -Kind $Kind -StepId $StepId -Timestamp $now
    $imagesDir = Join-Path $Session.WorkFolderPath 'images'
    if (-not (Test-Path -LiteralPath $imagesDir)) {
        New-Item -ItemType Directory -Path $imagesDir -Force | Out-Null
    }
    $tmpRaw = Join-Path $env:TEMP ("sc-raw-" + [guid]::NewGuid() + ".png")
    try {
        $captured = switch ($Kind) {
            'full'   { Invoke-FullScreenCapture    -OutputPath $tmpRaw }
            'window' { Invoke-ActiveWindowCapture  -OutputPath $tmpRaw }
            'rect'   { Invoke-RectSelectionCapture -OutputPath $tmpRaw }
        }
        if (-not $captured) { return $null }

        $finalPath = Join-Path $imagesDir $name
        if ($cfg.annotationEnabled) {
            $title = New-Object System.Text.StringBuilder 256
            $hwnd = [StepCreater.Win32]::GetForegroundWindow()
            [StepCreater.Win32]::GetWindowText($hwnd, $title, $title.Capacity) | Out-Null
            $caption = ('{0} | {1}' -f $title.ToString(), $now.ToString('HH:mm:ss'))
            $cursor = [System.Windows.Forms.Cursor]::Position
            $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
            $mp = New-Object System.Drawing.Point ($cursor.X - $vs.Left), ($cursor.Y - $vs.Top)

            $src = [System.Drawing.Bitmap]::FromFile($tmpRaw)
            try {
                $annot = Add-CaptureAnnotation -SourceBitmap $src -MousePosition $mp -Caption $caption
                $annot.Save($finalPath, [System.Drawing.Imaging.ImageFormat]::Png)
                $annot.Dispose()
            } finally { $src.Dispose() }
        } else {
            Move-Item -LiteralPath $tmpRaw -Destination $finalPath -Force
        }
    } finally {
        if (Test-Path -LiteralPath $tmpRaw) { Remove-Item -LiteralPath $tmpRaw -Force }
    }

    $ref = [ScreenshotRef]::new($name, $now, $Kind)
    if ([string]::IsNullOrEmpty($StepId)) {
        $Session.UnassignedScreenshots.Add($ref) | Out-Null
    } else {
        $idx = -1
        for ($i = 0; $i -lt $Session.Procedure.Steps.Count; $i++) {
            if ($Session.Procedure.Steps[$i].Id -eq $StepId) { $idx = $i; break }
        }
        if ($idx -ge 0) {
            $Session.Procedure.Steps[$idx].Evidence.Add($ref) | Out-Null
        } else {
            $Session.UnassignedScreenshots.Add($ref) | Out-Null
        }
    }
    return $ref
}

function Update-UnassignedTrayUI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [WorkSession]$Session,
        [Parameter(Mandatory)] $TrayPanel,
        [Parameter(Mandatory)] [scriptblock]$OnAssign
    )
    Add-Type -AssemblyName PresentationFramework

    # $OnAssign is referenced inside closures below; touch here to satisfy PSReviewUnusedParameter
    $null = $OnAssign

    $TrayPanel.Children.Clear()
    foreach ($ref in $Session.UnassignedScreenshots) {
        $path = Join-Path $Session.WorkFolderPath ("images/" + $ref.FileName)
        if (-not (Test-Path -LiteralPath $path)) { continue }

        $btn = New-Object System.Windows.Controls.Button
        $btn.Width = 120; $btn.Height = 80; $btn.Margin = '4'
        $btn.ToolTip = $ref.FileName

        $img = New-Object System.Windows.Controls.Image
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.CacheOption = 'OnLoad'
        $bmp.UriSource = (New-Object System.Uri $path)
        $bmp.DecodePixelWidth = 240
        $bmp.EndInit()
        $img.Source = $bmp
        $img.Stretch = 'Uniform'
        $btn.Content = $img

        $refLocal = $ref
        $btn.Add_Click({ & $OnAssign $refLocal }.GetNewClosure())
        $TrayPanel.Children.Add($btn) | Out-Null
    }
}

function Get-ProgressLabel {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [ProcedureDoc]$Procedure)
    $total = $Procedure.Steps.Count
    $done    = (@($Procedure.Steps | Where-Object { $_.Status -eq 'done'    })).Count
    $ng      = (@($Procedure.Steps | Where-Object { $_.Status -eq 'ng'      })).Count
    $skipped = (@($Procedure.Steps | Where-Object { $_.Status -eq 'skipped' })).Count
    $touched = $done + $ng + $skipped
    return ('進捗: {0} / {1} (完了 {2} / NG {3} / スキップ {4})' -f $touched, $total, $done, $ng, $skipped)
}

function Set-StepStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [Step]$Step,
        [Parameter(Mandatory)] [ValidateSet('pending','done','ng','skipped')] [string]$Status
    )
    $now = Get-Date
    if ($Status -eq 'pending') {
        $Step.Status   = 'pending'
        $Step.Started  = $null
        $Step.Finished = $null
        return
    }
    if (-not $Step.Started) { $Step.Started = $now }
    $Step.Finished = $now
    $Step.Status   = $Status
}

function Update-ExecChecklistUI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [WorkSession]$Session,
        [Parameter(Mandatory)] $ListBox,
        [Parameter(Mandatory)] $ProgressLabel
    )
    $ListBox.Items.Clear()
    foreach ($step in $Session.Procedure.Steps) {
        $mark = switch ($step.Status) {
            'done'    { '☑' }
            'ng'      { '⚠' }
            'skipped' { '↷' }
            default   { '☐' }
        }
        [void]$ListBox.Items.Add(('{0} {1}: {2}' -f $mark, $step.Id, $step.Title))
    }
    $ProgressLabel.Text = Get-ProgressLabel -Procedure $Session.Procedure
}
