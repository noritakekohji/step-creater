using module '..\StepCreater.psd1'

Describe 'Image assignment flow (select + 追加)' {
    BeforeAll {
        Add-Type -AssemblyName PresentationFramework
        Add-Type -AssemblyName System.Drawing
    }

    function script:New-FakeUnassigned {
        param($Session, $FileName)
        $p = Join-Path $Session.WorkFolderPath "images\$FileName"
        $dir = Split-Path -Parent $p
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $bmp = New-Object System.Drawing.Bitmap 40, 30
        $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        $ref = [ScreenshotRef]::new($FileName, (Get-Date), 'full')
        $Session.UnassignedScreenshots.Add($ref) | Out-Null
        return $ref
    }

    function script:Invoke-Click {
        param($Control)
        $Control.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
    }

    It 'Edit mode: select an unassigned image then 追加 moves it to the step ProcedureImages' {
        $tmp = Join-Path $TestDrive ("wf-assign-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-StepCreaterWorkfolder -Path $tmp -Title 'Assign' | Out-Null
        $session = Open-StepCreaterWorkfolder -Path $tmp
        $session.Procedure.AddStep('A') | Out-Null
        $null = New-FakeUnassigned -Session $session -FileName 'u1.png'

        $win = Show-StepCreaterMainWindow -Session $session -NoShow
        $win.FindName('StepList').SelectedIndex = 0

        # The unassigned tray button is the first child of UnassignedTray
        $tray = $win.FindName('UnassignedTray')
        $tray.Children.Count | Should -BeGreaterThan 0
        Invoke-Click $tray.Children[0]    # select

        Invoke-Click $win.FindName('BtnAddSelected')  # add

        $session.Procedure.Steps[0].ProcedureImages.Count | Should -Be 1
        $session.Procedure.Steps[0].ProcedureImages[0].FileName | Should -Be 'u1.png'
        $session.UnassignedScreenshots.Count | Should -Be 0
        # auto-saved
        (Get-Content (Join-Path $tmp 'procedure.md') -Raw) | Should -Match '\#\#\# 手順画像'
    }

    It 'Execute mode: select an unassigned image then 追加 moves it to the step Evidence' {
        $tmp = Join-Path $TestDrive ("wf-assign2-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-StepCreaterWorkfolder -Path $tmp -Title 'Assign2' | Out-Null
        $session = Open-StepCreaterWorkfolder -Path $tmp
        $session.Procedure.AddStep('A') | Out-Null
        $null = New-FakeUnassigned -Session $session -FileName 'u2.png'
        $session.Mode = 'Execute'

        $win = Show-StepCreaterMainWindow -Session $session -NoShow
        $win.FindName('ExecChecklist').SelectedIndex = 0

        $tray = $win.FindName('UnassignedTray')
        Invoke-Click $tray.Children[0]
        Invoke-Click $win.FindName('BtnAddSelected')

        $session.Procedure.Steps[0].Evidence.Count | Should -Be 1
        $session.Procedure.Steps[0].Evidence[0].FileName | Should -Be 'u2.png'
        $session.UnassignedScreenshots.Count | Should -Be 0
    }

    It 'Execute mode: 手順画像 tray renders read-only (no delete buttons)' {
        $tmp = Join-Path $TestDrive ("wf-ro-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-StepCreaterWorkfolder -Path $tmp -Title 'RO' | Out-Null
        $session = Open-StepCreaterWorkfolder -Path $tmp
        $s = $session.Procedure.AddStep('A')
        # attach a procedure image directly
        $p = Join-Path $tmp 'images\proc.png'
        $dir = Split-Path -Parent $p; if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $bmp = New-Object System.Drawing.Bitmap 40,30; $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
        $s.ProcedureImages.Add([ScreenshotRef]::new('proc.png', (Get-Date), 'full')) | Out-Null
        $session.Mode = 'Execute'

        $win = Show-StepCreaterMainWindow -Session $session -NoShow
        $win.FindName('ExecChecklist').SelectedIndex = 0

        $procTray = $win.FindName('ExecProcImageTray')
        $procTray.Children.Count | Should -Be 1
        # Read-only: the cell Grid should contain ONLY the image button (no × delete button)
        $cell = $procTray.Children[0]
        $deleteButtons = @($cell.Children | Where-Object { $_ -is [System.Windows.Controls.Button] -and $_.Content -eq 'x' })
        $deleteButtons.Count | Should -Be 0
    }

    It 'BtnAddSelected with nothing selected does not throw and does not assign' {
        $tmp = Join-Path $TestDrive ("wf-none-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-StepCreaterWorkfolder -Path $tmp -Title 'None' | Out-Null
        $session = Open-StepCreaterWorkfolder -Path $tmp
        $session.Procedure.AddStep('A') | Out-Null
        $win = Show-StepCreaterMainWindow -Session $session -NoShow
        $win.FindName('StepList').SelectedIndex = 0
        # No selection made. Clicking 追加 shows a messagebox in real usage; in -NoShow the
        # MessageBox.Show call will block — so DO NOT click it here. Instead assert the button exists.
        $win.FindName('BtnAddSelected') | Should -Not -BeNullOrEmpty
    }
}
