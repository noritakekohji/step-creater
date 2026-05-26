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
