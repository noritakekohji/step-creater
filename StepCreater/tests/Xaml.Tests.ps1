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
            'MenuNew','MenuOpen','MenuSave','MenuExportHtmlCreate','MenuExportHtmlExec','MenuCsvImport','MenuCsvSampleSave','MenuExit',
            'MenuTemplates','MenuSettings','MenuProcInfo','MenuDashboard',
            'StatusText','DirtyText',
            'TabEdit','TabExecute','TabCapture',
            'WorkfolderPath','BtnSave',
            'StepList','BtnAdd','BtnDelete','BtnUp','BtnDown',
            'TxtTitle','CboStatus','TxtBody','TxtCommand','TxtExpected','TxtNote',
            'TxtAuthor','TxtReviewer','TxtExecutor','TxtVerifier',
            'UnassignedTray',
            'EditPanel','ExecutePanel',
            'ProgressLabel','ExecChecklist',
            'ExecStepTitle','ExecBody','ExecCommand','BtnCopyCommand','ExecExpected',
            'ExecEvidenceTray','BtnComplete','BtnNg','BtnSkip',
            'EditEvidenceTray','BtnAddEvidence',
            'BtnAddSelected','UnassignedLabel','ExecProcImageTray'
        )) {
            $window.FindName($name) | Should -Not -BeNullOrEmpty -Because "$name should exist in XAML"
        }
    }
}
Describe 'DashboardWindow.xaml' {
    BeforeAll {
        Add-Type -AssemblyName PresentationFramework
        Add-Type -AssemblyName PresentationCore
        Add-Type -AssemblyName WindowsBase
        $script:dwPath = Join-Path $PSScriptRoot '..\ui\DashboardWindow.xaml'
    }

    It 'file exists' {
        Test-Path $script:dwPath | Should -BeTrue
    }

    It 'parses without error and produces a Window' {
        $xml = [xml](Get-Content -LiteralPath $script:dwPath -Raw)
        $reader = [System.Xml.XmlNodeReader]::new($xml)
        $win = [Windows.Markup.XamlReader]::Load($reader)
        $win | Should -Not -BeNullOrEmpty
        $win.GetType().Name | Should -Be 'Window'
    }

    It 'has all expected named controls' {
        $xml = [xml](Get-Content -LiteralPath $script:dwPath -Raw)
        $reader = [System.Xml.XmlNodeReader]::new($xml)
        $win = [Windows.Markup.XamlReader]::Load($reader)
        foreach ($name in @('TxtParentPath','BtnPickParent','BtnRescan','BtnExportCsv','BtnExportProceduresCsv','DashGrid','DashStatus','PieCanvas','SummaryGrid','LegendPanel')) {
            $win.FindName($name) | Should -Not -BeNullOrEmpty -Because "$name should exist in DashboardWindow.xaml"
        }
    }
}

Describe 'SettingsDialog.xaml' {
    BeforeAll {
        Add-Type -AssemblyName PresentationFramework
        $script:sxPath = Join-Path $PSScriptRoot '..\ui\SettingsDialog.xaml'
    }

    It 'file exists' { Test-Path $script:sxPath | Should -BeTrue }

    It 'parses without error' {
        $xml = [xml](Get-Content -LiteralPath $script:sxPath -Raw)
        $reader = [System.Xml.XmlNodeReader]::new($xml)
        $win = [Windows.Markup.XamlReader]::Load($reader)
        $win.GetType().Name | Should -Be 'Window'
        foreach ($n in @('TxtHkFull','TxtHkWindow','TxtHkRect','BtnOk','BtnCancel')) {
            $win.FindName($n) | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'ProcedureInfoDialog.xaml' {
    BeforeAll {
        Add-Type -AssemblyName PresentationFramework
        $script:pidPath = Join-Path $PSScriptRoot '..\ui\ProcedureInfoDialog.xaml'
    }

    It 'file exists' { Test-Path $script:pidPath | Should -BeTrue }

    It 'parses without error' {
        $xml = [xml](Get-Content -LiteralPath $script:pidPath -Raw)
        $reader = [System.Xml.XmlNodeReader]::new($xml)
        $win = [Windows.Markup.XamlReader]::Load($reader)
        $win.GetType().Name | Should -Be 'Window'
        foreach ($n in @('TxtProcTitle','TxtDefAuthor','TxtDefReviewer','TxtDefExecutor','TxtDefVerifier','BtnOk','BtnCancel')) {
            $win.FindName($n) | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'MaskEditor.xaml' {
    BeforeAll {
        Add-Type -AssemblyName PresentationFramework
        Add-Type -AssemblyName PresentationCore
        Add-Type -AssemblyName WindowsBase
        $script:mePath = Join-Path $PSScriptRoot '..\ui\MaskEditor.xaml'
    }

    It 'file exists' { Test-Path $script:mePath | Should -BeTrue }

    It 'parses without error and produces a Window' {
        $xml = [xml](Get-Content -LiteralPath $script:mePath -Raw)
        $reader = [System.Xml.XmlNodeReader]::new($xml)
        $win = [Windows.Markup.XamlReader]::Load($reader)
        $win | Should -Not -BeNullOrEmpty
        $win.GetType().Name | Should -Be 'Window'
    }

    It 'has all expected named controls' {
        $xml = [xml](Get-Content -LiteralPath $script:mePath -Raw)
        $reader = [System.Xml.XmlNodeReader]::new($xml)
        $win = [Windows.Markup.XamlReader]::Load($reader)
        foreach ($n in @('ImgCanvas','OverlayCanvas','DragRect',
                         'BtnBlackout','BtnFrame','BtnComment','BtnUndo','BtnSave','BtnCancel',
                         'ImageHost','ImageScroller')) {
            $win.FindName($n) | Should -Not -BeNullOrEmpty -Because "$n should exist in MaskEditor.xaml"
        }
    }
}
