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

    It 'creation mode omits evidence sections' {
        $doc = [ProcedureDoc]::new('Doc')
        $s = $doc.AddStep('A')
        $s.Evidence.Add([ScreenshotRef]::new('images/a.png', [datetime]'2026-05-27', 'full')) | Out-Null
        $html = ConvertTo-ProcedureHtml -Procedure $doc -Mode creation
        $html | Should -Not -Match 'section evidence'
        $html | Should -Not -Match 'src="images/a\.png"'
    }

    It 'execution mode shows evidence' {
        $doc = [ProcedureDoc]::new('Doc')
        $s = $doc.AddStep('A')
        $s.Evidence.Add([ScreenshotRef]::new('images/a.png', [datetime]'2026-05-27', 'full')) | Out-Null
        $html = ConvertTo-ProcedureHtml -Procedure $doc -Mode execution
        $html | Should -Match 'section evidence'
    }

    It 'execution mode shows status history when present' {
        $doc = [ProcedureDoc]::new('Doc')
        $s = $doc.AddStep('A')
        $s.StatusHistory.Add([pscustomobject]@{Status='creating';At=[datetime]'2026-05-27T10:00:00';ChangedBy=''}) | Out-Null
        $s.StatusHistory.Add([pscustomobject]@{Status='done';    At=[datetime]'2026-05-27T11:00:00';ChangedBy=''}) | Out-Null
        $html = ConvertTo-ProcedureHtml -Procedure $doc -Mode execution
        $html | Should -Match 'status-history'
        $html | Should -Match '作成中'
        $html | Should -Match '完了'
    }

    It 'creation mode shows author and reviewer' {
        $doc = [ProcedureDoc]::new('Doc')
        $doc.DefaultAuthor = 'Alice'
        $doc.DefaultReviewer = 'Bob'
        $doc.AddStep('A') | Out-Null
        $html = ConvertTo-ProcedureHtml -Procedure $doc -Mode creation
        $html | Should -Match 'Alice'
        $html | Should -Match 'Bob'
    }

    It 'creation mode omits working time duration span' {
        $doc = [ProcedureDoc]::new('Doc')
        $s = $doc.AddStep('A')
        $s.Started  = [datetime]'2026-05-27T10:00:00'
        $s.Finished = [datetime]'2026-05-27T10:05:23'
        $html = ConvertTo-ProcedureHtml -Procedure $doc -Mode creation
        $html | Should -Not -Match 'class="duration"'
        $html | Should -Not -Match '00:05:23'
    }
}

Describe 'Get-EffectiveRole' {
    It 'returns the step override when set' {
        $doc = [ProcedureDoc]::new('D'); $doc.DefaultAuthor = 'P'
        $s = $doc.AddStep('A'); $s.Author = 'S'
        Get-EffectiveRole -Step $s -Procedure $doc -Role Author | Should -Be 'S'
    }
    It 'falls back to procedure default' {
        $doc = [ProcedureDoc]::new('D'); $doc.DefaultAuthor = 'P'
        $s = $doc.AddStep('A')
        Get-EffectiveRole -Step $s -Procedure $doc -Role Author | Should -Be 'P'
    }
    It 'returns empty when neither set' {
        $doc = [ProcedureDoc]::new('D')
        $s = $doc.AddStep('A')
        Get-EffectiveRole -Step $s -Procedure $doc -Role Author | Should -Be ''
    }
}
