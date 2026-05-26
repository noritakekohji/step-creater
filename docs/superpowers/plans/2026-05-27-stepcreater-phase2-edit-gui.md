# StepCreater Phase 2: 手順書作成モード (Edit GUI) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the WPF main window for the procedure-creation mode: Step list pane, Step detail editor, file menu (New/Open/Save), template insertion, unsaved-changes detection, and ESC close confirmation.

**Architecture:** WPF window loaded from XAML via `[Windows.Markup.XamlReader]::Parse`. Code-behind style: event handlers in PowerShell manipulate `WorkSession.Procedure` and refresh UI controls directly. Mode tabs render but only "Edit" is functional this phase. Phase 3 will wire Capture into the Capture tab.

**Tech Stack:** PowerShell 5.1, WPF (PresentationFramework / WindowsBase / System.Xaml assemblies), Pester v5.

**Spec:** [docs/superpowers/specs/2026-05-27-stepcreater-design.md](../specs/2026-05-27-stepcreater-design.md)

**Predecessor:** [Phase 1 plan](2026-05-27-stepcreater-phase1-foundation.md) — must be complete and merged.

---

## File Structure

```
StepCreater/
  StepCreater.psd1                     # MODIFY — add new functions to FunctionsToExport
  StepCreater.psm1                     # MODIFY — append UI functions + helpers
  StepCreater.ps1                      # MODIFY — launch GUI when no -Init
  ui/
    MainWindow.xaml                    # CREATE — main window layout
    templates/
      iis-install.psd1                 # CREATE — sample template
      windows-update.psd1              # CREATE — sample template
  tests/
    Templates.Tests.ps1                # CREATE — template loader tests
    ProcedureOps.Tests.ps1             # CREATE — Insert/Remove/Move/Hash tests
    Xaml.Tests.ps1                     # CREATE — XAML parses cleanly
```

Single-module approach (per Phase 1 decision). XAML lives in `ui/MainWindow.xaml` as an external file so designers/devs can edit it without touching PowerShell strings.

---

## Task 1: Step Templates Data & Loader

**Files:**
- Create: `StepCreater/ui/templates/iis-install.psd1`
- Create: `StepCreater/ui/templates/windows-update.psd1`
- Create: `StepCreater/tests/Templates.Tests.ps1`
- Modify: `StepCreater/StepCreater.psm1` (append `Get-StepTemplates`)
- Modify: `StepCreater/StepCreater.psd1` (add `Get-StepTemplates` to FunctionsToExport)

- [ ] **Step 1: Create template files**

`StepCreater/ui/templates/iis-install.psd1`:

```powershell
@{
    Name           = 'IIS Install'
    Title          = 'IIS をインストール'
    BodyMarkdown   = 'Server Manager または PowerShell で IIS をインストールする。'
    Command        = 'Install-WindowsFeature -Name Web-Server -IncludeManagementTools'
    ExpectedResult = 'Success = True、ExitCode = 0 が表示される。'
    Note           = '再起動が必要な場合あり。'
}
```

`StepCreater/ui/templates/windows-update.psd1`:

```powershell
@{
    Name           = 'Windows Update'
    Title          = 'Windows Update を適用'
    BodyMarkdown   = '最新の Windows Update を適用する。完了後に再起動する。'
    Command        = 'Get-WindowsUpdate -Install -AcceptAll -AutoReboot'
    ExpectedResult = '全ての更新が「Installed」状態になる。'
    Note           = 'PSWindowsUpdate モジュールが必要。'
}
```

- [ ] **Step 2: Write failing test**

`StepCreater/tests/Templates.Tests.ps1`:

```powershell
using module '..\StepCreater.psd1'

Describe 'Get-StepTemplates' {
    It 'loads all .psd1 files from ui/templates/' {
        $templates = Get-StepTemplates
        $templates.Count | Should -BeGreaterOrEqual 2
    }

    It 'each template has required fields' {
        $templates = Get-StepTemplates
        foreach ($t in $templates) {
            $t.Name           | Should -Not -BeNullOrEmpty
            $t.Title          | Should -Not -BeNullOrEmpty
            $t.BodyMarkdown   | Should -Not -BeNullOrEmpty
        }
    }

    It 'returns IIS Install template' {
        $templates = Get-StepTemplates
        $iis = $templates | Where-Object { $_.Name -eq 'IIS Install' }
        $iis | Should -Not -BeNullOrEmpty
        $iis.Command | Should -Match 'Install-WindowsFeature'
    }
}
```

- [ ] **Step 3: Run, expect failure**

```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 Test
```

Expected: `Get-StepTemplates` not found.

- [ ] **Step 4: Implement loader**

Append to `StepCreater/StepCreater.psm1`:

```powershell
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
```

Add `'Get-StepTemplates'` to FunctionsToExport in `StepCreater.psd1`:

```powershell
FunctionsToExport = @(
    'Read-Procedure',
    'Write-Procedure',
    'New-StepCreaterWorkfolder',
    'Open-StepCreaterWorkfolder',
    'Get-StepCreaterConfig',
    'Set-StepCreaterConfig',
    'Get-StepTemplates'
)
```

- [ ] **Step 5: Run, expect pass + lint clean**

```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 All
```

Expected: 29 tests pass (26 prior + 3 new).

- [ ] **Step 6: Commit**

```bash
git add StepCreater/ui/templates/ StepCreater/tests/Templates.Tests.ps1 StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1
git commit -m "StepCreater: step templates loader"
```

---

## Task 2: ProcedureDoc Operations & Dirty Detection

These functions encapsulate the model mutations the UI will perform, so they're testable in isolation.

**Files:**
- Create: `StepCreater/tests/ProcedureOps.Tests.ps1`
- Modify: `StepCreater/StepCreater.psm1` (append helpers)
- Modify: `StepCreater/StepCreater.psd1` (export new functions)

- [ ] **Step 1: Write failing tests**

`StepCreater/tests/ProcedureOps.Tests.ps1`:

```powershell
using module '..\StepCreater.psd1'

Describe 'Procedure operations' {
    BeforeEach {
        $script:doc = [ProcedureDoc]::new('Doc')
        $script:a = $script:doc.AddStep('A')
        $script:b = $script:doc.AddStep('B')
        $script:c = $script:doc.AddStep('C')
    }

    It 'Add-ProcedureStepAt inserts at given index and renumbers IDs' {
        $new = Add-ProcedureStepAt -Procedure $script:doc -Index 1 -Title 'New'
        $script:doc.Steps.Count | Should -Be 4
        $script:doc.Steps[1].Title | Should -Be 'New'
        $script:doc.Steps[0].Id | Should -Be '01'
        $script:doc.Steps[1].Id | Should -Be '02'
        $script:doc.Steps[2].Id | Should -Be '03'
        $script:doc.Steps[3].Id | Should -Be '04'
        $new.Id | Should -Be '02'
    }

    It 'Remove-ProcedureStep removes at index and renumbers' {
        Remove-ProcedureStep -Procedure $script:doc -Index 1
        $script:doc.Steps.Count | Should -Be 2
        $script:doc.Steps[0].Title | Should -Be 'A'
        $script:doc.Steps[1].Title | Should -Be 'C'
        $script:doc.Steps[1].Id    | Should -Be '02'
    }

    It 'Move-ProcedureStep moves up' {
        Move-ProcedureStep -Procedure $script:doc -Index 2 -Direction Up
        $script:doc.Steps[0].Title | Should -Be 'A'
        $script:doc.Steps[1].Title | Should -Be 'C'
        $script:doc.Steps[2].Title | Should -Be 'B'
        $script:doc.Steps[1].Id    | Should -Be '02'
        $script:doc.Steps[2].Id    | Should -Be '03'
    }

    It 'Move-ProcedureStep at edge is no-op' {
        Move-ProcedureStep -Procedure $script:doc -Index 0 -Direction Up
        $script:doc.Steps[0].Title | Should -Be 'A'
    }
}

Describe 'Get-ProcedureHash' {
    It 'same content yields same hash' {
        $doc1 = [ProcedureDoc]::new('X'); $doc1.AddStep('S1') | Out-Null
        $doc2 = [ProcedureDoc]::new('X'); $doc2.AddStep('S1') | Out-Null
        (Get-ProcedureHash -Procedure $doc1) | Should -Be (Get-ProcedureHash -Procedure $doc2)
    }

    It 'modified content yields different hash' {
        $doc = [ProcedureDoc]::new('X'); $doc.AddStep('S1') | Out-Null
        $h1 = Get-ProcedureHash -Procedure $doc
        $doc.AddStep('S2') | Out-Null
        $h2 = Get-ProcedureHash -Procedure $doc
        $h1 | Should -Not -Be $h2
    }
}
```

- [ ] **Step 2: Run, expect failure**

```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 Test
```

- [ ] **Step 3: Implement helpers — append to `StepCreater.psm1`**

```powershell
function Add-ProcedureStepAt {
    [CmdletBinding()]
    [OutputType([Step])]
    param(
        [Parameter(Mandatory)] [ProcedureDoc]$Procedure,
        [Parameter(Mandatory)] [int]$Index,
        [Parameter(Mandatory)] [string]$Title
    )
    $step = [Step]::new('', $Title)  # temp id, will be renumbered
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
```

Add to FunctionsToExport in psd1: `'Add-ProcedureStepAt'`, `'Remove-ProcedureStep'`, `'Move-ProcedureStep'`, `'Update-ProcedureStepIds'`, `'Get-ProcedureHash'`.

Note: `Add`, `Remove`, `Move`, `Update` are all approved PowerShell verbs. PSScriptAnalyzer should not flag any of these names.

- [ ] **Step 4: Run, expect pass + lint clean**

```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 All
```

Expected: 35 tests pass (29 prior + 6 new), lint clean.

- [ ] **Step 5: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1 StepCreater/tests/ProcedureOps.Tests.ps1
git commit -m "StepCreater: procedure step operations + hash"
```

---

## Task 3: MainWindow.xaml (Layout)

**Files:**
- Create: `StepCreater/ui/MainWindow.xaml`
- Create: `StepCreater/tests/Xaml.Tests.ps1`

- [ ] **Step 1: Create XAML layout**

`StepCreater/ui/MainWindow.xaml`:

```xml
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="StepCreater" Height="700" Width="1100"
        WindowStartupLocation="CenterScreen">
    <DockPanel>
        <!-- Menu bar -->
        <Menu DockPanel.Dock="Top">
            <MenuItem Header="ファイル(_F)">
                <MenuItem x:Name="MenuNew"  Header="新規ワークフォルダ(_N)..." />
                <MenuItem x:Name="MenuOpen" Header="ワークフォルダを開く(_O)..." />
                <Separator/>
                <MenuItem x:Name="MenuSave" Header="保存(_S)" InputGestureText="Ctrl+S"/>
                <Separator/>
                <MenuItem x:Name="MenuExit" Header="終了(_X)"/>
            </MenuItem>
            <MenuItem x:Name="MenuTemplates" Header="テンプレ挿入(_T)"/>
        </Menu>

        <!-- Status bar -->
        <StatusBar DockPanel.Dock="Bottom">
            <StatusBarItem><TextBlock x:Name="StatusText" Text="準備完了"/></StatusBarItem>
            <Separator/>
            <StatusBarItem><TextBlock x:Name="DirtyText" Text=""/></StatusBarItem>
        </StatusBar>

        <!-- Top bar: mode tabs + workfolder path -->
        <Grid DockPanel.Dock="Top" Margin="8,4,8,4">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Orientation="Horizontal">
                <RadioButton x:Name="TabEdit"    GroupName="Mode" Content="作成"       IsChecked="True" Margin="2"/>
                <RadioButton x:Name="TabExecute" GroupName="Mode" Content="実施"       IsEnabled="False" Margin="2"/>
                <RadioButton x:Name="TabCapture" GroupName="Mode" Content="画像取得"   IsEnabled="False" Margin="2"/>
            </StackPanel>
            <TextBlock Grid.Column="1" x:Name="WorkfolderPath" VerticalAlignment="Center"
                       Margin="16,0,16,0" Foreground="DimGray"/>
            <Button Grid.Column="2" x:Name="BtnSave" Content="保存" Padding="12,4"/>
        </Grid>

        <!-- Main content: Step list + detail editor -->
        <Grid Margin="8">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="240"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- Step list pane -->
            <DockPanel Grid.Column="0" Margin="0,0,8,0">
                <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,4,0,0">
                    <Button x:Name="BtnAdd"    Content="+"  Width="28" Margin="0,0,2,0"/>
                    <Button x:Name="BtnDelete" Content="×"  Width="28" Margin="2,0,2,0"/>
                    <Button x:Name="BtnUp"     Content="↑"  Width="28" Margin="2,0,2,0"/>
                    <Button x:Name="BtnDown"   Content="↓"  Width="28" Margin="2,0,0,0"/>
                </StackPanel>
                <ListBox x:Name="StepList"/>
            </DockPanel>

            <!-- Detail editor -->
            <Grid Grid.Column="1">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <Grid Grid.Row="0" Margin="0,0,0,8">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="120"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="タイトル:" VerticalAlignment="Center" Margin="0,0,8,0"/>
                    <TextBox  Grid.Column="1" x:Name="TxtTitle"/>
                    <TextBlock Grid.Column="2" Text="ステータス:" VerticalAlignment="Center" Margin="16,0,8,0"/>
                    <ComboBox Grid.Column="3" x:Name="CboStatus">
                        <ComboBoxItem Content="pending"/>
                        <ComboBoxItem Content="done"/>
                        <ComboBoxItem Content="ng"/>
                        <ComboBoxItem Content="skipped"/>
                    </ComboBox>
                </Grid>

                <GroupBox Grid.Row="1" Header="手順" Margin="0,0,0,4">
                    <TextBox x:Name="TxtBody" AcceptsReturn="True" TextWrapping="Wrap"
                             VerticalScrollBarVisibility="Auto"/>
                </GroupBox>

                <Grid Grid.Row="2">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <GroupBox Grid.Column="0" Header="実行コマンド" Margin="0,4,4,0">
                        <TextBox x:Name="TxtCommand" AcceptsReturn="True" FontFamily="Consolas"
                                 VerticalScrollBarVisibility="Auto"/>
                    </GroupBox>
                    <GroupBox Grid.Column="1" Header="想定結果" Margin="4,4,0,0">
                        <TextBox x:Name="TxtExpected" AcceptsReturn="True" TextWrapping="Wrap"
                                 VerticalScrollBarVisibility="Auto"/>
                    </GroupBox>
                </Grid>

                <GroupBox Grid.Row="3" Header="備考" Margin="0,4,0,0" Height="80">
                    <TextBox x:Name="TxtNote" AcceptsReturn="True" TextWrapping="Wrap"
                             VerticalScrollBarVisibility="Auto"/>
                </GroupBox>
            </Grid>
        </Grid>
    </DockPanel>
</Window>
```

- [ ] **Step 2: Write failing test that XAML parses**

`StepCreater/tests/Xaml.Tests.ps1`:

```powershell
Describe 'MainWindow.xaml' {
    BeforeAll {
        Add-Type -AssemblyName PresentationFramework
        Add-Type -AssemblyName PresentationCore
        Add-Type -AssemblyName WindowsBase
        $script:xamlPath = Join-Path $PSScriptRoot '..\ui\MainWindow.xaml'
    }

    It 'file exists' {
        Test-Path $script:xamlPath | Should -BeTrue
    }

    It 'parses without error and produces a Window' {
        $xml = [xml](Get-Content -LiteralPath $script:xamlPath -Raw)
        $reader = [System.Xml.XmlNodeReader]::new($xml)
        $window = [Windows.Markup.XamlReader]::Load($reader)
        $window | Should -Not -BeNullOrEmpty
        $window.GetType().Name | Should -Be 'Window'
    }

    It 'has all expected named controls' {
        $xml = [xml](Get-Content -LiteralPath $script:xamlPath -Raw)
        $reader = [System.Xml.XmlNodeReader]::new($xml)
        $window = [Windows.Markup.XamlReader]::Load($reader)

        foreach ($name in @(
            'MenuNew','MenuOpen','MenuSave','MenuExit','MenuTemplates',
            'StatusText','DirtyText',
            'TabEdit','TabExecute','TabCapture',
            'WorkfolderPath','BtnSave',
            'StepList','BtnAdd','BtnDelete','BtnUp','BtnDown',
            'TxtTitle','CboStatus','TxtBody','TxtCommand','TxtExpected','TxtNote'
        )) {
            $window.FindName($name) | Should -Not -BeNullOrEmpty -Because "$name should exist in XAML"
        }
    }
}
```

- [ ] **Step 3: Run, expect failure (file doesn't exist yet — but it does now). Run, expect pass.**

```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 All
```

Expected: 38 tests pass (35 + 3), lint clean.

If parse fails, fix the XAML. If a named control is missing, add it to the XAML.

Note: XAML parsing requires STA thread. PowerShell 5.1 console is STA by default. If Pester runs in MTA mode somehow, you may see a TypeInitializationException — re-run from a fresh `powershell.exe` window.

- [ ] **Step 4: Commit**

```bash
git add StepCreater/ui/MainWindow.xaml StepCreater/tests/Xaml.Tests.ps1
git commit -m "StepCreater: MainWindow.xaml layout"
```

---

## Task 4: Show-StepCreaterMainWindow (Load + Populate Step List)

**Files:**
- Modify: `StepCreater/StepCreater.psm1` (append `Show-StepCreaterMainWindow`)
- Modify: `StepCreater/StepCreater.psd1` (export)

- [ ] **Step 1: Append function to `StepCreater.psm1`**

```powershell
function Show-StepCreaterMainWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [WorkSession]$Session,
        [switch]$NoShow   # for tests
    )

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $xamlPath = Join-Path $PSScriptRoot 'ui/MainWindow.xaml'
    $xml = [xml](Get-Content -LiteralPath $xamlPath -Raw)
    $reader = [System.Xml.XmlNodeReader]::new($xml)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    # Look up all named controls into a hashtable for convenience
    $c = @{}
    foreach ($name in @(
        'MenuNew','MenuOpen','MenuSave','MenuExit','MenuTemplates',
        'StatusText','DirtyText',
        'TabEdit','TabExecute','TabCapture',
        'WorkfolderPath','BtnSave',
        'StepList','BtnAdd','BtnDelete','BtnUp','BtnDown',
        'TxtTitle','CboStatus','TxtBody','TxtCommand','TxtExpected','TxtNote'
    )) { $c[$name] = $window.FindName($name) }

    # Initial population
    $c.WorkfolderPath.Text = $Session.WorkFolderPath
    $c.Title              = "StepCreater — $($Session.Procedure.Title)"
    Update-StepListUI -Session $Session -ListBox $c.StepList

    # Stash references on the Window for later tasks/tests
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
```

Export `'Show-StepCreaterMainWindow'` and `'Update-StepListUI'` from psd1.

- [ ] **Step 2: Manual smoke — launch the window**

Create a smoke folder and run:

```powershell
$tmp = Join-Path $env:TEMP "sc-smoke-$([guid]::NewGuid())"
Import-Module .\StepCreater\StepCreater.psd1 -Force
New-StepCreaterWorkfolder -Path $tmp -Title 'GUI Smoke' | Out-Null

# Add some steps via the data layer first so the list is non-empty
$session = Open-StepCreaterWorkfolder -Path $tmp
$session.Procedure.AddStep('準備') | Out-Null
$session.Procedure.AddStep('実行') | Out-Null

Show-StepCreaterMainWindow -Session $session
```

Expected: Window opens, title shows "StepCreater — GUI Smoke", workfolder path visible, two items in the Step list ("[pending] 01: 準備" / "[pending] 02: 実行"). Detail panel is empty (Task 5 wires it). Close the window to continue.

Cleanup: `Remove-Item $tmp -Recurse -Force`

- [ ] **Step 3: Run lint + tests (should still all pass)**

```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 All
```

Expected: 38 tests pass.

- [ ] **Step 4: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1
git commit -m "StepCreater: Show-StepCreaterMainWindow + step list population"
```

---

## Task 5: Step Detail Editor — Selection & Edit Sync

**Files:**
- Modify: `StepCreater/StepCreater.psm1` (extend `Show-StepCreaterMainWindow` body)

- [ ] **Step 1: Add helpers and wire selection-change + textbox sync**

Replace the `Show-StepCreaterMainWindow` function body in `StepCreater.psm1` with the extended version. The previously-defined function had the selection wiring as a TODO. Now fill it in:

After the "Initial population" block (and before stashing `$window.Tag`), insert:

```powershell
    # State: which Step is currently selected
    $script:_currentStepIndex = -1

    # Load Step into editor controls
    $loadStep = {
        param($idx)
        if ($idx -lt 0 -or $idx -ge $Session.Procedure.Steps.Count) {
            $c.TxtTitle.Text    = ''
            $c.TxtBody.Text     = ''
            $c.TxtCommand.Text  = ''
            $c.TxtExpected.Text = ''
            $c.TxtNote.Text     = ''
            $c.CboStatus.SelectedIndex = -1
            $script:_currentStepIndex = -1
            return
        }
        $step = $Session.Procedure.Steps[$idx]
        $script:_suppressEdit = $true
        $c.TxtTitle.Text    = $step.Title
        $c.TxtBody.Text     = $step.BodyMarkdown
        $c.TxtCommand.Text  = $step.Command
        $c.TxtExpected.Text = $step.ExpectedResult
        $c.TxtNote.Text     = $step.Note
        $c.CboStatus.SelectedIndex = @('pending','done','ng','skipped').IndexOf($step.Status)
        $script:_suppressEdit = $false
        $script:_currentStepIndex = $idx
    }

    # Save editor controls back into Step
    $saveEdits = {
        if ($script:_suppressEdit) { return }
        if ($script:_currentStepIndex -lt 0) { return }
        $step = $Session.Procedure.Steps[$script:_currentStepIndex]
        $step.Title          = $c.TxtTitle.Text
        $step.BodyMarkdown   = $c.TxtBody.Text
        $step.Command        = $c.TxtCommand.Text
        $step.ExpectedResult = $c.TxtExpected.Text
        $step.Note           = $c.TxtNote.Text
        if ($c.CboStatus.SelectedIndex -ge 0) {
            $step.Status = @('pending','done','ng','skipped')[$c.CboStatus.SelectedIndex]
        }
        Update-StepListUI -Session $Session -ListBox $c.StepList
        $c.StepList.SelectedIndex = $script:_currentStepIndex
        Update-DirtyIndicator -Window $window
    }

    # Wire selection-changed on the list
    $c.StepList.Add_SelectionChanged({ & $loadStep $c.StepList.SelectedIndex }.GetNewClosure())

    # Wire LostFocus on editor textboxes (commit on blur to avoid thrashing the list)
    foreach ($tb in @($c.TxtTitle, $c.TxtBody, $c.TxtCommand, $c.TxtExpected, $c.TxtNote)) {
        $tb.Add_LostFocus($saveEdits)
    }
    $c.CboStatus.Add_SelectionChanged($saveEdits)
```

Also add the `Update-DirtyIndicator` helper (used here and in later tasks):

```powershell
function Update-DirtyIndicator {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Window)
    $tag = $Window.Tag
    if (-not $tag) { return }
    $current = Get-ProcedureHash -Procedure $tag.Session.Procedure
    $isDirty = ($current -ne $tag.Baseline)
    $tag.Controls.DirtyText.Text = if ($isDirty) { '● 未保存' } else { '' }
}
```

Export `'Update-DirtyIndicator'`.

- [ ] **Step 2: Manual smoke**

Re-run the smoke from Task 4 Step 2. Verify:
1. Click a step in the list → fields populate
2. Edit Title → blur → list label updates
3. Change Status → list label updates, status bar shows "● 未保存"

- [ ] **Step 3: Run lint + tests**

```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 All
```

Expected: 38 tests pass.

- [ ] **Step 4: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1
git commit -m "StepCreater: step detail editor with sync + dirty indicator"
```

---

## Task 6: Step List Operations (Add/Delete/Up/Down)

**Files:**
- Modify: `StepCreater/StepCreater.psm1`

- [ ] **Step 1: Wire the four step buttons**

Insert after the textbox wiring in `Show-StepCreaterMainWindow`:

```powershell
    $c.BtnAdd.Add_Click({
        $idx = if ($c.StepList.SelectedIndex -ge 0) { $c.StepList.SelectedIndex + 1 } else { $Session.Procedure.Steps.Count }
        Add-ProcedureStepAt -Procedure $Session.Procedure -Index $idx -Title '新しい手順' | Out-Null
        Update-StepListUI -Session $Session -ListBox $c.StepList
        $c.StepList.SelectedIndex = $idx
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
        Update-DirtyIndicator -Window $window
    }.GetNewClosure())

    $c.BtnUp.Add_Click({
        $idx = $c.StepList.SelectedIndex
        if ($idx -lt 1) { return }
        Move-ProcedureStep -Procedure $Session.Procedure -Index $idx -Direction Up
        Update-StepListUI -Session $Session -ListBox $c.StepList
        $c.StepList.SelectedIndex = $idx - 1
        Update-DirtyIndicator -Window $window
    }.GetNewClosure())

    $c.BtnDown.Add_Click({
        $idx = $c.StepList.SelectedIndex
        if ($idx -lt 0 -or $idx -ge $Session.Procedure.Steps.Count - 1) { return }
        Move-ProcedureStep -Procedure $Session.Procedure -Index $idx -Direction Down
        Update-StepListUI -Session $Session -ListBox $c.StepList
        $c.StepList.SelectedIndex = $idx + 1
        Update-DirtyIndicator -Window $window
    }.GetNewClosure())
```

- [ ] **Step 2: Manual smoke**

1. Launch window
2. Click "+" → new Step appears at end (or after selected)
3. Select Step 2, click "↑" → moves up
4. Click "↓" → moves down
5. Click "×" → confirm dialog → delete
6. After each: "● 未保存" appears

- [ ] **Step 3: Lint+tests**

```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 All
```

- [ ] **Step 4: Commit**

```bash
git add StepCreater/StepCreater.psm1
git commit -m "StepCreater: Step add/delete/move buttons"
```

---

## Task 7: Save / File Menu & Auto-Save on Step Changes

**Files:**
- Modify: `StepCreater/StepCreater.psm1`
- Modify: `StepCreater/StepCreater.psd1` (export `Save-WorkSession`)

- [ ] **Step 1: Add Save helper and wire buttons/menu**

Append to `StepCreater.psm1`:

```powershell
function Save-WorkSession {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [WorkSession]$Session)
    $Session.Procedure.Updated = Get-Date
    $md = Write-Procedure -Procedure $Session.Procedure
    $mdPath = Join-Path $Session.WorkFolderPath 'procedure.md'
    Set-Content -LiteralPath $mdPath -Value $md -Encoding UTF8
}
```

Export `'Save-WorkSession'`.

- [ ] **Step 1b: Backfill auto-save into the Step structure handlers from Task 6**

Per spec section 8, Step add/delete/reorder triggers auto-save. Update each of the four click handlers (`BtnAdd`, `BtnDelete`, `BtnUp`, `BtnDown`) added in Task 6: add a `Save-WorkSession -Session $Session` call at the end of each handler, followed by `$window.Tag.Baseline = Get-ProcedureHash -Procedure $Session.Procedure` (so the dirty indicator clears after auto-save). Also do the same in the template insertion handler (Task 10 — when that lands).

Example for `BtnAdd`:

```powershell
    $c.BtnAdd.Add_Click({
        $idx = if ($c.StepList.SelectedIndex -ge 0) { $c.StepList.SelectedIndex + 1 } else { $Session.Procedure.Steps.Count }
        Add-ProcedureStepAt -Procedure $Session.Procedure -Index $idx -Title '新しい手順' | Out-Null
        Update-StepListUI -Session $Session -ListBox $c.StepList
        $c.StepList.SelectedIndex = $idx
        Save-WorkSession -Session $Session
        $window.Tag.Baseline = Get-ProcedureHash -Procedure $Session.Procedure
        Update-DirtyIndicator -Window $window
    }.GetNewClosure())
```

Apply the same pattern to BtnDelete, BtnUp, BtnDown.

Inside `Show-StepCreaterMainWindow`, after the step button wiring, add:

```powershell
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
    $saveBinding = [System.Windows.Input.KeyBinding]::new(
        [System.Windows.Input.RoutedCommand]::new(),
        [System.Windows.Input.Key]::S,
        [System.Windows.Input.ModifierKeys]::Control
    )
    $saveCommand = [System.Windows.Input.RoutedCommand]::new()
    $cmdBinding = [System.Windows.Input.CommandBinding]::new(
        $saveCommand,
        { & $doSave }
    )
    $window.CommandBindings.Add($cmdBinding) | Out-Null
    $kb = [System.Windows.Input.KeyBinding]::new($saveCommand,
        [System.Windows.Input.Key]::S, [System.Windows.Input.ModifierKeys]::Control)
    $window.InputBindings.Add($kb) | Out-Null
```

- [ ] **Step 2: Manual smoke**

1. Launch window, edit a step
2. Click "保存" → `procedure.md` updated, indicator clears
3. Edit again, Ctrl+S → same effect
4. Open `procedure.md` in an external editor → confirm changes persisted

- [ ] **Step 3: Lint+tests**

```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 All
```

- [ ] **Step 4: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1
git commit -m "StepCreater: Save button + Ctrl+S + File menu Exit"
```

---

## Task 8: Unsaved-Changes Detection & ESC/Close Handler

**Files:**
- Modify: `StepCreater/StepCreater.psm1`

- [ ] **Step 1: Wire closing handler and ESC**

Inside `Show-StepCreaterMainWindow`, before `if ($NoShow)`:

```powershell
    $confirmDiscard = {
        $current = Get-ProcedureHash -Procedure $Session.Procedure
        if ($current -eq $window.Tag.Baseline) { return $true }  # nothing to confirm
        $r = [System.Windows.MessageBox]::Show(
            '未保存の変更があります。終了しますか？',
            '確認', 'OKCancel', 'Warning')
        return ($r -eq 'OK')
    }

    $window.Add_Closing({
        param($sender, $e)
        if (-not (& $confirmDiscard)) { $e.Cancel = $true }
    }.GetNewClosure())

    $window.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
            $window.Close()
        }
    }.GetNewClosure())
```

- [ ] **Step 2: Manual smoke**

1. Launch, make no edits, ESC → window closes silently
2. Launch, edit, ESC → confirm dialog → Cancel → window stays
3. Edit, click "保存", ESC → window closes silently (baseline updated)
4. Edit, click ✕ on title bar → confirm dialog appears

- [ ] **Step 3: Lint+tests**

```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 All
```

- [ ] **Step 4: Commit**

```bash
git add StepCreater/StepCreater.psm1
git commit -m "StepCreater: unsaved-changes confirm + ESC handler"
```

---

## Task 9: New / Open Workfolder File Menu

**Files:**
- Modify: `StepCreater/StepCreater.psm1`

- [ ] **Step 1: Wire New/Open menus with folder picker**

Inside `Show-StepCreaterMainWindow`, after Save wiring:

```powershell
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
        # Replace session in place
        $tag = $window.Tag
        $tag.Session = $newSession
        $tag.Baseline = Get-ProcedureHash -Procedure $newSession.Procedure
        $c.WorkfolderPath.Text = $newSession.WorkFolderPath
        $window.Title = "StepCreater — $($newSession.Procedure.Title)"
        # Re-bind session reference in closures by re-launching
        # Simplest robust approach: close + relaunch
        $window.Close()
        Show-StepCreaterMainWindow -Session $newSession
    }.GetNewClosure())

    $c.MenuNew.Add_Click({
        $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dlg.Description = '新規ワークフォルダの作成先を選択'
        if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

        # Prompt for title via InputBox-style dialog
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
```

- [ ] **Step 2: Manual smoke**

1. Launch with one workfolder
2. File → "ワークフォルダを開く" → pick another workfolder → switches
3. File → "新規ワークフォルダ" → pick empty dir → enter title → opens new
4. Unsaved changes prompt fires before switching

- [ ] **Step 3: Lint+tests**

```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 All
```

- [ ] **Step 4: Commit**

```bash
git add StepCreater/StepCreater.psm1
git commit -m "StepCreater: New/Open workfolder menu"
```

---

## Task 10: Template Insertion Menu

**Files:**
- Modify: `StepCreater/StepCreater.psm1`

- [ ] **Step 1: Populate templates menu and wire click**

Inside `Show-StepCreaterMainWindow`, after step button wiring:

```powershell
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
            Update-DirtyIndicator -Window $window
        }.GetNewClosure())
        $c.MenuTemplates.Items.Add($mi) | Out-Null
    }
```

Also add auto-save inside the template click handler (after `Update-DirtyIndicator`):

```powershell
            Save-WorkSession -Session $Session
            $window.Tag.Baseline = Get-ProcedureHash -Procedure $Session.Procedure
            Update-DirtyIndicator -Window $window
```

- [ ] **Step 2: Manual smoke**

1. Launch window
2. Templates menu shows "IIS Install" and "Windows Update"
3. Click one → new Step inserted with template fields populated → file saved automatically

- [ ] **Step 3: Lint+tests**

```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 All
```

- [ ] **Step 4: Commit**

```bash
git add StepCreater/StepCreater.psm1
git commit -m "StepCreater: template insertion menu"
```

---

## Task 11: Entry Script Launches GUI

**Files:**
- Modify: `StepCreater/StepCreater.ps1`

- [ ] **Step 1: Replace CLI listing with GUI launch**

Update the trailing portion of `StepCreater/StepCreater.ps1` (after the `-Init` block). Replace from `if (-not $WorkFolder)` to the end with:

```powershell
if (-not $WorkFolder) {
    # Prompt user to pick a workfolder
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
```

- [ ] **Step 2: End-to-end manual smoke**

```powershell
# Create a workfolder
$tmp = Join-Path $env:TEMP "sc-e2e-$([guid]::NewGuid())"
.\StepCreater\StepCreater.ps1 -Init -WorkFolder $tmp -Title "E2E Test"

# Launch GUI on it
.\StepCreater\StepCreater.ps1 -WorkFolder $tmp
```

Verify the full flow:
1. Window opens with title "StepCreater — E2E Test"
2. Add Step → fill fields → Ctrl+S → close
3. Reopen the workfolder: edits persisted

Cleanup: `Remove-Item $tmp -Recurse -Force`

- [ ] **Step 3: Final lint+tests**

```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 All
```

Expected: 38+ tests pass, lint clean.

- [ ] **Step 4: Commit**

```bash
git add StepCreater/StepCreater.ps1
git commit -m "StepCreater: launch GUI from entry script"
```

---

## Phase 2 Done Criteria

- [ ] `Invoke-Build All` passes (lint + ≥38 tests)
- [ ] `StepCreater.ps1 -WorkFolder <path>` opens the GUI
- [ ] Step list shows all Steps; selection populates detail editor
- [ ] Add / Delete (with confirm) / Up / Down all work and renumber IDs
- [ ] Save and Ctrl+S persist to `procedure.md`
- [ ] Step add/delete/move/template insert auto-save immediately (per spec §8)
- [ ] "● 未保存" indicator appears on changes and clears on save
- [ ] ESC and window close prompt confirm on unsaved changes
- [ ] File → New / Open switch workfolders (with unsaved confirm)
- [ ] Template menu lists IIS Install / Windows Update and inserts them
- [ ] Manual edit of `procedure.md` outside the tool round-trips correctly (unknown sections preserved)

Phase 3 (capture基盤: hotkeys, screenshot, annotation, unassigned tray) starts after this is merged.
