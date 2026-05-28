using module '..\StepCreater.psd1'

Describe 'Unassigned tray callback (self-referencing closure)' {
    BeforeAll {
        Add-Type -AssemblyName PresentationFramework
        Add-Type -AssemblyName System.Drawing
    }

    It 'Update-UnassignedTrayUI is callable with the runtime callback without null OnSelect error' {
        $tmp = Join-Path $TestDrive ("wf-selfref-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-StepCreaterWorkfolder -Path $tmp -Title 'SelfRef' | Out-Null
        $session = Open-StepCreaterWorkfolder -Path $tmp
        $session.Procedure.AddStep('A') | Out-Null

        # Construct window (NoShow) so the tray box is wired
        $win = Show-StepCreaterMainWindow -Session $session -NoShow

        # Add a real PNG so the tray button is rendered
        $imgPath = Join-Path $tmp 'images\test.png'
        $bmp = New-Object System.Drawing.Bitmap 50, 50
        $bmp.Save($imgPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        $refImg = [ScreenshotRef]::new('test.png', (Get-Date), 'full')
        $session.UnassignedScreenshots.Add($refImg) | Out-Null

        # Locate the tray panel from the built window
        $tray = $win.FindName('UnassignedTray')

        # Construct a self-referencing callback using the hashtable-box pattern:
        $box = @{}
        $box.Fn = {
            param($imgRef)
            $null = $imgRef
            Update-UnassignedTrayUI -Session $session -TrayPanel $tray -OnSelect $box.Fn
        }.GetNewClosure()

        { Update-UnassignedTrayUI -Session $session -TrayPanel $tray -OnSelect $box.Fn } | Should -Not -Throw
        { & $box.Fn $refImg } | Should -Not -Throw
    }

    It 'Update-UnassignedTrayUI accepts $null OnSelect and uses no-op (defensive)' {
        $tmp = Join-Path $TestDrive ("wf-noop-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-StepCreaterWorkfolder -Path $tmp -Title 'Noop' | Out-Null
        $session = Open-StepCreaterWorkfolder -Path $tmp

        $panel = New-Object System.Windows.Controls.WrapPanel
        { Update-UnassignedTrayUI -Session $session -TrayPanel $panel -OnSelect $null } | Should -Not -Throw
    }
}
