using module '..\StepCreater.psd1'

Describe 'Get/Set-StepCreaterConfig' {
    BeforeEach {
        $script:tempRoot = Join-Path $TestDrive 'appdata'
        if (Test-Path $script:tempRoot) { Remove-Item $script:tempRoot -Recurse -Force }
        New-Item -ItemType Directory -Path $script:tempRoot | Out-Null
        $env:STEPCREATER_CONFIG_DIR = $script:tempRoot
    }
    AfterEach {
        Remove-Item Env:\STEPCREATER_CONFIG_DIR -ErrorAction SilentlyContinue
    }

    It 'returns defaults on first read' {
        $cfg = Get-StepCreaterConfig
        $cfg.hotkeys.fullScreen | Should -Be 'Ctrl+F12'
        $cfg.hotkeys.window     | Should -Be 'Ctrl+F11'
        $cfg.hotkeys.rect       | Should -Be 'Ctrl+Shift+F12'
        $cfg.annotationEnabled  | Should -BeTrue
        $cfg.recentWorkfolders.Count | Should -Be 0
    }

    It 'persists Set-StepCreaterConfig changes across reads' {
        $cfg = Get-StepCreaterConfig
        $cfg.hotkeys.fullScreen = 'Ctrl+Shift+P'
        Set-StepCreaterConfig -Config $cfg
        $reread = Get-StepCreaterConfig
        $reread.hotkeys.fullScreen | Should -Be 'Ctrl+Shift+P'
    }
}
