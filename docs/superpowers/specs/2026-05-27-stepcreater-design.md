---
title: StepCreater 設計書
date: 2026-05-27
status: draft
---

# StepCreater 設計書

社内PCで動作する、システム構築作業向けの手順書作成・実施・エビデンス取得ツール。
PowerShell 5 + WPF の単一スクリプト構成。追加ソフトウェアのインストール不要。

## 1. 目的とスコープ

- 構築作業の **手順書** を作る／読み込む／編集する
- 作業実施時に **画面キャプチャ** をショートカットで取得しエビデンス化する
- 手順書を **Markdown と HTML** の2形式で出力する。Markdownは入力としても使う（往復編集可能）

非スコープ：複数ユーザー同時編集、クラウド連携、自動コマンド実行。

## 2. 全体アーキテクチャ

### 配布形態
- メインスクリプト：`StepCreater.ps1`
- 同梱：`StepCreater.xaml`（WPF画面定義）、`StepCreater.psm1`（テスト対象のロジック関数群）
- 共通設定：`%APPDATA%\StepCreater\config.json`（ホットキー割当、最近使ったワークフォルダ等）

### プロセスモデル
- 単一プロセス、単一スクリプト起動
- メインスレッドは WPF UI（STA）
- バックグラウンドに **隠しメッセージウィンドウ** を1つ作り、`RegisterHotKey` (Win32) で登録したグローバルホットキーを `WM_HOTKEY` (0x0312) で受信
- ホットキー受信時は `Dispatcher.BeginInvoke` でUIスレッドへキャプチャ実行を委譲
- 終了時は `UnregisterHotKey` を finally で必ず呼ぶ

### 起動フロー
```
StepCreater.ps1 [-WorkFolder <path>] [-Mode capture|edit|execute]
  ├─ 引数なし          → ランチャーダイアログでフォルダ選択＋モード選択
  ├─ WorkFolder有＋procedure.md有 → 既存読込
  └─ WorkFolder無      → 新規作成、テンプレ procedure.md を生成
```

### 3モード（同一プロセス内、タブ切替）
- **手順書作成モード（edit）**：Step編集メイン画面
- **作業実施モード（execute）**：Stepチェックリスト＋現Stepエビデンス自動紐付け
- **画像取得モード（capture）**：トレイ常駐＋ホットキーキャプチャ（手順書作成中の素材集めや単発キャプチャ用途）

## 3. ワークフォルダ構成

```
workfolder/
  procedure.md         # 手順書（入出力兼用）
  procedure.html       # HTML出力（手動生成）
  images/
    YYYY-MM-DD_HHmmss_stepNN.png         # 全画面
    YYYY-MM-DD_HHmmss_stepNN_win.png     # アクティブウィンドウ
    YYYY-MM-DD_HHmmss_stepNN_rect.png    # 矩形選択
    .originals/                          # マスク前原本退避
  attachments/         # 手順書作成時の参考画像（任意）
  .stepcreater/
    state.json         # 現Step、未割当スクショ一覧、開始/終了時刻ログ
```

`stepNN` は作業実施モード時は現Step ID、画像取得モード／Step未選択時は `unassigned`。

## 4. Markdown スキーマ

YAML Front Matter + 見出しベースの自然なMarkdown。ツール再パース可能、ユーザー直接編集も可。

```markdown
---
title: サーバ構築手順書
created: 2026-05-27
updated: 2026-05-27T11:32:05
author: noritake.kohji
---

# サーバ構築手順書

## Step 1: IISインストール
<!-- step-id: 01 -->
- status: done
- started: 2026-05-27T10:30:01
- finished: 2026-05-27T10:31:20

### 手順
本文（Markdown自由記述）...

### 実行コマンド
```powershell
Install-WindowsFeature -Name Web-Server
```

### 想定結果
ExitCode が 0 で "Success" が表示される

### エビデンス
![cap1](images/2026-05-27_103045_step01.png)
![cap2](images/2026-05-27_103120_step01_win.png)

### 備考
（任意）
```

### パース規約
- `## Step N: タイトル` がStep境界
- 直下のHTMLコメント `<!-- step-id: NN -->` が **安定ID**（Step追加・削除しても画像紐付けがズレない）
- 続く箇条書きが status / started / finished メタ
- セクション名は `### 手順 / 実行コマンド / 想定結果 / エビデンス / 備考` の5種固定、順序固定、省略可
- status の値は `pending | done | ng | skipped`
- ユーザーが書いた **未知セクションは破棄せず保持** する（パース時にraw保管→書き戻し時に復元）

## 5. データモデル

```
WorkSession
  ├─ WorkFolderPath        : string
  ├─ Procedure             : ProcedureDoc
  ├─ CurrentStepIndex      : int
  ├─ UnassignedScreenshots : List<ScreenshotRef>
  └─ Mode                  : enum (Edit, Execute, Capture)

ProcedureDoc
  ├─ Title / Author / Created / Updated
  └─ Steps : List<Step>

Step
  ├─ Id (NN, 安定ID)
  ├─ Title
  ├─ BodyMarkdown
  ├─ Command
  ├─ ExpectedResult
  ├─ Status (pending|done|ng|skipped)
  ├─ Started / Finished : DateTime?
  ├─ Note
  ├─ Evidence : List<ScreenshotRef>
  └─ UnknownSectionsRaw : Dict<string,string>  # 未知セクション保持

ScreenshotRef
  ├─ FileName
  ├─ CapturedAt
  ├─ Kind (full|window|rect)
  └─ MaskedFromOriginal : bool
```

## 6. GUI 画面構成（WPF）

共通：上部にモード切替タブ、ワークフォルダパス、保存ボタン、ステータスバー。

### 手順書作成モード
- 左ペイン：Step一覧（並べ替え／追加／削除）
- 中央右：Step詳細編集（タイトル／手順／実行コマンド／想定結果／備考／エビデンスサムネ＋マスク）
- 下部：**未割当スクショトレイ** — ドラッグでStepに割当
- 「テンプレ挿入」メニューで雛形Step投入

### 作業実施モード
- 左ペイン：Stepチェックリスト（現Stepハイライト、進捗表示）
- 中央右：現Step表示（読み取り専用本文、実行コマンド「コピー」ボタン、想定結果）
- 下段：今Stepのエビデンスサムネ＋「完了して次へ」「NG」「スキップ」ボタン
- 完了/NG/スキップで開始/完了時刻自動記録

### 画像取得モード
- 最小化ツールバー（Always-on-top可）
- 「全画面／窓／矩形」ボタンと未割当枚数表示
- 「展開」ボタンで手順書作成モードへ復帰

## 7. キャプチャ & ホットキー

### 実装
- `Add-Type` でWin32 API（`RegisterHotKey` / `UnregisterHotKey`）をP/Invoke
- 隠しウィンドウ（`HwndSource`）で `WM_HOTKEY` 受信
- 全画面：`System.Windows.Forms.Screen` + `Graphics.CopyFromScreen` で PNG化（マルチモニタ対応）
- アクティブウィンドウ：`GetForegroundWindow` + `DwmGetWindowAttribute(DWMWA_EXTENDED_FRAME_BOUNDS)` で影を除いた実枠取得
- 矩形選択：全画面スクショ → 半透明オーバーレイ（全モニタを覆う）→ マウスドラッグ → クロップ

### 自動アノテーション
- マウス座標に半透明赤丸（半径20px、線3px）
- 画像下に黒帯キャプション：`アクティブウィンドウタイトル | 撮影時刻`
- config.json で ON/OFF 切替可

### マスク機能
- サムネをダブルクリック → 簡易マスクエディタ（矩形描画、黒塗り or モザイク）
- 保存時は原本を `images/.originals/` に退避してから上書き

### デフォルトホットキー（GUIから再割当可）
| 機能 | キー | 実装フェーズ |
|---|---|---|
| 全画面キャプチャ | Ctrl+F12 | 1 |
| アクティブウィンドウ | Ctrl+F11 | 1 |
| 矩形選択 | Ctrl+Shift+F12 | 1 |
| 直前を取り直し | Ctrl+Shift+F11 | 2（後回し） |
| 完了して次へ | Ctrl+F10 | 2（後回し） |

衝突検知：登録失敗時は警告ダイアログ表示。

### ESCキー挙動
| コンテキスト | 動作 |
|---|---|
| メインウィンドウ | 確認ダイアログ → OKで終了 |
| 矩形選択オーバーレイ | 選択キャンセル |
| マスクエディタ | 編集破棄して閉じる |
| 設定／テンプレ選択等のモーダル | キャンセル |

未保存検出：最終保存時の `procedure.md` ハッシュとメモリ状態を比較。

## 8. 状態管理・永続化

### 保存タイミング
- **手動**：Ctrl+S または保存ボタン → `procedure.md` を再生成
- **自動**：
  - Step追加・削除・並べ替え時
  - 作業実施モードでStatus変更時
  - キャプチャ取得時は `.stepcreater/state.json` のみ更新（Markdownは触らない）
- **終了時**：未保存があれば確認ダイアログ

### 往復編集
- 読込：`procedure.md` パース → ProcedureDoc 構築
- 書込：Step順、メタ箇条書き、5セクション固定順で再生成
- 未知セクションは raw 保持して書き戻し時に復元

### HTML 出力
- 「HTML出力」ボタン押下時のみ生成（重いため自動化しない）
- 画像は相対パス参照（Base64埋込ではない）
- 印刷用CSS同梱、画像クリックで Lightbox 拡大、目次自動生成、作業時間表示

## 9. テスト方針

| レイヤ | ツール | 対象 |
|---|---|---|
| 純ロジック | Pester v5 | Markdownパーサ／ジェネレータ、Stepモデル操作、ファイル名規約 |
| ファイルI/O | Pester v5 | TestDrive で workfolder 往復、未知セクション保持、壊れたMD回復 |
| キャプチャ | Pester v5 | 仮想 Bitmap → アノテーション結果のピクセル検証 |
| WPF UI | (手動QA) | ViewModelロジックは Pester、View本体は手動 |
| ホットキー | Python E2E | PyAutoGUI でキー送信 → ファイル生成確認 → Pillow で画像差分 |
| HTML出力 | Pester v5 | 生成HTMLの構造検証（正規表現 or HtmlAgilityPack） |

補助ツール：
- **PSScriptAnalyzer** — 静的解析、コミット前必須
- **InvokeBuild** — `Invoke-Build Test` で lint + test + package 一発実行

カバレッジ目標：純ロジック層 80% 以上。TDD推奨（Markdownパーサ等は仕様→失敗テスト→実装）。

## 10. 採用する追加機能

| # | 機能 | 概要 | フェーズ |
|---|---|---|---|
| 1 | 未割当スクショトレイ | 撮影直後・Step未紐付け画像の一覧、D&Dで割当 | 3 |
| 2 | 自動アノテーション | マウス位置赤丸＋撮影時刻キャプション | 3 |
| 3 | 作業時刻ログ | Step開始/完了時刻自動記録、HTMLに作業時間表示 | 4 |
| 4 | PII/機密マスク | 矩形でモザイク／黒塗り、原本は .originals/ へ退避 | 4 |
| 5 | サムネ＆Lightbox | HTML出力時に画像クリック拡大、印刷時はフル | 5 |
| 6 | 手順書テンプレ | よく使う雛形Step挿入 | 2 |
| 8 | 完了して次へ | Ctrl+F10 で作業実施モードの進行 | 6（後回し） |

不採用：#7 ハッシュ値記録（監査要件として明示されていないため）。

## 11. マイルストーン

- **フェーズ1：基盤** — 骨格、Pester/PSScriptAnalyzer/InvokeBuild導入、データモデル、Markdown往復、ワークフォルダ初期化
- **フェーズ2：手順書作成モード** — WPFメイン画面、Step編集、保存／自動保存、テンプレ挿入(#6)
- **フェーズ3：キャプチャ基盤** — Win32 P/Invoke、3種キャプチャ、アノテーション(#2)、未割当トレイ(#1)
- **フェーズ4：作業実施モード** — チェックリスト、現Step連動、時刻記録(#3)、マスクエディタ(#4)
- **フェーズ5：出力・仕上げ** — HTML出力(#5)、設定画面、ESC終了確認、エラーハンドリング、Python E2E
- **フェーズ6：後回し機能** — 完了して次へ(#8)、直前取り直し、画像取得モードの見た目調整

## 12. オープン項目（実装時に決める）

- WPF コントロールの具体的な Markdown エディタ実装（`TextBox` の素実装か、シンタックスハイライト付きの軽量エディタか）
- HTML 出力時の CSS テーマ（社内ブランドカラー等の指定があれば反映）
- マルチモニタDPIスケーリングの細部（混在DPI環境での座標補正）
- 配布手段（社内共有ドライブ、署名要否）
