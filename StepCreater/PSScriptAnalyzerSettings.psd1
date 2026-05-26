@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSUseShouldProcessForStateChangingFunctions',
        'PSAvoidUsingCmdletAliases',  # InvokeBuild DSL uses 'task' alias
        'PSAvoidUsingWriteHost',      # CLI/build output to console
        'PSUseSingularNouns'          # Get-StepTemplates returns a collection by design
    )
}
