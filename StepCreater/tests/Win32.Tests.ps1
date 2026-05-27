using module '..\StepCreater.psd1'

Describe 'Win32 P/Invoke types' {
    It 'Initialize-StepCreaterWin32 loads required types' {
        Initialize-StepCreaterWin32
        [StepCreater.Win32] | Should -Not -BeNullOrEmpty
    }

    It 'StepCreater.Win32 exposes RegisterHotKey method' {
        Initialize-StepCreaterWin32
        $m = [StepCreater.Win32].GetMethod('RegisterHotKey')
        $m | Should -Not -BeNullOrEmpty
    }

    It 'StepCreater.Win32 exposes UnregisterHotKey method' {
        Initialize-StepCreaterWin32
        $m = [StepCreater.Win32].GetMethod('UnregisterHotKey')
        $m | Should -Not -BeNullOrEmpty
    }

    It 'StepCreater.Win32 exposes GetForegroundWindow method' {
        Initialize-StepCreaterWin32
        $m = [StepCreater.Win32].GetMethod('GetForegroundWindow')
        $m | Should -Not -BeNullOrEmpty
    }
}
