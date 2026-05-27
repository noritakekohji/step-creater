using module '..\StepCreater.psd1'

Describe 'Get-StepDuration' {
    It 'returns "-" when Started is null' {
        $s = [Step]::new('01', 'A')
        Get-StepDuration -Step $s | Should -Be '-'
    }

    It 'returns "-" when Finished is null' {
        $s = [Step]::new('01', 'A')
        $s.Started = Get-Date
        Get-StepDuration -Step $s | Should -Be '-'
    }

    It 'returns formatted HH:mm:ss for a 5m23s span' {
        $s = [Step]::new('01', 'A')
        $s.Started  = [datetime]'2026-05-27T10:00:00'
        $s.Finished = [datetime]'2026-05-27T10:05:23'
        Get-StepDuration -Step $s | Should -Be '00:05:23'
    }

    It 'returns HH:mm:ss for a >1h span' {
        $s = [Step]::new('01', 'A')
        $s.Started  = [datetime]'2026-05-27T10:00:00'
        $s.Finished = [datetime]'2026-05-27T11:30:45'
        Get-StepDuration -Step $s | Should -Be '01:30:45'
    }
}
