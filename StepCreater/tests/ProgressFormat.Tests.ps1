using module '..\StepCreater.psd1'

Describe 'Get-ProgressLabel' {
    It 'counts done steps and total' {
        $doc = [ProcedureDoc]::new('X')
        $a = $doc.AddStep('A'); $a.Status = 'done'
        $b = $doc.AddStep('B'); $b.Status = 'done'
        $c = $doc.AddStep('C'); $c.Status = 'pending'
        Get-ProgressLabel -Procedure $doc | Should -Be '進捗: 2 / 3 (完了 2 / NG 0 / スキップ 0)'
    }

    It 'breaks down ng and skipped' {
        $doc = [ProcedureDoc]::new('X')
        $a = $doc.AddStep('A'); $a.Status = 'done'
        $b = $doc.AddStep('B'); $b.Status = 'ng'
        $c = $doc.AddStep('C'); $c.Status = 'skipped'
        $d = $doc.AddStep('D'); $d.Status = 'pending'
        Get-ProgressLabel -Procedure $doc | Should -Be '進捗: 3 / 4 (完了 1 / NG 1 / スキップ 1)'
    }

    It 'handles empty procedure' {
        $doc = [ProcedureDoc]::new('X')
        Get-ProgressLabel -Procedure $doc | Should -Be '進捗: 0 / 0 (完了 0 / NG 0 / スキップ 0)'
    }
}