@{
    Name           = 'Windows Update'
    Title          = 'Windows Update を適用'
    BodyMarkdown   = '最新の Windows Update を適用する。完了後に再起動する。'
    Command        = 'Get-WindowsUpdate -Install -AcceptAll -AutoReboot'
    ExpectedResult = '全ての更新が「Installed」状態になる。'
    Note           = 'PSWindowsUpdate モジュールが必要。'
}