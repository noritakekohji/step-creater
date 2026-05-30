using module '..\StepCreater.psd1'

Describe 'Set-StepStatus' {
    BeforeEach {
        $script:doc = [ProcedureDoc]::new('Doc')
        $script:step = $script:doc.AddStep('A')
    }

    It 'records Started and Finished on terminal status' {
        $before = Get-Date
        Set-StepStatus -Step $script:step -Status 'done'
        $script:step.Status   | Should -Be 'done'
        $script:step.Started  | Should -Not -BeNullOrEmpty
        $script:step.Finished | Should -Not -BeNullOrEmpty
        $script:step.Started  | Should -BeGreaterOrEqual $before
    }

    It 'appends history entry on each call' {
        Set-StepStatus -Step $script:step -Status 'executing'
        $script:step.StatusHistory.Count | Should -Be 1
        $script:step.StatusHistory[0].Status | Should -Be 'executing'
        Set-StepStatus -Step $script:step -Status 'done'
        $script:step.StatusHistory.Count | Should -Be 2
        $script:step.StatusHistory[1].Status | Should -Be 'done'
    }

    It 'sets creating and appends history but does not set Started/Finished' {
        Set-StepStatus -Step $script:step -Status 'creating'
        $script:step.Status   | Should -Be 'creating'
        $script:step.Started  | Should -BeNullOrEmpty
        $script:step.Finished | Should -BeNullOrEmpty
        $script:step.StatusHistory.Count | Should -Be 1
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
        Set-StepStatus -Step $script:step -Status 'aborted'
        $script:step.Finished | Should -BeGreaterThan $firstFinish
    }

    It 'sets Started on first non-creating transition' {
        Set-StepStatus -Step $script:step -Status 'reviewing'
        $script:step.Started  | Should -Not -BeNullOrEmpty
        $script:step.Finished | Should -BeNullOrEmpty
    }

    It 'sets Finished on aborted transition' {
        Set-StepStatus -Step $script:step -Status 'aborted'
        $script:step.Finished | Should -Not -BeNullOrEmpty
    }
}
