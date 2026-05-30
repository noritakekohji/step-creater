using module '..\StepCreater.psd1'

Describe 'Add-FrameWithCallout' {
    BeforeAll {
        Add-Type -AssemblyName System.Drawing
    }

    It 'returns same dimensions as source' {
        $src = New-Object System.Drawing.Bitmap 200, 150
        try {
            $out = Add-FrameWithCallout -SourceBitmap $src -Rect (New-Object System.Drawing.Rectangle 10, 10, 50, 40) -Text 'hi'
            try {
                $out.Width  | Should -Be 200
                $out.Height | Should -Be 150
            } finally { $out.Dispose() }
        } finally { $src.Dispose() }
    }

    It 'draws red on the frame edge pixels' {
        $src = New-Object System.Drawing.Bitmap 200, 150
        $g = [System.Drawing.Graphics]::FromImage($src)
        $g.FillRectangle([System.Drawing.Brushes]::White, 0, 0, 200, 150)
        $g.Dispose()
        try {
            $rect = New-Object System.Drawing.Rectangle 50, 50, 60, 40
            $out = Add-FrameWithCallout -SourceBitmap $src -Rect $rect -Text ''
            try {
                # Sample a pixel at the frame stroke. GDI DrawRectangle draws
                # an outline at the rect edge -- center of the top edge should be red-ish.
                $p = $out.GetPixel(80, 50)
                $p.R | Should -BeGreaterThan 150
                $p.G | Should -BeLessThan  80
                $p.B | Should -BeLessThan  80

                # Center of the rect should remain mostly white (the inside isn't filled).
                $pi = $out.GetPixel(80, 70)
                $pi.R | Should -BeGreaterThan 200
            } finally { $out.Dispose() }
        } finally { $src.Dispose() }
    }

    It 'accepts empty text and skips callout' {
        $src = New-Object System.Drawing.Bitmap 200, 150
        try {
            { Add-FrameWithCallout -SourceBitmap $src -Rect (New-Object System.Drawing.Rectangle 10, 10, 50, 40) -Text '' } | Should -Not -Throw
        } finally { $src.Dispose() }
    }
}
