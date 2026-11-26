import { useEffect, useMemo, useState } from 'react';
import {
  AlertTriangle,
  Check,
  CheckCircle2,
  Circle,
  ClipboardCopy,
  Download,
  FileCode2,
  RotateCcw,
  Terminal,
} from 'lucide-react';

export type VerificationStatus = 'pending' | 'passed' | 'issue';

interface FeatureCheckItem {
  id: string;
  number: string;
  categoryKey: 'master' | 'async' | 'sync' | 'giga' | 'msg' | 'ai';
  categoryLabel: string;
  title: string;
  targetFile: string;
  launchCommand: string;
  steps: string[];
  expected: string;
}

interface SavedItemRecord {
  status: VerificationStatus;
  memo: string;
  updatedAt: string;
}

type SavedStateMap = Record<string, SavedItemRecord>;

interface VerificationChecklistTabProps {
  onSelectFile: (filePath: string) => void;
}

const STORAGE_KEY = 'phototools_roadmap_verification_v1';

const FEATURE_ITEMS: FeatureCheckItem[] = [
  {
    id: 'master-01',
    number: '01',
    categoryKey: 'master',
    categoryLabel: '1. PhotoTools Master',
    title: '単独起動と日本語コンソール表示',
    targetFile: 'PhotoToolsMaster.ps1',
    launchCommand: 'D:\\PhotoTools\\StartPhotoToolsMaster.bat',
    steps: [
      'D:\\PhotoTools\\StartPhotoToolsMaster.bat をダブルクリックして起動します。',
      '上部ヘッダーと3つのタブ（フォルダ構造 & ワークフロー呼出 / 不整合チェック・診断 / 台帳自動補完・セルフヒーリング）の表示を確認します。',
    ],
    expected:
      '構文エラーや文字化けが発生せず、すべての見出し・ボタン・説明文が日本語で正しく表示されること。',
  },
  {
    id: 'master-02',
    number: '02',
    categoryKey: 'master',
    categoryLabel: '1. PhotoTools Master',
    title: '切替式ビュー（作業用 / 作業完了後 / 長期アーカイブ）のオンデマンドスキャン',
    targetFile: 'PhotoToolsMaster.ps1',
    launchCommand: 'タブ1「フォルダ構造 & ワークフロー呼出」内ラジオボタン切替',
    steps: [
      '「作業用ルート (Developed / Raw)」「作業完了後ルート」「長期アーカイブ」を順番にクリックして切り替えます。',
      '「フォルダをチェック・表示」ボタンを押し、一覧の再読込を確認します。',
    ],
    expected:
      '各ルート直下の日付フォルダ（YYYY_MM_DD 等）がリスト表示され、写真情報.txt の有無（「写真情報.txt有」または「詳細未登録(仮)」）が表示されること。',
  },
  {
    id: 'master-03',
    number: '03',
    categoryKey: 'master',
    categoryLabel: '1. PhotoTools Master',
    title: '日付スコープ選択からの DailyWorkflow 直接起動',
    targetFile: 'PhotoToolsMaster.ps1',
    launchCommand: '一覧の日付行を選択 →「選択した日付で DailyWorkflow を起動」',
    steps: [
      '日付フォルダ一覧から確認したい撮影日の行を1つクリックして選択します。',
      '右下の「選択した日付で DailyWorkflow を起動」ボタンを押します。',
    ],
    expected:
      '選択した日付フォルダが自動的に読み込まれた状態で DailyWorkflow ウィンドウが起動すること。',
  },
  {
    id: 'master-04',
    number: '04',
    categoryKey: 'master',
    categoryLabel: '1. PhotoTools Master',
    title: '作業用・アーカイブ間の重複日付フォルダ不整合チェック',
    targetFile: 'PhotoToolsMaster.ps1',
    launchCommand: 'タブ2「不整合チェック・診断」→「不整合チェックを実行」',
    steps: [
      '「不整合チェック・診断」タブを開きます。',
      '「不整合チェックを実行」ボタンを押し、下部コンソールの診断ログを確認します。',
    ],
    expected:
      '各ルートのスキャン件数が表示され、作業用とアーカイブの両方に同一日付フォルダが残っている場合は重複警告リストが出力されること。',
  },
  {
    id: 'master-05',
    number: '05',
    categoryKey: 'master',
    categoryLabel: '1. PhotoTools Master',
    title: 'Excel台帳の自動補完・仮登録行の自動正規化（セルフヒーリング）',
    targetFile: 'PhotoToolsMaster.ps1',
    launchCommand: 'タブ3「台帳自動補完・セルフヒーリング」→「台帳の自動補完・同期を実行」',
    steps: [
      '写真管理一覧.xlsx を Excel で開いている場合は一旦閉じます。',
      '「台帳自動補完・セルフヒーリング」タブで「台帳の自動補完・同期を実行」ボタンを押します。',
    ],
    expected:
      '全対象フォルダがスキャンされ、未登録フォルダの追加および 写真情報.txt 入力済みデータの正式行への反映が完了ログとともに記録されること。',
  },
  {
    id: 'async-06',
    number: '06',
    categoryKey: 'async',
    categoryLabel: '2. 非同期・安全制御',
    title: 'アプローチA：Step2 / Step5 ヘルパーの別プロセス非同期実行',
    targetFile: 'workflow/DailyWorkflow.ps1',
    launchCommand: 'StartDailyWorkflow.bat →「Step2 RAW複製移動」または「Step5 アーカイブ移動」',
    steps: [
      'DailyWorkflow を開き、対象日付を選択した状態で Step2（または Step5）を実行します。',
      '実行中に DailyWorkflow ウィンドウをドラッグ移動したりログ欄を確認したりします。',
    ],
    expected:
      '実ファイル移動処理が別 PowerShell プロセスで実行され、UIが「応答なし」で固まることなく完了後に移動件数ログが出力されること。',
  },
  {
    id: 'async-07',
    number: '07',
    categoryKey: 'async',
    categoryLabel: '2. 非同期・安全制御',
    title: 'MEGA共有リンク非同期取得 ＆ ポップアップ内リアルタイム処理ログ表示',
    targetFile: 'common/MegaHelper.ps1',
    launchCommand: 'PhotoInfoEditor（被写体プロパティ）→ MEGA欄「リンク取得/診断」',
    steps: [
      '任意の子フォルダで PhotoInfoEditor（被写体プロパティ）を開きます。',
      'MEGAリンク欄の「リンク取得/診断」ボタンを押し、表示されるポップアップ内の「実行処理ログ」欄を確認します。',
    ],
    expected:
      'ポップアップ内のログ欄に MEGAcmd 検出・リモートパス候補算出・mega-export 実行・応答結果がリアルタイムで表示され、取得完了ダイアログまでエラーなく進むこと。',
  },
  {
    id: 'async-08',
    number: '08',
    categoryKey: 'async',
    categoryLabel: '2. 非同期・安全制御',
    title: '処理中クローズ警告（閉じガード）と PhotoInfoEditor「閉じる / ×」ボタン動作',
    targetFile: 'editor/PhotoInfoEditor.ps1',
    launchCommand: 'MEGA通信中またはStep実行中の「×」押下 / PhotoInfoEditorの「閉じる」押下',
    steps: [
      'MEGAリンク取得ポップアップの通信中（または DailyWorkflow の Step 実行中）にウィンドウ右上の「×」を押して確認警告が出るか試します。',
      'PhotoInfoEditor で未変更のまま「閉じる」「×」を押した場合と、文字を入力してから「閉じる」「×」を押した場合の両方を試します。',
    ],
    expected:
      '通信・処理中は強制終了確認ダイアログが表示されて誤終了を防げること。また PhotoInfoEditor の「閉じる」「×」が確実に反応し、未保存変更時のみ確認が出ること。',
  },
  {
    id: 'sync-09',
    number: '09',
    categoryKey: 'sync',
    categoryLabel: '3. 子フォルダ名同期',
    title: 'DailyWorkflow からの子フォルダ名変更（取込・現像後・RAW 3ルート一括同期）',
    targetFile: 'workflow/DailyWorkflow.ps1',
    launchCommand: 'DailyWorkflow ツリーで子フォルダ選択 →「フォルダ名変更(3同期)」または右クリック',
    steps: [
      'DailyWorkflow のフォルダ構成ツリーで子フォルダ（例: 01）を選択します。',
      '「フォルダ名変更(3同期)」ボタン（または右クリックメニュー）を押し、新しい名前（例: 01_モデル名）を入力して確定します。',
    ],
    expected:
      '取込元・現像後・RAW の存在する全ルートで該当フォルダが一括リネームされ、画面ツリーと下部ログに同期完了が表示されること。',
  },
  {
    id: 'sync-10',
    number: '10',
    categoryKey: 'sync',
    categoryLabel: '3. 子フォルダ名同期',
    title: 'エクスプローラー変更時のリネーム自動追従（取込後・現像後どちらの変更もRAWまで連動）',
    targetFile: 'workflow/DailyWorkflow.ps1',
    launchCommand: 'エクスプローラーで片方のフォルダ名を変更 → DailyWorkflow「更新」ボタン',
    steps: [
      'エクスプローラー上で「現像後」または「取込元」のどちらか片方の子フォルダ名だけを変更します（例: 02 → 02_スタジオ名）。',
      'DailyWorkflow 画面上部の「更新」ボタンを押します（または Step3 / Step4 を起動します）。',
    ],
    expected:
      '連番プレフィックスまたは内部写真ファイル名の一致によりリネームが自動検出され、他ルートおよび RAW フォルダ側も同一名へ自動同期されること。',
  },
  {
    id: 'sync-11',
    number: '11',
    categoryKey: 'sync',
    categoryLabel: '3. 子フォルダ名同期',
    title: 'リネーム後の Excel 管理台帳パス保護 ＆ Step3 / Step4 維持確認',
    targetFile: 'common/ExcelHelper.ps1',
    launchCommand: '子フォルダ名変更後に 写真管理一覧.xlsx および Step3 / Step4 を確認',
    steps: [
      '既に台帳登録済みの子フォルダを「フォルダ名変更(3同期)」でリネームした後、写真管理一覧.xlsx を開いてパス列を確認します。',
      '続けて同日付で「Step3 現像後振分」または「Step4 重複JPG削除」を開きます。',
    ],
    expected:
      'Excel台帳の「相対パス」「フォルダ名」「取込フォルダ」「現像後フォルダ」列が新フォルダ名に更新されており、Step3 / Step4 もパス切れなく正常動作すること。',
  },
  {
    id: 'giga-12',
    number: '12',
    categoryKey: 'giga',
    categoryLabel: '4. ギガファイル便拡張',
    title: 'ギガファイル便 GUI コントロールの重なり（かぶり）解消確認',
    targetFile: 'gigafile/send_to_gigafile.ps1',
    launchCommand: 'フォルダ右クリック「送る」→ ギガファイル便 または「ギガファイル便で送る」',
    steps: [
      '任意のフォルダを対象にギガファイル便アップロードツールを起動します。',
      '「2. アップロード設定」枠内の「保持期限」「DLパスワード」「出力ファイル名（任意）：」および下部チェックボックスの配置を確認します。',
    ],
    expected:
      '「出力ファイル名（任意）：」ラベルとテキスト入力欄を含め、すべての文字や枠線が一切重ならず整然と表示されること。',
  },
  {
    id: 'giga-13',
    number: '13',
    categoryKey: 'giga',
    categoryLabel: '4. ギガファイル便拡張',
    title: '自動命名ZIP（写真情報.txt 解析による 日付_イベント_名前.zip 自動提案）',
    targetFile: 'gigafile/send_to_gigafile.ps1',
    launchCommand: '写真情報.txt 登録済みフォルダでギガファイル便ツールを起動',
    steps: [
      '撮影日・イベント名・モデル名が登録された 写真情報.txt を含む子フォルダでギガファイル便ツールを開きます。',
      '「出力ファイル名（任意）：」欄に初期表示されているファイル名を確認し、そのままアップロードを実行します。',
    ],
    expected:
      '起動時点で「日付_イベント名_モデル名.zip」形式のファイル名が自動セットされており、そのZIP名でアップロードされること。',
  },
  {
    id: 'giga-14',
    number: '14',
    categoryKey: 'giga',
    categoryLabel: '4. ギガファイル便拡張',
    title: '子フォルダ一括分割アップロード ＆ 全URL一覧リスト自動出力',
    targetFile: 'gigafile/send_to_gigafile.ps1',
    launchCommand: '日付親フォルダを選択 →「子フォルダごとに個別分割してアップロード…」にチェック',
    steps: [
      '複数の子フォルダ（01, 02 等）が入った「日付親フォルダ」を選択してギガファイル便ツールを起動します。',
      '「子フォルダごとに個別分割してアップロードし、全URL一覧リストを出力する」にチェックを入れて「アップロード開始」を押します。',
    ],
    expected:
      '子フォルダごとに個別ZIP化・アップロードが行われ、完了時に全フォルダ分のURL・削除キー一覧テキストがメモ帳で自動表示＆クリップボードへコピーされること。',
  },
  {
    id: 'giga-15',
    number: '15',
    categoryKey: 'giga',
    categoryLabel: '4. ギガファイル便拡張',
    title: 'アップロード完了後の URL・DLパスワード・保持期限自動記録 ＆「送付済み」更新',
    targetFile: 'gigafile/send_to_gigafile.ps1',
    launchCommand: 'アップロード完了後に対象フォルダの 写真情報.txt / 完了画面を確認',
    steps: [
      'PhotoInfoEditor・DailyWorkflow・または子フォルダ一括モードから保持期限・DLパスワード（任意）を設定してアップロードを完了させます。',
      '対象子フォルダ内の 写真情報.txt を開き、【ギガファイル便URL】【DLパスワード】【保持期限】（yyyy/MM/ddまで）と【データ送付状況】を確認します。',
      '完了画面に「送付メッセージ作成」ボタンが表示され、押下するとURL・パスワード・保持期限を引き継いだメッセージ作成画面が開くことを確認します。',
    ],
    expected:
      '発行されたURL・DLパスワード（設定時）・保持期限が 写真情報.txt へ自動記録され、送付状況が「送付済み」へ更新されること。また完了画面からそのまま送付メッセージ作成画面へ遷移できること。',
  },
  {
    id: 'sync-16',
    number: '16',
    categoryKey: 'sync',
    categoryLabel: '3. 子フォルダ名同期',
    title: '1日1人対応：日付フォルダ直下への 写真情報.txt 設定・表示・ギガファイル便送信',
    targetFile: 'workflow/DailyWorkflow.ps1',
    launchCommand: 'DailyWorkflow で日付フォルダ（ルート行）をダブルクリック → PhotoInfoEditor で保存',
    steps: [
      'DailyWorkflow で日付フォルダを開き、上部の「scene.txt を保存」で日付直下に scene.txt を保存します。',
      'フォルダ構成ツリーの一番上にある「日付フォルダ行」をダブルクリック（または選択して「被写体プロパティを開く」）し、モデル名・衣装を入力して保存します。',
      'ツリーの日付行にモデル名・衣装・送付状況が表示されること、また日付行を選択してギガファイル便送信や Excel台帳同期（SyncExcelFromTxt / PhotoToolsMaster）が動作することを確認します。',
    ],
    expected:
      '子フォルダを作らなくても日付フォルダ直下に 写真情報.txt が保存・ペア同期され、DailyWorkflow ツリー・PhotoToolsMaster・Excel台帳・ギガファイル便自動命名ZIPのすべてで正常に扱われること。',
  },
  {
    id: 'master-17',
    number: '17',
    categoryKey: 'master',
    categoryLabel: '1. PhotoTools Master',
    title: 'Master からの設定編集画面（settings.ini・履歴JSON・定型文・AIキャラ判定5タブ／即時反映）',
    targetFile: 'editor/SettingsEditor.ps1',
    launchCommand: 'PhotoToolsMaster 右上「設定編集 (settings.ini 等)」ボタン',
    steps: [
      'StartPhotoToolsMaster.bat を起動し、ヘッダー右上の「設定編集 (settings.ini 等)」ボタンを押します。',
      '5つのタブ（「フォルダ・パス設定」「期分け・拡張子・MEGA」「関連ファイル編集・OS登録」「メッセージ定型文」「AIキャラ判定」）がすべて正常に表示されることを確認します。',
      '「メッセージ定型文」タブで変数挿入・MEGA共通コメント5種が保存でき、「AIキャラ判定」タブでAPIキーのDPAPI暗号化保存・Google Cloud有料枠確認チェック・0トークン接続テスト・AI設定保存が機能することを確認します。',
      '「settings.ini を保存して反映」で settings.ini.bak の自動作成と Master 側の即時再読込を確認します。',
    ],
    expected:
      'GUI上から settings.ini・関連JSON・message_templates.json・ai_character_settings.json・DPAPI暗号化キーを安全に編集・保存でき、保存直後に反映されること。',
  },
  {
    id: 'master-18',
    number: '18',
    categoryKey: 'master',
    categoryLabel: '1. PhotoTools Master',
    title: '単独更新支援ツール（ZIP最新自動選択・GitHub取得・バックアップ・保護上書き・不要ファイル削除確認）',
    targetFile: 'updater/PhotoToolsUpdater.ps1',
    launchCommand: 'updater\\StartPhotoToolsUpdater.vbs をダブルクリック（別フォルダへ単体コピーしての実行も可）',
    steps: [
      'updater\\StartPhotoToolsUpdater.vbs をダブルクリックし、黒画面が出ずに更新支援GUIが起動することを確認します。',
      'ZIP保存フォルダ・対象ファイル名（例: PhotoTools.zip）・更新先フォルダを指定し、「選択 (最新を自動選択)」で (1)(2) 等を含む最新ZIPが自動選択されること（または GitHub URL 入力後に「GitHubから最新ZIPを取得」でダウンロードされること）を確認します。',
      '「指定フォルダへ更新を実行」を押し、backup\\ への事前退避、settings.ini の設定値維持（新規キーのみ追記）、data\\（message_templates.json 等含む）保護、ブロック解除、および不要ファイル確認ダイアログが正常に動作することを確認します。',
    ],
    expected:
      '本体に依存せず単独で起動・更新でき、既存設定・履歴・定型文データを壊さずに最新ZIPの上書き・バックアップ・不要ファイル整理まで一括完了できること。',
  },
  {
    id: 'sync-19',
    number: '19',
    categoryKey: 'sync',
    categoryLabel: '3. 子フォルダ名同期',
    title: '写真情報.txt の【X】（アカウント名）と【X_URL】（URL）分離 ＆ 既存データ自動修正',
    targetFile: 'common/PhotoInfoHelper.ps1',
    launchCommand: 'PhotoInfoEditor で新規保存、または既存の 写真情報.txt があるフォルダへ DailyWorkflow / PhotoInfoEditor / SyncExcel でアクセス',
    steps: [
      'PhotoInfoEditor でXアカウント（例: @sample_user または https://x.com/sample_user）を入力して保存し、作成された 写真情報.txt を開きます。',
      '【X】に @sample_user、新設された【X_URL】に https://x.com/sample_user が記録されていることを確認します。',
      '既に作成済みの【X】https://x.com/... 形式の 写真情報.txt があるフォルダを DailyWorkflow や PhotoInfoEditor（または SyncExcelFromTxt）で開き、ファイル内容が自動的に【X】アカウント名＋【X_URL】URL 形式へ書き換わっていることを確認します。',
    ],
    expected:
      '新規保存時は【X】にアカウント名・【X_URL】にURLが記載され、既存の旧形式データもアクセス時に元の最終更新日時を維持したまま自動修正されること。',
  },
  {
    id: 'msg-20',
    number: '20',
    categoryKey: 'msg',
    categoryLabel: '5. 送付メッセージ作成',
    title: '送付メッセージ作成（単体／まとめ起動・初期空欄・ギガ/MEGA切替・複数人/共演者表記）',
    targetFile: 'editor/MessageComposerDialog.ps1',
    launchCommand: 'PhotoInfoEditor「メッセージ作成」 / DailyWorkflow「メッセージ作成(まとめ可)」 / ギガファイル便完了後ボタン',
    steps: [
      'SettingsEditor「メッセージ定型文」タブで撮影区分（イベント／個撮／併せ等）に紐づく定型文を1件以上登録します。',
      'PhotoInfoEditor または DailyWorkflow（同一モデルの複数フォルダがある日）からメッセージ作成画面を開き、初期状態の本文欄が空欄のまま開くことを確認します。',
      '「ギガファイル便」または「MEGA」ラジオボタンを選び（MEGA時は画面上で共通コメント種別も切替可）、「メッセージを作成」を押します。',
      '複数リンク／複数人フォルダ選択時に「個撮リンク１」「複数リンク１＋次行に名前（キャラ名）（3名以上は、区切り）」、ギガファイル便のDLパスワード（入力時のみ）・保持期間（yyyy/MM/ddまで）が正しく整形されることを確認します。',
    ],
    expected:
      '初期表示では自動生成やMEGA通信を行わず、「メッセージを作成」押下時のみ選択方式に応じたメッセージが仕様通りの書式で生成されること。',
  },
  {
    id: 'msg-21',
    number: '21',
    categoryKey: 'msg',
    categoryLabel: '5. 送付メッセージ作成',
    title: 'MEGA未取得確認→取得書き戻し ＆ コピー後の「送付済み」一括更新連動',
    targetFile: 'editor/MessageComposerDialog.ps1',
    launchCommand: 'メッセージ作成画面 → MEGA選択「メッセージを作成」 →「クリップボードにコピー」',
    steps: [
      'MEGAリンク未取得のフォルダをチェックした状態で「MEGA」を選択し、「メッセージを作成」を押します。',
      '未取得フォルダ一覧付きの確認ダイアログ（はい：取得して作成／いいえ：取得せず作成／キャンセル）が表示され、「はい」で MegaHelper 経由の取得＋写真情報.txt＆Excel台帳への自動書き戻しが行われることを確認します。',
      '「コピー後にステータスを『送付済み』へ更新する」（初期ON）にチェックが入った状態で「クリップボードにコピー」を押し、対象フォルダの 写真情報.txt（ペア含む）および Excel台帳が「送付済み」へ更新されることを確認します。',
    ],
    expected:
      'MEGA未取得時のみ安全に確認取得でき、コピー操作と連動してチェック済みフォルダの送付ステータスが 写真情報.txt・Excel台帳・呼び出し元画面へ即座に反映されること。',
  },
  {
    id: 'ai-22',
    number: '22',
    categoryKey: 'ai',
    categoryLabel: '6. AIキャラ判定',
    title: '写真からAIキャラクター名検索（顔マスク・未設定警告・Exif除去縮小・DPAPI・キャラ名（作品名）反映）',
    targetFile: 'editor/CharacterLookupDialog.ps1',
    launchCommand: 'PhotoInfoEditor「写真からキャラ検索」 / SettingsEditor「AIキャラ判定」タブ',
    steps: [
      'SettingsEditor の「AIキャラ判定」タブで Google Cloud 請求先アカウント紐付け済み APIキーを保存（data\\gemini_api_key.dat にDPAPI暗号化保存・平文非保存）し、有料枠（学習不使用）確認チェックをONにして接続テストを実行します。',
      'PhotoInfoEditor で衣装・キャラ欄横の「写真からキャラ検索」ボタンを押し、フォルダ内写真を選択してマウスドラッグで顔・背景マスク（黒塗り／モザイク・1つ戻す・全消去）が適用できることを確認します。',
      'マスク0箇所のまま「この画像でAI検索」を押した際に未設定の確認警告ダイアログが表示されること、および検索後に候補一覧（確度・根拠付き）から既定書式「キャラ名（作品名）」（ほか2書式へ切替可）で衣装・キャラ欄へ反映されることを確認します。',
    ],
    expected:
      'Exif/メタデータ完全除去＋長辺縮小（メモリ上処理・一時ファイル非生成）・個人情報未送信の6層漏洩対策のもとで安全にキャラ候補を取得でき、選択候補が「キャラ名（作品名）」形式で衣装・キャラ欄へ反映されること。',
  },
];

interface SetupStep {
  step: string;
  title: string;
  command?: string;
  detail: string;
}

const SETUP_STEPS: SetupStep[] = [
  {
    step: '01',
    title: '修復版ZIPの取得と更新適用（単独更新支援ツール推奨）',
    command: 'D:\\PhotoTools\\updater\\StartPhotoToolsUpdater.vbs',
    detail:
      '右上の「修復版ZIPをダウンロード」から最新ZIPを取得します。初回は D:\\PhotoTools\\ へ手動展開し、2回目以降の更新は単独更新支援ツール（StartPhotoToolsUpdater.vbs）を使うと、事前バックアップ・settings.ini／data\\（履歴・定型文）保護・ブロック解除・不要ファイル整理まで一括実行できます。',
  },
  {
    step: '02',
    title: 'Windows インターネットブロック（Zone.Identifier）の一括解除（手動展開時）',
    command: 'D:\\PhotoTools\\UnblockFiles.bat',
    detail:
      '手動でZIP展開した場合は、.ps1 が SmartScreen 等にブロックされないよう展開直後に UnblockFiles.bat を1回実行してください（単独更新支援ツール使用時は自動実行されます）。',
  },
  {
    step: '03',
    title: '自動モジュールテスト（01〜12）の一括検証',
    command: 'D:\\PhotoTools\\RunTestManager.bat',
    detail:
      '本番データや台帳を汚さない一時サンドボックス上で 01. LogHelper 〜 12. GeminiCharacterHelper の構文・単体テストを一括検証できます。',
  },
  {
    step: '04',
    title: '右クリックメニュー・URLプロトコル・SendTo 連携の登録（初回のみ）',
    command: 'RegisterContextMenu.bat / RegisterProtocol.bat / gigafile\\install_gigafile_sendto.bat',
    detail:
      'フォルダパスを変更した場合や初回導入時は、各登録バッチ（または SettingsEditor のOS登録タブ）を実行すると %~dp0 基準で現在の配置先へ自動登録されます。',
  },
];

function formatNowTimestamp(): string {
  const d = new Date();
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}/${pad(d.getMonth() + 1)}/${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export default function VerificationChecklistTab({ onSelectFile }: VerificationChecklistTabProps) {
  const [subView, setSubView] = useState<'roadmap' | 'setup'>('roadmap');
  const [statusFilter, setStatusFilter] = useState<'all' | VerificationStatus>('all');
  const [categoryFilter, setCategoryFilter] = useState<'all' | FeatureCheckItem['categoryKey']>('all');
  const [records, setRecords] = useState<SavedStateMap>(() => {
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY);
      if (!raw) return {};
      const parsed = JSON.parse(raw) as SavedStateMap;
      return parsed && typeof parsed === 'object' ? parsed : {};
    } catch {
      return {};
    }
  });
  const [copiedReport, setCopiedReport] = useState(false);
  const [confirmingReset, setConfirmingReset] = useState(false);

  useEffect(() => {
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(records));
    } catch {
      // ignore storage quota errors
    }
  }, [records]);

  const getRecord = (id: string): SavedItemRecord => {
    return (
      records[id] ?? {
        status: 'pending',
        memo: '',
        updatedAt: '',
      }
    );
  };

  const handleStatusChange = (id: string, nextStatus: VerificationStatus) => {
    setRecords((prev) => {
      const cur = prev[id] ?? { status: 'pending', memo: '', updatedAt: '' };
      return {
        ...prev,
        [id]: {
          ...cur,
          status: nextStatus,
          updatedAt: formatNowTimestamp(),
        },
      };
    });
  };

  const handleMemoChange = (id: string, nextMemo: string) => {
    setRecords((prev) => {
      const cur = prev[id] ?? { status: 'pending', memo: '', updatedAt: '' };
      return {
        ...prev,
        [id]: {
          ...cur,
          memo: nextMemo,
          updatedAt: formatNowTimestamp(),
        },
      };
    });
  };

  const stats = useMemo(() => {
    let passed = 0;
    let issue = 0;
    let pending = 0;
    let withMemo = 0;
    for (const item of FEATURE_ITEMS) {
      const rec = records[item.id];
      const st = rec?.status ?? 'pending';
      if (st === 'passed') passed++;
      else if (st === 'issue') issue++;
      else pending++;
      if (rec?.memo && rec.memo.trim().length > 0) withMemo++;
    }
    const total = FEATURE_ITEMS.length;
    const pct = total > 0 ? Math.round((passed / total) * 100) : 0;
    const byCategory = {
      master: FEATURE_ITEMS.filter((i) => i.categoryKey === 'master').length,
      async: FEATURE_ITEMS.filter((i) => i.categoryKey === 'async').length,
      sync: FEATURE_ITEMS.filter((i) => i.categoryKey === 'sync').length,
      giga: FEATURE_ITEMS.filter((i) => i.categoryKey === 'giga').length,
      msg: FEATURE_ITEMS.filter((i) => i.categoryKey === 'msg').length,
      ai: FEATURE_ITEMS.filter((i) => i.categoryKey === 'ai').length,
    };
    return { total, passed, issue, pending, withMemo, pct, byCategory };
  }, [records]);

  const filteredItems = useMemo(() => {
    return FEATURE_ITEMS.filter((item) => {
      if (categoryFilter !== 'all' && item.categoryKey !== categoryFilter) return false;
      const st = records[item.id]?.status ?? 'pending';
      if (statusFilter !== 'all' && st !== statusFilter) return false;
      return true;
    });
  }, [categoryFilter, statusFilter, records]);

  const buildPlainTextReport = (): string => {
    const lines: string[] = [
      `PhotoTools Master & 拡張機能 動作確認メモ (${formatNowTimestamp()})`,
      `進捗: 確認OK ${stats.passed}/${stats.total}件 / 要再確認 ${stats.issue}件 / 未確認 ${stats.pending}件`,
      '================================================================',
      '',
    ];
    for (const item of FEATURE_ITEMS) {
      const rec = getRecord(item.id);
      const statusLabel =
        rec.status === 'passed' ? '[確認OK]' : rec.status === 'issue' ? '[要再確認]' : '[未確認]';
      lines.push(`${statusLabel} ${item.number}. ${item.title} (${item.categoryLabel})`);
      if (rec.updatedAt) {
        lines.push(`  更新日時: ${rec.updatedAt}`);
      }
      if (rec.memo.trim().length > 0) {
        lines.push(`  メモ: ${rec.memo.trim().replace(/\r?\n/g, ' / ')}`);
      }
      lines.push('');
    }
    return lines.join('\r\n');
  };

  const handleCopyReport = async () => {
    try {
      await navigator.clipboard.writeText(buildPlainTextReport());
      setCopiedReport(true);
      window.setTimeout(() => setCopiedReport(false), 2500);
    } catch {
      // ignore clipboard errors
    }
  };

  const handleDownloadReport = () => {
    const content = buildPlainTextReport();
    const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    const now = new Date();
    const pad = (n: number) => String(n).padStart(2, '0');
    a.href = url;
    a.download = `PhotoTools_確認メモ_${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}.txt`;
    document.body.appendChild(a);
    a.click();
    window.setTimeout(() => {
      a.remove();
      URL.revokeObjectURL(url);
    }, 5000);
  };

  const handleResetAll = () => {
    setRecords({});
    setConfirmingReset(false);
  };

  return (
    <div className="space-y-6">
      {/* Top Workspace Mode Bar */}
      <section className="bg-white border border-slate-200 p-5 space-y-4">
        <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-4">
          <div className="space-y-1">
            <h1 className="text-base font-bold text-slate-900">
              PhotoTools Master & 拡張ロードマップ機能 動作確認シート
            </h1>
            <p className="text-xs text-slate-600">
              実装済みの全{stats.total}機能を1つずつ実機で確認し、判定ステータスと気づき・エラー内容をメモできます（ブラウザに自動保存されます）。
            </p>
          </div>

          <div className="flex items-center gap-1 p-1 bg-slate-100 self-start shrink-0">
            <button
              type="button"
              onClick={() => setSubView('roadmap')}
              className={`px-3 py-1.5 text-xs font-medium whitespace-nowrap shrink-0 transition-colors ${
                subView === 'roadmap'
                  ? 'bg-white text-slate-900 font-semibold shadow-2xs'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              追加機能チェック・メモ ({stats.total}項目)
            </button>
            <button
              type="button"
              onClick={() => setSubView('setup')}
              className={`px-3 py-1.5 text-xs font-medium whitespace-nowrap shrink-0 transition-colors ${
                subView === 'setup'
                  ? 'bg-white text-slate-900 font-semibold shadow-2xs'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              展開・初期セットアップ手順
            </button>
          </div>
        </div>

        {subView === 'roadmap' && (
          <>
            {/* Progress & Export Strip */}
            <div className="pt-3 border-t border-slate-200 flex flex-col lg:flex-row lg:items-center justify-between gap-4">
              <div className="flex-1 space-y-2">
                <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-slate-600 font-mono tabular-nums">
                  <span className="font-semibold text-slate-900">
                    確認OK: {stats.passed} / {stats.total} ({stats.pct}%)
                  </span>
                  <span aria-hidden="true">·</span>
                  <span className="text-amber-700">要再確認: {stats.issue}</span>
                  <span aria-hidden="true">·</span>
                  <span>未確認: {stats.pending}</span>
                  <span aria-hidden="true">·</span>
                  <span>メモ記入済: {stats.withMemo}</span>
                </div>
                <div className="h-2 w-full bg-slate-100 overflow-hidden">
                  <div
                    className="h-full bg-emerald-600 transition-transform duration-150 origin-left"
                    style={{ transform: `scaleX(${stats.total > 0 ? stats.passed / stats.total : 0})` }}
                  />
                </div>
              </div>

              <div className="flex flex-wrap items-center gap-2 shrink-0">
                <button
                  type="button"
                  onClick={handleCopyReport}
                  className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium border border-slate-300 bg-white text-slate-800 hover:bg-slate-50 whitespace-nowrap shrink-0 transition-colors"
                >
                  {copiedReport ? (
                    <>
                      <Check className="w-3.5 h-3.5 text-emerald-600" />
                      <span>結果をコピーしました</span>
                    </>
                  ) : (
                    <>
                      <ClipboardCopy className="w-3.5 h-3.5 text-slate-500" />
                      <span>確認結果・メモをコピー</span>
                    </>
                  )}
                </button>

                <button
                  type="button"
                  onClick={handleDownloadReport}
                  className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium border border-slate-300 bg-white text-slate-800 hover:bg-slate-50 whitespace-nowrap shrink-0 transition-colors"
                >
                  <Download className="w-3.5 h-3.5 text-slate-500" />
                  <span>メモをTXT保存</span>
                </button>

                {!confirmingReset ? (
                  <button
                    type="button"
                    onClick={() => setConfirmingReset(true)}
                    className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium border border-slate-200 text-slate-600 hover:text-slate-900 hover:bg-slate-50 whitespace-nowrap shrink-0 transition-colors"
                  >
                    <RotateCcw className="w-3.5 h-3.5" />
                    <span>リセット</span>
                  </button>
                ) : (
                  <div className="inline-flex items-center gap-1.5">
                    <button
                      type="button"
                      onClick={handleResetAll}
                      className="px-2.5 py-1.5 text-xs font-semibold bg-red-600 text-white hover:bg-red-700 whitespace-nowrap shrink-0 transition-colors"
                    >
                      全消去する
                    </button>
                    <button
                      type="button"
                      onClick={() => setConfirmingReset(false)}
                      className="px-2.5 py-1.5 text-xs font-medium border border-slate-300 bg-white text-slate-700 hover:bg-slate-50 whitespace-nowrap shrink-0 transition-colors"
                    >
                      キャンセル
                    </button>
                  </div>
                )}
              </div>
            </div>

            {/* Category & Status Filters */}
            <div className="pt-3 border-t border-slate-200 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
              <div className="flex flex-wrap items-center gap-1">
                {(
                  [
                    { id: 'all', label: `全カテゴリ (${stats.total})` },
                    { id: 'master', label: `1. Master・設定・更新 (${stats.byCategory.master})` },
                    { id: 'async', label: `2. 非同期・MEGAログ (${stats.byCategory.async})` },
                    { id: 'sync', label: `3. フォルダ同期・X分離 (${stats.byCategory.sync})` },
                    { id: 'giga', label: `4. ギガファイル便 (${stats.byCategory.giga})` },
                    { id: 'msg', label: `5. 送付メッセージ (${stats.byCategory.msg})` },
                    { id: 'ai', label: `6. AIキャラ判定 (${stats.byCategory.ai})` },
                  ] as const
                ).map((cat) => (
                  <button
                    key={cat.id}
                    type="button"
                    onClick={() => setCategoryFilter(cat.id)}
                    className={`px-2.5 py-1 text-xs font-medium whitespace-nowrap shrink-0 transition-colors ${
                      categoryFilter === cat.id
                        ? 'bg-slate-900 text-white'
                        : 'bg-slate-100 text-slate-600 hover:text-slate-900'
                    }`}
                  >
                    {cat.label}
                  </button>
                ))}
              </div>

              <div className="flex items-center gap-1 self-start">
                {(
                  [
                    { id: 'all', label: 'すべて' },
                    { id: 'pending', label: '未確認のみ' },
                    { id: 'passed', label: '確認OK' },
                    { id: 'issue', label: '要再確認' },
                  ] as const
                ).map((st) => (
                  <button
                    key={st.id}
                    type="button"
                    onClick={() => setStatusFilter(st.id)}
                    className={`px-2.5 py-1 text-xs font-medium whitespace-nowrap shrink-0 border transition-colors ${
                      statusFilter === st.id
                        ? 'border-slate-900 bg-slate-900 text-white'
                        : 'border-slate-200 bg-white text-slate-600 hover:text-slate-900'
                    }`}
                  >
                    {st.label}
                  </button>
                ))}
              </div>
            </div>
          </>
        )}
      </section>

      {subView === 'roadmap' ? (
        filteredItems.length === 0 ? (
          <section className="bg-white border border-slate-200 p-8 text-center space-y-3">
            <p className="text-sm font-medium text-slate-800">
              現在の絞り込み条件に一致する確認項目はありません。
            </p>
            <button
              type="button"
              onClick={() => {
                setCategoryFilter('all');
                setStatusFilter('all');
              }}
              className="px-3.5 py-1.5 text-xs font-medium bg-slate-900 text-white hover:bg-slate-800 transition-colors"
            >
              フィルタを解除して全項目を表示
            </button>
          </section>
        ) : (
          <section className="bg-white border border-slate-200 divide-y divide-slate-200">
            {filteredItems.map((item) => {
              const rec = getRecord(item.id);
              return (
                <article key={item.id} className="p-5 space-y-4">
                  {/* Row 1: Title, Metadata & Status Selector */}
                  <div className="flex flex-col lg:flex-row lg:items-start justify-between gap-4">
                    <div className="space-y-1 min-w-0">
                      <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-slate-500">
                        <span className="font-mono font-semibold text-slate-700 tabular-nums">
                          項目 {item.number}
                        </span>
                        <span aria-hidden="true">·</span>
                        <span>{item.categoryLabel}</span>
                        <span aria-hidden="true">·</span>
                        <button
                          type="button"
                          onClick={() => onSelectFile(item.targetFile)}
                          className="inline-flex items-center gap-1 font-mono text-slate-700 hover:text-slate-950 underline underline-offset-2"
                        >
                          <FileCode2 className="w-3.5 h-3.5 shrink-0" />
                          <span>{item.targetFile}</span>
                        </button>
                        {rec.updatedAt && (
                          <>
                            <span aria-hidden="true">·</span>
                            <span className="font-mono tabular-nums">記録: {rec.updatedAt}</span>
                          </>
                        )}
                      </div>
                      <h2 className="text-sm font-bold text-slate-900">{item.title}</h2>
                    </div>

                    {/* Interactive Status Buttons */}
                    <div className="flex items-center gap-1.5 shrink-0 self-start">
                      <button
                        type="button"
                        onClick={() => handleStatusChange(item.id, 'pending')}
                        className={`inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium border whitespace-nowrap shrink-0 transition-colors ${
                          rec.status === 'pending'
                            ? 'border-slate-800 bg-slate-800 text-white'
                            : 'border-slate-200 bg-white text-slate-600 hover:text-slate-900'
                        }`}
                      >
                        <Circle className="w-3.5 h-3.5" />
                        <span>未確認</span>
                      </button>

                      <button
                        type="button"
                        onClick={() => handleStatusChange(item.id, 'passed')}
                        className={`inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium border whitespace-nowrap shrink-0 transition-colors ${
                          rec.status === 'passed'
                            ? 'border-emerald-700 bg-emerald-700 text-white'
                            : 'border-slate-200 bg-white text-slate-600 hover:text-emerald-800'
                        }`}
                      >
                        <CheckCircle2 className="w-3.5 h-3.5" />
                        <span>確認OK</span>
                      </button>

                      <button
                        type="button"
                        onClick={() => handleStatusChange(item.id, 'issue')}
                        className={`inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium border whitespace-nowrap shrink-0 transition-colors ${
                          rec.status === 'issue'
                            ? 'border-amber-700 bg-amber-700 text-white'
                            : 'border-slate-200 bg-white text-slate-600 hover:text-amber-800'
                        }`}
                      >
                        <AlertTriangle className="w-3.5 h-3.5" />
                        <span>要再確認</span>
                      </button>
                    </div>
                  </div>

                  {/* Row 2: Two-column Procedure + Memo */}
                  <div className="grid grid-cols-1 lg:grid-cols-12 gap-5 pt-1">
                    <div className="lg:col-span-7 space-y-2.5">
                      <div className="inline-flex items-center gap-2 px-2.5 py-1 bg-slate-950 text-slate-100 font-mono text-xs max-w-full">
                        <Terminal className="w-3.5 h-3.5 text-slate-400 shrink-0" />
                        <span className="truncate">{item.launchCommand}</span>
                      </div>

                      <div className="space-y-1">
                        <div className="text-xs font-semibold text-slate-800">確認手順:</div>
                        <ol className="list-decimal list-inside space-y-1 text-xs text-slate-700 leading-relaxed">
                          {item.steps.map((st, i) => (
                            <li key={i}>{st}</li>
                          ))}
                        </ol>
                      </div>

                      <div className="text-xs text-slate-600 leading-relaxed pt-0.5">
                        <span className="font-semibold text-slate-800">期待される動作: </span>
                        {item.expected}
                      </div>
                    </div>

                    <div className="lg:col-span-5 flex flex-col space-y-1.5">
                      <label
                        htmlFor={`memo-${item.id}`}
                        className="text-xs font-semibold text-slate-700 flex items-center justify-between"
                      >
                        <span>確認メモ（結果・気になった挙動・エラー内容など）</span>
                        {rec.memo.trim().length > 0 && (
                          <span className="font-normal text-[11px] text-emerald-700">自動保存済</span>
                        )}
                      </label>
                      <textarea
                        id={`memo-${item.id}`}
                        rows={4}
                        value={rec.memo}
                        onChange={(e) => handleMemoChange(item.id, e.target.value)}
                        placeholder="例: 正常に起動・表示された / 〇〇のボタンを押した時に△△になった 等"
                        className="w-full flex-1 px-3 py-2 text-xs text-slate-900 bg-slate-50 border border-slate-200 focus:bg-white focus:border-slate-900 focus:outline-none leading-relaxed resize-y"
                      />
                    </div>
                  </div>
                </article>
              );
            })}
          </section>
        )
      ) : (
        <section className="bg-white border border-slate-200">
          <div className="px-5 py-4 border-b border-slate-200">
            <h2 className="text-sm font-bold text-slate-900">Windows 実機への展開・初期セットアップ手順</h2>
            <p className="text-xs text-slate-500 mt-0.5">
              最新ZIPをダウンロード後、以下の手順で D:\PhotoTools\ へ展開・更新してから全{stats.total}項目の動作確認を行ってください。
            </p>
          </div>
          <div className="divide-y divide-slate-200">
            {SETUP_STEPS.map((s) => (
              <div key={s.step} className="p-5 flex flex-col md:flex-row gap-4">
                <div className="w-16 shrink-0">
                  <span className="font-mono text-xs font-bold text-slate-900 tabular-nums">
                    STEP {s.step}
                  </span>
                </div>
                <div className="flex-1 space-y-2">
                  <h3 className="text-sm font-semibold text-slate-900">{s.title}</h3>
                  <p className="text-xs text-slate-600 leading-relaxed">{s.detail}</p>
                  {s.command && (
                    <div className="inline-flex items-center gap-2 px-3 py-1.5 bg-slate-950 text-slate-100 font-mono text-xs">
                      <Terminal className="w-3.5 h-3.5 text-slate-400 shrink-0" />
                      <span>{s.command}</span>
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}
