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
        $s1.Evidence[0].FileName | Should -Be '2026-05-27_103045_step01.png'
        $s1.Evidence[1].FileName | Should -Be '2026-05-27_103120_step01_win.png'
    }

    It 'migrates old pending status to creating for Step 2' {
        $s2 = $script:doc.Steps[1]
        $s2.Status   | Should -Be 'creating'
        $s2.Started  | Should -BeNullOrEmpty
        $s2.Finished | Should -BeNullOrEmpty
    }

    It 'preserves unknown section "### 参考リンク" on Step 2' {
        $s2 = $script:doc.Steps[1]
        $s2.UnknownSectionsRaw.ContainsKey('### 参考リンク') | Should -BeTrue
        $s2.UnknownSectionsRaw['### 参考リンク']             | Should -Match 'https://example\.com'
    }
}

Describe 'Read-Procedure 手順画像' {
    It 'parses 手順画像 section into ProcedureImages' {
        $md = @"
---
title: PI Test
---

# PI Test

## Step 1: A
<!-- step-id: 01 -->
- status: creating

### 手順画像
![](images/p1.png)
![](images/p2.png)

### エビデンス
![](images/e1.png)
"@
        $tmp = New-TemporaryFile
        Set-Content -LiteralPath $tmp.FullName -Value $md -Encoding UTF8
        $doc = Read-Procedure -Path $tmp.FullName
        Remove-Item $tmp.FullName -Force
        $doc.Steps[0].ProcedureImages.Count | Should -Be 2
        $doc.Steps[0].ProcedureImages[0].FileName | Should -Be 'p1.png'
        $doc.Steps[0].Evidence.Count | Should -Be 1
        $doc.Steps[0].Evidence[0].FileName | Should -Be 'e1.png'
    }
}

Describe 'Read-Procedure status migration' {
    It 'migrates skipped to aborted' {
        $md = @"
---
title: T
---

# T

## Step 1: A
<!-- step-id: 01 -->
- status: skipped
"@
        $tmp = New-TemporaryFile
        Set-Content -LiteralPath $tmp.FullName -Value $md -Encoding UTF8
        $doc = Read-Procedure -Path $tmp.FullName
        Remove-Item $tmp.FullName -Force
        $doc.Steps[0].Status | Should -Be 'aborted'
    }

    It 'migrates pending to creating' {
        $md = @"
---
title: T
---

# T

## Step 1: A
<!-- step-id: 01 -->
- status: pending
"@
        $tmp = New-TemporaryFile
        Set-Content -LiteralPath $tmp.FullName -Value $md -Encoding UTF8
        $doc = Read-Procedure -Path $tmp.FullName
        Remove-Item $tmp.FullName -Force
        $doc.Steps[0].Status | Should -Be 'creating'
    }

    It 'passes new 8-value statuses through unchanged' {
        foreach ($s in @('creating','reviewing','created','executing','verifying','ng','aborted','done')) {
            $md = "---`ntitle: T`n---`n`n# T`n`n## Step 1: A`n<!-- step-id: 01 -->`n- status: $s`n"
            $tmp = New-TemporaryFile
            Set-Content -LiteralPath $tmp.FullName -Value $md -Encoding UTF8
            $doc = Read-Procedure -Path $tmp.FullName
            Remove-Item $tmp.FullName -Force
            $doc.Steps[0].Status | Should -Be $s
        }
    }
}

Describe 'Read-Procedure default front matter keys' {
    It 'parses defaultAuthor/Reviewer/Executor/Verifier into ProcedureDoc' {
        $md = @"
---
title: T
defaultAuthor: Alice
defaultReviewer: Bob
defaultExecutor: Charlie
defaultVerifier: Dave
---

# T
"@
        $tmp = New-TemporaryFile
        Set-Content -LiteralPath $tmp.FullName -Value $md -Encoding UTF8
        $doc = Read-Procedure -Path $tmp.FullName
        Remove-Item $tmp.FullName -Force
        $doc.DefaultAuthor   | Should -Be 'Alice'
        $doc.DefaultReviewer | Should -Be 'Bob'
        $doc.DefaultExecutor | Should -Be 'Charlie'
        $doc.DefaultVerifier | Should -Be 'Dave'
    }
}

Describe 'Read-Procedure role bullets' {
    It 'parses author/reviewer/executor/verifier bullets into Step' {
        $md = @"
---
title: T
---

# T

## Step 1: A
<!-- step-id: 01 -->
- status: creating
- author: Alice
- reviewer: Bob
- executor: Charlie
- verifier: Dave
"@
        $tmp = New-TemporaryFile
        Set-Content -LiteralPath $tmp.FullName -Value $md -Encoding UTF8
        $doc = Read-Procedure -Path $tmp.FullName
        Remove-Item $tmp.FullName -Force
        $doc.Steps[0].Author   | Should -Be 'Alice'
        $doc.Steps[0].Reviewer | Should -Be 'Bob'
        $doc.Steps[0].Executor | Should -Be 'Charlie'
        $doc.Steps[0].Verifier | Should -Be 'Dave'
    }
}

Describe 'Read-Procedure history section' {
    It 'parses ### 履歴 into StatusHistory entries' {
        $md = @"
---
title: T
---

# T

## Step 1: A
<!-- step-id: 01 -->
- status: done

### 履歴
- 2026-05-27T10:00:00 creating
- 2026-05-27T10:30:00 reviewing
- 2026-05-27T11:00:00 done
"@
        $tmp = New-TemporaryFile
        Set-Content -LiteralPath $tmp.FullName -Value $md -Encoding UTF8
        $doc = Read-Procedure -Path $tmp.FullName
        Remove-Item $tmp.FullName -Force
        $doc.Steps[0].StatusHistory.Count           | Should -Be 3
        $doc.Steps[0].StatusHistory[0].Status       | Should -Be 'creating'
        $doc.Steps[0].StatusHistory[0].At           | Should -Be ([datetime]'2026-05-27T10:00:00')
        $doc.Steps[0].StatusHistory[2].Status       | Should -Be 'done'
    }

    It 'leaves StatusHistory empty when ### 履歴 absent' {
        $md = @"
---
title: T
---

# T

## Step 1: A
<!-- step-id: 01 -->
- status: creating
"@
        $tmp = New-TemporaryFile
        Set-Content -LiteralPath $tmp.FullName -Value $md -Encoding UTF8
        $doc = Read-Procedure -Path $tmp.FullName
        Remove-Item $tmp.FullName -Force
        $doc.Steps[0].StatusHistory.Count | Should -Be 0
    }
}
