# StepCreater Phase 1: Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the non-GUI foundation of StepCreater: data model, Markdown round-trip (parse + generate), workfolder I/O, and CLI smoke test — verifiable end-to-end before any WPF code.

**Architecture:** PowerShell 5.1 module (`StepCreater.psm1`) exposing functions for reading/writing `procedure.md` and managing workfolders. Data classes defined in the module. Pester v5 covers all logic. No UI yet.

**Tech Stack:** PowerShell 5.1, Pester v5, PSScriptAnalyzer, InvokeBuild.

**Spec:** [docs/superpowers/specs/2026-05-27-stepcreater-design.md](../specs/2026-05-27-stepcreater-design.md)

---

## File Structure

All files under `StepCreater/` at repo root:

```
StepCreater/
  StepCreater.psd1                 # Module manifest
  StepCreater.psm1                 # Module: classes + public functions
  StepCreater.build.ps1            # InvokeBuild task definitions
  PSScriptAnalyzerSettings.psd1    # Lint config
  README.md                        # Module readme
  tests/
    Models.Tests.ps1               # Data class behavior
    Generator.Tests.ps1            # ProcedureDoc → markdown
    Parser.Tests.ps1               # markdown → ProcedureDoc
    Roundtrip.Tests.ps1            # parse(generate(x)) == x
    Workfolder.Tests.ps1           # New/Open workfolder, state.json
    Config.Tests.ps1               # %APPDATA% config
    fixtures/
      sample-procedure.md          # Hand-crafted example for parser tests
```

Each file has one responsibility. Classes live in `StepCreater.psm1` because PowerShell 5.1 class scoping requires they be defined in the module file directly.

---

## Task 1: Project Skeleton & Module Manifest

**Files:**
- Create: `StepCreater/StepCreater.psd1`
- Create: `StepCreater/StepCreater.psm1`
- Create: `StepCreater/README.md`

- [ ] **Step 1: Create folder and module manifest**

Create `StepCreater/StepCreater.psd1`:

```powershell
@{
    RootModule        = 'StepCreater.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'a3b2c1d4-e5f6-4789-90ab-cdef12345678'
    Author            = 'noritake.kohji'
    Description       = 'Procedure document & evidence capture tool for system construction work.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Read-Procedure',
        'Write-Procedure',
        'New-StepCreaterWorkfolder',
        'Open-StepCreaterWorkfolder',
        'Get-StepCreaterConfig',
        'Set-StepCreaterConfig'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
```

- [ ] **Step 2: Create empty module file with header**

Create `StepCreater/StepCreater.psm1`:

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Classes and functions are added in subsequent tasks.
```

- [ ] **Step 3: Create README stub**

Create `StepCreater/README.md`:

```markdown
# StepCreater

System construction procedure document & evidence capture tool. PowerShell 5.1 + WPF.

See `../docs/superpowers/specs/2026-05-27-stepcreater-design.md` for design.

## Phase 1 (this commit): foundation module — data model, Markdown I/O, workfolder.
```

- [ ] **Step 4: Verify module imports cleanly**

Run:
```powershell
Import-Module ./StepCreater/StepCreater.psd1 -Force; Get-Module StepCreater
```

Expected: module listed, no errors.

- [ ] **Step 5: Commit**

```bash
git add StepCreater/
git commit -m "StepCreater: scaffold module skeleton"
```

---

## Task 2: Test & Build Tooling

**Files:**
- Create: `StepCreater/PSScriptAnalyzerSettings.psd1`
- Create: `StepCreater/StepCreater.build.ps1`

- [ ] **Step 1: Ensure required modules are installed**

Run:
```powershell
Install-Module -Name Pester -RequiredVersion 5.5.0 -Force -Scope CurrentUser -SkipPublisherCheck
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
Install-Module -Name InvokeBuild -Force -Scope CurrentUser
```

Expected: three modules installed (or already present).

- [ ] **Step 2: Create PSScriptAnalyzer settings**

Create `StepCreater/PSScriptAnalyzerSettings.psd1`:

```powershell
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSUseShouldProcessForStateChangingFunctions'  # Phase 1 funcs are not destructive enough to warrant ShouldProcess
    )
}
```

- [ ] **Step 3: Create InvokeBuild task file**

Create `StepCreater/StepCreater.build.ps1`:

```powershell
# Run with: Invoke-Build -File StepCreater/StepCreater.build.ps1 <Task>
# Tasks: Lint, Test, All (default)

task Lint {
    $results = Invoke-ScriptAnalyzer -Path "$PSScriptRoot" -Recurse `
        -Settings "$PSScriptRoot/PSScriptAnalyzerSettings.psd1"
    if ($results) {
        $results | Format-Table -AutoSize | Out-String | Write-Host
        throw "PSScriptAnalyzer reported $($results.Count) issue(s)."
    }
}

task Test {
    $config = New-PesterConfiguration
    $config.Run.Path = "$PSScriptRoot/tests"
    $config.Output.Verbosity = 'Detailed'
    $config.Run.Exit = $true
    Invoke-Pester -Configuration $config
}

task All Lint, Test

task . All
```

- [ ] **Step 4: Verify build runs (no tests yet → Test task should pass with 0 tests)**

Run:
```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 Lint
```

Expected: PASS, no analyzer output.

- [ ] **Step 5: Commit**

```bash
git add StepCreater/PSScriptAnalyzerSettings.psd1 StepCreater/StepCreater.build.ps1
git commit -m "StepCreater: add Pester/PSScriptAnalyzer/InvokeBuild tooling"
```

---

## Task 3: Data Classes

**Files:**
- Create: `StepCreater/tests/Models.Tests.ps1`
- Modify: `StepCreater/StepCreater.psm1`

- [ ] **Step 1: Write failing test for ScreenshotRef**

Create `StepCreater/tests/Models.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module "$PSScriptRoot/../StepCreater.psd1" -Force
}

Describe 'ScreenshotRef' {
    It 'constructs with required fields' {
        $s = [ScreenshotRef]::new('2026-05-27_103045_step01.png', [datetime]'2026-05-27T10:30:45', 'full')
        $s.FileName | Should -Be '2026-05-27_103045_step01.png'
        $s.Kind     | Should -Be 'full'
        $s.MaskedFromOriginal | Should -BeFalse
    }
}

Describe 'Step' {
    It 'defaults to pending status with empty fields' {
        $step = [Step]::new('01', 'IIS Install')
        $step.Id              | Should -Be '01'
        $step.Title           | Should -Be 'IIS Install'
        $step.Status          | Should -Be 'pending'
        $step.BodyMarkdown    | Should -Be ''
        $step.Command         | Should -Be ''
        $step.ExpectedResult  | Should -Be ''
        $step.Note            | Should -Be ''
        $step.Evidence.Count  | Should -Be 0
        $step.Started         | Should -BeNullOrEmpty
        $step.Finished        | Should -BeNullOrEmpty
    }
}

Describe 'ProcedureDoc' {
    It 'has empty Steps list by default' {
        $doc = [ProcedureDoc]::new('Server Build')
        $doc.Title       | Should -Be 'Server Build'
        $doc.Steps.Count | Should -Be 0
    }

    It 'AddStep assigns sequential zero-padded IDs' {
        $doc = [ProcedureDoc]::new('Doc')
        $a = $doc.AddStep('First')
        $b = $doc.AddStep('Second')
        $a.Id | Should -Be '01'
        $b.Id | Should -Be '02'
        $doc.Steps.Count | Should -Be 2
    }
}
```

- [ ] **Step 2: Run tests, expect failure**

Run:
```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 Test
```

Expected: FAIL — `[ScreenshotRef]` / `[Step]` / `[ProcedureDoc]` not found.

- [ ] **Step 3: Add classes to module**

Replace the contents of `StepCreater/StepCreater.psm1` with:

```powershell
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
    [string] $Status                          # pending | done | ng | skipped
    [Nullable[datetime]] $Started
    [Nullable[datetime]] $Finished
    [string] $Note
    [System.Collections.Generic.List[ScreenshotRef]] $Evidence
    [hashtable] $UnknownSectionsRaw           # heading -> raw markdown content

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
```

- [ ] **Step 4: Run tests, expect pass**

Run:
```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 Test
```

Expected: 4 PASS, 0 FAIL.

- [ ] **Step 5: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/tests/Models.Tests.ps1
git commit -m "StepCreater: add data classes (ScreenshotRef, Step, ProcedureDoc)"
```

---

## Task 4: Markdown Generator (ProcedureDoc → string)

**Files:**
- Create: `StepCreater/tests/Generator.Tests.ps1`
- Modify: `StepCreater/StepCreater.psm1`

- [ ] **Step 1: Write failing generator tests**

Create `StepCreater/tests/Generator.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module "$PSScriptRoot/../StepCreater.psd1" -Force
}

Describe 'Write-Procedure (generator)' {
    It 'emits YAML front matter with title' {
        $doc = [ProcedureDoc]::new('Sample Doc')
        $doc.Created = [datetime]'2026-05-27'
        $md = Write-Procedure -Procedure $doc
        $md | Should -Match '(?ms)^---\r?\ntitle: Sample Doc\r?\ncreated: 2026-05-27\r?\n.*?---'
    }

    It 'emits H1 title after front matter' {
        $doc = [ProcedureDoc]::new('Sample Doc')
        $md = Write-Procedure -Procedure $doc
        $md | Should -Match '(?m)^# Sample Doc$'
    }

    It 'emits Step heading, step-id comment, and meta bullets' {
        $doc = [ProcedureDoc]::new('Doc')
        $step = $doc.AddStep('IIS Install')
        $step.Status = 'done'
        $step.Started  = [datetime]'2026-05-27T10:30:01'
        $step.Finished = [datetime]'2026-05-27T10:31:20'
        $md = Write-Procedure -Procedure $doc
        $md | Should -Match '(?m)^## Step 1: IIS Install$'
        $md | Should -Match '<!-- step-id: 01 -->'
        $md | Should -Match '(?m)^- status: done$'
        $md | Should -Match '(?m)^- started: 2026-05-27T10:30:01$'
        $md | Should -Match '(?m)^- finished: 2026-05-27T10:31:20$'
    }

    It 'emits the five fixed sections when present' {
        $doc = [ProcedureDoc]::new('Doc')
        $s = $doc.AddStep('Step1')
        $s.BodyMarkdown   = 'Do the thing.'
        $s.Command        = 'Install-WindowsFeature -Name Web-Server'
        $s.ExpectedResult = 'Exit code 0'
        $s.Note           = 'Reboot may be required'
        $s.Evidence.Add([ScreenshotRef]::new('img/a.png', [datetime]'2026-05-27', 'full')) | Out-Null
        $md = Write-Procedure -Procedure $doc

        $md | Should -Match '### 手順'
        $md | Should -Match 'Do the thing\.'
        $md | Should -Match '### 実行コマンド'
        $md | Should -Match '(?ms)```powershell\r?\nInstall-WindowsFeature -Name Web-Server\r?\n```'
        $md | Should -Match '### 想定結果'
        $md | Should -Match 'Exit code 0'
        $md | Should -Match '### エビデンス'
        $md | Should -Match '!\[\]\(img/a\.png\)'
        $md | Should -Match '### 備考'
        $md | Should -Match 'Reboot may be required'
    }

    It 'omits empty sections' {
        $doc = [ProcedureDoc]::new('Doc')
        $s = $doc.AddStep('Step1')
        $s.BodyMarkdown = 'Body only.'
        $md = Write-Procedure -Procedure $doc
        $md | Should -Not -Match '### 実行コマンド'
        $md | Should -Not -Match '### 想定結果'
        $md | Should -Not -Match '### エビデンス'
        $md | Should -Not -Match '### 備考'
    }

    It 'preserves unknown sections via UnknownSectionsRaw' {
        $doc = [ProcedureDoc]::new('Doc')
        $s = $doc.AddStep('Step1')
        $s.UnknownSectionsRaw['### 参考リンク'] = "- https://example.com`n- https://contoso.com"
        $md = Write-Procedure -Procedure $doc
        $md | Should -Match '### 参考リンク'
        $md | Should -Match 'https://example\.com'
    }
}
```

- [ ] **Step 2: Run tests, expect failure**

Run:
```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 Test
```

Expected: FAIL — `Write-Procedure` not found.

- [ ] **Step 3: Implement Write-Procedure**

Append to `StepCreater/StepCreater.psm1`:

```powershell
function Write-Procedure {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ProcedureDoc]$Procedure
    )

    $sb = [System.Text.StringBuilder]::new()
    $nl = "`r`n"

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
        if ($step.Started)  { [void]$sb.Append("- started: $($step.Started.Value.ToString('s'))$nl") }
        if ($step.Finished) { [void]$sb.Append("- finished: $($step.Finished.Value.ToString('s'))$nl") }
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

        # Unknown sections preserved as-is
        foreach ($key in $step.UnknownSectionsRaw.Keys) {
            [void]$sb.Append("$key$nl")
            [void]$sb.Append($step.UnknownSectionsRaw[$key].TrimEnd())
            [void]$sb.Append("$nl$nl")
        }
    }

    return $sb.ToString()
}
```

Add `'Write-Procedure'` to `FunctionsToExport` in `StepCreater.psd1` (already present from Task 1).

- [ ] **Step 4: Run tests, expect pass**

Run:
```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 Test
```

Expected: 10 PASS (4 prior + 6 new), 0 FAIL.

- [ ] **Step 5: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/tests/Generator.Tests.ps1
git commit -m "StepCreater: Markdown generator (ProcedureDoc -> string)"
```

---

## Task 5: Markdown Parser (string → ProcedureDoc)

**Files:**
- Create: `StepCreater/tests/Parser.Tests.ps1`
- Create: `StepCreater/tests/fixtures/sample-procedure.md`
- Modify: `StepCreater/StepCreater.psm1`

- [ ] **Step 1: Create fixture file**

Create `StepCreater/tests/fixtures/sample-procedure.md`:

```markdown
---
title: Sample Doc
created: 2026-05-27
updated: 2026-05-27T11:32:05
author: tester
---

# Sample Doc

## Step 1: IIS Install
<!-- step-id: 01 -->
- status: done
- started: 2026-05-27T10:30:01
- finished: 2026-05-27T10:31:20

### 手順
Install IIS via Server Manager or PowerShell.

### 実行コマンド
```powershell
Install-WindowsFeature -Name Web-Server
```

### 想定結果
Exit code 0 and "Success" printed.

### エビデンス
![](images/2026-05-27_103045_step01.png)
![](images/2026-05-27_103120_step01_win.png)

### 備考
Reboot may be required.

## Step 2: Configure Site
<!-- step-id: 02 -->
- status: pending

### 手順
Edit the default site bindings.

### 参考リンク
- https://example.com
```

- [ ] **Step 2: Write failing parser tests**

Create `StepCreater/tests/Parser.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module "$PSScriptRoot/../StepCreater.psd1" -Force
    $script:fixturePath = "$PSScriptRoot/fixtures/sample-procedure.md"
}

Describe 'Read-Procedure (parser)' {
    BeforeAll {
        $script:doc = Read-Procedure -Path $script:fixturePath
    }

    It 'parses title from front matter' {
        $script:doc.Title | Should -Be 'Sample Doc'
    }

    It 'parses author and created date' {
        $script:doc.Author          | Should -Be 'tester'
        $script:doc.Created.Value   | Should -Be ([datetime]'2026-05-27')
    }

    It 'parses two steps' {
        $script:doc.Steps.Count | Should -Be 2
    }

    It 'parses Step 1 metadata' {
        $s1 = $script:doc.Steps[0]
        $s1.Id              | Should -Be '01'
        $s1.Title           | Should -Be 'IIS Install'
        $s1.Status          | Should -Be 'done'
        $s1.Started.Value   | Should -Be ([datetime]'2026-05-27T10:30:01')
        $s1.Finished.Value  | Should -Be ([datetime]'2026-05-27T10:31:20')
    }

    It 'parses Step 1 body and command' {
        $s1 = $script:doc.Steps[0]
        $s1.BodyMarkdown   | Should -Match 'Install IIS via Server Manager'
        $s1.Command        | Should -Match 'Install-WindowsFeature -Name Web-Server'
        $s1.ExpectedResult | Should -Match 'Exit code 0'
        $s1.Note           | Should -Match 'Reboot may be required'
    }

    It 'parses Step 1 evidence images' {
        $s1 = $script:doc.Steps[0]
        $s1.Evidence.Count       | Should -Be 2
        $s1.Evidence[0].FileName | Should -Be 'images/2026-05-27_103045_step01.png'
        $s1.Evidence[1].FileName | Should -Be 'images/2026-05-27_103120_step01_win.png'
    }

    It 'defaults missing meta to pending and null times for Step 2' {
        $s2 = $script:doc.Steps[1]
        $s2.Status   | Should -Be 'pending'
        $s2.Started  | Should -BeNullOrEmpty
        $s2.Finished | Should -BeNullOrEmpty
    }

    It 'preserves unknown section "### 参考リンク" on Step 2' {
        $s2 = $script:doc.Steps[1]
        $s2.UnknownSectionsRaw.ContainsKey('### 参考リンク') | Should -BeTrue
        $s2.UnknownSectionsRaw['### 参考リンク']             | Should -Match 'https://example\.com'
    }
}
```

- [ ] **Step 3: Run tests, expect failure**

Run:
```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 Test
```

Expected: FAIL — `Read-Procedure` not found.

- [ ] **Step 4: Implement Read-Procedure**

Append to `StepCreater/StepCreater.psm1`:

```powershell
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
        $i++  # skip closing ---
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
        $title = $matches[2].Trim()

        # step-id (prefer explicit, else from heading number)
        $id = if ($block -match '<!-- step-id:\s*(\S+)\s*-->') { $matches[1] }
              else { '{0:D2}' -f [int]$matches[1] }

        $step = [Step]::new($id, $title)

        # Meta bullets
        if ($block -match '(?m)^- status:\s*(\S+)\s*$')   { $step.Status   = $matches[1] }
        if ($block -match '(?m)^- started:\s*(\S+)\s*$')  { $step.Started  = [datetime]::Parse($matches[1]) }
        if ($block -match '(?m)^- finished:\s*(\S+)\s*$') { $step.Finished = [datetime]::Parse($matches[1]) }

        # Section split: lines starting with "### "
        $sectionMatches = [regex]::Matches($block, '(?m)^### (.+?)\r?\n')
        for ($s = 0; $s -lt $sectionMatches.Count; $s++) {
            $heading = '### ' + $sectionMatches[$s].Groups[1].Value.Trim()
            $start   = $sectionMatches[$s].Index + $sectionMatches[$s].Length
            $end     = if ($s + 1 -lt $sectionMatches.Count) { $sectionMatches[$s + 1].Index } else { $block.Length }
            $content = $block.Substring($start, $end - $start).Trim()

            switch ($heading) {
                '### 手順'         { $step.BodyMarkdown   = $content }
                '### 実行コマンド' {
                    # Strip fenced code block if present
                    if ($content -match '(?ms)^```\w*\r?\n(.*?)\r?\n```') { $step.Command = $matches[1].Trim() }
                    else                                                  { $step.Command = $content }
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
```

- [ ] **Step 5: Run tests, expect pass**

Run:
```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 Test
```

Expected: all PASS (10 prior + 8 new = 18).

- [ ] **Step 6: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/tests/Parser.Tests.ps1 StepCreater/tests/fixtures/sample-procedure.md
git commit -m "StepCreater: Markdown parser (string -> ProcedureDoc)"
```

---

## Task 6: Round-Trip Test (parse(generate(x)) preserves data)

**Files:**
- Create: `StepCreater/tests/Roundtrip.Tests.ps1`

- [ ] **Step 1: Write round-trip test**

Create `StepCreater/tests/Roundtrip.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module "$PSScriptRoot/../StepCreater.psd1" -Force
}

Describe 'Markdown round-trip' {
    It 'preserves all Step fields through generate -> parse' {
        $doc = [ProcedureDoc]::new('Round-Trip Doc')
        $doc.Author  = 'tester'
        $doc.Created = [datetime]'2026-05-27'

        $a = $doc.AddStep('Install')
        $a.BodyMarkdown   = 'Install the thing.'
        $a.Command        = 'Install-WindowsFeature -Name Web-Server'
        $a.ExpectedResult = 'Exit code 0'
        $a.Status         = 'done'
        $a.Started        = [datetime]'2026-05-27T10:00:00'
        $a.Finished       = [datetime]'2026-05-27T10:05:00'
        $a.Note           = 'Reboot first.'
        $a.Evidence.Add([ScreenshotRef]::new('images/x.png', [datetime]'2026-05-27', 'full')) | Out-Null

        $b = $doc.AddStep('Configure')
        $b.BodyMarkdown   = 'Edit bindings.'
        $b.UnknownSectionsRaw['### 参考リンク'] = '- https://example.com'

        $md = Write-Procedure -Procedure $doc
        $tmp = New-TemporaryFile
        Set-Content -LiteralPath $tmp -Value $md -Encoding UTF8
        $parsed = Read-Procedure -Path $tmp

        $parsed.Title             | Should -Be 'Round-Trip Doc'
        $parsed.Author            | Should -Be 'tester'
        $parsed.Steps.Count       | Should -Be 2

        $parsed.Steps[0].Title           | Should -Be 'Install'
        $parsed.Steps[0].Status          | Should -Be 'done'
        $parsed.Steps[0].Command         | Should -Match 'Install-WindowsFeature'
        $parsed.Steps[0].Started.Value   | Should -Be ([datetime]'2026-05-27T10:00:00')
        $parsed.Steps[0].Finished.Value  | Should -Be ([datetime]'2026-05-27T10:05:00')
        $parsed.Steps[0].Evidence.Count  | Should -Be 1
        $parsed.Steps[0].Evidence[0].FileName | Should -Be 'images/x.png'

        $parsed.Steps[1].UnknownSectionsRaw['### 参考リンク'] | Should -Match 'example.com'

        Remove-Item $tmp -Force
    }
}
```

- [ ] **Step 2: Run tests, expect pass (no new implementation needed)**

Run:
```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 Test
```

Expected: round-trip test PASS. If fails, fix the parser or generator until it passes.

- [ ] **Step 3: Commit**

```bash
git add StepCreater/tests/Roundtrip.Tests.ps1
git commit -m "StepCreater: round-trip test for Markdown I/O"
```

---

## Task 7: Workfolder Initialization & Open

**Files:**
- Create: `StepCreater/tests/Workfolder.Tests.ps1`
- Modify: `StepCreater/StepCreater.psm1`

- [ ] **Step 1: Write failing workfolder tests**

Create `StepCreater/tests/Workfolder.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module "$PSScriptRoot/../StepCreater.psd1" -Force
}

Describe 'New-StepCreaterWorkfolder' {
    BeforeEach {
        $script:wf = Join-Path $TestDrive 'wf1'
    }

    It 'creates the expected folder layout' {
        New-StepCreaterWorkfolder -Path $script:wf -Title 'My Doc' | Out-Null
        Test-Path (Join-Path $script:wf 'procedure.md')                  | Should -BeTrue
        Test-Path (Join-Path $script:wf 'images')                        | Should -BeTrue
        Test-Path (Join-Path $script:wf 'attachments')                   | Should -BeTrue
        Test-Path (Join-Path $script:wf '.stepcreater')                  | Should -BeTrue
        Test-Path (Join-Path $script:wf '.stepcreater/state.json')       | Should -BeTrue
    }

    It 'writes procedure.md with title from parameter' {
        New-StepCreaterWorkfolder -Path $script:wf -Title 'My Doc' | Out-Null
        $md = Get-Content (Join-Path $script:wf 'procedure.md') -Raw
        $md | Should -Match 'title: My Doc'
        $md | Should -Match '(?m)^# My Doc$'
    }

    It 'refuses to overwrite existing non-empty folder unless -Force' {
        New-Item -ItemType Directory -Path $script:wf | Out-Null
        New-Item -ItemType File -Path (Join-Path $script:wf 'existing.txt') | Out-Null
        { New-StepCreaterWorkfolder -Path $script:wf -Title 'X' } | Should -Throw
    }
}

Describe 'Open-StepCreaterWorkfolder' {
    BeforeEach {
        $script:wf = Join-Path $TestDrive 'wf2'
        New-StepCreaterWorkfolder -Path $script:wf -Title 'Open Test' | Out-Null
    }

    It 'returns a session with parsed Procedure' {
        $sess = Open-StepCreaterWorkfolder -Path $script:wf
        $sess.WorkFolderPath  | Should -Be (Resolve-Path $script:wf).Path
        $sess.Procedure.Title | Should -Be 'Open Test'
    }

    It 'creates state.json with default contents if missing' {
        Remove-Item (Join-Path $script:wf '.stepcreater/state.json') -Force
        $sess = Open-StepCreaterWorkfolder -Path $script:wf
        Test-Path (Join-Path $script:wf '.stepcreater/state.json') | Should -BeTrue
        $sess.CurrentStepIndex | Should -Be 0
    }
}
```

- [ ] **Step 2: Run tests, expect failure**

Run:
```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 Test
```

Expected: FAIL — workfolder functions not found.

- [ ] **Step 3: Add WorkSession class and workfolder functions**

Append to `StepCreater/StepCreater.psm1`:

```powershell
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
```

- [ ] **Step 4: Run tests, expect pass**

Run:
```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 Test
```

Expected: all PASS (19 prior + 5 new = 24).

- [ ] **Step 5: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/tests/Workfolder.Tests.ps1
git commit -m "StepCreater: workfolder init and open (with state.json)"
```

---

## Task 8: Tool-Wide Config in %APPDATA%

**Files:**
- Create: `StepCreater/tests/Config.Tests.ps1`
- Modify: `StepCreater/StepCreater.psm1`

- [ ] **Step 1: Write failing config tests**

Create `StepCreater/tests/Config.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module "$PSScriptRoot/../StepCreater.psd1" -Force
}

Describe 'Get/Set-StepCreaterConfig' {
    BeforeEach {
        $script:tempRoot = Join-Path $TestDrive 'appdata'
        New-Item -ItemType Directory -Path $script:tempRoot | Out-Null
        $env:STEPCREATER_CONFIG_DIR = $script:tempRoot
    }
    AfterEach {
        Remove-Item Env:\STEPCREATER_CONFIG_DIR -ErrorAction SilentlyContinue
    }

    It 'returns defaults on first read' {
        $cfg = Get-StepCreaterConfig
        $cfg.hotkeys.fullScreen | Should -Be 'Ctrl+F12'
        $cfg.hotkeys.window     | Should -Be 'Ctrl+F11'
        $cfg.hotkeys.rect       | Should -Be 'Ctrl+Shift+F12'
        $cfg.annotationEnabled  | Should -BeTrue
        $cfg.recentWorkfolders.Count | Should -Be 0
    }

    It 'persists Set-StepCreaterConfig changes across reads' {
        $cfg = Get-StepCreaterConfig
        $cfg.hotkeys.fullScreen = 'Ctrl+Shift+P'
        Set-StepCreaterConfig -Config $cfg
        $reread = Get-StepCreaterConfig
        $reread.hotkeys.fullScreen | Should -Be 'Ctrl+Shift+P'
    }
}
```

- [ ] **Step 2: Run tests, expect failure**

Run:
```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 Test
```

Expected: FAIL — config functions not found.

- [ ] **Step 3: Implement config functions**

Append to `StepCreater/StepCreater.psm1`:

```powershell
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
```

- [ ] **Step 4: Run tests, expect pass**

Run:
```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 Test
```

Expected: all PASS (24 prior + 2 new = 26).

- [ ] **Step 5: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/tests/Config.Tests.ps1
git commit -m "StepCreater: tool-wide config in %APPDATA%"
```

---

## Task 9: CLI Smoke Test Entry Point

**Files:**
- Create: `StepCreater/StepCreater.ps1`

- [ ] **Step 1: Implement entry script (Phase 1: CLI only, no GUI)**

Create `StepCreater/StepCreater.ps1`:

```powershell
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
```

- [ ] **Step 2: Manually verify CLI end-to-end**

Run from repo root:
```powershell
$tmp = Join-Path $env:TEMP "stepcreater-smoke-$([guid]::NewGuid())"
.\StepCreater\StepCreater.ps1 -Init -WorkFolder $tmp -Title "Smoke Test"
.\StepCreater\StepCreater.ps1 -WorkFolder $tmp
```

Expected output for second invocation:
```
Opened: <tmp path>
Title : Smoke Test
Steps : 0
Mode  : Edit
```

Then check files:
```powershell
Get-ChildItem $tmp -Recurse | Select-Object FullName
Get-Content (Join-Path $tmp 'procedure.md')
```

Expected: `procedure.md`, `images/`, `attachments/`, `.stepcreater/state.json` all present.

Cleanup:
```powershell
Remove-Item $tmp -Recurse -Force
```

- [ ] **Step 3: Run full build (lint + test) before commit**

Run:
```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 All
```

Expected: PSScriptAnalyzer clean, 26 Pester tests pass.

- [ ] **Step 4: Commit**

```bash
git add StepCreater/StepCreater.ps1
git commit -m "StepCreater: CLI entry point (Phase 1 smoke test)"
```

---

## Phase 1 Done Criteria

- [ ] `Invoke-Build All` passes (lint + 26 tests)
- [ ] Smoke test creates a workfolder and reopens it, printing parsed contents
- [ ] `procedure.md` round-trips losslessly through generate→write→read
- [ ] Unknown sections in user-edited Markdown are preserved
- [ ] `%APPDATA%\StepCreater\config.json` reads/writes correctly with defaults

Phase 2 (手順書作成モード WPF GUI) starts after Phase 1 is merged.
