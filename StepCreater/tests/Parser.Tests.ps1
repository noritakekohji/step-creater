using module '..\StepCreater.psd1'

Describe 'Read-Procedure (parser)' {
    BeforeAll {
        $script:fixturePath = "$PSScriptRoot/fixtures/sample-procedure.md"
        $script:doc = Read-Procedure -Path $script:fixturePath
    }

    It 'parses title from front matter' {
        $script:doc.Title | Should -Be 'Sample Doc'
    }

    It 'parses author and created date' {
        $script:doc.Author        | Should -Be 'tester'
        $script:doc.Created       | Should -Be ([datetime]'2026-05-27')
    }

    It 'parses two steps' {
        $script:doc.Steps.Count | Should -Be 2
    }

    It 'parses Step 1 metadata' {
        $s1 = $script:doc.Steps[0]
        $s1.Id              | Should -Be '01'
        $s1.Title           | Should -Be 'IIS Install'
        $s1.Status          | Should -Be 'done'
        $s1.Started         | Should -Be ([datetime]'2026-05-27T10:30:01')
        $s1.Finished        | Should -Be ([datetime]'2026-05-27T10:31:20')
    }

    It 'parses Step 1 body and command' {
        $s1 = $script:doc.Steps[0]
        $s1.BodyMarkdown   | Should -Match 'Install IIS via Server Manager'
        $s1.Command        | Should -Match 'Install-WindowsFeature -Name Web-Server'
        $s1.ExpectedResult | Should -Match 'Exit code 0'
        $s1.Note           | Should -Match 'Reboot may be required'
    }

    It 'parses Step 1 evidence images' {
        $s1 = $script:doc.Steps[0]
        $s1.Evidence.Count       | Should -Be 2
        $s1.Evidence[0].FileName | Should -Be 'images/2026-05-27_103045_step01.png'
        $s1.Evidence[1].FileName | Should -Be 'images/2026-05-27_103120_step01_win.png'
    }

    It 'defaults missing meta to pending and null times for Step 2' {
        $s2 = $script:doc.Steps[1]
        $s2.Status   | Should -Be 'pending'
        $s2.Started  | Should -BeNullOrEmpty
        $s2.Finished | Should -BeNullOrEmpty
    }

    It 'preserves unknown section "### 参考リンク" on Step 2' {
        $s2 = $script:doc.Steps[1]
        $s2.UnknownSectionsRaw.ContainsKey('### 参考リンク') | Should -BeTrue
        $s2.UnknownSectionsRaw['### 参考リンク']             | Should -Match 'https://example\.com'
    }
}