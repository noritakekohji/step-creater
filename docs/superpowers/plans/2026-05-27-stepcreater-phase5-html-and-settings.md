# StepCreater Phase 5: HTML出力 & 設定画面 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 手順書を HTML として出力（目次・Lightbox 拡大・印刷用 CSS・Step ごとの作業時間表示）し、ホットキーやアノテーション設定を GUI から変更できるようにする。

**Architecture:** HTML生成は純関数 `ConvertTo-ProcedureHtml`（ProcedureDoc → string）で実装し Pester でテスト。ファイル菜単に「HTML出力」を追加。設定ダイアログは別 WPF Window（`SettingsDialog.xaml`）で、保存時に `Set-StepCreaterConfig` を呼び、ホットキーは即時 re-register。

**Tech Stack:** PowerShell 5.1, WPF, System.Drawing (for Base64 image embedding option), Pester v5.

**Spec:** [../specs/2026-05-27-stepcreater-design.md](../specs/2026-05-27-stepcreater-design.md)

**Predecessor:** Phase 4（作業実施モード）— must be merged.

---

## File Structure

```
StepCreater/
  StepCreater.psd1                       # MODIFY — export new functions
  StepCreater.psm1                       # MODIFY — html generator, settings dialog
  ui/
    MainWindow.xaml                      # MODIFY — add "HTML出力" menu item, "設定" menu
    SettingsDialog.xaml                  # CREATE — settings UI
  tests/
    Html.Tests.ps1                       # CREATE — html generator
    StepDuration.Tests.ps1               # CREATE — duration helper
```

---

## Task 1: Step Duration Helper

Pure function: given a Step, return its working time as a formatted string ("00:05:23") or `'-'` if not started/finished.

**Files:**
- Create: `StepCreater/tests/StepDuration.Tests.ps1`
- Modify: `StepCreater/StepCreater.psm1` (append `Get-StepDuration`)
- Modify: `StepCreater/StepCreater.psd1` (export)

- [ ] **Step 1: Write failing tests**

`StepCreater/tests/StepDuration.Tests.ps1` (UTF-8 with BOM):

```powershell
using module '..\StepCreater.psd1'

Describe 'Get-StepDuration' {
    It 'returns "-" when Started is null' {
        $s = [Step]::new('01', 'A')
        Get-StepDuration -Step $s | Should -Be '-'
    }

    It 'returns "-" when Finished is null' {
        $s = [Step]::new('01', 'A')
        $s.Started = Get-Date
        Get-StepDuration -Step $s | Should -Be '-'
    }

    It 'returns formatted HH:mm:ss for a 5m23s span' {
        $s = [Step]::new('01', 'A')
        $s.Started  = [datetime]'2026-05-27T10:00:00'
        $s.Finished = [datetime]'2026-05-27T10:05:23'
        Get-StepDuration -Step $s | Should -Be '00:05:23'
    }

    It 'returns HH:mm:ss for a >1h span' {
        $s = [Step]::new('01', 'A')
        $s.Started  = [datetime]'2026-05-27T10:00:00'
        $s.Finished = [datetime]'2026-05-27T11:30:45'
        Get-StepDuration -Step $s | Should -Be '01:30:45'
    }
}
```

- [ ] **Step 2: Run, expect failure**

```powershell
cd C:\Users\kohji\data\claude\StepCreater
Invoke-Build -File StepCreater/StepCreater.build.ps1 Test
```

- [ ] **Step 3: Implement — append to `StepCreater/StepCreater.psm1`**

```powershell
function Get-StepDuration {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [Step]$Step)
    if (-not $Step.Started -or -not $Step.Finished) { return '-' }
    $span = $Step.Finished - $Step.Started
    return ('{0:D2}:{1:D2}:{2:D2}' -f [int]$span.TotalHours, $span.Minutes, $span.Seconds)
}
```

Export `'Get-StepDuration'`.

- [ ] **Step 4: Run All — expect pass**

Expected: 91 tests pass (87 + 4), lint clean.

- [ ] **Step 5: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1 StepCreater/tests/StepDuration.Tests.ps1
git commit -m "Phase5: Get-StepDuration helper"
```

---

## Task 2: HTML Generator

`ConvertTo-ProcedureHtml -Procedure <doc>` → string containing standalone HTML with:
- `<!DOCTYPE html>` and embedded CSS (print-friendly)
- Title from procedure
- Table of contents (linked anchors)
- Per-Step section: status badge, working time, body, command (code block), expected result, evidence (clickable images opening Lightbox div), note
- Lightbox: click image → overlay full-size, click overlay to dismiss
- Images use relative paths (`images/...`)

**Files:**
- Create: `StepCreater/tests/Html.Tests.ps1`
- Modify: `StepCreater/StepCreater.psm1` (append `ConvertTo-ProcedureHtml`)
- Modify: `StepCreater/StepCreater.psd1` (export)

- [ ] **Step 1: Write failing tests**

`StepCreater/tests/Html.Tests.ps1` (UTF-8 with BOM):

```powershell
using module '..\StepCreater.psd1'

Describe 'ConvertTo-ProcedureHtml' {
    BeforeAll {
        $script:doc = [ProcedureDoc]::new('Test Procedure')
        $script:doc.Author = 'tester'
        $script:doc.Created = [datetime]'2026-05-27'
        $a = $script:doc.AddStep('IIS Install')
        $a.BodyMarkdown   = 'Install **IIS** via PowerShell.'
        $a.Command        = 'Install-WindowsFeature -Name Web-Server'
        $a.ExpectedResult = 'Exit code 0'
        $a.Status         = 'done'
        $a.Started        = [datetime]'2026-05-27T10:00:00'
        $a.Finished       = [datetime]'2026-05-27T10:05:23'
        $a.Note           = 'May need restart.'
        $a.Evidence.Add([ScreenshotRef]::new('images/a.png', [datetime]'2026-05-27', 'full')) | Out-Null

        $b = $script:doc.AddStep('Configure')
        $b.Status = 'pending'

        $script:html = ConvertTo-ProcedureHtml -Procedure $script:doc
    }

    It 'returns a string starting with <!DOCTYPE html>' {
        $script:html | Should -Match '^<!DOCTYPE html>'
    }

    It 'includes the procedure title in <title> and h1' {
        $script:html | Should -Match '<title>Test Procedure</title>'
        $script:html | Should -Match '<h1[^>]*>Test Procedure</h1>'
    }

    It 'includes a table of contents linking to each step' {
        $script:html | Should -Match 'href="#step-01"'
        $script:html | Should -Match 'href="#step-02"'
    }

    It 'shows status badges' {
        $script:html | Should -Match 'badge-done'
        $script:html | Should -Match 'badge-pending'
    }

    It 'shows working time for completed steps' {
        $script:html | Should -Match '00:05:23'
    }

    It 'renders evidence images with relative paths' {
        $script:html | Should -Match 'src="images/a\.png"'
    }

    It 'renders code block for command' {
        $script:html | Should -Match 'Install-WindowsFeature -Name Web-Server'
        $script:html | Should -Match '<pre'
    }

    It 'escapes HTML entities in user content' {
        $doc2 = [ProcedureDoc]::new('Test & Title')
        $s = $doc2.AddStep('A < B')
        $s.BodyMarkdown = '<script>alert(1)</script>'
        $html = ConvertTo-ProcedureHtml -Procedure $doc2
        $html | Should -Match 'Test &amp; Title'
        $html | Should -Match 'A &lt; B'
        $html | Should -Not -Match '<script>alert\(1\)</script>'
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement — append to `StepCreater/StepCreater.psm1`**

```powershell
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
.lightbox { display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.85); z-index: 100; justify-content: center; align-items: center; cursor: zoom-out; }
.lightbox.visible { display: flex; }
.lightbox img { max-width: 95%; max-height: 95%; }
@media print {
    .toc { page-break-after: always; }
    h2 { page-break-before: always; }
    .evidence img { max-width: 100%; max-height: none; page-break-inside: avoid; }
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

    # TOC
    [void]$sb.AppendLine('<div class="toc"><strong>目次</strong><ol>')
    foreach ($step in $Procedure.Steps) {
        $stTitle = & $esc $step.Title
        [void]$sb.AppendLine("<li><a href=`"#step-$($step.Id)`">Step $($step.Id): $stTitle</a></li>")
    }
    [void]$sb.AppendLine('</ol></div>')

    # Steps
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
        if ($step.Command) {
            [void]$sb.AppendLine('<div class="section"><h3>実行コマンド</h3><pre>' + (& $esc $step.Command) + '</pre></div>')
        }
        if ($step.ExpectedResult) {
            [void]$sb.AppendLine('<div class="section"><h3>想定結果</h3><div>' + (& $esc $step.ExpectedResult) + '</div></div>')
        }
        if ($step.Evidence.Count -gt 0) {
            [void]$sb.AppendLine('<div class="section evidence"><h3>エビデンス</h3><div>')
            foreach ($ev in $step.Evidence) {
                $src = & $esc $ev.FileName
                [void]$sb.AppendLine("<img src=`"$src`" alt=`"$src`" onclick=`"sc_lb(this.src)`">")
            }
            [void]$sb.AppendLine('</div></div>')
        }
        if ($step.Note) {
            [void]$sb.AppendLine('<div class="section"><h3>備考</h3><div>' + (& $esc $step.Note) + '</div></div>')
        }
    }

    # Lightbox + script
    [void]$sb.AppendLine('<div class="lightbox" id="sc_lightbox" onclick="this.classList.remove(''visible'')"><img id="sc_lb_img"></div>')
    [void]$sb.AppendLine('<script>function sc_lb(src){var lb=document.getElementById("sc_lightbox");document.getElementById("sc_lb_img").src=src;lb.classList.add("visible");}</script>')
    [void]$sb.AppendLine('</body></html>')

    return $sb.ToString()
}
```

Export `'ConvertTo-ProcedureHtml'`.

- [ ] **Step 4: Run All — expect pass**

Expected: 99 tests pass (91 + 8), lint clean.

- [ ] **Step 5: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1 StepCreater/tests/Html.Tests.ps1
git commit -m "Phase5: HTML generator (ToC + Lightbox + print CSS + duration)"
```

---

## Task 3: HTML Output Menu Item

**Files:**
- Modify: `StepCreater/ui/MainWindow.xaml` (add menu item)
- Modify: `StepCreater/StepCreater.psm1` (wire menu)
- Modify: `StepCreater/tests/Xaml.Tests.ps1` (add named control)

- [ ] **Step 1: Add menu item to MainWindow.xaml**

In the `<MenuItem Header="ファイル(_F)">` block, AFTER `<MenuItem x:Name="MenuSave" ... />`, insert:

```xml
                <MenuItem x:Name="MenuExportHtml" Header="HTML出力(_E)..."/>
```

(Keep separators / Exit as-is.)

- [ ] **Step 2: Add MenuExportHtml to Xaml.Tests.ps1 named-controls list**

- [ ] **Step 3: Wire menu in Show-StepCreaterMainWindow**

In the `$c` lookup foreach, ADD `'MenuExportHtml'`. After the save wiring (Task 7 of Phase 2 — `$c.MenuSave.Add_Click...`), add:

```powershell
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
```

- [ ] **Step 4: Run All — expect pass + lint clean**

```powershell
cd C:\Users\kohji\data\claude\StepCreater
Invoke-Build -File StepCreater/StepCreater.build.ps1 All
```

Expected: 99 tests still pass (XAML test now also checks MenuExportHtml).

- [ ] **Step 5: Commit**

```bash
git add StepCreater/ui/MainWindow.xaml StepCreater/StepCreater.psm1 StepCreater/tests/Xaml.Tests.ps1
git commit -m "Phase5: HTML出力 menu item"
```

---

## Task 4: SettingsDialog.xaml

**Files:**
- Create: `StepCreater/ui/SettingsDialog.xaml`

- [ ] **Step 1: Create XAML** (UTF-8 with BOM)

`StepCreater/ui/SettingsDialog.xaml`:

```xml
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="設定" Height="380" Width="480"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
    <DockPanel Margin="12">
        <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button x:Name="BtnOk"     Content="OK"       Padding="14,4" Margin="0,0,4,0"/>
            <Button x:Name="BtnCancel" Content="キャンセル" Padding="14,4"/>
        </StackPanel>

        <StackPanel>
            <TextBlock FontWeight="Bold" Text="ホットキー" Margin="0,0,0,6"/>
            <Grid Margin="0,0,0,12">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="140"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <TextBlock Grid.Row="0" Grid.Column="0" Text="全画面" VerticalAlignment="Center"/>
                <TextBox   Grid.Row="0" Grid.Column="1" x:Name="TxtHkFull"   Margin="0,2"/>
                <TextBlock Grid.Row="1" Grid.Column="0" Text="アクティブウィンドウ" VerticalAlignment="Center"/>
                <TextBox   Grid.Row="1" Grid.Column="1" x:Name="TxtHkWindow" Margin="0,2"/>
                <TextBlock Grid.Row="2" Grid.Column="0" Text="矩形選択" VerticalAlignment="Center"/>
                <TextBox   Grid.Row="2" Grid.Column="1" x:Name="TxtHkRect"   Margin="0,2"/>
            </Grid>

            <TextBlock FontWeight="Bold" Text="アノテーション" Margin="0,8,0,6"/>
            <CheckBox x:Name="ChkAnnotation" Content="マウス位置に赤丸とキャプションバーを追加する"/>

            <TextBlock FontStyle="Italic" Foreground="DimGray" TextWrapping="Wrap" Margin="0,16,0,0"
                       Text="例: Ctrl+F12, Ctrl+Shift+F11, Alt+S。OKで保存し、ホットキーは即時再登録されます。"/>
        </StackPanel>
    </DockPanel>
</Window>
```

- [ ] **Step 2: Add a parse test in Xaml.Tests.ps1**

Append a new Describe block at the end of `StepCreater/tests/Xaml.Tests.ps1`:

```powershell
Describe 'SettingsDialog.xaml' {
    BeforeAll {
        Add-Type -AssemblyName PresentationFramework
        $script:sxPath = Join-Path $PSScriptRoot '..\ui\SettingsDialog.xaml'
    }

    It 'file exists' { Test-Path $script:sxPath | Should -BeTrue }

    It 'parses without error' {
        $xml = [xml](Get-Content -LiteralPath $script:sxPath -Raw)
        $reader = [System.Xml.XmlNodeReader]::new($xml)
        $win = [Windows.Markup.XamlReader]::Load($reader)
        $win.GetType().Name | Should -Be 'Window'
        foreach ($n in @('TxtHkFull','TxtHkWindow','TxtHkRect','ChkAnnotation','BtnOk','BtnCancel')) {
            $win.FindName($n) | Should -Not -BeNullOrEmpty
        }
    }
}
```

- [ ] **Step 3: Run All — expect pass**

Expected: 101 tests pass (99 + 2).

- [ ] **Step 4: Commit**

```bash
git add StepCreater/ui/SettingsDialog.xaml StepCreater/tests/Xaml.Tests.ps1
git commit -m "Phase5: SettingsDialog.xaml"
```

---

## Task 5: Show-SettingsDialog (Logic + Persistence) + Settings Menu Item + Hotkey Hot-Reload

**Files:**
- Modify: `StepCreater/ui/MainWindow.xaml` (add MenuSettings)
- Modify: `StepCreater/tests/Xaml.Tests.ps1` (add MenuSettings)
- Modify: `StepCreater/StepCreater.psm1` (append `Show-SettingsDialog`, wire menu, hot-reload hotkeys)
- Modify: `StepCreater/StepCreater.psd1` (export)

- [ ] **Step 1: Add MenuSettings to MainWindow.xaml**

In the existing menu bar, after the File menu, add a new top-level menu:

```xml
            <MenuItem x:Name="MenuSettings" Header="設定(_S)..."/>
```

Add `'MenuSettings'` to the Xaml.Tests.ps1 list.

- [ ] **Step 2: Implement Show-SettingsDialog**

Append to `StepCreater/StepCreater.psm1`:

```powershell
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
        # Validate combos by parsing — throw if invalid
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
```

Export `'Show-SettingsDialog'`.

- [ ] **Step 3: Wire MenuSettings inside Show-StepCreaterMainWindow with hotkey hot-reload**

Add `'MenuSettings'` to the `$c` hashtable lookup list.

After the existing menu wiring (somewhere reasonable, e.g. after MenuExportHtml from Task 3) and BEFORE the `Add_Loaded` block, insert:

```powershell
    $c.MenuSettings.Add_Click({
        if (-not (Show-SettingsDialog -Owner $window)) { return }

        # Hot-reload hotkeys if registered
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
```

NOTE: `$captureHandler` is defined inside `Add_Loaded` block in Phase 3. To make it visible to the settings handler, you need to lift its definition OUT of `Add_Loaded` and into the outer function scope. Modify the code so:

a) Move the `$captureHandler = { ... }.GetNewClosure()` definition OUT of `Add_Loaded` and into the outer `Show-StepCreaterMainWindow` body (before `$c.MenuSettings.Add_Click`).

b) The `Add_Loaded` block now only contains the initial `Register-StepCreaterHotkeys` call, using the lifted `$captureHandler`.

Read the current code carefully and make this lift cleanly.

- [ ] **Step 4: Run All — expect pass + lint clean**

Expected: 101 tests still pass (no new tests; settings dialog requires display).

- [ ] **Step 5: Commit**

```bash
git add StepCreater/ui/MainWindow.xaml StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1 StepCreater/tests/Xaml.Tests.ps1
git commit -m "Phase5: Show-SettingsDialog + hot-reload hotkeys"
```

---

## Task 6: Final Integration Smoke

- [ ] **Step 1: Programmatic smoke**

```powershell
cd C:\Users\kohji\data\claude\StepCreater
Import-Module .\StepCreater\StepCreater.psd1 -Force
$tmp = Join-Path $env:TEMP "sc-p5-final-$([guid]::NewGuid())"
New-StepCreaterWorkfolder -Path $tmp -Title 'Phase 5 Final' | Out-Null
$session = Open-StepCreaterWorkfolder -Path $tmp
$a = $session.Procedure.AddStep('A')
$a.BodyMarkdown = 'Body A'
$a.Command = 'Get-Process'
$a.Status = 'done'
$a.Started  = [datetime]'2026-05-27T10:00:00'
$a.Finished = [datetime]'2026-05-27T10:01:30'
Save-WorkSession -Session $session

# HTML generation
$html = ConvertTo-ProcedureHtml -Procedure $session.Procedure
$htmlPath = Join-Path $tmp 'procedure.html'
Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8
Write-Host "HTML path: $htmlPath"
Write-Host "HTML size: $((Get-Item $htmlPath).Length) bytes"
Write-Host "Contains TOC anchor: $($html -match 'href=`"#step-01`"')"
Write-Host "Contains duration:   $($html -match '00:01:30')"

# Window construction (NoShow)
$win = Show-StepCreaterMainWindow -Session $session -NoShow
Write-Host "MenuExportHtml found: $($null -ne $win.FindName('MenuExportHtml'))"
Write-Host "MenuSettings found:   $($null -ne $win.FindName('MenuSettings'))"

Remove-Item $tmp -Recurse -Force
```

Expected output:
- HTML size > 2000 bytes
- TOC anchor present
- Duration `00:01:30` present
- Both MenuExportHtml and MenuSettings exist on window

- [ ] **Step 2: Final build**

```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 All
```

Expected: 101 tests pass, lint clean.

- [ ] **Step 3: No commit unless smoke surfaced issues.**

---

## Phase 5 Done Criteria

- [ ] `Invoke-Build All` passes (lint + ≥101 tests)
- [ ] ファイル→「HTML出力」で `procedure.html` が生成され、ブラウザで開ける
- [ ] HTML に目次・ステータスバッジ・作業時間が表示される
- [ ] 画像クリックで Lightbox 拡大表示、印刷時はフル画像
- [ ] 「設定」メニューでホットキー再割当・アノテーション切替が可能
- [ ] 設定保存後、即時にホットキーが再登録される
- [ ] 不正なホットキー文字列は警告ダイアログ

これで Phase 1〜5 完了 — フェーズスコープに記載した機能はすべて実装済み。後続作業は実機テスト・PR レビュー・運用フィードバック対応。
