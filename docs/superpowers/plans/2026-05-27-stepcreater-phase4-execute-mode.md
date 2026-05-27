# StepCreater Phase 4: 作業実施モード & マスクエディタ Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 「作業実施モード」を有効化。手順書を読み取り専用で表示し、Step単位の完了／NG／スキップ操作、開始・完了時刻の自動記録、コマンドのワンクリックコピー、現Stepへのキャプチャ自動紐付けを実装。加えて画像マスクエディタ（黒塗り）を提供。

**Architecture:** 既存の MainWindow.xaml に「Execute モード用パネル」を追加し、`Visibility` トグルで Edit／Execute を切り替える。モード切替は `TabEdit`/`TabExecute` ラジオで駆動。Phase 3 のキャプチャパイプラインに「現Step ID」を渡せるよう拡張。マスクエディタは別の WPF Window として実装。

**Tech Stack:** PowerShell 5.1, WPF, System.Drawing (GDI+), Pester v5.

**Spec:** [../specs/2026-05-27-stepcreater-design.md](../specs/2026-05-27-stepcreater-design.md)

**Predecessor:** Phase 3（キャプチャ基盤）— must be merged.

---

## File Structure

```
StepCreater/
  StepCreater.psd1                       # MODIFY — export new functions
  StepCreater.psm1                       # MODIFY — execute-mode wiring, mask helpers
  ui/
    MainWindow.xaml                      # MODIFY — Execute mode panel + checklist styling
    MaskEditor.xaml                      # CREATE — mask editor window
  tests/
    ExecuteOps.Tests.ps1                 # CREATE — Complete/NG/Skip time logic
    Mask.Tests.ps1                       # CREATE — black-out rect application
    ProgressFormat.Tests.ps1             # CREATE — progress string formatting
```

---

## Task 1: MainWindow.xaml — Execute Mode Panel

**Files:**
- Modify: `StepCreater/ui/MainWindow.xaml`
- Modify: `StepCreater/tests/Xaml.Tests.ps1`

- [ ] **Step 1: Enable Execute tab and add execute panel**

Read `StepCreater/ui/MainWindow.xaml`. Change `TabExecute` `IsEnabled="False"` to `IsEnabled="True"`.

Then replace the current main content area `<Grid Margin="8">` so it contains BOTH the existing edit-mode UI (now wrapped in a Grid named `EditPanel`) AND a new `ExecutePanel`. Use `Visibility` to toggle them.

The new main content Grid should look like:

```xml
        <Grid Margin="8">
            <!-- Edit mode panel (existing layout) -->
            <Grid x:Name="EditPanel" Visibility="Visible">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="240"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <!-- ... existing Step list pane and detail editor unchanged ... -->
            </Grid>

            <!-- Execute mode panel (new) -->
            <Grid x:Name="ExecutePanel" Visibility="Collapsed">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="280"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <!-- Left: Step checklist -->
                <DockPanel Grid.Column="0" Margin="0,0,8,0">
                    <TextBlock DockPanel.Dock="Top" x:Name="ProgressLabel"
                               FontWeight="Bold" Margin="0,0,0,4"/>
                    <ListBox x:Name="ExecChecklist"/>
                </DockPanel>

                <!-- Right: current step viewer -->
                <Grid Grid.Column="1">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <TextBlock Grid.Row="0" x:Name="ExecStepTitle" FontSize="16" FontWeight="Bold" Margin="0,0,0,8"/>

                    <GroupBox Grid.Row="1" Header="手順">
                        <ScrollViewer VerticalScrollBarVisibility="Auto">
                            <TextBox x:Name="ExecBody" IsReadOnly="True" TextWrapping="Wrap"
                                     BorderThickness="0" Background="White"/>
                        </ScrollViewer>
                    </GroupBox>

                    <Grid Grid.Row="2" Margin="0,8,0,0">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <GroupBox Grid.Column="0" Header="実行コマンド">
                            <TextBox x:Name="ExecCommand" IsReadOnly="True" FontFamily="Consolas"
                                     BorderThickness="0" Background="WhiteSmoke" Padding="4"/>
                        </GroupBox>
                        <Button Grid.Column="1" x:Name="BtnCopyCommand" Content="コピー"
                                Margin="8,0,0,0" Padding="12,4" VerticalAlignment="Bottom"/>
                    </Grid>

                    <GroupBox Grid.Row="3" Header="想定結果" Margin="0,8,0,0">
                        <TextBox x:Name="ExecExpected" IsReadOnly="True" TextWrapping="Wrap"
                                 BorderThickness="0" Background="White"/>
                    </GroupBox>

                    <Grid Grid.Row="4" Margin="0,12,0,0">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <WrapPanel Grid.Column="0" x:Name="ExecEvidenceTray" Orientation="Horizontal"/>
                        <StackPanel Grid.Column="1" Orientation="Horizontal">
                            <Button x:Name="BtnComplete" Content="✓ 完了して次へ" Padding="14,6" Margin="0,0,4,0"/>
                            <Button x:Name="BtnNg"       Content="⚠ NG"             Padding="14,6" Margin="0,0,4,0"/>
                            <Button x:Name="BtnSkip"     Content="スキップ"         Padding="14,6"/>
                        </StackPanel>
                    </Grid>
                </Grid>
            </Grid>
        </Grid>
```

IMPORTANT: keep the existing Step list + detail editor markup intact INSIDE the new `<Grid x:Name="EditPanel">`. Move all of it into the EditPanel wrapper without changing any element names or attributes inside.

- [ ] **Step 2: Update Xaml.Tests.ps1**

Add the new named controls to the assertion list in `StepCreater/tests/Xaml.Tests.ps1`:

```
'EditPanel','ExecutePanel',
'ProgressLabel','ExecChecklist',
'ExecStepTitle','ExecBody','ExecCommand','BtnCopyCommand','ExecExpected',
'ExecEvidenceTray','BtnComplete','BtnNg','BtnSkip'
```

- [ ] **Step 3: Run All — expect pass + lint clean**

```powershell
cd C:\Users\kohji\data\claude\StepCreater
Invoke-Build -File StepCreater/StepCreater.build.ps1 All
```

Expected: 71 tests pass (XAML test now checks more controls).

- [ ] **Step 4: Commit**

```bash
git add StepCreater/ui/MainWindow.xaml StepCreater/tests/Xaml.Tests.ps1
git commit -m "Phase4: add Execute mode panel to MainWindow.xaml"
```

---

## Task 2: Progress Format Helper + Checklist Population

**Files:**
- Create: `StepCreater/tests/ProgressFormat.Tests.ps1`
- Modify: `StepCreater/StepCreater.psm1` (append `Get-ProgressLabel`, `Update-ExecChecklistUI`)
- Modify: `StepCreater/StepCreater.psd1` (export)

- [ ] **Step 1: Write failing tests**

`StepCreater/tests/ProgressFormat.Tests.ps1` (UTF-8 with BOM):

```powershell
using module '..\StepCreater.psd1'

Describe 'Get-ProgressLabel' {
    It 'counts done steps and total' {
        $doc = [ProcedureDoc]::new('X')
        $a = $doc.AddStep('A'); $a.Status = 'done'
        $b = $doc.AddStep('B'); $b.Status = 'done'
        $c = $doc.AddStep('C'); $c.Status = 'pending'
        Get-ProgressLabel -Procedure $doc | Should -Be '進捗: 2 / 3 (完了 2 / NG 0 / スキップ 0)'
    }

    It 'breaks down ng and skipped' {
        $doc = [ProcedureDoc]::new('X')
        $a = $doc.AddStep('A'); $a.Status = 'done'
        $b = $doc.AddStep('B'); $b.Status = 'ng'
        $c = $doc.AddStep('C'); $c.Status = 'skipped'
        $d = $doc.AddStep('D'); $d.Status = 'pending'
        Get-ProgressLabel -Procedure $doc | Should -Be '進捗: 3 / 4 (完了 1 / NG 1 / スキップ 1)'
    }

    It 'handles empty procedure' {
        $doc = [ProcedureDoc]::new('X')
        Get-ProgressLabel -Procedure $doc | Should -Be '進捗: 0 / 0 (完了 0 / NG 0 / スキップ 0)'
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement — append to `StepCreater/StepCreater.psm1`**

```powershell
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
```

Export `'Get-ProgressLabel'` and `'Update-ExecChecklistUI'`.

- [ ] **Step 4: Run All — expect pass**

Expected: 74 tests pass (71 + 3), lint clean.

- [ ] **Step 5: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1 StepCreater/tests/ProgressFormat.Tests.ps1
git commit -m "Phase4: progress label + execute mode checklist UI"
```

---

## Task 3: Step Status Transition Helpers (Complete / NG / Skip)

**Files:**
- Create: `StepCreater/tests/ExecuteOps.Tests.ps1`
- Modify: `StepCreater/StepCreater.psm1` (append `Set-StepStatus`)
- Modify: `StepCreater/StepCreater.psd1` (export)

- [ ] **Step 1: Write failing tests**

`StepCreater/tests/ExecuteOps.Tests.ps1` (UTF-8 with BOM):

```powershell
using module '..\StepCreater.psd1'

Describe 'Set-StepStatus' {
    BeforeEach {
        $script:doc = [ProcedureDoc]::new('Doc')
        $script:step = $script:doc.AddStep('A')
    }

    It 'records Started when transitioning from pending to in-progress (done)' {
        $before = Get-Date
        Set-StepStatus -Step $script:step -Status 'done'
        $script:step.Status   | Should -Be 'done'
        $script:step.Started  | Should -Not -BeNullOrEmpty
        $script:step.Finished | Should -Not -BeNullOrEmpty
        $script:step.Started  | Should -BeGreaterOrEqual $before
    }

    It 'records Started but not Finished when status is non-terminal (not currently used but invariant)' {
        # All Phase 4 transitions are terminal (done/ng/skipped); pending is reset
        Set-StepStatus -Step $script:step -Status 'pending'
        $script:step.Status   | Should -Be 'pending'
        $script:step.Started  | Should -BeNullOrEmpty
        $script:step.Finished | Should -BeNullOrEmpty
    }

    It 'preserves prior Started time on subsequent terminal transitions' {
        Set-StepStatus -Step $script:step -Status 'done'
        $firstStart = $script:step.Started
        Start-Sleep -Milliseconds 20
        Set-StepStatus -Step $script:step -Status 'ng'
        $script:step.Started | Should -Be $firstStart
        $script:step.Status  | Should -Be 'ng'
    }

    It 'sets Finished anew on each terminal transition' {
        Set-StepStatus -Step $script:step -Status 'done'
        $firstFinish = $script:step.Finished
        Start-Sleep -Milliseconds 20
        Set-StepStatus -Step $script:step -Status 'skipped'
        $script:step.Finished | Should -BeGreaterThan $firstFinish
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement — append to `StepCreater/StepCreater.psm1`**

```powershell
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
    # Terminal: done | ng | skipped
    if (-not $Step.Started) { $Step.Started = $now }
    $Step.Finished = $now
    $Step.Status   = $Status
}
```

Export `'Set-StepStatus'`.

- [ ] **Step 4: Run All — expect pass**

Expected: 78 tests pass (74 + 4).

- [ ] **Step 5: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1 StepCreater/tests/ExecuteOps.Tests.ps1
git commit -m "Phase4: Set-StepStatus with auto-timestamp"
```

---

## Task 4: Mode Toggle Wiring + Execute Mode Population

**Files:**
- Modify: `StepCreater/StepCreater.psm1` (extend `Show-StepCreaterMainWindow`)

- [ ] **Step 1: Add execute mode helpers in Show-StepCreaterMainWindow**

In the `$c` hashtable lookup list (`foreach ($name in @(...))`), add:

```
'EditPanel','ExecutePanel',
'ProgressLabel','ExecChecklist',
'ExecStepTitle','ExecBody','ExecCommand','BtnCopyCommand','ExecExpected',
'ExecEvidenceTray','BtnComplete','BtnNg','BtnSkip'
```

After the existing Edit-mode wiring and BEFORE the `Add_Loaded` for hotkeys, add:

```powershell
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

        # Evidence thumbnails for current step
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

    # Apply initial mode based on Session.Mode
    & $applyMode $Session.Mode
```

- [ ] **Step 2: Run All — expect pass + lint clean**

Expected: 78 tests still pass.

- [ ] **Step 3: Commit**

```bash
git add StepCreater/StepCreater.psm1
git commit -m "Phase4: mode toggle + Execute mode initial population"
```

---

## Task 5: Copy Command + Complete/NG/Skip Buttons

**Files:**
- Modify: `StepCreater/StepCreater.psm1`

- [ ] **Step 1: Wire the four buttons**

In `Show-StepCreaterMainWindow`, after the execute mode helpers from Task 4, add:

```powershell
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
```

- [ ] **Step 2: Run All — expect pass + lint clean**

Expected: 78 tests still pass.

- [ ] **Step 3: Commit**

```bash
git add StepCreater/StepCreater.psm1
git commit -m "Phase4: Copy command + Complete/NG/Skip buttons"
```

---

## Task 6: Auto-Capture to Current Step in Execute Mode

**Files:**
- Modify: `StepCreater/StepCreater.psm1` (modify the `Add_Loaded` capture handler)

- [ ] **Step 1: Route captures by mode**

Find the `$captureHandler` closure inside `$window.Add_Loaded({...})` (added in Phase 3 Task 11). Replace its body so that in Execute mode the current step receives the capture. Replace `Save-StepCreaterCapture -Session $Session -Kind $kind -StepId ''` with:

```powershell
                $stepId = ''
                if ($Session.Mode -eq 'Execute' -and $c.ExecChecklist.SelectedIndex -ge 0) {
                    $stepId = $Session.Procedure.Steps[$c.ExecChecklist.SelectedIndex].Id
                }
                Save-StepCreaterCapture -Session $Session -Kind $kind -StepId $stepId | Out-Null
                if ($Session.Mode -eq 'Execute') {
                    Update-ExecChecklistUI -Session $Session -ListBox $c.ExecChecklist -ProgressLabel $c.ProgressLabel
                    & $loadExecStep $c.ExecChecklist.SelectedIndex
                } else {
                    Update-UnassignedTrayUI -Session $Session -TrayPanel $c.UnassignedTray -OnAssign $assignToCurrent
                }
```

(The rest of the handler — `Save-WorkSession`, baseline update, status message — stays the same.)

- [ ] **Step 2: Run All — expect pass + lint clean**

- [ ] **Step 3: Commit**

```bash
git add StepCreater/StepCreater.psm1
git commit -m "Phase4: route captures to current Step in Execute mode"
```

---

## Task 7: MaskEditor.xaml + Black-out Logic

**Files:**
- Create: `StepCreater/ui/MaskEditor.xaml`
- Create: `StepCreater/tests/Mask.Tests.ps1`
- Modify: `StepCreater/StepCreater.psm1` (append `Add-BlackoutRect`)
- Modify: `StepCreater/StepCreater.psd1` (export)

- [ ] **Step 1: Create XAML (UTF-8 with BOM)**

`StepCreater/ui/MaskEditor.xaml`:

```xml
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="マスクエディタ" Height="700" Width="1000"
        WindowStartupLocation="CenterScreen">
    <DockPanel>
        <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="8">
            <TextBlock VerticalAlignment="Center" Text="ドラッグで矩形を描画 → [追加] で黒塗り。Ctrl+Z で1つ戻す。保存で確定。"
                       Foreground="DimGray"/>
        </StackPanel>
        <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" HorizontalAlignment="Right" Margin="8">
            <Button x:Name="BtnAddRect" Content="追加"   Padding="12,4" Margin="0,0,4,0"/>
            <Button x:Name="BtnUndo"    Content="戻す"   Padding="12,4" Margin="0,0,4,0"/>
            <Button x:Name="BtnSave"    Content="保存"   Padding="12,4" Margin="0,0,4,0"/>
            <Button x:Name="BtnCancel"  Content="キャンセル" Padding="12,4"/>
        </StackPanel>
        <Grid>
            <Image x:Name="ImgCanvas" Stretch="None"/>
            <Canvas x:Name="OverlayCanvas" Background="Transparent">
                <Rectangle x:Name="DragRect" Stroke="Red" StrokeThickness="2"
                           Fill="#33FF0000" Visibility="Collapsed"/>
            </Canvas>
        </Grid>
    </DockPanel>
</Window>
```

- [ ] **Step 2: Write failing tests for Add-BlackoutRect**

`StepCreater/tests/Mask.Tests.ps1` (UTF-8 with BOM):

```powershell
using module '..\StepCreater.psd1'

Describe 'Add-BlackoutRect' {
    BeforeAll {
        Add-Type -AssemblyName System.Drawing
    }

    It 'returns a bitmap with the rect area filled black' {
        $src = New-Object System.Drawing.Bitmap 100, 100
        # Fill source with white
        $g = [System.Drawing.Graphics]::FromImage($src)
        $g.FillRectangle([System.Drawing.Brushes]::White, 0, 0, 100, 100)
        $g.Dispose()

        $rect = New-Object System.Drawing.Rectangle 10, 10, 30, 30
        $out = Add-BlackoutRect -SourceBitmap $src -Rect $rect

        # Pixel inside the rect should be black
        $p = $out.GetPixel(20, 20)
        $p.R | Should -Be 0
        $p.G | Should -Be 0
        $p.B | Should -Be 0

        # Pixel outside should remain white
        $q = $out.GetPixel(80, 80)
        $q.R | Should -Be 255
        $q.G | Should -Be 255
        $q.B | Should -Be 255
    }

    It 'returns same dimensions as input' {
        $src = New-Object System.Drawing.Bitmap 200, 150
        $out = Add-BlackoutRect -SourceBitmap $src -Rect (New-Object System.Drawing.Rectangle 0, 0, 10, 10)
        $out.Width  | Should -Be 200
        $out.Height | Should -Be 150
    }
}
```

- [ ] **Step 3: Run, expect failure**

- [ ] **Step 4: Implement — append to `StepCreater/StepCreater.psm1`**

```powershell
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
```

Export `'Add-BlackoutRect'`.

- [ ] **Step 5: Run All — expect pass**

Expected: 80 tests pass (78 + 2).

- [ ] **Step 6: Commit**

```bash
git add StepCreater/ui/MaskEditor.xaml StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1 StepCreater/tests/Mask.Tests.ps1
git commit -m "Phase4: MaskEditor.xaml + Add-BlackoutRect"
```

---

## Task 8: Show-MaskEditor (Window Logic) + Originals Retention

**Files:**
- Modify: `StepCreater/StepCreater.psm1` (append `Show-MaskEditor`)
- Modify: `StepCreater/StepCreater.psd1` (export)

- [ ] **Step 1: Implement — append to `StepCreater/StepCreater.psm1`**

```powershell
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

    # Working copy of bitmap (in-memory)
    $current = [System.Drawing.Bitmap]::FromFile($ImagePath)
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
        # Retain original
        $imagesDir = Split-Path -Parent $ImagePath
        $originalsDir = Join-Path $imagesDir '.originals'
        if (-not (Test-Path -LiteralPath $originalsDir)) {
            New-Item -ItemType Directory -Path $originalsDir -Force | Out-Null
        }
        $originalDest = Join-Path $originalsDir (Split-Path -Leaf $ImagePath)
        if (-not (Test-Path -LiteralPath $originalDest)) {
            Copy-Item -LiteralPath $ImagePath -Destination $originalDest -Force
        }
        $current.Save($ImagePath, [System.Drawing.Imaging.ImageFormat]::Png)
        $state.Saved = $true
        $win.Close()
    }.GetNewClosure())

    $btnCancel.Add_Click({ $win.Close() }.GetNewClosure())

    $win.Add_KeyDown({
        if ($_.Key -eq [System.Windows.Input.Key]::Escape) { $win.Close() }
    }.GetNewClosure())

    [void]$win.ShowDialog()

    # Dispose all bitmaps
    foreach ($b in $history) { $b.Dispose() }
    $current.Dispose()

    return $state.Saved
}
```

Export `'Show-MaskEditor'`.

- [ ] **Step 2: Run All — expect pass + lint clean (no new tests; window requires display)**

Expected: 80 tests still pass.

- [ ] **Step 3: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1
git commit -m "Phase4: Show-MaskEditor with originals retention"
```

---

## Task 9: Double-Click Thumbnail to Open Mask Editor

Connect mask editor to the existing unassigned tray (Phase 3) and the new ExecEvidenceTray.

**Files:**
- Modify: `StepCreater/StepCreater.psm1`

- [ ] **Step 1: Update `Update-UnassignedTrayUI`**

Find `Update-UnassignedTrayUI`. After `$btn.Add_Click({ & $OnAssign $refLocal }.GetNewClosure())`, ALSO wire double-click for mask:

```powershell
        $sessionLocal = $Session
        $btn.AddHandler([System.Windows.UIElement]::MouseDoubleClickEvent, {
            $path = Join-Path $sessionLocal.WorkFolderPath ("images/" + $refLocal.FileName)
            if (Show-MaskEditor -ImagePath $path) {
                # nothing to refresh here — the image path is unchanged; bitmap cache may need flush
            }
        }.GetNewClosure())
```

This intentionally piggy-backs on the existing click handler; users single-click to assign, double-click to mask.

- [ ] **Step 2: Wire double-click in `$loadExecStep`**

In `Show-StepCreaterMainWindow`, find the foreach where `$img` is created inside `$loadExecStep`. After `$c.ExecEvidenceTray.Children.Add($img) | Out-Null`, replace the simple `Image` add with a `Button` wrapping the image, OR add a mouse handler. Simpler: change the image element to be wrapped in a Button just for the click target:

Find the Image creation block in `$loadExecStep` and replace with:

```powershell
            $btn = New-Object System.Windows.Controls.Button
            $btn.Width = 110; $btn.Height = 78; $btn.Margin = '2'; $btn.Padding = 0
            $btn.ToolTip = $ev.FileName + ' (ダブルクリックでマスク編集)'
            $img = New-Object System.Windows.Controls.Image
            $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
            $bmp.BeginInit(); $bmp.CacheOption = 'OnLoad'
            $bmp.UriSource = (New-Object System.Uri $path)
            $bmp.DecodePixelWidth = 200
            $bmp.EndInit()
            $img.Source = $bmp; $img.Stretch = 'Uniform'
            $btn.Content = $img

            $evLocal = $ev
            $sessionLocal = $Session
            $btn.AddHandler([System.Windows.UIElement]::MouseDoubleClickEvent, {
                $imgPath = Join-Path $sessionLocal.WorkFolderPath ("images/" + $evLocal.FileName)
                [void](Show-MaskEditor -ImagePath $imgPath)
                # Re-render the step to refresh thumbnails
                & $loadExecStep $c.ExecChecklist.SelectedIndex
            }.GetNewClosure())

            $c.ExecEvidenceTray.Children.Add($btn) | Out-Null
```

- [ ] **Step 3: Run All — expect pass + lint clean**

- [ ] **Step 4: Commit**

```bash
git add StepCreater/StepCreater.psm1
git commit -m "Phase4: double-click thumbnail to open mask editor"
```

---

## Task 10: Final Integration Smoke

**Files:** (no code changes — verification only)

- [ ] **Step 1: Programmatic end-to-end smoke**

```powershell
cd C:\Users\kohji\data\claude\StepCreater
Import-Module .\StepCreater\StepCreater.psd1 -Force
$tmp = Join-Path $env:TEMP "sc-p4-final-$([guid]::NewGuid())"
New-StepCreaterWorkfolder -Path $tmp -Title 'Phase 4 Final' | Out-Null
$session = Open-StepCreaterWorkfolder -Path $tmp

# Add steps via model
$a = $session.Procedure.AddStep('A')
$a.BodyMarkdown = 'Do A'
$a.Command = 'Get-Process'

$b = $session.Procedure.AddStep('B')
Save-WorkSession -Session $session

# Window construction in Execute mode
$session.Mode = 'Execute'
$win = Show-StepCreaterMainWindow -Session $session -NoShow

# Verify execute panel is visible
$win.FindName('ExecutePanel').Visibility | Out-Host
$win.FindName('EditPanel').Visibility    | Out-Host
$win.FindName('ExecChecklist').Items.Count | Out-Host
$win.FindName('ProgressLabel').Text | Out-Host

# Trigger status change
Set-StepStatus -Step $a -Status 'done'
Update-ExecChecklistUI -Session $session -ListBox $win.FindName('ExecChecklist') -ProgressLabel $win.FindName('ProgressLabel')
$win.FindName('ProgressLabel').Text | Out-Host
$a.Started  | Out-Host
$a.Finished | Out-Host

Remove-Item $tmp -Recurse -Force
```

Expected:
- `ExecutePanel` Visibility = Visible, `EditPanel` = Collapsed
- ExecChecklist has 2 items
- Initial progress: `進捗: 0 / 2 (完了 0 / NG 0 / スキップ 0)`
- After Set-StepStatus done on A: `進捗: 1 / 2 (完了 1 / NG 0 / スキップ 0)`
- `$a.Started` and `$a.Finished` are non-null datetimes

- [ ] **Step 2: Final build**

```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 All
```

Expected: 80 tests pass, lint clean.

- [ ] **Step 3: No commit needed unless smoke surfaced issues.**

---

## Phase 4 Done Criteria

- [ ] `Invoke-Build All` passes (lint + ≥80 tests)
- [ ] Execute タブが有効化され、Edit と切り替え可能
- [ ] Execute モード時にチェックリストと進捗ラベルが表示される
- [ ] 「コピー」で実行コマンドがクリップボードへ
- [ ] 「完了」「NG」「スキップ」で `Status` と `Started`/`Finished` が更新され、自動保存される
- [ ] 完了で次Stepへ自動進行（NGは留まる）
- [ ] Execute モード時のキャプチャは現Stepの Evidence に自動紐付け
- [ ] サムネをダブルクリックでマスクエディタが起動
- [ ] マスク保存時に `images/.originals/` に原本が退避される

Phase 5（HTML出力／設定画面／仕上げ）は本フェーズマージ後に着手。
