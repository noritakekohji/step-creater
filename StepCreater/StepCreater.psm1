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
        'TxtTitle','CboStatus','TxtBody','TxtCommand','TxtExpected','TxtNote'
    )) { $c[$name] = $window.FindName($name) }

    $c.WorkfolderPath.Text = $Session.WorkFolderPath
    $window.Title          = "StepCreater - $($Session.Procedure.Title)"
    Update-StepListUI -Session $Session -ListBox $c.StepList

    $window.Tag = [pscustomobject]@{
        Session  = $Session
        Controls = $c
        Baseline = (Get-ProcedureHash -Procedure $Session.Procedure)
    }

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