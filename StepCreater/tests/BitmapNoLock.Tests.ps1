using module '..\StepCreater.psd1'

Describe 'Read-BitmapNoLock and Save-BitmapPng round-trip without file lock' {
    BeforeAll {
        Add-Type -AssemblyName System.Drawing
    }

    It 'does NOT hold the source file open (can be written to immediately)' {
        $tmp = Join-Path $TestDrive ("nolock-" + ([guid]::NewGuid().ToString('N').Substring(0,8)) + ".png")
        $bmp = New-Object System.Drawing.Bitmap 40, 30
        try {
            Save-BitmapPng -Bitmap $bmp -Path $tmp
        } finally { $bmp.Dispose() }

        $loaded = Read-BitmapNoLock -Path $tmp
        try {
            # The fact that Save-BitmapPng to the same path succeeds is the contract
            { Save-BitmapPng -Bitmap $loaded -Path $tmp } | Should -Not -Throw
        } finally { $loaded.Dispose() }
    }

    It 'mask-editor scenario: load -> modify -> save to same path succeeds (regression for file-in-use crash)' {
        $tmp = Join-Path $TestDrive ("masklock-" + ([guid]::NewGuid().ToString('N').Substring(0,8)) + ".png")
        $bmp = New-Object System.Drawing.Bitmap 60, 60
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.FillRectangle([System.Drawing.Brushes]::White, 0, 0, 60, 60)
        $g.Dispose()
        try { Save-BitmapPng -Bitmap $bmp -Path $tmp } finally { $bmp.Dispose() }

        $current = Read-BitmapNoLock -Path $tmp
        try {
            $modified = Add-BlackoutRect -SourceBitmap $current -Rect (New-Object System.Drawing.Rectangle 5, 5, 20, 20)
            try {
                { Save-BitmapPng -Bitmap $modified -Path $tmp } | Should -Not -Throw
            } finally { $modified.Dispose() }
        } finally { $current.Dispose() }

        $reloaded = Read-BitmapNoLock -Path $tmp
        try {
            $pix = $reloaded.GetPixel(10, 10)
            $pix.R | Should -Be 0
        } finally { $reloaded.Dispose() }
    }
}
