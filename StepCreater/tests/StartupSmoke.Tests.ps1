using module '..\StepCreater.psd1'

Describe 'Show-StepCreaterMainWindow startup smoke (real pump)' {
    BeforeAll {
        Add-Type -AssemblyName PresentationFramework
        Add-Type -AssemblyName WindowsBase
    }

    It 'opens and closes cleanly on a fresh workfolder' {
        $tmp = Join-Path $TestDrive ("wf-smoke-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-StepCreaterWorkfolder -Path $tmp -Title 'Smoke' | Out-Null
        $session = Open-StepCreaterWorkfolder -Path $tmp

        # Build the window in NoShow mode so we can attach the auto-close BEFORE Loaded
        $win = Show-StepCreaterMainWindow -Session $session -NoShow

        $errors = New-Object System.Collections.Generic.List[string]
        $win.Add_Loaded({
            # Schedule close on the dispatcher so Loaded handler finishes first
            $win.Dispatcher.BeginInvoke(
                [System.Windows.Threading.DispatcherPriority]::ApplicationIdle,
                [Action]{ $win.Close() }
            ) | Out-Null
        }.GetNewClosure())

        # Hook unhandled-exception in the dispatcher
        $dispatcher = $win.Dispatcher
        $exHandler = {
            param($src, $e)
            $null = $src
            $errors.Add($e.Exception.ToString()) | Out-Null
            $e.Handled = $true   # keep test running
        }
        $dispatcher.add_UnhandledException($exHandler)

        try {
            { [void]$win.ShowDialog() } | Should -Not -Throw
        } finally {
            $dispatcher.remove_UnhandledException($exHandler)
        }

        $errors.Count | Should -Be 0 -Because (($errors -join "`n---`n"))
    }

    It 'opens and closes cleanly on a workfolder with steps and unassigned screenshots' {
        Add-Type -AssemblyName System.Drawing
        $tmp = Join-Path $TestDrive ("wf-smoke2-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-StepCreaterWorkfolder -Path $tmp -Title 'Smoke2' | Out-Null
        $session = Open-StepCreaterWorkfolder -Path $tmp
        $session.Procedure.AddStep('A') | Out-Null
        $session.Procedure.AddStep('B') | Out-Null

        # Add a fake unassigned screenshot (file + ref) so the tray rendering exercises
        $imgPath = Join-Path $tmp 'images\fake.png'
        $bmp = New-Object System.Drawing.Bitmap 100, 100
        $bmp.Save($imgPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        $session.UnassignedScreenshots.Add([ScreenshotRef]::new('fake.png', (Get-Date), 'full')) | Out-Null

        $win = Show-StepCreaterMainWindow -Session $session -NoShow

        $errors = New-Object System.Collections.Generic.List[string]
        $win.Add_Loaded({
            $win.Dispatcher.BeginInvoke(
                [System.Windows.Threading.DispatcherPriority]::ApplicationIdle,
                [Action]{ $win.Close() }
            ) | Out-Null
        }.GetNewClosure())

        $dispatcher = $win.Dispatcher
        $exHandler = {
            param($src, $e)
            $null = $src
            $errors.Add($e.Exception.ToString()) | Out-Null
            $e.Handled = $true
        }
        $dispatcher.add_UnhandledException($exHandler)

        try {
            { [void]$win.ShowDialog() } | Should -Not -Throw
        } finally {
            $dispatcher.remove_UnhandledException($exHandler)
        }

        $errors.Count | Should -Be 0 -Because (($errors -join "`n---`n"))
    }
}
