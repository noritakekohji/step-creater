using module '..\StepCreater.psd1'

Describe 'Add-CaptureAnnotation' {
    BeforeAll {
        Add-Type -AssemblyName System.Drawing
    }

    It 'returns a bitmap of same dimensions as input' {
        $src = New-Object System.Drawing.Bitmap 800, 600
        $out = Add-CaptureAnnotation -SourceBitmap $src -MousePosition (New-Object System.Drawing.Point 100, 100) `
            -Caption 'Test | 10:30:45' -CaptionHeight 0
        $out.Width  | Should -Be 800
        $out.Height | Should -Be 600
    }

    It 'returns a taller bitmap when CaptionHeight > 0' {
        $src = New-Object System.Drawing.Bitmap 800, 600
        $out = Add-CaptureAnnotation -SourceBitmap $src -MousePosition (New-Object System.Drawing.Point 100, 100) `
            -Caption 'Test' -CaptionHeight 30
        $out.Height | Should -Be 630
    }

    It 'returns original height when MousePosition is outside bounds and no caption' {
        $src = New-Object System.Drawing.Bitmap 800, 600
        $out = Add-CaptureAnnotation -SourceBitmap $src -MousePosition (New-Object System.Drawing.Point -50, -50) `
            -Caption '' -CaptionHeight 0
        $out.Height | Should -Be 600
    }
}
