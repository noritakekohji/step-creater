@{
    RootModule        = 'StepCreater.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'a3b2c1d4-e5f6-4789-90ab-cdef12345678'
    Author            = 'noritake.kohji'
    Description       = 'Procedure document & evidence capture tool for system construction work.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-ImageBareName',
        'Read-Procedure',
        'Write-Procedure',
        'New-StepCreaterWorkfolder',
        'Open-StepCreaterWorkfolder',
        'Get-StepCreaterConfig',
        'Set-StepCreaterConfig',
        'Get-StepTemplates',
        'Get-UserTemplateFolder',
        'Add-ProcedureStepAt',
        'Remove-ProcedureStep',
        'Move-ProcedureStep',
        'Update-ProcedureStepIds',
        'Get-ProcedureHash',
        'Show-StepCreaterMainWindow',
        'Update-StepListUI',
        'Update-DirtyIndicator',
        'Save-WorkSession',
        'Initialize-StepCreaterWin32',
        'Get-CaptureFileName',
        'Save-BitmapPng',
        'Read-BitmapNoLock',
        'Invoke-FullScreenCapture',
        'Invoke-ActiveWindowCapture',
        'ConvertTo-HotkeySpec',
        'Register-StepCreaterHotkeys',
        'Unregister-StepCreaterHotkeys',
        'Add-CaptureAnnotation',
        'Invoke-RectSelectionCapture',
        'Save-StepCreaterCapture',
        'Update-UnassignedTrayUI',
        'Update-StepImageTray',
        'Get-ProgressLabel',
        'Update-ExecChecklistUI',
        'Set-StepStatus',
        'Add-BlackoutRect',
        'Add-FrameRect',
        'Add-CommentRect',
        'Show-MaskEditor',
        'Get-StepDuration',
        'Get-EffectiveRole',
        'ConvertTo-ProcedureHtml',
        'Show-ProcedureInfoDialog',
        'Show-SettingsDialog',
        'Get-DashboardRows',
        'Get-DashboardSummary',
        'Update-DashboardPieChart',
        'Export-DashboardCsv',
        'Show-DashboardWindow',
        'ConvertTo-SanitizedFolderName',
        'Save-SampleCsvTemplate',
        'Import-ProceduresFromCsv',
        'Export-ProceduresToCsv'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
