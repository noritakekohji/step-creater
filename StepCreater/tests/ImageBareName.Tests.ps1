using module '..\StepCreater.psd1'

Describe 'Get-ImageBareName' {
    It 'returns bare name unchanged' { Get-ImageBareName 'foo.png' | Should -Be 'foo.png' }
    It 'strips images/ prefix'       { Get-ImageBareName 'images/foo.png' | Should -Be 'foo.png' }
    It 'strips images\ prefix'       { Get-ImageBareName 'images\foo.png' | Should -Be 'foo.png' }
    It 'strips nested dirs'          { Get-ImageBareName 'a/b/foo.png' | Should -Be 'foo.png' }
    It 'handles empty string'        { Get-ImageBareName '' | Should -Be '' }
}