# PhotoTools & ギガファイル便連携システム 完全詳細仕様書（第2部：データスキーマ・外部連携・関数・引き継ぎ仕様）

本ドキュメントは、第1部（`PhotoTools_Specification_Part1.md`）に続く完全仕様書の第2部であり、全設定ファイル・データファイル・Excel台帳・履歴JSON・モジュール関数シグネチャ・ギガファイル便連携ツール（Windows版確定ベースラインおよびAndroid版移行ベースライン）のすべての仕様を網羅する。

---

## 1. 設定ファイル仕様（`D:\PhotoTools\settings.ini`）

文字コード：`UTF-8`（BOMあり／なし両対応）または `Shift-JIS`。`key=value` 形式（`#` および `;` で始まる行はコメントとして無視）。

| キー名 | 必須 | デフォルト値例 | 説明 |
| :--- | :---: | :--- | :--- |
| `RawRootPath` | 必須 | `G:\写真\取込` | RAW・JPEG取込側のルートディレクトリパス。 |
| `DevelopedRootPath` | 必須 | `G:\写真\現像後` | 現像・レタッチ完了側のルートディレクトリパス。 |
| `ExcelLedgerPath` | 必須 | `D:\PhotoTools\data\写真管理一覧.xlsx` | 写真管理Excel台帳のフルパス。 |
| `XHistoryPath` | 任意 | `D:\PhotoTools\data\x_history.json` | Xアカウント・表示名・撮影日の学習履歴JSONパス。 |
| `SceneHistoryPath` | 任意 | `D:\PhotoTools\data\scene_history.json` | 衣装名・キャラ名・イベント名の学習履歴JSONパス。 |
| `GigaFileScriptPath` | 任意 | `D:\PhotoTools\gigafile\send_to_gigafile.ps1` | 連携用ギガファイル便スクリプトのフルパス。 |
| `MegaSyncRootPath` | 任意 | `C:\Users\sasuke\MEGA\PhotoShare` | MEGAクラウド同期用ルートフォルダパス。 |

---

## 2. テキストデータファイル完全フォーマット仕様

### 2.1 `写真情報.txt`（文字コード：UTF-8 BOM付き / 改行コード：CRLF）

対象フォルダ（取込側および現像後側の双方）の直下に保存されるマスターテキストファイル。
**共通ヘッダ部** と、**`-----` で区切られた人数分の被写体ブロック部** の2層構造を持つ。

#### フォーマット定義
```text
【撮影日】YYYY_MM_DD
【撮影区分】イベント | 個撮 | 併せ | その他
【イベント・場所】<イベント名または撮影場所>
【作品・ジャンル】<作品名またはジャンル>
【データ送付状況】未送付 | 送付済 | 保留
【ギガファイル便URL】<共有URL>
【MEGA共有URL】<MEGA共有リンク>
【メモ】<全体コメント・削除キー・パスワード控え等（複数行可）>
-----
【名前】<1人目のモデル表示名>
【衣装・キャラ】<1人目の衣装名またはキャラ名>
【Xアカウント】@<1人目のXスクリーンネーム>
-----
【名前】<2人目のモデル表示名>
【衣装・キャラ】<2人目の衣装名またはキャラ名>
【Xアカウント】@<2人目のXスクリーンネーム>
```

#### 読込・後方互換ルール（重要）
1. **枠別 `【衣装・キャラ】` の優先読込**：
   * `-----` 以降の人物ブロック内に `【衣装・キャラ】` が存在する場合は、その人物枠固有の `CostumeOrChar` プロパティとして読み込む。
2. **旧形式からの自動移行（後方互換）**：
   * 過去バージョンで作成された `写真情報.txt` において、共通ヘッダ側（最初の `-----` より前）に `【衣装・キャラ】` が記載されており、かつ1人目ブロックに `【衣装・キャラ】` が存在しない場合、**1人目の枠へ自動的に値を引き継ぐ**。保存時は新仕様（人物ブロック内出力）へ正規化される。
3. **双方向同期優先順位**：
   * 取込側と現像後側の双方に `写真情報.txt` が存在する場合、**更新日時（`LastWriteTime`）が新しい方**を正とし、もう片方へ上書きコピーして完全一致させる。

### 2.2 `event.txt` および `scene.txt`（文字コード：UTF-8 / CRLF）

* **`event.txt`**：撮影日親フォルダ（例：`G:\写真\取込\2026_10_04\event.txt`）に配置。1行目にイベント名または撮影場所名を記載する。新規フォルダ起動時の `【イベント・場所】` 初期値として自動採用される。
* **`scene.txt`**：被写体個別フォルダ（例：`G:\写真\取込\2026_10_04\モデルA\scene.txt`）に配置。1行目に衣装名またはキャラ名を記載する。既存 `event.txt` からの引き継ぎ補完にも対応する。

---

## 3. Excel管理台帳仕様（`写真管理一覧.xlsx`）

### 3.1 レコード出力単位と一意キー
* **出力単位**：**1人物（1登録枠）＝ 1行** として出力する。2人登録されているフォルダを保存した場合は2行が作成・更新される。
* **一意キー（重複判定・上書き更新キー）**：
  * `撮影日（YYYY_MM_DD）` ＋ `フォルダ名（被写体フォルダ名）` ＋ `枠番号（1, 2, ...）` の複合キーで既存行を検索する。
  * 一致する行が存在する場合はその行を**上書き更新**し、存在しない場合は最終行の次に**新規追加**する。

### 3.2 カラム構成（シート名：`管理一覧` または第1シート）

| 列番号 | 列名 | 格納データ | 備考 |
| :---: | :--- | :--- | :--- |
| A (1) | `撮影日` | `YYYY_MM_DD` | 文字列書式（`@`）で保存 |
| B (2) | `撮影区分` | イベント / 個撮 / 併せ / その他 | |
| C (3) | `イベント・場所` | 共通ヘッダのイベント・場所 | |
| D (4) | `作品・ジャンル` | 共通ヘッダの作品・ジャンル | |
| E (5) | `枠番号` | `1`, `2`, `3` ... | 複数人登録時の連番 |
| F (6) | `名前` | 該当枠の被写体名 | |
| G (7) | `衣装・キャラ` | 該当枠の衣装名またはキャラ名 | 枠連動データ |
| H (8) | `Xアカウント` | `@` 付きのXアカウント名 | |
| I (9) | `データ送付状況` | 未送付 / 送付済 / 保留 | |
| J (10) | `ギガファイル便URL` | 共有URL | |
| K (11) | `MEGA共有URL` | MEGA共有URL | |
| L (12) | `取込フォルダパス` | `G:\写真\取込\...` | 存在する場合記載 |
| M (13) | `現像後フォルダパス` | `G:\写真\現像後\...` | 存在する場合記載 |
| N (14) | `メモ` | 共通ヘッダのメモ欄内容 | 改行は空白またはLFへ正規化 |
| O (15) | `最終更新日時` | `YYYY/MM/DD HH:mm:ss` | 保存実行時のタイムスタンプ |

### 3.3 COMオブジェクト解放・ロック対策
* `New-Object -ComObject Excel.Application` 使用時は `Visible = $false`、`DisplayAlerts = $false` を設定する。
* 保存・終了処理は必ず `try { ... } finally { ... }` ブロックで囲み、`[System.Runtime.InteropServices.Marshal]::ReleaseComObject()` と `[GC]::Collect()` を実行してバックグラウンドに `EXCEL.EXE` プロセスが残留しないよう制御する。
* Excelファイルがユーザーによって開かれてロックされている場合は、エラーメッセージを表示してCSV/テキスト側への保存のみ先行完了させる。

---

## 4. 学習履歴JSONスキーマ

### 4.1 `x_history.json`（Xアカウント・表示名・撮影日履歴）
```json
[
  {
    "account": "@sample_cosplayer",
    "name": "サンプル表示名",
    "lastDate": "2026_10_04",
    "updatedAt": "2026-10-05T14:30:00"
  }
]
```
* **重複排除キー**：`account`（小文字正規化した `@id`）。同一アカウント保存時は `name`・`lastDate`・`updatedAt` を最新値で上書きし、配列の先頭へ移動する。
* **履歴検索ダイアログ連携**：`Show-XHistoryDialog` で `-FilterDate "YYYY_MM_DD"` が指定された場合、初期表示で `lastDate -eq $FilterDate` に一致するレコードのみを抽出し、UI上のチェックボックス切り替えで全件表示と即座に切り替えられる。

### 4.2 `scene_history.json`（衣装・キャラ名学習履歴）
```json
[
  {
    "value": "キャラクターA（通常衣装）",
    "category": "イベント",
    "lastDate": "2026_10_04",
    "count": 3
  }
]
```
* 保存時に**登録枠の全人数分**の `CostumeOrChar`（空欄を除く）を走査し、重複排除・使用回数カウントアップ・最新順ソートを行って保存する。

---

## 5. 分離モジュール公開関数仕様

### 5.1 `common\PhotoEditorLogic.ps1`
| 関数名 | 引数 | 戻り値 | 役割 |
| :--- | :--- | :--- | :--- |
| `Initialize-PhotoEditorEnvironment` | `-BaseDir <string>` | `[hashtable]` (`$EffectiveConfig`) | `settings.ini` 読込と環境パス初期化。 |
| `Resolve-PairedPhotoFolders` | `-TargetPath <string> -Config <hashtable>` | `[hashtable]` (`RawFolder`, `DevFolder`, `DateStr`, `FolderName`) | 選択パスから取込・現像後のペアフォルダと撮影日を解決。 |
| `Sync-PhotoInfoFiles` | `-RawFolder <string> -DevFolder <string>` | `[string]` (有効な `写真情報.txt` パス) | 更新日時比較による双方向最新同期。 |
| `Read-PhotoInfoData` | `-FilePath <string> -DateStr <string> -RawFolder <string> -DevFolder <string>` | `[hashtable]` (`Header`, `Persons` 配列) | `写真情報.txt` および `event.txt`/`scene.txt` の統合読込（旧ヘッダ衣装の1人目自動移行含む）。 |
| `Find-SameDayCostumeForModel` | `-ModelName <string> -DateStr <string> -Config <hashtable> -CurrentPersons <array>` | `[string]` (一致した衣装・キャラ名、なければ `""`) | 編集中他枠および同日親フォルダ配下の全 `写真情報.txt` から同一モデル名の衣装・キャラ名を検索。 |
| `Save-AllPhotoInfoAndLedger` | `-Data <hashtable> -RawFolder <string> -DevFolder <string> -Config <hashtable>` | `[hashtable]` (`Success`, `Message`) | 両フォルダへの `写真情報.txt` 保存、履歴JSON学習、Excel台帳更新の一括実行。 |

### 5.2 `common\XHelper.ps1`
* **重要スコープ規定**：`PhotoInfoEditor.ps1` の**スクリプトトップレベルスコープ**で `. "$BaseDir\common\XHelper.ps1"` として直接ドットソース読込を行うこと（関数内部で読み込むとローカルスコープに閉じ込められ呼び出し側から未定義になるため）。
* **`Get-XDisplayName`**：
  * シグネチャ：`param([Parameter(Position=0)][string]$Account, [Parameter(Position=1)][hashtable]$Config = @{})`
  * 取得順序：① `https://publish.twitter.com/oembed?url=https://x.com/<id>` ➔ ② `https://api.fxtwitter.com/<id>` ➔ ③ `https://api.vxtwitter.com/<id>` ➔ ④ `https://x.com/<id>` HTMLタイトル解析。
  * サニタイズ：末尾の `(@id) / X` や `@以降` 文字列を正規表現で除去して表示名のみ返却。
* **`Save-XHistory`**：
  * 3引数（`$Account, $Name, $Config`）および4引数（`$Account, $Name, $Config, $DateStr`）の両呼び出しに対応。
* **`Show-XHistoryDialog`**：
  * シグネチャ：`param([Parameter(Position=0)][hashtable]$Config = @{}, [Parameter(Position=1)][string]$FilterDate = "")`
  * 戻り値：選択時 `@{ account = "@..."; name = "..." }`、キャンセル時 `$null`。

---

## 6. ギガファイル便 自動アップロードツール連携・移行ベースライン仕様

### 6.1 `PhotoInfoEditor` からのコールバック連携仕様
1. `PhotoInfoEditor` 内の「ギガファイル便で送る」ボタン押下時、一時JSONファイルパス（例：`%TEMP%\gf_cb_<guid>.json`）を生成し、`-CallbackResultFile "<一時JSONパス>"` 引数を付けて `send_to_gigafile.ps1` を起動する。
2. `send_to_gigafile.ps1` はアップロード完了時、以下のJSONをUTF-8で書き出す。
   ```json
   {
     "url": "https://23.gigafile.nu/0228-xxxxxxxxxxxxxxxxxxxx",
     "delkey": "4120",
     "password": "",
     "lifetime": "100",
     "files": ["IMG_7991.jpg", "IMG_7992.jpg"],
     "uploadedAt": "2026/11/20 05:10:00"
   }
   ```
3. `PhotoInfoEditor` 側はプロセス終了後に一時JSONを読み取り、`【ギガファイル便URL】` 欄へ `url` を自動セットし、`【メモ】` 欄へ削除キー・パスワード・期限を追記して一時JSONを削除する。

### 6.2 Windows単体版（確定ベースライン）仕様要点
* **インストール先**：`%USERPROFILE%\GigaFileTool\`（`send_to_gigafile.ps1` / `launch_gigafile.bat` / `install_gigafile_tool.bat`）
* **画面レイアウト（`720px × 720px` 固定5段構成）**：
  1. 対象ツリービュー（単体ファイルは非圧縮、フォルダおよび複数選択時は `Zip64` 有効で自動ZIP圧縮）
  2. アップロード設定（保持期限 `3/5/7/14/30/60/100日`、DLパスワード最大32文字）
  3. 実行ボタン＆進捗バー＆リアルタイムログ
  4. 発行結果エリア（共有URL・削除キー、各コピーボタン、自動クリップボードコピー）
  5. フッターボタン（`履歴フォルダを開く`、`エラーログフォルダを開く`、`閉じる`）
* **通信仕様**：`https://gigafile.nu/` トップページから `var server = "..."` とセッションCookieを取得 ➔ `https://<server>/upload_chunk.php` へ **50MBチャンク分割送信** ➔ パスワード指定時は `https://<server>/set_password.php` へPOST。
* **ログ出力仕様**：
  * 完了時：`履歴\gigafile_yyyyMMdd_HHmmss.txt` に【メール送信用】と【自分用 管理メモ】を分離して出力し、メモ帳を自動起動。
  * 通常ログ：`process_log.txt` へ追記。
  * エラー時：`エラーログ\error_log_yyyyMMdd_HHmmss.txt` を毎回新規作成（追記なし）。

### 6.3 Android単体アプリ版（移行用ベースライン）仕様要点
* **推奨構成**：Python + **Flet**（APKビルド対応）または **Pydroid 3**（`tkinter` + `requests`）。
* **保存先パス**：`/storage/emulated/0/Download/GigaFileTool/` 配下に `履歴/`、`エラーログ/`、`process_log.txt` を生成（Android 11以降は `MANAGE_EXTERNAL_STORAGE` またはアプリ固有ディレクトリ／SAF経由保存を考慮）。
* **通信・圧縮アルゴリズム**：Windows版と完全同一（50MBチャンク分割送信、`allowZip64=True` の自動ZIP化、`upload_chunk.php` / `set_password.php` エンドポイント利用）。
