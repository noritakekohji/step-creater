using module '..\StepCreater.psd1'

Describe 'Write-Procedure (generator)' {
    It 'emits YAML front matter with title' {
        $doc = [ProcedureDoc]::new('Sample Doc')
        $doc.Created = [datetime]'2026-05-27'
        $md = Write-Procedure -Procedure $doc
        $md | Should -Match '(?ms)^---\r?\ntitle: Sample Doc\r?\ncreated: 2026-05-27\r?\n.*?---'
    }

    It 'emits H1 title after front matter' {
        $doc = [ProcedureDoc]::new('Sample Doc')
        $md = Write-Procedure -Procedure $doc
        $md | Should -Match '(?m)^# Sample Doc$'
    }

    It 'emits Step heading, step-id comment, and meta bullets' {
        $doc = [ProcedureDoc]::new('Doc')
        $step = $doc.AddStep('IIS Install')
        $step.Status = 'done'
        $step.Started  = [datetime]'2026-05-27T10:30:01'
        $step.Finished = [datetime]'2026-05-27T10:31:20'
        $md = Write-Procedure -Procedure $doc
        $md | Should -Match '(?m)^## Step 1: IIS Install$'
        $md | Should -Match '<!-- step-id: 01 -->'
        $md | Should -Match '(?m)^- status: done$'
        $md | Should -Match '(?m)^- started: 2026-05-27T10:30:01$'
        $md | Should -Match '(?m)^- finished: 2026-05-27T10:31:20$'
    }

    It 'emits the five fixed sections when present' {
        $doc = [ProcedureDoc]::new('Doc')
        $s = $doc.AddStep('Step1')
        $s.BodyMarkdown   = 'Do the thing.'
        $s.Command        = 'Install-WindowsFeature -Name Web-Server'
        $s.ExpectedResult = 'Exit code 0'
        $s.Note           = 'Reboot may be required'
        $s.Evidence.Add([ScreenshotRef]::new('img/a.png', [datetime]'2026-05-27', 'full')) | Out-Null
        $md = Write-Procedure -Procedure $doc

        $md | Should -Match '### 手順'
        $md | Should -Match 'Do the thing\.'
        $md | Should -Match '### 実行コマンド'
        $md | Should -Match '(?ms)```powershell\r?\nInstall-WindowsFeature -Name Web-Server\r?\n```'
        $md | Should -Match '### 想定結果'
        $md | Should -Match 'Exit code 0'
        $md | Should -Match '### エビデンス'
        $md | Should -Match '!\[\]\(img/a\.png\)'
        $md | Should -Match '### 備考'
        $md | Should -Match 'Reboot may be required'
    }

    It 'omits empty sections' {
        $doc = [ProcedureDoc]::new('Doc')
        $s = $doc.AddStep('Step1')
        $s.BodyMarkdown = 'Body only.'
        $md = Write-Procedure -Procedure $doc
        $md | Should -Not -Match '### 実行コマンド'
        $md | Should -Not -Match '### 想定結果'
        $md | Should -Not -Match '### エビデンス'
        $md | Should -Not -Match '### 備考'
    }

    It 'preserves unknown sections via UnknownSectionsRaw' {
        $doc = [ProcedureDoc]::new('Doc')
        $s = $doc.AddStep('Step1')
        $s.UnknownSectionsRaw['### 参考リンク'] = "- https://example.com`n- https://contoso.com"
        $md = Write-Procedure -Procedure $doc
        $md | Should -Match '### 参考リンク'
        $md | Should -Match 'https://example\.com'
    }

    It 'emits 手順画像 section when ProcedureImages present' {
        $doc = [ProcedureDoc]::new('Doc')
        $s = $doc.AddStep('Step1')
        $s.ProcedureImages.Add([ScreenshotRef]::new('images/proc1.png', [datetime]'2026-05-27', 'full')) | Out-Null
        $md = Write-Procedure -Procedure $doc
        $md | Should -Match '### 手順画像'
        $md | Should -Match '!\[\]\(images/proc1\.png\)'
    }
}