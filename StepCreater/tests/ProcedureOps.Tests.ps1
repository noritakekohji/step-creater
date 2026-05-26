using module '..\StepCreater.psd1'

Describe 'Procedure operations' {
    BeforeEach {
        $script:doc = [ProcedureDoc]::new('Doc')
        $script:a = $script:doc.AddStep('A')
        $script:b = $script:doc.AddStep('B')
        $script:c = $script:doc.AddStep('C')
    }

    It 'Add-ProcedureStepAt inserts at given index and renumbers IDs' {
        $new = Add-ProcedureStepAt -Procedure $script:doc -Index 1 -Title 'New'
        $script:doc.Steps.Count | Should -Be 4
        $script:doc.Steps[1].Title | Should -Be 'New'
        $script:doc.Steps[0].Id | Should -Be '01'
        $script:doc.Steps[1].Id | Should -Be '02'
        $script:doc.Steps[2].Id | Should -Be '03'
        $script:doc.Steps[3].Id | Should -Be '04'
        $new.Id | Should -Be '02'
    }

    It 'Remove-ProcedureStep removes at index and renumbers' {
        Remove-ProcedureStep -Procedure $script:doc -Index 1
        $script:doc.Steps.Count | Should -Be 2
        $script:doc.Steps[0].Title | Should -Be 'A'
        $script:doc.Steps[1].Title | Should -Be 'C'
        $script:doc.Steps[1].Id    | Should -Be '02'
    }

    It 'Move-ProcedureStep moves up' {
        Move-ProcedureStep -Procedure $script:doc -Index 2 -Direction Up
        $script:doc.Steps[0].Title | Should -Be 'A'
        $script:doc.Steps[1].Title | Should -Be 'C'
        $script:doc.Steps[2].Title | Should -Be 'B'
        $script:doc.Steps[1].Id    | Should -Be '02'
        $script:doc.Steps[2].Id    | Should -Be '03'
    }

    It 'Move-ProcedureStep at edge is no-op' {
        Move-ProcedureStep -Procedure $script:doc -Index 0 -Direction Up
        $script:doc.Steps[0].Title | Should -Be 'A'
    }
}

Describe 'Get-ProcedureHash' {
    It 'same content yields same hash' {
        $doc1 = [ProcedureDoc]::new('X'); $doc1.AddStep('S1') | Out-Null
        $doc2 = [ProcedureDoc]::new('X'); $doc2.AddStep('S1') | Out-Null
        (Get-ProcedureHash -Procedure $doc1) | Should -Be (Get-ProcedureHash -Procedure $doc2)
    }

    It 'modified content yields different hash' {
        $doc = [ProcedureDoc]::new('X'); $doc.AddStep('S1') | Out-Null
        $h1 = Get-ProcedureHash -Procedure $doc
        $doc.AddStep('S2') | Out-Null
        $h2 = Get-ProcedureHash -Procedure $doc
        $h1 | Should -Not -Be $h2
    }
}
