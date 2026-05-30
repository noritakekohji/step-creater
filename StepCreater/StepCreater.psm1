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
    [System.Collections.Generic.List[ScreenshotRef]] $ProcedureImages
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
        $this.ProcedureImages     = [System.Collections.Generic.List[ScreenshotRef]]::new()
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

function Get-ImageBareName {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$FileName)
    if ([string]::IsNullOrEmpty($FileName)) { return '' }
    # Split-Path -Leaf strips any directory prefix (images/, img\, etc.)
    return (Split-Path -Path ($FileName -replace '/', '\') -Leaf)
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

        if ($step.ProcedureImages.Count -gt 0) {
            [void]$sb.Append("### 手順画像$nl")
            foreach ($pi in $step.ProcedureImages) {
                [void]$sb.Append("![](images/$(Get-ImageBareName $pi.FileName))$nl")
            }
            [void]$sb.Append($nl)
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
                [void]$sb.Append("![](images/$(Get-ImageBareName $ev.FileName))$nl")
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
                '### 手順画像'   {
                    foreach ($m in [regex]::Matches($content, '!\[[^\]]*\]\(([^)]+)\)')) {
                        $step.ProcedureImages.Add(
                            [ScreenshotRef]::new((Get-ImageBareName $m.Groups[1].Value), [datetime]::MinValue, 'full')
                        ) | Out-Null
                    }
                }
                '### エビデンス'   {
                    foreach ($m in [regex]::Matches($content, '!\[[^\]]*\]\(([^)]+)\)')) {
                        $step.Evidence.Add(
                            [ScreenshotRef]::new((Get-ImageBareName $m.Groups[1].Value), [datetime]::MinValue, 'full')
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
        'MenuNew','MenuOpen','MenuSave','MenuExportHtml','MenuExit','MenuTemplates','MenuSettings','MenuDashboard',
        'StatusText','DirtyText',
        'TabEdit','TabExecute','TabCapture',
        'WorkfolderPath','BtnSave',
        'StepList','BtnAdd','BtnDelete','BtnUp','BtnDown',
        'TxtTitle','CboStatus','TxtBody','TxtCommand','TxtExpected','TxtNote',
        'UnassignedTray',
        'EditPanel','ExecutePanel',
        'ProgressLabel','ExecChecklist',
        'ExecStepTitle','ExecBody','ExecCommand','BtnCopyCommand','ExecExpected',
        'ExecEvidenceTray','BtnComplete','BtnNg','BtnSkip',
        'EditEvidenceTray','BtnAddEvidence',
        'BtnAddSelected','UnassignedLabel','ExecProcImageTray'
    )) { $c[$name] = $window.FindName($name) }

    $c.WorkfolderPath.Text = $Session.WorkFolderPath
    $window.Title          = "StepCreater - $($Session.Procedure.Title)"
    Update-StepListUI -Session $Session -ListBox $c.StepList

    # Editor sync state
    $editorState = [pscustomobject]@{
        CurrentStepIndex = -1
        SuppressEdit     = $false
    }

    $window.Tag = [pscustomobject]@{
        Session  = $Session
        Controls = $c
        Baseline = (Get-ProcedureHash -Procedure $Session.Procedure)
    }

    # ---- Hashtable boxes (defined early so closures can reference them) ----

    # Selection state for unassigned tray
    $selBox = @{ Ref = $null }

    # Unassigned tray refresh box
    $traySelectBox = @{}
    $traySelectBox.Refresh = {
        Update-UnassignedTrayUI -Session $Session -TrayPanel $c.UnassignedTray -OnSelect $traySelectBox.OnSelect -SelectedRef $selBox.Ref
    }.GetNewClosure()
    $traySelectBox.OnSelect = {
        param($ref)
        $selBox.Ref = $ref
        & $traySelectBox.Refresh
    }.GetNewClosure()

    # Edit-mode procedure image tray box
    $editProcBox = @{}
    $editProcBox.Refresh = {
        Update-StepImageTray -Session $Session -StepIndex $c.StepList.SelectedIndex -TrayPanel $c.EditEvidenceTray -Kind procedure -OnRemove $editProcBox.OnRemove
    }.GetNewClosure()
    $editProcBox.OnRemove = {
        param($imgRef)
        $idx = $c.StepList.SelectedIndex
        if ($idx -lt 0) { return }
        $Session.Procedure.Steps[$idx].ProcedureImages.Remove($imgRef) | Out-Null
        $Session.UnassignedScreenshots.Add($imgRef) | Out-Null
        & $editProcBox.Refresh
        & $traySelectBox.Refresh
        Save-WorkSession -Session $Session
        $window.Tag.Baseline = Get-ProcedureHash -Procedure $Session.Procedure
        Update-DirtyIndicator -Window $window
    }.GetNewClosure()

    # Execute-mode evidence tray box
    $execEvidBox = @{}
    $execEvidBox.Refresh = {
        $idx = $c.ExecChecklist.SelectedIndex
        if ($idx -lt 0) {
            $c.ExecEvidenceTray.Children.Clear()
            return
        }
        Update-StepImageTray -Session $Session -StepIndex $idx -TrayPanel $c.ExecEvidenceTray -Kind evidence -OnRemove $execEvidBox.OnRemove
        Update-StepImageTray -Session $Session -StepIndex $idx -TrayPanel $c.ExecProcImageTray -Kind procedure -ReadOnly
    }.GetNewClosure()
    $execEvidBox.OnRemove = {
        param($imgRef)
        $idx = $c.ExecChecklist.SelectedIndex
        if ($idx -lt 0) { return }
        $Session.Procedure.Steps[$idx].Evidence.Remove($imgRef) | Out-Null
        $Session.UnassignedScreenshots.Add($imgRef) | Out-Null
        & $execEvidBox.Refresh
        & $traySelectBox.Refresh
        Save-WorkSession -Session $Session
        $window.Tag.Baseline = Get-ProcedureHash -Procedure $Session.Procedure
        Update-DirtyIndicator -Window $window
    }.GetNewClosure()

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
            $c.EditEvidenceTray.Children.Clear()
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
        & $editProcBox.Refresh
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

    $c.BtnAddEvidence.Add_Click({
        $idx = $c.StepList.SelectedIndex
        if ($idx -lt 0) {
            [System.Windows.MessageBox]::Show(
                '先にStepを選択してください。', '情報', 'OK', 'Information') | Out-Null
            return
        }
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = [System.Windows.Forms.OpenFileDialog]::new()
        $dlg.Filter = '画像ファイル (*.png;*.jpg;*.jpeg;*.gif;*.bmp)|*.png;*.jpg;*.jpeg;*.gif;*.bmp|すべてのファイル|*.*'
        $dlg.Multiselect = $true
        if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

        $imagesDir = Join-Path $Session.WorkFolderPath 'images'
        if (-not (Test-Path -LiteralPath $imagesDir)) {
            New-Item -ItemType Directory -Path $imagesDir -Force | Out-Null
        }
        $step = $Session.Procedure.Steps[$idx]
        foreach ($src in $dlg.FileNames) {
            $stamp = (Get-Date).ToString('yyyy-MM-dd_HHmmss')
            $ext = [System.IO.Path]::GetExtension($src)
            $name = "${stamp}_step$($step.Id)_manual$ext"
            $n = 1
            while (Test-Path -LiteralPath (Join-Path $imagesDir $name)) {
                $name = "${stamp}_step$($step.Id)_manual_$n$ext"
                $n++
            }
            $dst = Join-Path $imagesDir $name
            Copy-Item -LiteralPath $src -Destination $dst -Force
            $ref = [ScreenshotRef]::new($name, (Get-Date), 'full')
            $step.ProcedureImages.Add($ref) | Out-Null
        }
        & $editProcBox.Refresh
        Save-WorkSession -Session $Session
        $window.Tag.Baseline = Get-ProcedureHash -Procedure $Session.Procedure
        Update-DirtyIndicator -Window $window
        $c.StatusText.Text = "$($dlg.FileNames.Count) 個の画像を Step $($step.Id) に追加しました。"
    }.GetNewClosure())

    # BtnAddSelected: assign selected unassigned image to current step (mode-dependent)
    $c.BtnAddSelected.Add_Click({
        if (-not $selBox.Ref) {
            [System.Windows.MessageBox]::Show('未割当スクリーンショットを1つ選択してください。','情報','OK','Information') | Out-Null
            return
        }
        $ref = $selBox.Ref
        if ($Session.Mode -eq 'Execute') {
            $idx = $c.ExecChecklist.SelectedIndex
            if ($idx -lt 0) {
                [System.Windows.MessageBox]::Show('割当先のStepを選択してください。','情報','OK','Information') | Out-Null
                return
            }
            $Session.UnassignedScreenshots.Remove($ref) | Out-Null
            $Session.Procedure.Steps[$idx].Evidence.Add($ref) | Out-Null
            & $execEvidBox.Refresh
        } else {
            $idx = $c.StepList.SelectedIndex
            if ($idx -lt 0) {
                [System.Windows.MessageBox]::Show('割当先のStepを選択してください。','情報','OK','Information') | Out-Null
                return
            }
            $Session.UnassignedScreenshots.Remove($ref) | Out-Null
            $Session.Procedure.Steps[$idx].ProcedureImages.Add($ref) | Out-Null
            & $editProcBox.Refresh
        }
        $selBox.Ref = $null
        & $traySelectBox.Refresh
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
    $c.MenuExportHtml.Add_Click({
        Save-WorkSession -Session $Session
        $htmlPath = Join-Path $Session.WorkFolderPath 'procedure.html'
        $html = ConvertTo-ProcedureHtml -Procedure $Session.Procedure
        Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8
        $c.StatusText.Text = "HTML出力: $htmlPath"
        $r = [System.Windows.MessageBox]::Show(
            "出力しました:`n$htmlPath`n`nブラウザで開きますか?",
            'HTML出力', 'YesNo', 'Information')
        if ($r -eq 'Yes') { Start-Process $htmlPath }
    }.GetNewClosure())
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

    # Initial render of unassigned tray
    & $traySelectBox.Refresh

    # ---- Execute mode helpers ----
    $loadExecStep = {
        param($idx)
        if ($idx -lt 0 -or $idx -ge $Session.Procedure.Steps.Count) {
            $c.ExecStepTitle.Text = ''
            $c.ExecBody.Text      = ''
            $c.ExecCommand.Text   = ''
            $c.ExecExpected.Text  = ''
            $c.ExecEvidenceTray.Children.Clear()
            $c.ExecProcImageTray.Children.Clear()
            return
        }
        $step = $Session.Procedure.Steps[$idx]
        $c.ExecStepTitle.Text = "Step $($step.Id): $($step.Title)"
        $c.ExecBody.Text      = $step.BodyMarkdown
        $c.ExecCommand.Text   = $step.Command
        $c.ExecExpected.Text  = $step.ExpectedResult

        Update-StepImageTray -Session $Session -StepIndex $idx -TrayPanel $c.ExecProcImageTray -Kind procedure -ReadOnly
        Update-StepImageTray -Session $Session -StepIndex $idx -TrayPanel $c.ExecEvidenceTray -Kind evidence -OnRemove $execEvidBox.OnRemove
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

    $c.BtnCopyCommand.Add_Click({
        $idx = $c.ExecChecklist.SelectedIndex
        if ($idx -lt 0) { return }
        $cmd = $Session.Procedure.Steps[$idx].Command
        if ([string]::IsNullOrWhiteSpace($cmd)) { return }
        [System.Windows.Clipboard]::SetText($cmd)
        $c.StatusText.Text = ('コマンドをコピーしました ({0})' -f (Get-Date -Format HH:mm:ss))
    }.GetNewClosure())

    $advanceTo = {
        param($newStatus, $moveNext)
        $idx = $c.ExecChecklist.SelectedIndex
        if ($idx -lt 0) { return }
        $step = $Session.Procedure.Steps[$idx]
        Set-StepStatus -Step $step -Status $newStatus
        Save-WorkSession -Session $Session
        $window.Tag.Baseline = Get-ProcedureHash -Procedure $Session.Procedure
        Update-DirtyIndicator -Window $window
        Update-ExecChecklistUI -Session $Session -ListBox $c.ExecChecklist -ProgressLabel $c.ProgressLabel
        if ($moveNext -and ($idx + 1) -lt $Session.Procedure.Steps.Count) {
            $c.ExecChecklist.SelectedIndex = $idx + 1
        } else {
            $c.ExecChecklist.SelectedIndex = $idx
            & $loadExecStep $idx
        }
    }.GetNewClosure()

    $c.BtnComplete.Add_Click({ & $advanceTo 'done'    $true  }.GetNewClosure())
    $c.BtnNg.Add_Click({       & $advanceTo 'ng'      $false }.GetNewClosure())
    $c.BtnSkip.Add_Click({     & $advanceTo 'skipped' $true  }.GetNewClosure())

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

    $captureHandler = {
        param($kind)
        try {
            $stepId = ''
            if ($Session.Mode -eq 'Execute' -and $c.ExecChecklist.SelectedIndex -ge 0) {
                $stepId = $Session.Procedure.Steps[$c.ExecChecklist.SelectedIndex].Id
            }
            Save-StepCreaterCapture -Session $Session -Kind $kind -StepId $stepId | Out-Null
            if ($Session.Mode -eq 'Execute') {
                Update-ExecChecklistUI -Session $Session -ListBox $c.ExecChecklist -ProgressLabel $c.ProgressLabel
                & $loadExecStep $c.ExecChecklist.SelectedIndex
            } else {
                & $traySelectBox.Refresh
            }
            Save-WorkSession -Session $Session
            $window.Tag.Baseline = Get-ProcedureHash -Procedure $Session.Procedure
            Update-DirtyIndicator -Window $window
            $c.StatusText.Text = "キャプチャ保存 ($(Get-Date -Format HH:mm:ss))"
        } catch {
            $c.StatusText.Text = "キャプチャ失敗: $($_.Exception.Message)"
        }
    }.GetNewClosure()

    $c.MenuSettings.Add_Click({
        if (-not (Show-SettingsDialog -Owner $window)) { return }

        if ($window.Tag.PSObject.Properties['HotkeyHandle'] -and $window.Tag.HotkeyHandle) {
            Unregister-StepCreaterHotkeys -Handle $window.Tag.HotkeyHandle
            $cfg2 = Get-StepCreaterConfig
            $hk = Register-StepCreaterHotkeys -Window $window -Combos @{
                full   = $cfg2.hotkeys.fullScreen
                window = $cfg2.hotkeys.window
                rect   = $cfg2.hotkeys.rect
            } -OnFull   { & $captureHandler 'full'   } `
               -OnWindow { & $captureHandler 'window' } `
               -OnRect   { & $captureHandler 'rect'   }
            $window.Tag.HotkeyHandle = $hk
        }
        $c.StatusText.Text = "設定を更新しました ($(Get-Date -Format HH:mm:ss))"
    }.GetNewClosure())

    $c.MenuDashboard.Add_Click({
        # Pass the current workfolder's parent as default
        $parent = Split-Path -Parent $Session.WorkFolderPath
        Show-DashboardWindow -Owner $window -InitialParent $parent
    }.GetNewClosure())

    $window.Add_Loaded({
        try {
            $cfg = Get-StepCreaterConfig
            $hk = Register-StepCreaterHotkeys -Window $window -Combos @{
                full   = $cfg.hotkeys.fullScreen
                window = $cfg.hotkeys.window
                rect   = $cfg.hotkeys.rect
            } -OnFull   { & $captureHandler 'full'   } `
               -OnWindow { & $captureHandler 'window' } `
               -OnRect   { & $captureHandler 'rect'   }
            $window.Tag | Add-Member -NotePropertyName HotkeyHandle -NotePropertyValue $hk -Force
        } catch {
            $c.StatusText.Text = "ホットキー登録失敗: $($_.Exception.Message)"
        }
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

function Save-BitmapPng {
    <#
    .SYNOPSIS
      Saves a bitmap as PNG to a file path, bypassing GDI+'s issue with non-ASCII paths.
      Retries briefly on IOException (file in use), useful when a transient antivirus
      scan or thumbnail render briefly holds the destination handle.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Drawing.Bitmap]$Bitmap,
        [Parameter(Mandatory)] [string]$Path
    )
    Add-Type -AssemblyName System.Drawing
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $ms = New-Object System.IO.MemoryStream
    try {
        $Bitmap.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $bytes = $ms.ToArray()
        $lastErr = $null
        for ($attempt = 1; $attempt -le 5; $attempt++) {
            try {
                [System.IO.File]::WriteAllBytes($Path, $bytes)
                return
            } catch [System.IO.IOException] {
                $lastErr = $_
                Start-Sleep -Milliseconds (50 * $attempt)
            }
        }
        throw $lastErr
    } finally {
        $ms.Dispose()
    }
}

function Read-BitmapNoLock {
    <#
    .SYNOPSIS
      Loads a Bitmap from a file WITHOUT holding the file handle.
      Bitmap.FromFile keeps the underlying file locked for the lifetime of the
      bitmap, which prevents subsequent writes to the same path. Reading the
      bytes into memory and constructing the bitmap from a stream avoids that.
    #>
    [CmdletBinding()]
    [OutputType([System.Drawing.Bitmap])]
    param([Parameter(Mandatory)] [string]$Path)
    Add-Type -AssemblyName System.Drawing
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $ms = New-Object System.IO.MemoryStream (,$bytes)
    return [System.Drawing.Bitmap]::FromStream($ms)
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
    Save-BitmapPng -Bitmap $bitmap -Path $OutputPath
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
    Save-BitmapPng -Bitmap $bitmap -Path $OutputPath
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
        try {
            if ($msg -ne [StepCreater.Win32]::WM_HOTKEY) { return [IntPtr]::Zero }
            $id = [int]$wparam
            $reg = $registrations[$id]
            if (-not $reg) { return [IntPtr]::Zero }
            switch ($reg.Kind) {
                'full'   { & $OnFull   }
                'window' { & $OnWindow }
                'rect'   { & $OnRect   }
            }
            # Mark handled. $handled is a [ref] bool from native; assign via .Value
            # with a safety net (some StrictMode configurations dislike .Value on PSReference).
            if ($null -ne $handled) {
                try { $handled.Value = $true } catch { Write-Verbose "hook: handled.Value assign failed: $_" }
            }
        } catch {
            # Never let the hook propagate an exception — it would kill the WPF message pump.
            Write-Verbose "hotkey hook exception: $_"
        }
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
    Save-BitmapPng -Bitmap $bitmap -Path $OutputPath
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

            $src = Read-BitmapNoLock -Path $tmpRaw
            try {
                $annot = Add-CaptureAnnotation -SourceBitmap $src -MousePosition $mp -Caption $caption
                Save-BitmapPng -Bitmap $annot -Path $finalPath
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
        [Parameter()] [scriptblock]$OnSelect = $null,
        [Parameter()] [ScreenshotRef]$SelectedRef = $null
    )
    Add-Type -AssemblyName PresentationFramework

    # If no callback supplied, install a no-op so click doesn't error.
    if ($null -eq $OnSelect) { $OnSelect = { param($r); $null = $r } }

    $TrayPanel.Children.Clear()
    foreach ($ref in $Session.UnassignedScreenshots) {
        $path = Join-Path $Session.WorkFolderPath ("images\" + (Get-ImageBareName $ref.FileName))
        if (-not (Test-Path -LiteralPath $path)) { continue }

        $btn = New-Object System.Windows.Controls.Button
        $btn.Width = 120; $btn.Height = 80; $btn.Margin = '4'
        $btn.ToolTip = $ref.FileName + ' (クリックで選択 / ダブルクリックでマスク編集)'

        # Highlight if selected
        if ($SelectedRef -and $ref.FileName -eq $SelectedRef.FileName) {
            $btn.BorderBrush = [System.Windows.Media.Brushes]::DodgerBlue
            $btn.BorderThickness = '3'
        }

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
        $btn.Add_Click({ & $OnSelect $refLocal }.GetNewClosure())
        $sessionLocal = $Session
        $btn.add_MouseDoubleClick({
            $p = Join-Path $sessionLocal.WorkFolderPath ("images\" + (Get-ImageBareName $refLocal.FileName))
            [void](Show-MaskEditor -ImagePath $p)
        }.GetNewClosure())
        $TrayPanel.Children.Add($btn) | Out-Null
    }
}

function Update-StepImageTray {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [WorkSession]$Session,
        [Parameter(Mandatory)] [int]$StepIndex,
        [Parameter(Mandatory)] $TrayPanel,
        [Parameter(Mandatory)] [ValidateSet('procedure','evidence')] [string]$Kind,
        [Parameter()] [switch]$ReadOnly,
        [Parameter()] [scriptblock]$OnRemove = $null
    )
    Add-Type -AssemblyName PresentationFramework
    if ($null -eq $OnRemove) { $OnRemove = { param($r); $null = $r } }

    $TrayPanel.Children.Clear()
    if ($StepIndex -lt 0 -or $StepIndex -ge $Session.Procedure.Steps.Count) { return }
    $step = $Session.Procedure.Steps[$StepIndex]
    $list = if ($Kind -eq 'procedure') { $step.ProcedureImages } else { $step.Evidence }

    foreach ($img in $list) {
        $path = Join-Path $Session.WorkFolderPath ("images\" + (Get-ImageBareName $img.FileName))
        if (-not (Test-Path -LiteralPath $path)) { continue }

        $cell = New-Object System.Windows.Controls.Grid
        $cell.Width = 110; $cell.Height = 80; $cell.Margin = '2'

        $btn = New-Object System.Windows.Controls.Button
        $btn.Padding = '0'
        $btn.ToolTip = $img.FileName + ' (ダブルクリックで拡大/マスク編集)'
        $imgCtl = New-Object System.Windows.Controls.Image
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit(); $bmp.CacheOption = 'OnLoad'
        $bmp.UriSource = (New-Object System.Uri $path)
        $bmp.DecodePixelWidth = 220
        $bmp.EndInit()
        $imgCtl.Source = $bmp; $imgCtl.Stretch = 'Uniform'
        $btn.Content = $imgCtl

        $imgLocal = $img
        $sessionLocal = $Session
        $btn.add_MouseDoubleClick({
            $p = Join-Path $sessionLocal.WorkFolderPath ("images\" + (Get-ImageBareName $imgLocal.FileName))
            [void](Show-MaskEditor -ImagePath $p)
        }.GetNewClosure())
        $cell.Children.Add($btn) | Out-Null

        if (-not $ReadOnly) {
            $delBtn = New-Object System.Windows.Controls.Button
            $delBtn.Content = 'x'
            $delBtn.Width = 18; $delBtn.Height = 18; $delBtn.Padding = '0'; $delBtn.FontSize = 10
            $delBtn.HorizontalAlignment = 'Right'; $delBtn.VerticalAlignment = 'Top'; $delBtn.Margin = '0,2,2,0'
            $delBtn.ToolTip = 'この画像を外す（ファイルは残ります）'
            $delBtn.Background = [System.Windows.Media.Brushes]::White
            $delBtn.add_Click({ & $OnRemove $imgLocal }.GetNewClosure())
            $cell.Children.Add($delBtn) | Out-Null
        }

        $TrayPanel.Children.Add($cell) | Out-Null
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

function Add-BlackoutRect {
    [CmdletBinding()]
    [OutputType([System.Drawing.Bitmap])]
    param(
        [Parameter(Mandatory)] [System.Drawing.Bitmap]$SourceBitmap,
        [Parameter(Mandatory)] [System.Drawing.Rectangle]$Rect
    )
    Add-Type -AssemblyName System.Drawing
    $out = New-Object System.Drawing.Bitmap $SourceBitmap
    $g = [System.Drawing.Graphics]::FromImage($out)
    try {
        $g.FillRectangle([System.Drawing.Brushes]::Black, $Rect)
    } finally { $g.Dispose() }
    return $out
}

function Show-MaskEditor {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string]$ImagePath
    )
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName System.Drawing

    if (-not (Test-Path -LiteralPath $ImagePath)) {
        throw "Image not found: $ImagePath"
    }

    $xamlPath = Join-Path $PSScriptRoot 'ui/MaskEditor.xaml'
    $xml = [xml](Get-Content -LiteralPath $xamlPath -Raw)
    $reader = [System.Xml.XmlNodeReader]::new($xml)
    $win = [Windows.Markup.XamlReader]::Load($reader)

    $imgCanvas    = $win.FindName('ImgCanvas')
    $overlay      = $win.FindName('OverlayCanvas')
    $dragRect     = $win.FindName('DragRect')
    $btnAddRect   = $win.FindName('BtnAddRect')
    $btnUndo      = $win.FindName('BtnUndo')
    $btnSave      = $win.FindName('BtnSave')
    $btnCancel    = $win.FindName('BtnCancel')

    $current = Read-BitmapNoLock -Path $ImagePath
    $history = New-Object System.Collections.Generic.Stack[System.Drawing.Bitmap]
    $state   = [pscustomobject]@{ Down = $false; X0 = 0; Y0 = 0; Saved = $false }

    $refreshImage = {
        $ms = New-Object System.IO.MemoryStream
        $current.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.StreamSource = $ms
        $bmp.CacheOption = 'OnLoad'
        $bmp.EndInit()
        $imgCanvas.Source = $bmp
        $imgCanvas.Width  = $current.Width
        $imgCanvas.Height = $current.Height
    }.GetNewClosure()
    & $refreshImage

    $overlay.Add_MouseLeftButtonDown({
        $p = $_.GetPosition($overlay)
        $state.Down = $true; $state.X0 = $p.X; $state.Y0 = $p.Y
        [System.Windows.Controls.Canvas]::SetLeft($dragRect, $p.X)
        [System.Windows.Controls.Canvas]::SetTop($dragRect, $p.Y)
        $dragRect.Width = 0; $dragRect.Height = 0
        $dragRect.Visibility = 'Visible'
    }.GetNewClosure())

    $overlay.Add_MouseMove({
        if (-not $state.Down) { return }
        $p = $_.GetPosition($overlay)
        $x = [Math]::Min($state.X0, $p.X); $y = [Math]::Min($state.Y0, $p.Y)
        [System.Windows.Controls.Canvas]::SetLeft($dragRect, $x)
        [System.Windows.Controls.Canvas]::SetTop($dragRect, $y)
        $dragRect.Width  = [Math]::Abs($p.X - $state.X0)
        $dragRect.Height = [Math]::Abs($p.Y - $state.Y0)
    }.GetNewClosure())

    $overlay.Add_MouseLeftButtonUp({ $state.Down = $false }.GetNewClosure())

    $btnAddRect.Add_Click({
        if ($dragRect.Width -lt 2 -or $dragRect.Height -lt 2) { return }
        $rect = New-Object System.Drawing.Rectangle `
            ([int][System.Windows.Controls.Canvas]::GetLeft($dragRect)), `
            ([int][System.Windows.Controls.Canvas]::GetTop($dragRect)), `
            ([int]$dragRect.Width), ([int]$dragRect.Height)
        $history.Push($current) | Out-Null
        $current = Add-BlackoutRect -SourceBitmap $current -Rect $rect
        & $refreshImage
        $dragRect.Visibility = 'Collapsed'
    }.GetNewClosure())

    $btnUndo.Add_Click({
        if ($history.Count -gt 0) {
            $current.Dispose()
            $current = $history.Pop()
            & $refreshImage
        }
    }.GetNewClosure())

    $btnSave.Add_Click({
        $imagesDir = Split-Path -Parent $ImagePath
        $originalsDir = Join-Path $imagesDir '.originals'
        if (-not (Test-Path -LiteralPath $originalsDir)) {
            New-Item -ItemType Directory -Path $originalsDir -Force | Out-Null
        }
        $originalDest = Join-Path $originalsDir (Split-Path -Leaf $ImagePath)
        if (-not (Test-Path -LiteralPath $originalDest)) {
            Copy-Item -LiteralPath $ImagePath -Destination $originalDest -Force
        }
        Save-BitmapPng -Bitmap $current -Path $ImagePath
        $state.Saved = $true
        $win.Close()
    }.GetNewClosure())

    $btnCancel.Add_Click({ $win.Close() }.GetNewClosure())

    $win.Add_KeyDown({
        if ($_.Key -eq [System.Windows.Input.Key]::Escape) { $win.Close() }
    }.GetNewClosure())

    [void]$win.ShowDialog()

    foreach ($b in $history) { $b.Dispose() }
    $current.Dispose()

    return $state.Saved
}

function Get-StepDuration {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [Step]$Step)
    if (-not $Step.Started -or -not $Step.Finished) { return '-' }
    $span = $Step.Finished - $Step.Started
    $hours = [int][math]::Floor($span.TotalHours)
    return ('{0:D2}:{1:D2}:{2:D2}' -f $hours, $span.Minutes, $span.Seconds)
}

function ConvertTo-ProcedureHtml {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [ProcedureDoc]$Procedure)

    $esc = {
        param($s)
        if ($null -eq $s) { return '' }
        $s = [string]$s
        $s = $s -replace '&', '&amp;'
        $s = $s -replace '<', '&lt;'
        $s = $s -replace '>', '&gt;'
        $s = $s -replace '"', '&quot;'
        return $s
    }

    $title = & $esc $Procedure.Title
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="ja"><head><meta charset="UTF-8">')
    [void]$sb.AppendLine("<title>$title</title>")
    [void]$sb.AppendLine('<style>')
    [void]$sb.AppendLine(@'
body { font-family: "Segoe UI", "Yu Gothic UI", sans-serif; max-width: 1000px; margin: 24px auto; padding: 0 16px; color: #222; }
h1 { border-bottom: 2px solid #444; padding-bottom: 8px; }
h2 { margin-top: 32px; border-bottom: 1px solid #ccc; padding-bottom: 4px; }
.meta { color: #666; font-size: 0.9em; }
.toc { background: #f7f7f7; padding: 12px 16px; border-radius: 4px; }
.toc ol { margin: 4px 0; }
.badge { display: inline-block; padding: 2px 8px; border-radius: 10px; font-size: 0.85em; margin-right: 8px; color: white; }
.badge-pending { background: #888; }
.badge-done    { background: #28a745; }
.badge-ng      { background: #dc3545; }
.badge-skipped { background: #ffc107; color: #222; }
.duration { color: #555; font-size: 0.9em; margin-left: 8px; }
.section { margin-top: 12px; }
.section h3 { margin: 8px 0 4px; font-size: 1em; color: #555; }
pre { background: #f4f4f4; padding: 10px; border-radius: 4px; font-family: Consolas, monospace; overflow-x: auto; }
.evidence img { max-width: 320px; max-height: 240px; margin: 6px; cursor: zoom-in; border: 1px solid #ddd; }
.procedure-images img { max-width: 320px; max-height: 240px; margin: 6px; cursor: zoom-in; border: 1px solid #ddd; }
.lightbox { display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.85); z-index: 100; justify-content: center; align-items: center; cursor: zoom-out; }
.lightbox.visible { display: flex; }
.lightbox img { max-width: 95%; max-height: 95%; }
@media print {
    .toc { page-break-after: always; }
    h2 { page-break-before: always; }
    .evidence img, .procedure-images img { max-width: 100%; max-height: none; page-break-inside: avoid; }
    .lightbox { display: none !important; }
}
'@)
    [void]$sb.AppendLine('</style></head><body>')

    [void]$sb.AppendLine("<h1>$title</h1>")
    $meta = @()
    if ($Procedure.Author)  { $meta += "Author: " + (& $esc $Procedure.Author) }
    if ($Procedure.Created) { $meta += "Created: " + $Procedure.Created.ToString('yyyy-MM-dd') }
    if ($Procedure.Updated) { $meta += "Updated: " + $Procedure.Updated.ToString('yyyy-MM-dd HH:mm') }
    if ($meta.Count -gt 0)  { [void]$sb.AppendLine('<div class="meta">' + ($meta -join ' | ') + '</div>') }

    [void]$sb.AppendLine('<div class="toc"><strong>目次</strong><ol>')
    foreach ($step in $Procedure.Steps) {
        $stTitle = & $esc $step.Title
        [void]$sb.AppendLine("<li><a href=`"#step-$($step.Id)`">Step $($step.Id): $stTitle</a></li>")
    }
    [void]$sb.AppendLine('</ol></div>')

    foreach ($step in $Procedure.Steps) {
        $stTitle = & $esc $step.Title
        $statusClass = "badge badge-" + $step.Status
        $statusLabel = switch ($step.Status) {
            'done'    { '完了' }
            'ng'      { 'NG' }
            'skipped' { 'スキップ' }
            default   { '未実施' }
        }
        $dur = Get-StepDuration -Step $step

        [void]$sb.AppendLine("<h2 id=`"step-$($step.Id)`">Step $($step.Id): $stTitle</h2>")
        [void]$sb.AppendLine("<span class=`"$statusClass`">$statusLabel</span><span class=`"duration`">作業時間: $dur</span>")

        if ($step.BodyMarkdown) {
            [void]$sb.AppendLine('<div class="section"><h3>手順</h3><div>' + (& $esc $step.BodyMarkdown) + '</div></div>')
        }
        if ($step.ProcedureImages.Count -gt 0) {
            [void]$sb.AppendLine('<div class="section procedure-images"><h3>手順画像</h3><div>')
            foreach ($pi in $step.ProcedureImages) {
                $src = & $esc ("images/" + (Get-ImageBareName $pi.FileName))
                [void]$sb.AppendLine("<img src=`"$src`" alt=`"$src`" onclick=`"sc_lb(this.src)`">")
            }
            [void]$sb.AppendLine('</div></div>')
        }
        if ($step.Command) {
            [void]$sb.AppendLine('<div class="section"><h3>実行コマンド</h3><pre>' + (& $esc $step.Command) + '</pre></div>')
        }
        if ($step.ExpectedResult) {
            [void]$sb.AppendLine('<div class="section"><h3>想定結果</h3><div>' + (& $esc $step.ExpectedResult) + '</div></div>')
        }
        if ($step.Evidence.Count -gt 0) {
            [void]$sb.AppendLine('<div class="section evidence"><h3>エビデンス</h3><div>')
            foreach ($ev in $step.Evidence) {
                $src = & $esc ("images/" + (Get-ImageBareName $ev.FileName))
                [void]$sb.AppendLine("<img src=`"$src`" alt=`"$src`" onclick=`"sc_lb(this.src)`">")
            }
            [void]$sb.AppendLine('</div></div>')
        }
        if ($step.Note) {
            [void]$sb.AppendLine('<div class="section"><h3>備考</h3><div>' + (& $esc $step.Note) + '</div></div>')
        }
    }

    [void]$sb.AppendLine('<div class="lightbox" id="sc_lightbox" onclick="this.classList.remove(''visible'')"><img id="sc_lb_img"></div>')
    [void]$sb.AppendLine('<script>function sc_lb(src){var lb=document.getElementById("sc_lightbox");document.getElementById("sc_lb_img").src=src;lb.classList.add("visible");}</script>')
    [void]$sb.AppendLine('</body></html>')

    return $sb.ToString()
}

function Show-SettingsDialog {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter()] $Owner)

    Add-Type -AssemblyName PresentationFramework

    $xamlPath = Join-Path $PSScriptRoot 'ui/SettingsDialog.xaml'
    $xml = [xml](Get-Content -LiteralPath $xamlPath -Raw)
    $reader = [System.Xml.XmlNodeReader]::new($xml)
    $win = [Windows.Markup.XamlReader]::Load($reader)
    if ($Owner) { $win.Owner = $Owner }

    $cfg = Get-StepCreaterConfig
    $txtFull   = $win.FindName('TxtHkFull')
    $txtWindow = $win.FindName('TxtHkWindow')
    $txtRect   = $win.FindName('TxtHkRect')
    $chkAnnot  = $win.FindName('ChkAnnotation')

    $txtFull.Text   = $cfg.hotkeys.fullScreen
    $txtWindow.Text = $cfg.hotkeys.window
    $txtRect.Text   = $cfg.hotkeys.rect
    $chkAnnot.IsChecked = [bool]$cfg.annotationEnabled

    $saved = [pscustomobject]@{ Ok = $false }

    $win.FindName('BtnOk').Add_Click({
        try {
            ConvertTo-HotkeySpec -Combo $txtFull.Text   | Out-Null
            ConvertTo-HotkeySpec -Combo $txtWindow.Text | Out-Null
            ConvertTo-HotkeySpec -Combo $txtRect.Text   | Out-Null
        } catch {
            [System.Windows.MessageBox]::Show("ホットキーの書式が不正です: $($_.Exception.Message)",
                'エラー', 'OK', 'Error') | Out-Null
            return
        }
        $cfg.hotkeys.fullScreen = $txtFull.Text
        $cfg.hotkeys.window     = $txtWindow.Text
        $cfg.hotkeys.rect       = $txtRect.Text
        $cfg.annotationEnabled  = [bool]$chkAnnot.IsChecked
        Set-StepCreaterConfig -Config $cfg
        $saved.Ok = $true
        $win.Close()
    }.GetNewClosure())

    $win.FindName('BtnCancel').Add_Click({ $win.Close() }.GetNewClosure())
    $win.Add_KeyDown({
        if ($_.Key -eq [System.Windows.Input.Key]::Escape) { $win.Close() }
    }.GetNewClosure())

    [void]$win.ShowDialog()
    return $saved.Ok
}

function Get-DashboardRows {
    <#
    .SYNOPSIS
      Scans a parent folder recursively for StepCreater workfolders (any directory
      containing procedure.md) and returns flat Step-level rows for dashboard display.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)] [string]$ParentFolder)

    if (-not (Test-Path -LiteralPath $ParentFolder)) {
        throw "Parent folder not found: $ParentFolder"
    }

    $rows = New-Object System.Collections.Generic.List[object]
    $mdFiles = Get-ChildItem -LiteralPath $ParentFolder -Filter 'procedure.md' -Recurse -File -ErrorAction SilentlyContinue

    foreach ($mdFile in $mdFiles) {
        $wfPath = $mdFile.DirectoryName
        $wfName = Split-Path -Leaf $wfPath
        $updated = $mdFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
        try {
            $doc = Read-Procedure -Path $mdFile.FullName
        } catch {
            # Surface a single failed row so the user knows
            $rows.Add([pscustomobject]@{
                Workfolder     = $wfName
                WorkfolderPath = $wfPath
                ProcedureTitle = "(読み込み失敗: $($_.Exception.Message))"
                StepNo         = 0
                StepId         = ''
                StepTitle      = ''
                Status         = 'error'
                Started        = ''
                Finished       = ''
                Duration       = ''
                Updated        = $updated
            }) | Out-Null
            continue
        }

        $no = 0
        foreach ($step in $doc.Steps) {
            $no++
            $started  = if ($step.Started)  { $step.Started.ToString('yyyy-MM-dd HH:mm:ss') }  else { '' }
            $finished = if ($step.Finished) { $step.Finished.ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
            $rows.Add([pscustomobject]@{
                Workfolder     = $wfName
                WorkfolderPath = $wfPath
                ProcedureTitle = $doc.Title
                StepNo         = $no
                StepId         = $step.Id
                StepTitle      = $step.Title
                Status         = $step.Status
                Started        = $started
                Finished       = $finished
                Duration       = (Get-StepDuration -Step $step)
                Updated        = $updated
            }) | Out-Null
        }
    }
    return $rows.ToArray()
}

function Export-DashboardCsv {
    <#
    .SYNOPSIS
      Exports dashboard rows to CSV with UTF-8 BOM (so Excel opens Japanese cleanly
      with a double-click).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]]$Rows,
        [Parameter(Mandatory)] [string]$Path
    )
    # Use ConvertTo-Csv (in-memory) then write with explicit UTF-8 BOM
    $csv = $Rows | ConvertTo-Csv -NoTypeInformation
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllLines($Path, $csv, $utf8Bom)
}

function Show-DashboardWindow {
    [CmdletBinding()]
    param(
        [Parameter()] $Owner,
        [Parameter()] [string]$InitialParent
    )
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName System.Windows.Forms

    $xamlPath = Join-Path $PSScriptRoot 'ui/DashboardWindow.xaml'
    $xml = [xml](Get-Content -LiteralPath $xamlPath -Raw)
    $reader = [System.Xml.XmlNodeReader]::new($xml)
    $win = [Windows.Markup.XamlReader]::Load($reader)
    if ($Owner) { $win.Owner = $Owner }

    $txtPath     = $win.FindName('TxtParentPath')
    $btnPick     = $win.FindName('BtnPickParent')
    $btnRescan   = $win.FindName('BtnRescan')
    $btnExport   = $win.FindName('BtnExportCsv')
    $grid        = $win.FindName('DashGrid')
    $status      = $win.FindName('DashStatus')

    $state = [pscustomobject]@{ Parent = $InitialParent; Rows = @() }

    $doScan = {
        if (-not $state.Parent -or -not (Test-Path -LiteralPath $state.Parent)) {
            $status.Text = '親フォルダを選択してください。'
            $grid.ItemsSource = $null
            return
        }
        try {
            $rows = Get-DashboardRows -ParentFolder $state.Parent
            $state.Rows = $rows
            $grid.ItemsSource = $rows
            $procCount = (@($rows | Select-Object -ExpandProperty WorkfolderPath -Unique)).Count
            $status.Text = "$procCount 件の手順書 / $($rows.Count) 行 を表示中。"
        } catch {
            $status.Text = "スキャン失敗: $($_.Exception.Message)"
        }
    }.GetNewClosure()

    if ($InitialParent) { $txtPath.Text = $InitialParent; & $doScan }

    $btnPick.Add_Click({
        $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dlg.Description = 'ダッシュボード対象の親フォルダを選択'
        if ($state.Parent) { $dlg.SelectedPath = $state.Parent }
        if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $state.Parent = $dlg.SelectedPath
        $txtPath.Text = $dlg.SelectedPath
        & $doScan
    }.GetNewClosure())

    $btnRescan.Add_Click({ & $doScan }.GetNewClosure())

    $btnExport.Add_Click({
        if (-not $state.Rows -or $state.Rows.Count -eq 0) {
            [System.Windows.MessageBox]::Show('出力する行がありません。','情報','OK','Information') | Out-Null
            return
        }
        $sfd = [System.Windows.Forms.SaveFileDialog]::new()
        $sfd.Filter = 'CSV (*.csv)|*.csv'
        $sfd.FileName = ('dashboard_' + (Get-Date -Format 'yyyy-MM-dd_HHmmss') + '.csv')
        if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        try {
            Export-DashboardCsv -Rows $state.Rows -Path $sfd.FileName
            $status.Text = "CSV出力: $($sfd.FileName)"
        } catch {
            [System.Windows.MessageBox]::Show("CSV出力に失敗: $($_.Exception.Message)",'エラー','OK','Error') | Out-Null
        }
    }.GetNewClosure())

    $win.Add_KeyDown({
        if ($_.Key -eq [System.Windows.Input.Key]::Escape) { $win.Close() }
    }.GetNewClosure())

    [void]$win.ShowDialog()
}
