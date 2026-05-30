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
        $md | Should -Match '!\[\]\(images/a\.png\)'
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

    It 'prepends images/ to a BARE evidence filename in markdown (regression)' {
        $doc = [ProcedureDoc]::new('Doc')
        $s = $doc.AddStep('A')
        $s.Evidence.Add([ScreenshotRef]::new('cap1.png', (Get-Date), 'full')) | Out-Null
        $md = Write-Procedure -Procedure $doc
        $md | Should -Match '!\[\]\(images/cap1\.png\)'
    }

    It 'emits ### 履歴 section when StatusHistory is non-empty' {
        $doc = [ProcedureDoc]::new('Doc')
        $s = $doc.AddStep('A')
        $s.StatusHistory.Add([pscustomobject]@{ Status = 'creating';  At = [datetime]'2026-05-27T10:00:00'; ChangedBy = '' }) | Out-Null
        $s.StatusHistory.Add([pscustomobject]@{ Status = 'reviewing'; At = [datetime]'2026-05-27T10:30:00'; ChangedBy = '' }) | Out-Null
        $md = Write-Procedure -Procedure $doc
        $md | Should -Match '### 履歴'
        $md | Should -Match '2026-05-27T10:00:00 creating'
        $md | Should -Match '2026-05-27T10:30:00 reviewing'
    }

    It 'omits ### 履歴 section when StatusHistory is empty' {
        $doc = [ProcedureDoc]::new('Doc')
        $doc.AddStep('A') | Out-Null
        $md = Write-Procedure -Procedure $doc
        $md | Should -Not -Match '### 履歴'
    }

    It 'emits default* front matter keys when ProcedureDoc.Default* set' {
        $doc = [ProcedureDoc]::new('Doc')
        $doc.DefaultAuthor   = 'Alice'
        $doc.DefaultReviewer = 'Bob'
        $doc.DefaultExecutor = 'Charlie'
        $doc.DefaultVerifier = 'Dave'
        $md = Write-Procedure -Procedure $doc
        $md | Should -Match '(?m)^defaultAuthor: Alice$'
        $md | Should -Match '(?m)^defaultReviewer: Bob$'
        $md | Should -Match '(?m)^defaultExecutor: Charlie$'
        $md | Should -Match '(?m)^defaultVerifier: Dave$'
    }

    It 'omits default* front matter keys when empty' {
        $doc = [ProcedureDoc]::new('Doc')
        $md = Write-Procedure -Procedure $doc
        $md | Should -Not -Match 'defaultAuthor'
        $md | Should -Not -Match 'defaultReviewer'
    }

    It 'emits per-step role bullets when set' {
        $doc = [ProcedureDoc]::new('Doc')
        $s = $doc.AddStep('A')
        $s.Author   = 'Alice'
        $s.Reviewer = 'Bob'
        $s.Executor = 'Charlie'
        $s.Verifier = 'Dave'
        $md = Write-Procedure -Procedure $doc
        $md | Should -Match '(?m)^- author: Alice$'
        $md | Should -Match '(?m)^- reviewer: Bob$'
        $md | Should -Match '(?m)^- executor: Charlie$'
        $md | Should -Match '(?m)^- verifier: Dave$'
    }

    It 'omits per-step role bullets when empty' {
        $doc = [ProcedureDoc]::new('Doc')
        $doc.AddStep('A') | Out-Null
        $md = Write-Procedure -Procedure $doc
        $md | Should -Not -Match '(?m)^- author:'
        $md | Should -Not -Match '(?m)^- reviewer:'
    }
}
