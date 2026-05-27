# StepCreater Phase 3: キャプチャ基盤 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** グローバルホットキーで全画面／アクティブウィンドウ／矩形選択のスクリーンショットを取得し、自動アノテーション（マウス位置赤丸＋撮影時刻キャプション）を付けて `images/` フォルダに保存。撮影直後の画像は未割当トレイに表示し、現Stepへドラッグで割当。

**Architecture:** Win32 P/Invoke で `RegisterHotKey` / `UnregisterHotKey` を呼び、隠し `HwndSource` で `WM_HOTKEY` 受信。キャプチャは `System.Drawing.Graphics.CopyFromScreen` ＋ DWM API。矩形選択は半透明オーバーレイ Window。アノテーションは GDI+ でビットマップ後処理。未割当画像は `MainWindow.xaml` 下部に新規追加する WrapPanel に表示。

**Tech Stack:** PowerShell 5.1, Win32 API (P/Invoke), System.Drawing (GDI+), WPF, Pester v5.

**Spec:** [../specs/2026-05-27-stepcreater-design.md](../specs/2026-05-27-stepcreater-design.md)

**Predecessor:** Phase 2 (Edit GUI) — must be merged before Phase 3 starts on top of main.

---

## File Structure

```
StepCreater/
  StepCreater.psd1                  # MODIFY — export new functions
  StepCreater.psm1                  # MODIFY — append capture + hotkey + annotation
  ui/
    MainWindow.xaml                 # MODIFY — add unassigned tray
    RectSelector.xaml               # CREATE — rect overlay window
  tests/
    Win32.Tests.ps1                 # CREATE — P/Invoke types exist
    CaptureFilename.Tests.ps1       # CREATE — filename generator
    Annotation.Tests.ps1            # CREATE — annotation pure logic
    Hotkey.Tests.ps1                # CREATE — hotkey string parser
    UnassignedTray.Tests.ps1        # CREATE — tray bindings
```

Per-task additions appended to `StepCreater.psm1` keep the single-module pattern from Phase 1/2.

---

## Task 1: Win32 P/Invoke Types

**Files:**
- Create: `StepCreater/tests/Win32.Tests.ps1`
- Modify: `StepCreater/StepCreater.psm1` (append `Initialize-StepCreaterWin32`)
- Modify: `StepCreater/StepCreater.psd1` (export)

- [ ] **Step 1: Write failing test**

`StepCreater/tests/Win32.Tests.ps1`:

```powershell
using module '..\StepCreater.psd1'

Describe 'Win32 P/Invoke types' {
    It 'Initialize-StepCreaterWin32 loads required types' {
        Initialize-StepCreaterWin32
        [StepCreater.Win32] | Should -Not -BeNullOrEmpty
    }

    It 'StepCreater.Win32 exposes RegisterHotKey method' {
        Initialize-StepCreaterWin32
        $m = [StepCreater.Win32].GetMethod('RegisterHotKey')
        $m | Should -Not -BeNullOrEmpty
    }

    It 'StepCreater.Win32 exposes UnregisterHotKey method' {
        Initialize-StepCreaterWin32
        $m = [StepCreater.Win32].GetMethod('UnregisterHotKey')
        $m | Should -Not -BeNullOrEmpty
    }

    It 'StepCreater.Win32 exposes GetForegroundWindow method' {
        Initialize-StepCreaterWin32
        $m = [StepCreater.Win32].GetMethod('GetForegroundWindow')
        $m | Should -Not -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Run, expect failure**

```powershell
cd C:\Users\kohji\data\claude\StepCreater
Invoke-Build -File StepCreater/StepCreater.build.ps1 Test
```

- [ ] **Step 3: Implement type loader**

Append to `StepCreater/StepCreater.psm1`:

```powershell
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
```

Add `'Initialize-StepCreaterWin32'` to FunctionsToExport.

- [ ] **Step 4: Run All — expect pass + lint clean**

```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 All
```

Expected: 59 tests pass (55 prior + 4 new), lint clean.

- [ ] **Step 5: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1 StepCreater/tests/Win32.Tests.ps1
git commit -m "Phase3: Win32 P/Invoke types (hotkey, window enumeration, DWM)"
```

---

## Task 2: Screenshot Filename Generator

Pure function — easy to test, used by all capture types.

**Files:**
- Create: `StepCreater/tests/CaptureFilename.Tests.ps1`
- Modify: `StepCreater/StepCreater.psm1` (append `Get-CaptureFileName`)
- Modify: `StepCreater/StepCreater.psd1` (export)

- [ ] **Step 1: Write failing tests**

`StepCreater/tests/CaptureFilename.Tests.ps1`:

```powershell
using module '..\StepCreater.psd1'

Describe 'Get-CaptureFileName' {
    It 'returns YYYY-MM-DD_HHmmss_stepNN.png for full kind' {
        $name = Get-CaptureFileName -Kind 'full' -StepId '03' -Timestamp ([datetime]'2026-05-27T10:30:45')
        $name | Should -Be '2026-05-27_103045_step03.png'
    }

    It 'appends _win for window kind' {
        $name = Get-CaptureFileName -Kind 'window' -StepId '01' -Timestamp ([datetime]'2026-05-27T10:30:45')
        $name | Should -Be '2026-05-27_103045_step01_win.png'
    }

    It 'appends _rect for rect kind' {
        $name = Get-CaptureFileName -Kind 'rect' -StepId '01' -Timestamp ([datetime]'2026-05-27T10:30:45')
        $name | Should -Be '2026-05-27_103045_step01_rect.png'
    }

    It 'uses "unassigned" when StepId is empty' {
        $name = Get-CaptureFileName -Kind 'full' -StepId '' -Timestamp ([datetime]'2026-05-27T10:30:45')
        $name | Should -Be '2026-05-27_103045_unassigned.png'
    }
}
```

- [ ] **Step 2: Run, expect failure**

```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 Test
```

- [ ] **Step 3: Implement**

Append to `StepCreater/StepCreater.psm1`:

```powershell
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
```

Export `'Get-CaptureFileName'`.

- [ ] **Step 4: Run All — expect pass**

Expected: 63 tests pass (59 + 4).

- [ ] **Step 5: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1 StepCreater/tests/CaptureFilename.Tests.ps1
git commit -m "Phase3: capture filename generator"
```

---

## Task 3: Full-Screen Capture

**Files:**
- Modify: `StepCreater/StepCreater.psm1` (append `Invoke-FullScreenCapture`)
- Modify: `StepCreater/StepCreater.psd1` (export)

No Pester test (real capture requires display). Manual smoke.

- [ ] **Step 1: Implement**

Append to `StepCreater/StepCreater.psm1`:

```powershell
function Invoke-FullScreenCapture {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$OutputPath
    )
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Span all monitors (virtual screen)
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
```

Export `'Invoke-FullScreenCapture'`.

- [ ] **Step 2: Manual smoke**

```powershell
cd C:\Users\kohji\data\claude\StepCreater
Import-Module .\StepCreater\StepCreater.psd1 -Force
$out = Join-Path $env:TEMP "sc-full-$([guid]::NewGuid()).png"
Invoke-FullScreenCapture -OutputPath $out
# Open the PNG to verify it captured all monitors
Start-Process $out
```

Verify the saved PNG shows the desktop. Close the viewer.

- [ ] **Step 3: Run All — expect pass + lint clean (no new tests)**

```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 All
```

- [ ] **Step 4: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1
git commit -m "Phase3: full-screen capture"
```

---

## Task 4: Active-Window Capture

Uses DWM extended frame bounds to capture the foreground window without the drop shadow.

**Files:**
- Modify: `StepCreater/StepCreater.psm1` (append `Invoke-ActiveWindowCapture`)
- Modify: `StepCreater/StepCreater.psd1` (export)

- [ ] **Step 1: Implement**

Append to `StepCreater/StepCreater.psm1`:

```powershell
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
        # Fallback: regular GetWindowRect (includes shadow on aero)
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
```

Export `'Invoke-ActiveWindowCapture'`.

- [ ] **Step 2: Manual smoke**

```powershell
Import-Module .\StepCreater\StepCreater.psd1 -Force
$out = Join-Path $env:TEMP "sc-win-$([guid]::NewGuid()).png"

# Open Notepad and switch to it, then countdown
Start-Process notepad
Start-Sleep -Seconds 3  # give yourself time to focus Notepad
Invoke-ActiveWindowCapture -OutputPath $out
Start-Process $out
```

Verify the PNG shows the Notepad window only (not the full desktop).

- [ ] **Step 3: Run All — expect pass + lint clean**

- [ ] **Step 4: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1
git commit -m "Phase3: active-window capture via DWM"
```

---

## Task 5: Hotkey Parser & Modifier Constants

Parse strings like `"Ctrl+Shift+F12"` to `(mods, vkey)` pairs the Win32 API expects.

**Files:**
- Create: `StepCreater/tests/Hotkey.Tests.ps1`
- Modify: `StepCreater/StepCreater.psm1` (append `ConvertTo-HotkeySpec`)
- Modify: `StepCreater/StepCreater.psd1` (export)

- [ ] **Step 1: Write failing tests**

`StepCreater/tests/Hotkey.Tests.ps1`:

```powershell
using module '..\StepCreater.psd1'

Describe 'ConvertTo-HotkeySpec' {
    It 'parses Ctrl+F12' {
        $spec = ConvertTo-HotkeySpec -Combo 'Ctrl+F12'
        $spec.Modifiers | Should -Be 0x2   # MOD_CONTROL
        $spec.VKey      | Should -Be 0x7B  # VK_F12
    }

    It 'parses Ctrl+Shift+F11' {
        $spec = ConvertTo-HotkeySpec -Combo 'Ctrl+Shift+F11'
        $spec.Modifiers | Should -Be (0x2 -bor 0x4)
        $spec.VKey      | Should -Be 0x7A  # VK_F11
    }

    It 'parses Alt+S' {
        $spec = ConvertTo-HotkeySpec -Combo 'Alt+S'
        $spec.Modifiers | Should -Be 0x1
        $spec.VKey      | Should -Be 0x53
    }

    It 'is case-insensitive' {
        $spec = ConvertTo-HotkeySpec -Combo 'ctrl+f12'
        $spec.VKey | Should -Be 0x7B
    }

    It 'throws on unknown key' {
        { ConvertTo-HotkeySpec -Combo 'Ctrl+Nope' } | Should -Throw
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement**

Append to `StepCreater/StepCreater.psm1`:

```powershell
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
        '^f([1-9]|1[0-2])$' { 0x6F + [int]$matches[1] }       # F1 = 0x70, F12 = 0x7B
        '^[a-z]$'           { [int][char]([string]$keyToken).ToUpperInvariant() }
        '^[0-9]$'           { [int][char][string]$keyToken }
        default             { throw "Unknown key '$keyToken' in combo '$Combo'." }
    }
    return [pscustomobject]@{ Modifiers = $mods; VKey = $vk }
}
```

Export `'ConvertTo-HotkeySpec'`.

- [ ] **Step 4: Run All — expect pass**

Expected: 68 tests (63 + 5).

- [ ] **Step 5: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1 StepCreater/tests/Hotkey.Tests.ps1
git commit -m "Phase3: hotkey combo parser"
```

---

## Task 6: Hotkey Registration via Hidden HwndSource

Register the three default hotkeys and dispatch `WM_HOTKEY` to PowerShell scriptblocks.

**Files:**
- Modify: `StepCreater/StepCreater.psm1` (append `Register-StepCreaterHotkeys`, `Unregister-StepCreaterHotkeys`)
- Modify: `StepCreater/StepCreater.psd1` (export)

- [ ] **Step 1: Implement registration**

Append to `StepCreater/StepCreater.psm1`:

```powershell
function Register-StepCreaterHotkeys {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] $Window,                  # WPF Window to anchor HwndSource
        [Parameter(Mandatory)] [hashtable]$Combos,       # @{ full = 'Ctrl+F12'; window = 'Ctrl+F11'; rect = 'Ctrl+Shift+F12' }
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
        param($hwnd, $msg, $wparam, $lparam, $handled)
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
```

Export both functions.

- [ ] **Step 2: Manual smoke (requires interactive PowerShell to hold focus)**

```powershell
Import-Module .\StepCreater\StepCreater.psd1 -Force
Add-Type -AssemblyName PresentationFramework
$w = [System.Windows.Window]::new()
$w.Title = 'Hotkey test'
$w.Width = 400; $w.Height = 200
$w.Add_Loaded({
    $handle = Register-StepCreaterHotkeys -Window $w -Combos @{
        full = 'Ctrl+F12'; window = 'Ctrl+F11'; rect = 'Ctrl+Shift+F12'
    } -OnFull   { [System.Windows.MessageBox]::Show('Full!') } `
       -OnWindow { [System.Windows.MessageBox]::Show('Window!') } `
       -OnRect   { [System.Windows.MessageBox]::Show('Rect!') }
    $w.Tag = $handle
})
$w.Add_Closed({ Unregister-StepCreaterHotkeys -Handle $w.Tag })
$w.ShowDialog() | Out-Null
```

Press Ctrl+F12 / Ctrl+F11 / Ctrl+Shift+F12 in any application — each shows its dialog. Close the window.

- [ ] **Step 3: Run All — expect pass + lint clean (no new tests)**

- [ ] **Step 4: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1
git commit -m "Phase3: global hotkey registration via HwndSource"
```

---

## Task 7: Annotation (Mouse Circle + Caption Bar)

Post-process the captured bitmap: draw a semi-transparent red circle at the cursor position, and add a black caption bar at the bottom with active window title + timestamp.

**Files:**
- Create: `StepCreater/tests/Annotation.Tests.ps1`
- Modify: `StepCreater/StepCreater.psm1` (append `Add-CaptureAnnotation`)
- Modify: `StepCreater/StepCreater.psd1` (export)

- [ ] **Step 1: Write failing tests**

`StepCreater/tests/Annotation.Tests.ps1`:

```powershell
using module '..\StepCreater.psd1'

Describe 'Add-CaptureAnnotation' {
    BeforeAll {
        Add-Type -AssemblyName System.Drawing
    }

    It 'returns a bitmap of same dimensions as input' {
        $src = New-Object System.Drawing.Bitmap 800, 600
        $out = Add-CaptureAnnotation -SourceBitmap $src -MousePosition (New-Object System.Drawing.Point 100, 100) `
            -Caption 'Test | 10:30:45' -CaptionHeight 0
        $out.Width  | Should -Be 800
        $out.Height | Should -Be 600
    }

    It 'returns a taller bitmap when CaptionHeight > 0' {
        $src = New-Object System.Drawing.Bitmap 800, 600
        $out = Add-CaptureAnnotation -SourceBitmap $src -MousePosition (New-Object System.Drawing.Point 100, 100) `
            -Caption 'Test' -CaptionHeight 30
        $out.Height | Should -Be 630
    }

    It 'returns original height when MousePosition is outside bounds and no caption' {
        $src = New-Object System.Drawing.Bitmap 800, 600
        $out = Add-CaptureAnnotation -SourceBitmap $src -MousePosition (New-Object System.Drawing.Point -50, -50) `
            -Caption '' -CaptionHeight 0
        $out.Height | Should -Be 600
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement**

Append to `StepCreater/StepCreater.psm1`:

```powershell
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

        # Red circle at mouse
        if ($MousePosition.X -ge 0 -and $MousePosition.Y -ge 0 `
            -and $MousePosition.X -le $SourceBitmap.Width `
            -and $MousePosition.Y -le $SourceBitmap.Height) {
            $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(180, 220, 0, 0)), 3
            try {
                $r = $CircleRadius
                $g.DrawEllipse($pen, $MousePosition.X - $r, $MousePosition.Y - $r, $r * 2, $r * 2)
            } finally { $pen.Dispose() }
        }

        # Caption bar
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
```

Export `'Add-CaptureAnnotation'`.

- [ ] **Step 4: Run All — expect pass**

Expected: 71 tests (68 + 3).

- [ ] **Step 5: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1 StepCreater/tests/Annotation.Tests.ps1
git commit -m "Phase3: capture annotation (mouse circle + caption bar)"
```

---

## Task 8: Rectangle Selection Overlay

Show a semi-transparent fullscreen window. User drags a rectangle. ESC cancels.

**Files:**
- Create: `StepCreater/ui/RectSelector.xaml`
- Modify: `StepCreater/StepCreater.psm1` (append `Invoke-RectSelectionCapture`)
- Modify: `StepCreater/StepCreater.psd1` (export)

- [ ] **Step 1: Create overlay XAML**

`StepCreater/ui/RectSelector.xaml` (UTF-8 with BOM):

```xml
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True"
        Background="#33000000" Topmost="True" ShowInTaskbar="False"
        Cursor="Cross">
    <Canvas x:Name="RootCanvas">
        <Rectangle x:Name="SelRect" Stroke="Red" StrokeThickness="2"
                   Fill="#33FF0000" Visibility="Collapsed"/>
    </Canvas>
</Window>
```

- [ ] **Step 2: Implement function**

Append to `StepCreater/StepCreater.psm1`:

```powershell
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
    $result = $null

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
```

Export `'Invoke-RectSelectionCapture'`.

- [ ] **Step 3: Manual smoke**

```powershell
Import-Module .\StepCreater\StepCreater.psd1 -Force
$out = Join-Path $env:TEMP "sc-rect-$([guid]::NewGuid()).png"
Invoke-RectSelectionCapture -OutputPath $out
Start-Process $out
```

Drag a rectangle → PNG saved with that region. Try again, press ESC → no file (return value is $null).

- [ ] **Step 4: Run All — expect pass + lint clean**

- [ ] **Step 5: Commit**

```bash
git add StepCreater/ui/RectSelector.xaml StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1
git commit -m "Phase3: rectangle selection capture"
```

---

## Task 9: Capture Pipeline (orchestrator)

Wraps capture + annotation + filename + save into a single function used by hotkey handlers and the unassigned tray.

**Files:**
- Modify: `StepCreater/StepCreater.psm1` (append `Save-StepCreaterCapture`)
- Modify: `StepCreater/StepCreater.psd1` (export)

- [ ] **Step 1: Implement**

Append to `StepCreater/StepCreater.psm1`:

```powershell
function Save-StepCreaterCapture {
    [CmdletBinding()]
    [OutputType([ScreenshotRef])]
    param(
        [Parameter(Mandatory)] [WorkSession]$Session,
        [Parameter(Mandatory)] [ValidateSet('full','window','rect')] [string]$Kind,
        [Parameter()] [string]$StepId = ''   # empty = unassigned
    )
    Initialize-StepCreaterWin32
    Add-Type -AssemblyName System.Drawing

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
        if (-not $captured) { return $null }   # user cancelled rect

        $finalPath = Join-Path $imagesDir $name
        if ($cfg.annotationEnabled) {
            # Title of foreground window
            $title = New-Object System.Text.StringBuilder 256
            $hwnd = [StepCreater.Win32]::GetForegroundWindow()
            [StepCreater.Win32]::GetWindowText($hwnd, $title, $title.Capacity) | Out-Null
            $caption = ('{0} | {1}' -f $title.ToString(), $now.ToString('HH:mm:ss'))
            $cursor = [System.Windows.Forms.Cursor]::Position
            # MousePosition is in screen coords; for window/rect we'd need to offset, but for
            # the visual cue at the captured area we approximate with absolute coords minus virtual origin.
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
        $idx = $Session.Procedure.Steps.FindIndex({ param($s) $s.Id -eq $StepId })
        if ($idx -ge 0) {
            $Session.Procedure.Steps[$idx].Evidence.Add($ref) | Out-Null
        } else {
            $Session.UnassignedScreenshots.Add($ref) | Out-Null
        }
    }
    return $ref
}
```

Export `'Save-StepCreaterCapture'`.

- [ ] **Step 2: Manual smoke**

```powershell
Import-Module .\StepCreater\StepCreater.psd1 -Force
$tmp = Join-Path $env:TEMP "sc-cap-smoke-$([guid]::NewGuid())"
New-StepCreaterWorkfolder -Path $tmp -Title 'Capture Smoke'
$session = Open-StepCreaterWorkfolder -Path $tmp
$ref = Save-StepCreaterCapture -Session $session -Kind 'full' -StepId ''
Write-Host "Saved: $($ref.FileName)"
Test-Path (Join-Path $tmp "images/$($ref.FileName)")
$session.UnassignedScreenshots.Count
Remove-Item $tmp -Recurse -Force
```

Expected: 1 unassigned, image file exists.

- [ ] **Step 3: Run All — expect pass + lint clean**

- [ ] **Step 4: Commit**

```bash
git add StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1
git commit -m "Phase3: Save-StepCreaterCapture orchestrator"
```

---

## Task 10: Unassigned Tray UI

Add a horizontal strip at the bottom of MainWindow showing unassigned screenshot thumbnails. Single-click to assign to the currently-selected Step.

**Files:**
- Modify: `StepCreater/ui/MainWindow.xaml`
- Modify: `StepCreater/StepCreater.psm1` (extend `Show-StepCreaterMainWindow` + add `Update-UnassignedTrayUI`)
- Modify: `StepCreater/tests/Xaml.Tests.ps1` (verify new control)

- [ ] **Step 1: Update XAML — add tray above the status bar**

In `StepCreater/ui/MainWindow.xaml`, between the closing `</Grid>` of the main content and the closing `</DockPanel>`, insert before the StatusBar (or below the main content Grid) a DockPanel.Dock=Bottom panel:

Replace the current `<StatusBar DockPanel.Dock="Bottom">` block (keep StatusBar unchanged) and INSERT a new bottom panel BEFORE the StatusBar declaration:

```xml
        <Border DockPanel.Dock="Bottom" BorderBrush="LightGray" BorderThickness="0,1,0,0"
                Background="#FAFAFA" Padding="6" Height="120">
            <DockPanel>
                <TextBlock DockPanel.Dock="Top" Text="未割当スクリーンショット (クリックで現Stepに割当)"
                           FontSize="11" Foreground="DimGray" Margin="0,0,0,4"/>
                <ScrollViewer HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Disabled">
                    <WrapPanel x:Name="UnassignedTray" Orientation="Horizontal"/>
                </ScrollViewer>
            </DockPanel>
        </Border>
```

NOTE: In DockPanel, last child fills remaining space. Order matters — the new bottom panel must be declared BEFORE the main content Grid (which fills the remaining space) but the existing layout has the main content Grid last. Adjust order: Menu (Top), top bar Grid (Top), StatusBar (Bottom), Unassigned tray Border (Bottom — added BEFORE StatusBar in markup so it sits ABOVE the status bar), then main content Grid (fills rest).

Final order in markup inside `<DockPanel>`:
1. `<Menu DockPanel.Dock="Top">` (existing)
2. `<Grid DockPanel.Dock="Top" Margin="8,4,8,4">` (existing top bar)
3. `<StatusBar DockPanel.Dock="Bottom">` (existing) — KEEP AT BOTTOM
4. `<Border DockPanel.Dock="Bottom" ...>` (new tray) — INSERT ABOVE StatusBar in markup so it docks above status bar
5. `<Grid Margin="8">` (main content — fills remainder)

Add `UnassignedTray` to the Xaml.Tests.ps1 named-controls list.

- [ ] **Step 2: Implement Update-UnassignedTrayUI**

Append to `StepCreater/StepCreater.psm1`:

```powershell
function Update-UnassignedTrayUI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [WorkSession]$Session,
        [Parameter(Mandatory)] $TrayPanel,
        [Parameter(Mandatory)] $OnAssign       # scriptblock receiving (screenshotRef)
    )
    Add-Type -AssemblyName PresentationFramework

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
```

Export `'Update-UnassignedTrayUI'`.

- [ ] **Step 3: Wire tray inside Show-StepCreaterMainWindow**

In the `$c` hashtable lookup, add `'UnassignedTray'` to the list of names. Then after the Step list operations are wired (Task 6 area), add:

```powershell
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
```

- [ ] **Step 4: Update Xaml.Tests.ps1 named-controls list**

Add `'UnassignedTray'` to the `foreach ($name in @(...))` array in the existing test.

- [ ] **Step 5: Run All — expect pass + lint clean**

- [ ] **Step 6: Commit**

```bash
git add StepCreater/ui/MainWindow.xaml StepCreater/StepCreater.psm1 StepCreater/StepCreater.psd1 StepCreater/tests/Xaml.Tests.ps1
git commit -m "Phase3: unassigned screenshot tray UI + assign-to-current"
```

---

## Task 11: Wire Hotkeys into Show-StepCreaterMainWindow

Final integration: register hotkeys when window loads, unregister on close, capture into unassigned (since Execute mode is Phase 4), refresh the tray after each capture.

**Files:**
- Modify: `StepCreater/StepCreater.psm1`

- [ ] **Step 1: Wire registration in Show-StepCreaterMainWindow**

Inside `Show-StepCreaterMainWindow`, before `[void]$window.ShowDialog()`, add:

```powershell
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
        $window.Tag | Add-Member -NotePropertyName HotkeyHandle -NotePropertyValue $hk
    }.GetNewClosure())

    $window.Add_Closed({
        if ($window.Tag.HotkeyHandle) {
            Unregister-StepCreaterHotkeys -Handle $window.Tag.HotkeyHandle
        }
    }.GetNewClosure())
```

- [ ] **Step 2: Manual end-to-end smoke**

```powershell
cd C:\Users\kohji\data\claude\StepCreater
$tmp = Join-Path $env:TEMP "sc-p3-final-$([guid]::NewGuid())"
.\StepCreater\StepCreater.ps1 -Init -WorkFolder $tmp -Title "Phase 3 Final"
.\StepCreater\StepCreater.ps1 -WorkFolder $tmp
```

In the GUI:
1. Press Ctrl+F12 — full-screen capture appears in tray
2. Open Notepad, press Ctrl+F11 — Notepad-only capture appears in tray
3. Press Ctrl+Shift+F12 — drag rect → capture appears in tray
4. Add a Step, select it, click a tray thumbnail → moves to that Step's Evidence
5. Save / close window
6. Re-open `procedure.md` in an editor → evidence links point to images

Cleanup: `Remove-Item $tmp -Recurse -Force`

- [ ] **Step 3: Run All — expect pass + lint clean**

Expected: 71+ tests pass (or higher if you added integration tests).

- [ ] **Step 4: Commit**

```bash
git add StepCreater/StepCreater.psm1
git commit -m "Phase3: wire hotkeys to main window for in-edit-mode capture"
```

---

## Phase 3 Done Criteria

- [ ] `Invoke-Build All` passes (lint + ≥71 tests)
- [ ] Ctrl+F12 captures all monitors → saved to `images/` with annotation
- [ ] Ctrl+F11 captures foreground window (DWM-precise bounds, no shadow) → saved
- [ ] Ctrl+Shift+F12 shows overlay → drag rect → cropped capture saved; ESC cancels
- [ ] Captures arrive in the unassigned tray as thumbnails
- [ ] Clicking a tray thumbnail with a Step selected moves it to that Step's Evidence
- [ ] On window close, hotkeys are released (verify by re-opening and re-registering)
- [ ] Annotation (red circle + caption bar) appears on saved PNGs when enabled
- [ ] `Get-StepCreaterConfig` hotkeys are used (changing config + restart works)

Phase 4 (作業実施モード — Execute mode + status transitions + per-Step timer) starts after this is merged.
