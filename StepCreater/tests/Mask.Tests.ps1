using module '..\StepCreater.psd1'

Describe 'Add-BlackoutRect' {
    BeforeAll {
        Add-Type -AssemblyName System.Drawing
    }

    It 'returns a bitmap with the rect area filled black' {
        $src = New-Object System.Drawing.Bitmap 100, 100
        $g = [System.Drawing.Graphics]::FromImage($src)
        $g.FillRectangle([System.Drawing.Brushes]::White, 0, 0, 100, 100)
        $g.Dispose()

        $rect = New-Object System.Drawing.Rectangle 10, 10, 30, 30
        $out = Add-BlackoutRect -SourceBitmap $src -Rect $rect

        $p = $out.GetPixel(20, 20)
        $p.R | Should -Be 0
        $p.G | Should -Be 0
        $p.B | Should -Be 0

        $q = $out.GetPixel(80, 80)
        $q.R | Should -Be 255
        $q.G | Should -Be 255
        $q.B | Should -Be 255
    }

    It 'returns same dimensions as input' {
        $src = New-Object System.Drawing.Bitmap 200, 150
        $out = Add-BlackoutRect -SourceBitmap $src -Rect (New-Object System.Drawing.Rectangle 0, 0, 10, 10)
        $out.Width  | Should -Be 200
        $out.Height | Should -Be 150
    }
}