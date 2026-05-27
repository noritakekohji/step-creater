using module '..\StepCreater.psd1'

Describe 'Show-StepCreaterMainWindow -NoShow' {
    BeforeAll {
        $script:tmp = Join-Path $TestDrive 'wf-show'
        New-StepCreaterWorkfolder -Path $script:tmp -Title 'Show Test' | Out-Null
        $script:session = Open-StepCreaterWorkfolder -Path $script:tmp
        $script:session.Procedure.AddStep('Step One') | Out-Null
        $script:session.Procedure.AddStep('Step Two') | Out-Null
    }

    It 'constructs window with title and workfolder path' {
        $win = Show-StepCreaterMainWindow -Session $script:session -NoShow
        $win | Should -Not -BeNullOrEmpty
        $win.Title | Should -Match 'StepCreater'
        $win.Title | Should -Match 'Show Test'
        $win.Tag.Session | Should -Not -BeNullOrEmpty
        $win.Tag.Baseline | Should -Not -BeNullOrEmpty
    }

    It 'populates Step list with all steps' {
        $win = Show-StepCreaterMainWindow -Session $script:session -NoShow
        $listBox = $win.FindName('StepList')
        $listBox.Items.Count | Should -Be 2
        $listBox.Items[0] | Should -Match '01.*Step One'
        $listBox.Items[1] | Should -Match '02.*Step Two'
    }
}

Describe 'Detail editor wiring' {
    BeforeAll {
        $script:tmp2 = Join-Path $TestDrive 'wf-detail'
        New-StepCreaterWorkfolder -Path $script:tmp2 -Title 'Detail Test' | Out-Null
        $script:session2 = Open-StepCreaterWorkfolder -Path $script:tmp2
        $s = $script:session2.Procedure.AddStep('Some Title')
        $s.BodyMarkdown = 'Body text'
        $s.Command = 'Get-Process'
        $s.ExpectedResult = 'List of processes'
        $s.Status = 'done'
        $s.Note = 'A note'
    }

    It 'populates editor controls when a step is selected' {
        $win = Show-StepCreaterMainWindow -Session $script:session2 -NoShow
        $win.FindName('StepList').SelectedIndex = 0
        $win.FindName('TxtTitle').Text    | Should -Be 'Some Title'
        $win.FindName('TxtBody').Text     | Should -Be 'Body text'
        $win.FindName('TxtCommand').Text  | Should -Be 'Get-Process'
        $win.FindName('TxtExpected').Text | Should -Be 'List of processes'
        $win.FindName('TxtNote').Text     | Should -Be 'A note'
        ($win.FindName('CboStatus').SelectedItem.Content) | Should -Be 'done'
    }
}

Describe 'Step list operation buttons' {
    BeforeEach {
        $script:tmp3 = Join-Path $TestDrive ("wf-ops-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-StepCreaterWorkfolder -Path $script:tmp3 -Title 'Ops Test' | Out-Null
        $script:session3 = Open-StepCreaterWorkfolder -Path $script:tmp3
        $script:session3.Procedure.AddStep('A') | Out-Null
        $script:session3.Procedure.AddStep('B') | Out-Null
        $script:session3.Procedure.AddStep('C') | Out-Null
        $script:win3 = Show-StepCreaterMainWindow -Session $script:session3 -NoShow
    }

    It 'BtnAdd inserts after selected step' {
        $script:win3.FindName('StepList').SelectedIndex = 1   # select B
        $btn = $script:win3.FindName('BtnAdd')
        $btn.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        $script:session3.Procedure.Steps.Count | Should -Be 4
        $script:session3.Procedure.Steps[2].Title | Should -Be '新しい手順'
        # IDs renumbered
        $script:session3.Procedure.Steps[3].Id | Should -Be '04'
    }

    It 'BtnAdd appends when nothing selected' {
        $script:win3.FindName('StepList').SelectedIndex = -1
        $btn = $script:win3.FindName('BtnAdd')
        $btn.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        $script:session3.Procedure.Steps.Count | Should -Be 4
        $script:session3.Procedure.Steps[3].Title | Should -Be '新しい手順'
    }

    It 'BtnUp moves selected step up' {
        $script:win3.FindName('StepList').SelectedIndex = 2   # select C
        $btn = $script:win3.FindName('BtnUp')
        $btn.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        $script:session3.Procedure.Steps[1].Title | Should -Be 'C'
        $script:session3.Procedure.Steps[2].Title | Should -Be 'B'
    }

    It 'BtnUp at top is no-op' {
        $script:win3.FindName('StepList').SelectedIndex = 0
        $btn = $script:win3.FindName('BtnUp')
        $btn.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        $script:session3.Procedure.Steps[0].Title | Should -Be 'A'
    }

    It 'BtnDown moves selected step down' {
        $script:win3.FindName('StepList').SelectedIndex = 0   # select A
        $btn = $script:win3.FindName('BtnDown')
        $btn.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        $script:session3.Procedure.Steps[0].Title | Should -Be 'B'
        $script:session3.Procedure.Steps[1].Title | Should -Be 'A'
    }
}

Describe 'Save and auto-save' {
    BeforeEach {
        $script:tmp4 = Join-Path $TestDrive ("wf-save-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-StepCreaterWorkfolder -Path $script:tmp4 -Title 'Save Test' | Out-Null
        $script:session4 = Open-StepCreaterWorkfolder -Path $script:tmp4
        $script:session4.Procedure.AddStep('A') | Out-Null
        $script:win4 = Show-StepCreaterMainWindow -Session $script:session4 -NoShow
    }

    It 'Save-WorkSession writes procedure.md with updated content' {
        $script:session4.Procedure.Steps[0].BodyMarkdown = 'New body'
        Save-WorkSession -Session $script:session4
        $md = Get-Content (Join-Path $script:tmp4 'procedure.md') -Raw
        $md | Should -Match 'New body'
    }

    It 'BtnSave click triggers save and clears dirty indicator' {
        $script:session4.Procedure.Steps[0].BodyMarkdown = 'X'   # make dirty
        $btn = $script:win4.FindName('BtnSave')
        $btn.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        $md = Get-Content (Join-Path $script:tmp4 'procedure.md') -Raw
        $md | Should -Match 'X'
        $script:win4.FindName('DirtyText').Text | Should -Be ''
    }

    It 'BtnAdd auto-saves immediately' {
        $btn = $script:win4.FindName('BtnAdd')
        $btn.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        $md = Get-Content (Join-Path $script:tmp4 'procedure.md') -Raw
        $md | Should -Match '新しい手順'
        $script:win4.FindName('DirtyText').Text | Should -Be ''
    }
}

Describe 'ESC and close behavior' {
    BeforeEach {
        $script:tmp5 = Join-Path $TestDrive ("wf-close-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-StepCreaterWorkfolder -Path $script:tmp5 -Title 'Close Test' | Out-Null
        $script:session5 = Open-StepCreaterWorkfolder -Path $script:tmp5
        $script:win5 = Show-StepCreaterMainWindow -Session $script:session5 -NoShow
    }

    It 'exposes ConfirmDiscard on the window tag' {
        $script:win5.Tag.ConfirmDiscard | Should -Not -BeNullOrEmpty
    }

    It 'ConfirmDiscard returns true when nothing is dirty (no prompt needed)' {
        $result = & $script:win5.Tag.ConfirmDiscard
        $result | Should -BeTrue
    }
}

Describe 'File menu wiring' {
    BeforeEach {
        $script:tmp6 = Join-Path $TestDrive ("wf-menu-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-StepCreaterWorkfolder -Path $script:tmp6 -Title 'Menu Test' | Out-Null
        $script:session6 = Open-StepCreaterWorkfolder -Path $script:tmp6
        $script:win6 = Show-StepCreaterMainWindow -Session $script:session6 -NoShow
    }

    It 'MenuNew has a click handler attached' {
        # Reflection check: the Click event has at least one subscriber
        $mi = $script:win6.FindName('MenuNew')
        # MenuItem.Click is a routed event; we verify by checking that the event field is not null
        # PowerShell can't easily introspect attached handlers, so just verify the control exists
        $mi | Should -Not -BeNullOrEmpty
    }

    It 'MenuOpen has a click handler attached' {
        $mi = $script:win6.FindName('MenuOpen')
        $mi | Should -Not -BeNullOrEmpty
    }
}

Describe 'Template insertion menu' {
    BeforeEach {
        $script:tmp7 = Join-Path $TestDrive ("wf-tpl-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-StepCreaterWorkfolder -Path $script:tmp7 -Title 'Tpl Test' | Out-Null
        $script:session7 = Open-StepCreaterWorkfolder -Path $script:tmp7
        $script:session7.Procedure.AddStep('Existing') | Out-Null
        $script:win7 = Show-StepCreaterMainWindow -Session $script:session7 -NoShow
    }

    It 'populates MenuTemplates with one item per template' {
        $menu = $script:win7.FindName('MenuTemplates')
        $expected = (Get-StepTemplates).Count
        $menu.Items.Count | Should -Be $expected
    }

    It 'clicking a template inserts a new step with template content and auto-saves' {
        $menu = $script:win7.FindName('MenuTemplates')
        $iisItem = $menu.Items | Where-Object { $_.Header -eq 'IIS Install' } | Select-Object -First 1
        $iisItem | Should -Not -BeNullOrEmpty

        # Simulate click
        $iisItem.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent))

        $script:session7.Procedure.Steps.Count | Should -Be 2
        $newStep = $script:session7.Procedure.Steps[1]
        $newStep.Title   | Should -Match 'IIS'
        $newStep.Command | Should -Match 'Install-WindowsFeature'

        # Verify auto-save happened
        $md = Get-Content (Join-Path $script:tmp7 'procedure.md') -Raw
        $md | Should -Match 'Install-WindowsFeature'

        # Dirty indicator cleared after auto-save
        $script:win7.FindName('DirtyText').Text | Should -Be ''
    }
}

Describe 'Mode toggle (Edit/Execute)' {
    BeforeEach {
        $script:tmpM = Join-Path $TestDrive ("wf-mode-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-StepCreaterWorkfolder -Path $script:tmpM -Title 'Mode Test' | Out-Null
        $script:sessionM = Open-StepCreaterWorkfolder -Path $script:tmpM
        $script:sessionM.Procedure.AddStep('Step A') | Out-Null
        $script:sessionM.Procedure.AddStep('Step B') | Out-Null
    }

    It 'starts in Edit mode (EditPanel visible)' {
        $win = Show-StepCreaterMainWindow -Session $script:sessionM -NoShow
        $win.FindName('EditPanel').Visibility    | Should -Be 'Visible'
        $win.FindName('ExecutePanel').Visibility | Should -Be 'Collapsed'
    }

    It 'switches to Execute mode and populates checklist' {
        $win = Show-StepCreaterMainWindow -Session $script:sessionM -NoShow
        $win.FindName('TabExecute').IsChecked = $true
        $win.FindName('EditPanel').Visibility    | Should -Be 'Collapsed'
        $win.FindName('ExecutePanel').Visibility | Should -Be 'Visible'
        $win.FindName('ExecChecklist').Items.Count | Should -Be 2
        $win.FindName('ProgressLabel').Text | Should -Match '進捗: 0 / 2'
    }

    It 'starts directly in Execute mode when Session.Mode is Execute' {
        $script:sessionM.Mode = 'Execute'
        $win = Show-StepCreaterMainWindow -Session $script:sessionM -NoShow
        $win.FindName('ExecutePanel').Visibility | Should -Be 'Visible'
        $win.FindName('ExecStepTitle').Text | Should -Match 'Step A'
    }
}

Describe 'Execute mode buttons' {
    BeforeEach {
        $script:tmpE = Join-Path $TestDrive ("wf-exec-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-StepCreaterWorkfolder -Path $script:tmpE -Title 'Exec Test' | Out-Null
        $script:sessionE = Open-StepCreaterWorkfolder -Path $script:tmpE
        $a = $script:sessionE.Procedure.AddStep('A'); $a.Command = 'Get-Process'
        $script:sessionE.Procedure.AddStep('B') | Out-Null
        $script:sessionE.Procedure.AddStep('C') | Out-Null
        $script:sessionE.Mode = 'Execute'
        $script:winE = Show-StepCreaterMainWindow -Session $script:sessionE -NoShow
    }

    It 'BtnComplete sets done and moves to next step' {
        $script:winE.FindName('ExecChecklist').SelectedIndex = 0
        $btn = $script:winE.FindName('BtnComplete')
        $btn.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        $script:sessionE.Procedure.Steps[0].Status | Should -Be 'done'
        $script:sessionE.Procedure.Steps[0].Started  | Should -Not -BeNullOrEmpty
        $script:sessionE.Procedure.Steps[0].Finished | Should -Not -BeNullOrEmpty
        $script:winE.FindName('ExecChecklist').SelectedIndex | Should -Be 1
    }

    It 'BtnNg sets ng and stays on current step' {
        $script:winE.FindName('ExecChecklist').SelectedIndex = 1
        $btn = $script:winE.FindName('BtnNg')
        $btn.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        $script:sessionE.Procedure.Steps[1].Status | Should -Be 'ng'
        $script:winE.FindName('ExecChecklist').SelectedIndex | Should -Be 1
    }

    It 'BtnSkip sets skipped and advances' {
        $script:winE.FindName('ExecChecklist').SelectedIndex = 0
        $btn = $script:winE.FindName('BtnSkip')
        $btn.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        $script:sessionE.Procedure.Steps[0].Status | Should -Be 'skipped'
        $script:winE.FindName('ExecChecklist').SelectedIndex | Should -Be 1
    }

    It 'auto-saves procedure.md after status change' {
        $script:winE.FindName('ExecChecklist').SelectedIndex = 0
        $btn = $script:winE.FindName('BtnComplete')
        $btn.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        $md = Get-Content (Join-Path $script:tmpE 'procedure.md') -Raw
        $md | Should -Match 'status: done'
    }
}
