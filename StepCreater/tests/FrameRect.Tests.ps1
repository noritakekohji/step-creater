using module '..\StepCreater.psd1'

Describe 'Add-FrameRect' {
    BeforeAll { Add-Type -AssemblyName System.Drawing }

    It 'returns same dimensions as source' {
        $src = New-Object System.Drawing.Bitmap 200, 150
        try {
            $out = Add-FrameRect -SourceBitmap $src -Rect (New-Object System.Drawing.Rectangle 10, 10, 50, 40)
            try {
                $out.Width  | Should -Be 200
                $out.Height | Should -Be 150
            } finally { $out.Dispose() }
        } finally { $src.Dispose() }
    }

    It 'draws red on the frame top edge and leaves the rectangle interior unfilled' {
        $src = New-Object System.Drawing.Bitmap 200, 150
        $g = [System.Drawing.Graphics]::FromImage($src)
        $g.FillRectangle([System.Drawing.Brushes]::White, 0, 0, 200, 150)
        $g.Dispose()
        try {
            $rect = New-Object System.Drawing.Rectangle 50, 50, 60, 40
            $out = Add-FrameRect -SourceBitmap $src -Rect $rect
            try {
                # Edge pixel ~ red
                $edge = $out.GetPixel(80, 50)
                $edge.R | Should -BeGreaterThan 150
                $edge.G | Should -BeLessThan 100
                $edge.B | Should -BeLessThan 100

                # Interior remains close to white
                $inside = $out.GetPixel(80, 70)
                $inside.R | Should -BeGreaterThan 200
                $inside.G | Should -BeGreaterThan 200
                $inside.B | Should -BeGreaterThan 200
            } finally { $out.Dispose() }
        } finally { $src.Dispose() }
    }
}
