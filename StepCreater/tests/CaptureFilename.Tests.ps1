using module '..\StepCreater.psd1'

Describe 'Get-CaptureFileName' {
    It 'returns YYYY-MM-DD_HHmmss_stepNN.png for full kind' {
        $name = Get-CaptureFileName -Kind 'full' -StepId '03' -Timestamp ([datetime]'2026-05-27T10:30:45')
        $name | Should -Be '2026-05-27_103045_step03.png'
    }

    It 'appends _win for window kind' {
        $name = Get-CaptureFileName -Kind 'window' -StepId '01' -Timestamp ([datetime]'2026-05-27T10:30:45')
        $name | Should -Be '2026-05-27_103045_step01_win.png'
    }

    It 'appends _rect for rect kind' {
        $name = Get-CaptureFileName -Kind 'rect' -StepId '01' -Timestamp ([datetime]'2026-05-27T10:30:45')
        $name | Should -Be '2026-05-27_103045_step01_rect.png'
    }

    It 'uses "unassigned" when StepId is empty' {
        $name = Get-CaptureFileName -Kind 'full' -StepId '' -Timestamp ([datetime]'2026-05-27T10:30:45')
        $name | Should -Be '2026-05-27_103045_unassigned.png'
    }
}
