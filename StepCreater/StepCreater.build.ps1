# Run with: Invoke-Build -File StepCreater/StepCreater.build.ps1 <Task>
# Tasks: Lint, Test, All (default)

task Lint {
    $results = Invoke-ScriptAnalyzer -Path "$PSScriptRoot" -Recurse `
        -Settings "$PSScriptRoot/PSScriptAnalyzerSettings.psd1"
    if ($results) {
        $results | Format-Table -AutoSize | Out-String | Write-Host
        throw "PSScriptAnalyzer reported $($results.Count) issue(s)."
    }
}

task Test {
    $config = New-PesterConfiguration
    $config.Run.Path = "$PSScriptRoot/tests"
    $config.Output.Verbosity = 'Detailed'
    $config.Run.Exit = $true
    Invoke-Pester -Configuration $config
}

task All Lint, Test

task . All
