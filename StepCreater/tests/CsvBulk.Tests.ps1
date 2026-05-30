using module '..\StepCreater.psd1'

Describe 'ConvertTo-SanitizedFolderName' {
    It 'returns empty for empty input' { ConvertTo-SanitizedFolderName '' | Should -Be '' }
    It 'replaces forbidden chars with _' {
        ConvertTo-SanitizedFolderName 'abc/def:ghi?xyz' | Should -Be 'abc_def_ghi_xyz'
    }
    It 'preserves Japanese' {
        ConvertTo-SanitizedFolderName '手順書 A' | Should -Be '手順書 A'
    }
}

Describe 'Save-SampleCsvTemplate' {
    It 'writes a CSV with UTF-8 BOM and the expected header' {
        $tmp = Join-Path $TestDrive ("tpl-" + ([guid]::NewGuid().ToString('N').Substring(0,8)) + ".csv")
        Save-SampleCsvTemplate -Path $tmp
        Test-Path $tmp | Should -BeTrue
        $bytes = [System.IO.File]::ReadAllBytes($tmp)
        $bytes[0] | Should -Be 0xEF
        $bytes[1] | Should -Be 0xBB
        $bytes[2] | Should -Be 0xBF
        $text = [System.IO.File]::ReadAllText($tmp, [System.Text.UTF8Encoding]::new($true))
        $text | Should -Match 'ProcedureTitle'
        $text | Should -Match 'StepTitle'
        $text | Should -Match 'サーバ構築手順'
    }
}

Describe 'Import-ProceduresFromCsv' {
    It 'creates one workfolder per ProcedureTitle group with all steps' {
        $csvPath = Join-Path $TestDrive ("imp-" + ([guid]::NewGuid().ToString('N').Substring(0,8)) + ".csv")
        $out     = Join-Path $TestDrive ("out-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))

        # Build a tiny CSV
        $rows = @(
            [pscustomobject]@{ProcedureTitle='P1'; WorkfolderName='p1'; DefaultAuthor='A'; DefaultReviewer=''; DefaultExecutor=''; DefaultVerifier=''; StepTitle='S1'; StepBody='b1'; StepCommand=''; StepExpected=''; StepNote=''; StepStatus='creating'; StepAuthor=''; StepReviewer=''; StepExecutor=''; StepVerifier=''}
            [pscustomobject]@{ProcedureTitle='P1'; WorkfolderName=''; DefaultAuthor=''; DefaultReviewer=''; DefaultExecutor=''; DefaultVerifier=''; StepTitle='S2'; StepBody='b2'; StepCommand='cmd'; StepExpected=''; StepNote=''; StepStatus='done'; StepAuthor=''; StepReviewer=''; StepExecutor=''; StepVerifier=''}
            [pscustomobject]@{ProcedureTitle='P2'; WorkfolderName=''; DefaultAuthor=''; DefaultReviewer=''; DefaultExecutor=''; DefaultVerifier=''; StepTitle='X';  StepBody=''; StepCommand=''; StepExpected=''; StepNote=''; StepStatus='creating'; StepAuthor=''; StepReviewer=''; StepExecutor=''; StepVerifier=''}
        )
        $csv = $rows | ConvertTo-Csv -NoTypeInformation
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllLines($csvPath, $csv, $utf8Bom)

        $r = Import-ProceduresFromCsv -CsvPath $csvPath -OutputFolder $out
        $r.Created.Count | Should -Be 2
        $r.Errors.Count  | Should -Be 0

        # P1: two steps, default author = A
        $p1md = Get-Content (Join-Path $out 'p1\procedure.md') -Raw
        $p1md | Should -Match 'title: P1'
        $p1md | Should -Match 'defaultAuthor: A'
        $p1md | Should -Match '## Step 1: S1'
        $p1md | Should -Match '## Step 2: S2'
        $p1md | Should -Match '- status: done'

        # P2: workfolder name sanitized from title
        Test-Path (Join-Path $out 'P2\procedure.md') | Should -BeTrue
    }

    It 'returns an error row when required columns are missing' {
        $csvPath = Join-Path $TestDrive ("bad-" + ([guid]::NewGuid().ToString('N').Substring(0,8)) + ".csv")
        $out     = Join-Path $TestDrive ("badout-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        @('Foo,Bar','a,b') | Set-Content -LiteralPath $csvPath -Encoding UTF8
        $r = Import-ProceduresFromCsv -CsvPath $csvPath -OutputFolder $out
        $r.Created.Count | Should -Be 0
        $r.Errors.Count  | Should -BeGreaterThan 0
    }
}

Describe 'Export-ProceduresToCsv' {
    It 'round-trips through import: export then re-import produces same procedures' {
        $src = Join-Path $TestDrive ("src-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        $csv = Join-Path $TestDrive ("rt-"  + ([guid]::NewGuid().ToString('N').Substring(0,8)) + ".csv")
        $dst = Join-Path $TestDrive ("dst-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))

        # Build source: two workfolders, one with 2 steps, one with 1
        $a = Join-Path $src 'A'
        New-StepCreaterWorkfolder -Path $a -Title 'Proc A' | Out-Null
        $sessA = Open-StepCreaterWorkfolder -Path $a
        $sessA.Procedure.DefaultAuthor = 'Alice'
        $sa1 = $sessA.Procedure.AddStep('Setup'); $sa1.Status = 'done'; $sa1.ExpectedResult = 'OK'
        $sessA.Procedure.AddStep('Done')  | Out-Null
        Save-WorkSession -Session $sessA

        $b = Join-Path $src 'B'
        New-StepCreaterWorkfolder -Path $b -Title 'Proc B' | Out-Null
        $sessB = Open-StepCreaterWorkfolder -Path $b
        $sessB.Procedure.AddStep('Solo') | Out-Null
        Save-WorkSession -Session $sessB

        $n = Export-ProceduresToCsv -ParentFolder $src -CsvPath $csv
        $n | Should -Be 3

        # Now re-import to a fresh folder
        $r = Import-ProceduresFromCsv -CsvPath $csv -OutputFolder $dst
        $r.Created.Count | Should -Be 2
        $r.Errors.Count  | Should -Be 0

        Test-Path (Join-Path $dst 'A\procedure.md') | Should -BeTrue
        $a2 = Read-Procedure -Path (Join-Path $dst 'A\procedure.md')
        $a2.Title              | Should -Be 'Proc A'
        $a2.DefaultAuthor      | Should -Be 'Alice'
        $a2.Steps.Count        | Should -Be 2
        $a2.Steps[0].Status    | Should -Be 'done'
        $a2.Steps[0].ExpectedResult | Should -Be 'OK'
    }
}
