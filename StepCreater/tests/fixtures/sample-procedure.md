---
title: Sample Doc
created: 2026-05-27
updated: 2026-05-27T11:32:05
author: tester
---

# Sample Doc

## Step 1: IIS Install
<!-- step-id: 01 -->
- status: done
- started: 2026-05-27T10:30:01
- finished: 2026-05-27T10:31:20

### 手順
Install IIS via Server Manager or PowerShell.

### 実行コマンド
```powershell
Install-WindowsFeature -Name Web-Server
```

### 想定結果
Exit code 0 and "Success" printed.

### エビデンス
![](images/2026-05-27_103045_step01.png)
![](images/2026-05-27_103120_step01_win.png)

### 備考
Reboot may be required.

## Step 2: Configure Site
<!-- step-id: 02 -->
- status: pending

### 手順
Edit the default site bindings.

### 参考リンク
- https://example.com
