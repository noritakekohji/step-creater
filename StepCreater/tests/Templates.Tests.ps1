using module '..\StepCreater.psd1'

Describe 'Get-StepTemplates' {
    It 'loads all .psd1 files from ui/templates/' {
        $templates = Get-StepTemplates
        $templates.Count | Should -BeGreaterOrEqual 2
    }

    It 'each template has required fields' {
        $templates = Get-StepTemplates
        foreach ($t in $templates) {
            $t.Name           | Should -Not -BeNullOrEmpty
            $t.Title          | Should -Not -BeNullOrEmpty
            $t.BodyMarkdown   | Should -Not -BeNullOrEmpty
        }
    }

    It 'returns IIS Install template' {
        $templates = Get-StepTemplates
        $iis = $templates | Where-Object { $_.Name -eq 'IIS Install' }
        $iis | Should -Not -BeNullOrEmpty
        $iis.Command | Should -Match 'Install-WindowsFeature'
    }
}

Describe 'Get-UserTemplateFolder + user override' {
    BeforeEach {
        $script:fakeConfigDir = Join-Path $TestDrive ("appdata-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-Item -ItemType Directory -Path $script:fakeConfigDir | Out-Null
        $env:STEPCREATER_CONFIG_DIR = $script:fakeConfigDir
    }
    AfterEach { Remove-Item Env:\STEPCREATER_CONFIG_DIR -ErrorAction SilentlyContinue }

    It 'returns the per-user folder under STEPCREATER_CONFIG_DIR\templates' {
        $expected = Join-Path $script:fakeConfigDir 'templates'
        Get-UserTemplateFolder | Should -Be $expected
    }

    It 'merges bundled and user templates; user wins on Name conflict' {
        $userDir = Join-Path $script:fakeConfigDir 'templates'
        New-Item -ItemType Directory -Path $userDir | Out-Null

        # Override an existing bundled template name
        $override = @"
@{
    Name           = 'IIS Install'
    Title          = 'MY IIS Install'
    BodyMarkdown   = 'overridden body'
    Command        = 'overridden command'
    ExpectedResult = ''
    Note           = ''
}
"@
        $utf8 = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText((Join-Path $userDir 'iis-override.psd1'), $override, $utf8)

        # Add a brand-new template
        $newTpl = @"
@{
    Name           = 'My Brand New'
    Title          = 'New Title'
    BodyMarkdown   = 'New body'
    Command        = ''
    ExpectedResult = ''
    Note           = ''
}
"@
        [System.IO.File]::WriteAllText((Join-Path $userDir 'mine.psd1'), $newTpl, $utf8)

        $templates = Get-StepTemplates
        $iis = $templates | Where-Object { $_.Name -eq 'IIS Install' }
        $iis.Title   | Should -Be 'MY IIS Install'
        $iis.Command | Should -Be 'overridden command'

        ($templates | Where-Object { $_.Name -eq 'My Brand New' }).Title | Should -Be 'New Title'
    }
}
