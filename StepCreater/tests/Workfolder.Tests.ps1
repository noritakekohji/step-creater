using module '..\StepCreater.psd1'

Describe 'New-StepCreaterWorkfolder' {
    BeforeEach {
        $script:wf = Join-Path $TestDrive 'wf1'
        if (Test-Path $script:wf) { Remove-Item $script:wf -Recurse -Force }
    }

    It 'creates the expected folder layout' {
        New-StepCreaterWorkfolder -Path $script:wf -Title 'My Doc' | Out-Null
        Test-Path (Join-Path $script:wf 'procedure.md')                  | Should -BeTrue
        Test-Path (Join-Path $script:wf 'images')                        | Should -BeTrue
        Test-Path (Join-Path $script:wf 'attachments')                   | Should -BeTrue
        Test-Path (Join-Path $script:wf '.stepcreater')                  | Should -BeTrue
        Test-Path (Join-Path $script:wf '.stepcreater/state.json')       | Should -BeTrue
    }

    It 'writes procedure.md with title from parameter' {
        New-StepCreaterWorkfolder -Path $script:wf -Title 'My Doc' | Out-Null
        $md = Get-Content (Join-Path $script:wf 'procedure.md') -Raw
        $md | Should -Match 'title: My Doc'
        $md | Should -Match '(?m)^# My Doc$'
    }

    It 'refuses to overwrite existing non-empty folder unless -Force' {
        New-Item -ItemType Directory -Path $script:wf | Out-Null
        New-Item -ItemType File -Path (Join-Path $script:wf 'existing.txt') | Out-Null
        { New-StepCreaterWorkfolder -Path $script:wf -Title 'X' } | Should -Throw
    }
}

Describe 'Open-StepCreaterWorkfolder' {
    BeforeEach {
        $script:wf = Join-Path $TestDrive 'wf2'
        if (Test-Path $script:wf) { Remove-Item $script:wf -Recurse -Force }
        New-StepCreaterWorkfolder -Path $script:wf -Title 'Open Test' | Out-Null
    }

    It 'returns a session with parsed Procedure' {
        $sess = Open-StepCreaterWorkfolder -Path $script:wf
        $sess.WorkFolderPath  | Should -Be (Resolve-Path $script:wf).Path
        $sess.Procedure.Title | Should -Be 'Open Test'
    }

    It 'creates state.json with default contents if missing' {
        Remove-Item (Join-Path $script:wf '.stepcreater/state.json') -Force
        $sess = Open-StepCreaterWorkfolder -Path $script:wf
        Test-Path (Join-Path $script:wf '.stepcreater/state.json') | Should -BeTrue
        $sess.CurrentStepIndex | Should -Be 0
    }
}
