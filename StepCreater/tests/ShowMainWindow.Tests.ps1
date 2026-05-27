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
