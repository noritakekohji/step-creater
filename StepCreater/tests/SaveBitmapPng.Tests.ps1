using module '..\StepCreater.psd1'

Describe 'Save-BitmapPng' {
    BeforeAll {
        Add-Type -AssemblyName System.Drawing
    }

    It 'saves a PNG to a regular ASCII path' {
        $tmp = Join-Path $TestDrive ("ascii-" + ([guid]::NewGuid().ToString('N').Substring(0,8)) + ".png")
        $bmp = New-Object System.Drawing.Bitmap 40, 30
        try {
            Save-BitmapPng -Bitmap $bmp -Path $tmp
            Test-Path -LiteralPath $tmp | Should -BeTrue
            (Get-Item $tmp).Length | Should -BeGreaterThan 0
        } finally { $bmp.Dispose() }
    }

    It 'saves a PNG to a path containing Japanese characters (GDI+ regression)' {
        $jpDir = Join-Path $TestDrive ("テスト_" + ([guid]::NewGuid().ToString('N').Substring(0,8)))
        New-Item -ItemType Directory -Path $jpDir | Out-Null
        $tmp = Join-Path $jpDir '手順書画像.png'
        $bmp = New-Object System.Drawing.Bitmap 40, 30
        try {
            { Save-BitmapPng -Bitmap $bmp -Path $tmp } | Should -Not -Throw
            Test-Path -LiteralPath $tmp | Should -BeTrue

            $bytes = [System.IO.File]::ReadAllBytes($tmp)
            $ms = New-Object System.IO.MemoryStream (,$bytes)
            try {
                $loaded = [System.Drawing.Image]::FromStream($ms)
                $loaded.Width  | Should -Be 40
                $loaded.Height | Should -Be 30
                $loaded.Dispose()
            } finally { $ms.Dispose() }
        } finally { $bmp.Dispose() }
    }

    It 'creates the parent directory if missing' {
        $deepPath = Join-Path $TestDrive ("dir1\dir2\out_" + ([guid]::NewGuid().ToString('N').Substring(0,8)) + ".png")
        $bmp = New-Object System.Drawing.Bitmap 10, 10
        try {
            Save-BitmapPng -Bitmap $bmp -Path $deepPath
            Test-Path -LiteralPath $deepPath | Should -BeTrue
        } finally { $bmp.Dispose() }
    }
}