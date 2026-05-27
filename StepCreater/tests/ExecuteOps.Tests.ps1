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

    It 'resets Started and Finished to null on pending' {
        Set-StepStatus -Step $script:step -Status 'done'
        Set-StepStatus -Step $script:step -Status 'pending'
        $script:step.Status   | Should -Be 'pending'
        $script:step.Started  | Should -BeNullOrEmpty
        $script:step.Finished | Should -BeNullOrEmpty
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
        Set-StepStatus -Step $script:step -Status 'skipped'
        $script:step.Finished | Should -BeGreaterThan $firstFinish
    }
}
