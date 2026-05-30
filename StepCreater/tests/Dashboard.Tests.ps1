using module '..\StepCreater.psd1'

Describe 'Get-DashboardRows' {
    It 'scans subdirectories and returns rows for each Step' {
        $root = Join-Path $TestDrive ("dash-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-Item -ItemType Directory -Path $root | Out-Null

        # Workfolder A
        $a = Join-Path $root 'A'
        New-StepCreaterWorkfolder -Path $a -Title 'Proc A' | Out-Null
        $sessA = Open-StepCreaterWorkfolder -Path $a
        $sa1 = $sessA.Procedure.AddStep('Setup'); $sa1.Status = 'done'
        $sa1.Started  = [datetime]'2026-05-27T10:00:00'
        $sa1.Finished = [datetime]'2026-05-27T10:05:00'
        $sessA.Procedure.AddStep('Configure') | Out-Null
        Save-WorkSession -Session $sessA

        # Workfolder B (nested)
        $b = Join-Path $root 'sub\B'
        New-StepCreaterWorkfolder -Path $b -Title 'Proc B' | Out-Null
        $sessB = Open-StepCreaterWorkfolder -Path $b
        $sb1 = $sessB.Procedure.AddStep('Install'); $sb1.Status = 'ng'
        Save-WorkSession -Session $sessB

        $rows = @(Get-DashboardRows -ParentFolder $root)
        $rows.Count | Should -Be 3

        $rowsA = @($rows | Where-Object { $_.Workfolder -eq 'A' })
        $rowsA.Count                       | Should -Be 2
        $rowsA[0].ProcedureTitle           | Should -Be 'Proc A'
        $rowsA[0].StepNo                   | Should -Be 1
        $rowsA[0].StepId                   | Should -Be '01'
        $rowsA[0].StepTitle                | Should -Be 'Setup'
        $rowsA[0].Status                   | Should -Be 'done'
        $rowsA[0].Started                  | Should -Be '2026-05-27 10:00:00'
        $rowsA[0].Finished                 | Should -Be '2026-05-27 10:05:00'
        $rowsA[0].Duration                 | Should -Be '00:05:00'

        $rowB = @($rows | Where-Object { $_.Workfolder -eq 'B' })[0]
        $rowB.ProcedureTitle | Should -Be 'Proc B'
        $rowB.Status         | Should -Be 'ng'
        $rowB.Duration       | Should -Be '-'
    }

    It 'includes a row with creating status step' {
        $root2 = Join-Path $TestDrive ("dash2-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-Item -ItemType Directory -Path $root2 | Out-Null
        $c = Join-Path $root2 'C'
        New-StepCreaterWorkfolder -Path $c -Title 'Proc C' | Out-Null
        $sessC = Open-StepCreaterWorkfolder -Path $c
        $sessC.Procedure.AddStep('Init') | Out-Null
        # Default status is creating — no explicit set needed
        Save-WorkSession -Session $sessC

        $rows = @(Get-DashboardRows -ParentFolder $root2)
        $rows.Count | Should -Be 1
        $rows[0].Status | Should -Be 'creating'
    }

    It 'throws if parent folder does not exist' {
        { Get-DashboardRows -ParentFolder 'C:\does\not\exist\nope' } | Should -Throw
    }

    It 'returns empty array when parent has no workfolders' {
        $empty = Join-Path $TestDrive ("empty-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-Item -ItemType Directory -Path $empty | Out-Null
        $rows = @(Get-DashboardRows -ParentFolder $empty)
        $rows.Count | Should -Be 0
    }
}

Describe 'Export-DashboardCsv' {
    It 'writes UTF-8 BOM CSV with all expected columns' {
        $rows = @(
            [pscustomobject]@{
                Workfolder='A'; WorkfolderPath='C:\A'; ProcedureTitle='手順書'; StepNo=1; StepId='01';
                StepTitle='テスト'; Status='done'; Started='2026-05-27 10:00:00';
                Finished='2026-05-27 10:05:00'; Duration='00:05:00'; Updated='2026-05-27 10:05:00'
            }
        )
        $tmp = Join-Path $TestDrive ("d-" + ([guid]::NewGuid().ToString('N').Substring(0,8)) + ".csv")
        Export-DashboardCsv -Rows $rows -Path $tmp

        Test-Path $tmp | Should -BeTrue
        $bytes = [System.IO.File]::ReadAllBytes($tmp)
        # UTF-8 BOM
        $bytes[0] | Should -Be 0xEF
        $bytes[1] | Should -Be 0xBB
        $bytes[2] | Should -Be 0xBF

        $text = [System.IO.File]::ReadAllText($tmp, [System.Text.UTF8Encoding]::new($true))
        $text | Should -Match 'Workfolder'
        $text | Should -Match 'ProcedureTitle'
        $text | Should -Match '手順書'
        $text | Should -Match 'テスト'
    }
}