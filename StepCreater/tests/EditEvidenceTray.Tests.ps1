using module '..\StepCreater.psd1'

Describe 'Update-EditEvidenceTray' {
    BeforeAll {
        Add-Type -AssemblyName PresentationFramework
        Add-Type -AssemblyName System.Drawing
    }

    It 'renders one cell per Evidence entry on the selected step' {
        $tmp = Join-Path $TestDrive ("wf-evtray-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-StepCreaterWorkfolder -Path $tmp -Title 'EvTray' | Out-Null
        $session = Open-StepCreaterWorkfolder -Path $tmp
        $s = $session.Procedure.AddStep('A')

        # Create two PNGs and attach as evidence
        foreach ($n in 'a','b') {
            $p = Join-Path $tmp "images\$n.png"
            $bmp = New-Object System.Drawing.Bitmap 30, 30
            $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
            $s.Evidence.Add([ScreenshotRef]::new("$n.png", (Get-Date), 'full')) | Out-Null
        }

        $panel = New-Object System.Windows.Controls.WrapPanel
        Update-EditEvidenceTray -Session $session -StepIndex 0 -TrayPanel $panel -OnRemove { param($r); $null = $r }
        $panel.Children.Count | Should -Be 2
    }

    It 'tolerates StepIndex -1 (clears tray)' {
        $tmp = Join-Path $TestDrive ("wf-evtray2-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-StepCreaterWorkfolder -Path $tmp -Title 'EvTray2' | Out-Null
        $session = Open-StepCreaterWorkfolder -Path $tmp
        $panel = New-Object System.Windows.Controls.WrapPanel
        # Pre-populate with one item to confirm it gets cleared
        $panel.Children.Add((New-Object System.Windows.Controls.Button)) | Out-Null
        Update-EditEvidenceTray -Session $session -StepIndex -1 -TrayPanel $panel -OnRemove { param($r); $null = $r }
        $panel.Children.Count | Should -Be 0
    }

    It 'OnRemove callback fires when the x button is clicked' {
        $tmp = Join-Path $TestDrive ("wf-evtray3-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-StepCreaterWorkfolder -Path $tmp -Title 'EvTray3' | Out-Null
        $session = Open-StepCreaterWorkfolder -Path $tmp
        $s = $session.Procedure.AddStep('A')
        $p = Join-Path $tmp 'images\x.png'
        $bmp = New-Object System.Drawing.Bitmap 30, 30
        $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
        $ref = [ScreenshotRef]::new('x.png', (Get-Date), 'full')
        $s.Evidence.Add($ref) | Out-Null

        $panel = New-Object System.Windows.Controls.WrapPanel
        $called = @{ Count = 0; LastRef = $null }
        $cb = { param($r); $called.Count++; $called.LastRef = $r }.GetNewClosure()
        Update-EditEvidenceTray -Session $session -StepIndex 0 -TrayPanel $panel -OnRemove $cb

        # Locate the delete button: cell Grid contains [Button(img), Button(x)]
        $cell = $panel.Children[0]
        $delBtn = $cell.Children | Where-Object { $_.Content -eq 'x' } | Select-Object -First 1
        $delBtn | Should -Not -BeNullOrEmpty
        $delBtn.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))

        $called.Count   | Should -Be 1
        $called.LastRef | Should -Be $ref
    }
}
