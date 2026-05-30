using module '..\StepCreater.psd1'

Describe 'ConvertTo-ProcedureHtml' {
    BeforeAll {
        $script:doc = [ProcedureDoc]::new('Test Procedure')
        $script:doc.Author = 'tester'
        $script:doc.Created = [datetime]'2026-05-27'
        $a = $script:doc.AddStep('IIS Install')
        $a.BodyMarkdown   = 'Install **IIS** via PowerShell.'
        $a.Command        = 'Install-WindowsFeature -Name Web-Server'
        $a.ExpectedResult = 'Exit code 0'
        $a.Status         = 'done'
        $a.Started        = [datetime]'2026-05-27T10:00:00'
        $a.Finished       = [datetime]'2026-05-27T10:05:23'
        $a.Note           = 'May need restart.'
        $a.Evidence.Add([ScreenshotRef]::new('images/a.png', [datetime]'2026-05-27', 'full')) | Out-Null

        $b = $script:doc.AddStep('Configure')
        $b.Status = 'creating'

        $script:html = ConvertTo-ProcedureHtml -Procedure $script:doc
    }

    It 'returns a string starting with `<!DOCTYPE html`>' {
        $script:html | Should -Match '^<!DOCTYPE html>'
    }

    It 'includes the procedure title in <title> and h1' {
        $script:html | Should -Match '<title>Test Procedure</title>'
        $script:html | Should -Match '<h1[^>]*>Test Procedure</h1>'
    }

    It 'includes a table of contents linking to each step' {
        $script:html | Should -Match 'href="#step-01"'
        $script:html | Should -Match 'href="#step-02"'
    }

    It 'shows status badges' {
        $script:html | Should -Match 'badge-done'
        $script:html | Should -Match 'badge-creating'
    }

    It 'shows working time for completed steps' {
        $script:html | Should -Match '00:05:23'
    }

    It 'renders evidence images with relative paths' {
        $script:html | Should -Match 'src="images/a\.png"'
    }

    It 'renders code block for command' {
        $script:html | Should -Match 'Install-WindowsFeature -Name Web-Server'
        $script:html | Should -Match '<pre'
    }

    It 'escapes HTML entities in user content' {
        $doc2 = [ProcedureDoc]::new('Test & Title')
        $s = $doc2.AddStep('A < B')
        $s.BodyMarkdown = '<script>alert(1)</script>'
        $html = ConvertTo-ProcedureHtml -Procedure $doc2
        $html | Should -Match 'Test &amp; Title'
        $html | Should -Match 'A &lt; B'
        $html | Should -Not -Match '<script>alert\(1\)</script>'
    }

    It 'renders 手順画像 images' {
        $doc = [ProcedureDoc]::new('Doc')
        $s = $doc.AddStep('A')
        $s.ProcedureImages.Add([ScreenshotRef]::new('images/proc.png', [datetime]'2026-05-27', 'full')) | Out-Null
        $html = ConvertTo-ProcedureHtml -Procedure $doc
        $html | Should -Match 'procedure-images'
        $html | Should -Match 'src="images/proc\.png"'
    }

    It 'prepends images/ to a BARE evidence filename (regression)' {
        $doc = [ProcedureDoc]::new('Doc')
        $s = $doc.AddStep('A')
        $s.Evidence.Add([ScreenshotRef]::new('2026-05-27_103045_step01.png', (Get-Date), 'full')) | Out-Null
        $html = ConvertTo-ProcedureHtml -Procedure $doc
        $html | Should -Match 'src="images/2026-05-27_103045_step01\.png"'
        $html | Should -Not -Match 'src="2026-05-27_103045_step01\.png"'
    }
}
