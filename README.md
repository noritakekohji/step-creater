# StepCreater

社内システム構築作業向けの **手順書作成・実施・エビデンス取得ツール**。PowerShell 5.1 + WPF。追加ソフトウェアのインストール不要（社内PC前提）。

## 機能

3モード構成：

- **手順書作成モード** — Step単位で手順書を作成・編集
- **作業実施モード** — 手順書に沿って作業し、エビデンスを自動紐付け
- **画像取得モード** — グローバルホットキーでバックグラウンド画面キャプチャ

出力は Markdown と HTML の2形式。Markdown は入力としても使える（往復編集可能）。

## ドキュメント

- 設計書: [docs/superpowers/specs/2026-05-27-stepcreater-design.md](docs/superpowers/specs/2026-05-27-stepcreater-design.md)
- 実装計画:
  - [Phase 1: 基盤（データモデル、Markdown I/O、CLI）](docs/superpowers/plans/2026-05-27-stepcreater-phase1-foundation.md)
  - [Phase 2: 手順書作成モード GUI](docs/superpowers/plans/2026-05-27-stepcreater-phase2-edit-gui.md)

## 現在のステータス

| Phase | 内容 | 状態 |
|---|---|---|
| 1 | 基盤 | ✅ 完了 |
| 2 | 手順書作成モード (WPF GUI) | 🚧 進行中 |
| 3 | キャプチャ基盤 | 未着手 |
| 4 | 作業実施モード | 未着手 |
| 5 | HTML出力 / 仕上げ | 未着手 |

## 開発

### 要件
- Windows + PowerShell 5.1
- Pester v5, PSScriptAnalyzer, InvokeBuild（PSGalleryから取得）

### セットアップ
```powershell
Install-Module -Name Pester -RequiredVersion 5.5.0 -Force -Scope CurrentUser -SkipPublisherCheck
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
Install-Module -Name InvokeBuild -Force -Scope CurrentUser
```

### テスト & lint
```powershell
Invoke-Build -File StepCreater/StepCreater.build.ps1 All
```

### 起動（Phase 1 CLI）
```powershell
# 新規ワークフォルダ作成
.\StepCreater\StepCreater.ps1 -Init -WorkFolder C:\temp\proc1 -Title "サーバ構築"

# 既存ワークフォルダを開く
.\StepCreater\StepCreater.ps1 -WorkFolder C:\temp\proc1
```

## インストール / アンインストール

エンドユーザー向けの per-user インストーラ（管理者権限不要）：

```
install.bat       -- %LOCALAPPDATA%\Programs\StepCreater にコピー＋スタートメニュー登録
uninstall.bat     -- 上記をアンインストール（config は任意削除）
```

ワークフォルダ（手順書本体）はインストール／アンインストールの影響を受けません。
