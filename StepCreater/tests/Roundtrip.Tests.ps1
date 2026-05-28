using module '..\StepCreater.psd1'

Describe 'Markdown round-trip' {
    It 'preserves all Step fields through generate -> parse' {
        $doc = [ProcedureDoc]::new('Round-Trip Doc')
        $doc.Author  = 'tester'
        $doc.Created = [datetime]'2026-05-27'

        $a = $doc.AddStep('Install')
        $a.BodyMarkdown   = 'Install the thing.'
        $a.Command        = 'Install-WindowsFeature -Name Web-Server'
        $a.ExpectedResult = 'Exit code 0'
        $a.Status         = 'done'
        $a.Started        = [datetime]'2026-05-27T10:00:00'
        $a.Finished       = [datetime]'2026-05-27T10:05:00'
        $a.Note           = 'Reboot first.'
        $a.Evidence.Add([ScreenshotRef]::new('x.png', [datetime]'2026-05-27', 'full')) | Out-Null
        $a.ProcedureImages.Add([ScreenshotRef]::new('proc.png', [datetime]'2026-05-27', 'full')) | Out-Null

        $b = $doc.AddStep('Configure')
        $b.BodyMarkdown   = 'Edit bindings.'
        $b.UnknownSectionsRaw['### 参考リンク'] = '- https://example.com'

        $md = Write-Procedure -Procedure $doc
        $tmp = New-TemporaryFile
        Set-Content -LiteralPath $tmp.FullName -Value $md -Encoding UTF8
        $parsed = Read-Procedure -Path $tmp.FullName

        $parsed.Title             | Should -Be 'Round-Trip Doc'
        $parsed.Author            | Should -Be 'tester'
        $parsed.Steps.Count       | Should -Be 2

        $parsed.Steps[0].Title           | Should -Be 'Install'
        $parsed.Steps[0].Status          | Should -Be 'done'
        $parsed.Steps[0].Command         | Should -Match 'Install-WindowsFeature'
        $parsed.Steps[0].Started         | Should -Be ([datetime]'2026-05-27T10:00:00')
        $parsed.Steps[0].Finished        | Should -Be ([datetime]'2026-05-27T10:05:00')
        $parsed.Steps[0].Evidence.Count  | Should -Be 1
        $parsed.Steps[0].Evidence[0].FileName | Should -Be 'x.png'
        $parsed.Steps[0].ProcedureImages.Count | Should -Be 1
        $parsed.Steps[0].ProcedureImages[0].FileName | Should -Be 'proc.png'

        $parsed.Steps[1].UnknownSectionsRaw['### 参考リンク'] | Should -Match 'example.com'

        Remove-Item $tmp.FullName -Force
    }
}