Describe 'MainWindow.xaml' {
    BeforeAll {
        Add-Type -AssemblyName PresentationFramework
        Add-Type -AssemblyName PresentationCore
        Add-Type -AssemblyName WindowsBase
        $script:xamlPath = Join-Path $PSScriptRoot '..\ui\MainWindow.xaml'
    }

    It 'file exists' {
        Test-Path $script:xamlPath | Should -BeTrue
    }

    It 'parses without error and produces a Window' {
        $xml = [xml](Get-Content -LiteralPath $script:xamlPath -Raw)
        $reader = [System.Xml.XmlNodeReader]::new($xml)
        $window = [Windows.Markup.XamlReader]::Load($reader)
        $window | Should -Not -BeNullOrEmpty
        $window.GetType().Name | Should -Be 'Window'
    }

    It 'has all expected named controls' {
        $xml = [xml](Get-Content -LiteralPath $script:xamlPath -Raw)
        $reader = [System.Xml.XmlNodeReader]::new($xml)
        $window = [Windows.Markup.XamlReader]::Load($reader)

        foreach ($name in @(
            'MenuNew','MenuOpen','MenuSave','MenuExit','MenuTemplates',
            'StatusText','DirtyText',
            'TabEdit','TabExecute','TabCapture',
            'WorkfolderPath','BtnSave',
            'StepList','BtnAdd','BtnDelete','BtnUp','BtnDown',
            'TxtTitle','CboStatus','TxtBody','TxtCommand','TxtExpected','TxtNote',
            'UnassignedTray',
            'EditPanel','ExecutePanel',
            'ProgressLabel','ExecChecklist',
            'ExecStepTitle','ExecBody','ExecCommand','BtnCopyCommand','ExecExpected',
            'ExecEvidenceTray','BtnComplete','BtnNg','BtnSkip'
        )) {
            $window.FindName($name) | Should -Not -BeNullOrEmpty -Because "$name should exist in XAML"
        }
    }
}