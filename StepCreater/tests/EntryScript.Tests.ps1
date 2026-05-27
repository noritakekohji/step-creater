# Integration tests that run StepCreater.ps1 in a child process.
# We exercise paths that don't open the WPF dialog (i.e., -Init).

Describe 'StepCreater.ps1 entry script' {
    BeforeAll {
        $script:scriptPath = Join-Path $PSScriptRoot '..\StepCreater.ps1'
        $script:scriptPath | Should -Exist

        function script:Invoke-StepCreaterScript {
            param([string[]]$ScriptArgs, [int]$TimeoutMs = 30000)
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = 'powershell.exe'
            $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script:scriptPath`" $($ScriptArgs -join ' ')"
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            $psi.CreateNoWindow = $true
            $proc = [System.Diagnostics.Process]::Start($psi)
            if (-not $proc.WaitForExit($TimeoutMs)) {
                $proc.Kill()
                throw "Process timed out after ${TimeoutMs}ms"
            }
            return [pscustomobject]@{
                ExitCode = $proc.ExitCode
                StdOut   = $proc.StandardOutput.ReadToEnd()
                StdErr   = $proc.StandardError.ReadToEnd()
            }
        }
    }

    BeforeEach {
        $script:tmpFolder = Join-Path $TestDrive ("entry-" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
    }

    It '-Init creates the workfolder layout with given title' {
        $result = Invoke-StepCreaterScript -ScriptArgs @('-Init', '-WorkFolder', "`"$script:tmpFolder`"", '-Title', '"Entry Test"')
        $result.ExitCode | Should -Be 0
        $result.StdOut   | Should -Match 'Created workfolder'

        Test-Path (Join-Path $script:tmpFolder 'procedure.md')                | Should -BeTrue
        Test-Path (Join-Path $script:tmpFolder 'images')                      | Should -BeTrue
        Test-Path (Join-Path $script:tmpFolder 'attachments')                 | Should -BeTrue
        Test-Path (Join-Path $script:tmpFolder '.stepcreater\state.json')     | Should -BeTrue

        $md = Get-Content (Join-Path $script:tmpFolder 'procedure.md') -Raw
        $md | Should -Match 'title: Entry Test'
    }

    It '-Init without -Title fails' {
        $result = Invoke-StepCreaterScript -ScriptArgs @('-Init', '-WorkFolder', "`"$script:tmpFolder`"")
        $result.ExitCode | Should -Not -Be 0
        $result.StdErr   | Should -Match '-Title'
    }

    It '-Init without -WorkFolder fails' {
        $result = Invoke-StepCreaterScript -ScriptArgs @('-Init', '-Title', '"X"')
        $result.ExitCode | Should -Not -Be 0
        $result.StdErr   | Should -Match '-WorkFolder'
    }

    It 'imported module path is valid (smoke-import only)' {
        # Run a tiny inline child that imports the module and exits 0 if ok.
        $psd1 = Join-Path $PSScriptRoot '..\StepCreater.psd1'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Import-Module '$psd1' -Force; if (Get-Command Show-StepCreaterMainWindow -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
        $LASTEXITCODE | Should -Be 0
    }
}
