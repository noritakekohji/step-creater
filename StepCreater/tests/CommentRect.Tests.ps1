using module '..\StepCreater.psd1'

Describe 'Add-CommentRect' {
    BeforeAll { Add-Type -AssemblyName System.Drawing }

    It 'returns same dimensions as source' {
        $src = New-Object System.Drawing.Bitmap 200, 150
        try {
            $out = Add-CommentRect -SourceBitmap $src -Rect (New-Object System.Drawing.Rectangle 10, 10, 100, 60) -Text 'hi'
            try {
                $out.Width  | Should -Be 200
                $out.Height | Should -Be 150
            } finally { $out.Dispose() }
        } finally { $src.Dispose() }
    }

    It 'fills the rectangle area with light yellow background' {
        $src = New-Object System.Drawing.Bitmap 200, 150
        $g = [System.Drawing.Graphics]::FromImage($src)
        $g.FillRectangle([System.Drawing.Brushes]::Blue, 0, 0, 200, 150)
        $g.Dispose()
        try {
            $rect = New-Object System.Drawing.Rectangle 50, 50, 100, 60
            $out = Add-CommentRect -SourceBitmap $src -Rect $rect -Text ''
            try {
                # Pixel well inside the comment rect (avoid the border) should be light/yellow-ish
                # definitely not the original blue.
                $p = $out.GetPixel(100, 80)
                $p.B | Should -BeLessThan 240    # was 255 blue — alpha blend reduces it
                ($p.R + $p.G) | Should -BeGreaterThan ($p.B + 20)   # warmer than blue
            } finally { $out.Dispose() }
        } finally { $src.Dispose() }
    }

    It 'accepts empty text and just draws the box' {
        $src = New-Object System.Drawing.Bitmap 200, 150
        try {
            { Add-CommentRect -SourceBitmap $src -Rect (New-Object System.Drawing.Rectangle 10, 10, 50, 40) -Text '' } | Should -Not -Throw
        } finally { $src.Dispose() }
    }
}
