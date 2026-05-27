using module '..\StepCreater.psd1'

Describe 'ConvertTo-HotkeySpec' {
    It 'parses Ctrl+F12' {
        $spec = ConvertTo-HotkeySpec -Combo 'Ctrl+F12'
        $spec.Modifiers | Should -Be 0x2
        $spec.VKey      | Should -Be 0x7B
    }

    It 'parses Ctrl+Shift+F11' {
        $spec = ConvertTo-HotkeySpec -Combo 'Ctrl+Shift+F11'
        $spec.Modifiers | Should -Be (0x2 -bor 0x4)
        $spec.VKey      | Should -Be 0x7A
    }

    It 'parses Alt+S' {
        $spec = ConvertTo-HotkeySpec -Combo 'Alt+S'
        $spec.Modifiers | Should -Be 0x1
        $spec.VKey      | Should -Be 0x53
    }

    It 'is case-insensitive' {
        $spec = ConvertTo-HotkeySpec -Combo 'ctrl+f12'
        $spec.VKey | Should -Be 0x7B
    }

    It 'throws on unknown key' {
        { ConvertTo-HotkeySpec -Combo 'Ctrl+Nope' } | Should -Throw
    }
}