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
        $sa1.ExpectedResult = 'OK'
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
        $rowsA[0].ExpectedResult           | Should -Be 'OK'
        $rowsA[0].Status                   | Should -Be 'done'
        $rowsA[0].Finished                 | Should -Be '2026-05-27'

        $rowB = @($rows | Where-Object { $_.Workfolder -eq 'B' })[0]
        $rowB.ProcedureTitle | Should -Be 'Proc B'
        $rowB.Status         | Should -Be 'ng'
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
                StepTitle='テスト'; Status='done'; Executor='ExecUser'; Verifier='VerUser';
                Started='2026-05-27'; Finished='2026-05-27'; Duration='00:05:00'; Updated='2026-05-27 10:05:00'
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

Describe 'Get-DashboardSummary' {
    It 'counts statuses per procedure and total' {
        $rows = @(
            [pscustomobject]@{Workfolder='A'; WorkfolderPath='C:\A'; ProcedureTitle='Proc A'; Status='done'; Executor='X'; Verifier='Y'; StepNo=1; StepId='01'; StepTitle='a'; Started=''; Finished=''; Duration=''; Updated=''}
            [pscustomobject]@{Workfolder='A'; WorkfolderPath='C:\A'; ProcedureTitle='Proc A'; Status='creating'; Executor='X'; Verifier='Y'; StepNo=2; StepId='02'; StepTitle='b'; Started=''; Finished=''; Duration=''; Updated=''}
            [pscustomobject]@{Workfolder='B'; WorkfolderPath='C:\B'; ProcedureTitle='Proc B'; Status='ng'; Executor='Z'; Verifier='Y'; StepNo=1; StepId='01'; StepTitle='c'; Started=''; Finished=''; Duration=''; Updated=''}
        )
        $sum = Get-DashboardSummary -Rows $rows
        $sum.PerProcedure.Count          | Should -Be 2
        $procA = $sum.PerProcedure | Where-Object { $_.ProcedureTitle -eq 'Proc A' }
        $procA.Total      | Should -Be 2
        $procA.done       | Should -Be 1
        $procA.creating   | Should -Be 1
        $sum.Total.done | Should -Be 1
        $sum.Total.ng   | Should -Be 1
    }

    It 'returns empty PerProcedure on empty rows' {
        $sum = Get-DashboardSummary -Rows @()
        $sum.PerProcedure.Count | Should -Be 0
    }
}

Describe 'Update-DashboardPieChart' {
    BeforeAll { Add-Type -AssemblyName PresentationFramework }

    It 'renders one Path per non-zero status' {
        $canvas = New-Object System.Windows.Controls.Canvas
        $counts = [pscustomobject]@{
            creating=2; reviewing=0; created=0; executing=1; verifying=0; ng=1; aborted=0; done=0
        }
        Update-DashboardPieChart -Canvas $canvas -Counts $counts
        # 3 paths for the 3 non-zero statuses
        $paths = @($canvas.Children | Where-Object { $_.GetType().Name -eq 'Path' })
        $paths.Count | Should -Be 3
    }

    It 'shows a "no data" text when all counts are zero' {
        $canvas = New-Object System.Windows.Controls.Canvas
        $counts = [pscustomobject]@{
            creating=0; reviewing=0; created=0; executing=0; verifying=0; ng=0; aborted=0; done=0
        }
        Update-DashboardPieChart -Canvas $canvas -Counts $counts
        $texts = @($canvas.Children | Where-Object { $_.GetType().Name -eq 'TextBlock' })
        $texts.Count | Should -Be 1
    }

    It 'populates LegendPanel rows when supplied' {
        $canvas = New-Object System.Windows.Controls.Canvas
        $legend = New-Object System.Windows.Controls.StackPanel
        $counts = [pscustomobject]@{
            creating=2; reviewing=0; created=0; executing=1; verifying=0; ng=1; aborted=0; done=0
        }
        Update-DashboardPieChart -Canvas $canvas -Counts $counts -LegendPanel $legend
        # 3 non-zero statuses → 3 legend rows
        $legend.Children.Count | Should -Be 3
    }
}

Describe 'Get-DashboardRows new columns' {
    It 'emits Executor and Verifier from effective role' {
        $tmp = Join-Path $TestDrive ("dash2-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-Item -ItemType Directory -Path $tmp | Out-Null
        $wf = Join-Path $tmp 'W'
        New-StepCreaterWorkfolder -Path $wf -Title 'Proc' | Out-Null
        $sess = Open-StepCreaterWorkfolder -Path $wf
        $sess.Procedure.DefaultExecutor = 'DefExec'
        $sess.Procedure.DefaultVerifier = 'DefVer'
        $s = $sess.Procedure.AddStep('A'); $s.Verifier = 'StepVer'   # step override
        Save-WorkSession -Session $sess

        $rows = @(Get-DashboardRows -ParentFolder $tmp)
        $rows.Count | Should -Be 1
        $rows[0].Executor | Should -Be 'DefExec'    # fallback from default
        $rows[0].Verifier | Should -Be 'StepVer'    # step override
    }

    It 'emits dates only (yyyy-MM-dd) for Finished; no Started or Duration columns' {
        $tmp = Join-Path $TestDrive ("dash3-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-Item -ItemType Directory -Path $tmp | Out-Null
        $wf = Join-Path $tmp 'W'
        New-StepCreaterWorkfolder -Path $wf -Title 'Proc' | Out-Null
        $sess = Open-StepCreaterWorkfolder -Path $wf
        $s = $sess.Procedure.AddStep('A')
        $s.Started  = [datetime]'2026-05-27T10:00:00'
        $s.Finished = [datetime]'2026-05-27T11:30:00'
        $s.Status = 'done'
        Save-WorkSession -Session $sess

        $rows = @(Get-DashboardRows -ParentFolder $tmp)
        $rows[0].Finished | Should -Be '2026-05-27'
        $rows[0].PSObject.Properties['Started']  | Should -BeNullOrEmpty
        $rows[0].PSObject.Properties['Duration'] | Should -BeNullOrEmpty
    }

    It 'emits ExpectedResult column' {
        $tmp = Join-Path $TestDrive ("dash-er-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-Item -ItemType Directory -Path $tmp | Out-Null
        $wf = Join-Path $tmp 'W'
        New-StepCreaterWorkfolder -Path $wf -Title 'Proc' | Out-Null
        $sess = Open-StepCreaterWorkfolder -Path $wf
        $s = $sess.Procedure.AddStep('Build'); $s.ExpectedResult = 'Compile OK'
        Save-WorkSession -Session $sess
        $rows = @(Get-DashboardRows -ParentFolder $tmp)
        $rows[0].ExpectedResult | Should -Be 'Compile OK'
    }
}