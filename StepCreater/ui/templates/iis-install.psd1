@{
    Name           = 'IIS Install'
    Title          = 'IIS をインストール'
    BodyMarkdown   = 'Server Manager または PowerShell で IIS をインストールする。'
    Command        = 'Install-WindowsFeature -Name Web-Server -IncludeManagementTools'
    ExpectedResult = 'Success = True、ExitCode = 0 が表示される。'
    Note           = '再起動が必要な場合あり。'
}