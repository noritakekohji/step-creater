using module '..\StepCreater.psd1'

Describe 'ScreenshotRef' {
    It 'constructs with required fields' {
        $s = [ScreenshotRef]::new('2026-05-27_103045_step01.png', [datetime]'2026-05-27T10:30:45', 'full')
        $s.FileName | Should -Be '2026-05-27_103045_step01.png'
        $s.Kind     | Should -Be 'full'
        $s.MaskedFromOriginal | Should -BeFalse
    }
}

Describe 'Step' {
    It 'defaults to creating status with empty fields' {
        $step = [Step]::new('01', 'IIS Install')
        $step.Id              | Should -Be '01'
        $step.Title           | Should -Be 'IIS Install'
        $step.Status          | Should -Be 'creating'
        $step.BodyMarkdown    | Should -Be ''
        $step.Command         | Should -Be ''
        $step.ExpectedResult  | Should -Be ''
        $step.Note            | Should -Be ''
        $step.Evidence.Count  | Should -Be 0
        $step.ProcedureImages.Count | Should -Be 0
        $step.Started         | Should -BeNullOrEmpty
        $step.Finished        | Should -BeNullOrEmpty
        $step.Author          | Should -Be ''
        $step.Reviewer        | Should -Be ''
        $step.Executor        | Should -Be ''
        $step.Verifier        | Should -Be ''
        $step.StatusHistory.Count | Should -Be 0
    }
}

Describe 'ProcedureDoc' {
    It 'has empty Steps list by default' {
        $doc = [ProcedureDoc]::new('Server Build')
        $doc.Title            | Should -Be 'Server Build'
        $doc.Steps.Count      | Should -Be 0
        $doc.DefaultAuthor    | Should -Be ''
        $doc.DefaultReviewer  | Should -Be ''
        $doc.DefaultExecutor  | Should -Be ''
        $doc.DefaultVerifier  | Should -Be ''
    }

    It 'AddStep assigns sequential zero-padded IDs' {
        $doc = [ProcedureDoc]::new('Doc')
        $a = $doc.AddStep('First')
        $b = $doc.AddStep('Second')
        $a.Id | Should -Be '01'
        $b.Id | Should -Be '02'
        $doc.Steps.Count | Should -Be 2
    }
}
