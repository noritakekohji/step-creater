using module '..\StepCreater.psd1'

Describe 'Hotkey hook scriptblock' {
    BeforeAll {
        Add-Type -AssemblyName PresentationFramework
        Initialize-StepCreaterWin32
    }

    It 'Register-StepCreaterHotkeys returns a handle exposing the hook scriptblock' {
        $win = New-Object System.Windows.Window
        $win.Width = 200; $win.Height = 100
        $win.Add_Loaded({
            $handle = Register-StepCreaterHotkeys -Window $win -Combos @{
                full = 'Ctrl+F12'; window = 'Ctrl+F11'; rect = 'Ctrl+Shift+F12'
            } -OnFull {} -OnWindow {} -OnRect {}
            $win.Tag = $handle
            $win.Dispatcher.BeginInvoke(
                [System.Windows.Threading.DispatcherPriority]::ApplicationIdle,
                [Action]{ $win.Close() }
            ) | Out-Null
        }.GetNewClosure())

        [void]$win.ShowDialog()

        $handle = $win.Tag
        $handle | Should -Not -BeNullOrEmpty
        $handle.Hook | Should -BeOfType [scriptblock]

        # Synthetic call: non-WM_HOTKEY message should return IntPtr.Zero without touching $handled
        $handled = $false
        $result = & $handle.Hook ([IntPtr]::Zero) 0x0001 ([IntPtr]::Zero) ([IntPtr]::Zero) ([ref]$handled)
        $result   | Should -Be ([IntPtr]::Zero)
        $handled | Should -BeFalse

        # Synthetic call with null $handled should not throw (regression for bug #1)
        { & $handle.Hook ([IntPtr]::Zero) 0x0001 ([IntPtr]::Zero) ([IntPtr]::Zero) $null } | Should -Not -Throw

        Unregister-StepCreaterHotkeys -Handle $handle
    }
}
