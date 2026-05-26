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
