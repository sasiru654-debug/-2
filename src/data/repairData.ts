export interface TestModuleSpec {
  id: string;
  name: string;
  scope: string;
}

export interface SettingsFieldSpec {
  section: 'Paths' | 'ArchivePeriod' | 'Extensions' | 'Mega';
  key: string;
  label: string;
  hint: string;
  defaultValue: string;
}

export interface RepairHistoryItem {
  rev: string;
  phase: string;
  target: string;
  summary: string;
  files: string[];
  status: '検証済' | '確認待ち' | '確認・調整中';
}

export const REPAIR_HISTORY: RepairHistoryItem[] = [
  {
    rev: 'REV-48',
    phase: '単独起動の PhotoTools 自動更新支援ツール（PhotoToolsUpdater.ps1 / StartPhotoToolsUpdater.vbs）の新規実装',
    target: 'ZIPダウンロード後の解凍・上書き・ブロック解除・不要ファイル整理を自動化する、本体非依存の単独更新支援 GUI ツールを新規作成。',
    summary:
      '① 完全自己完結型の WinForms GUI ツール updater/PhotoToolsUpdater.ps1 および黒画面ゼロ・ASCII専用ランチャー updater/StartPhotoToolsUpdater.vbs を新規実装（本体や common\\*.ps1 非依存のため別フォルダへ単体コピーしても動作）。② ブラウザ連番 (1)(2)... を同一ファイル名として認識し更新日時最新のZIPを自動選択する「選択」機能、GitHub リポジトリからの最新ブランチZIP自動取得（公開／PAT非公開両対応）、ZIP内パッケージルート自動判定（PhotoTools.zip / GitHub archive 両対応）、更新前の自動バックアップ（backup\\ 直近5世代保持）、settings.ini の既存値維持＋新規キー追記マージ／完全スキップ切替、data\\・backup\\・updater_settings.json 完全保護、自動ブロック解除（Unblock-File）、および不要ファイルのチェックボックス確認削除ダイアログを搭載。',
    files: [
      'updater/PhotoToolsUpdater.ps1',
      'updater/StartPhotoToolsUpdater.vbs',
      'src/components/VerificationChecklistTab.tsx',
      'src/data/repairData.ts',
    ],
    status: '確認待ち',
  },
  {
    rev: 'REV-47',
    phase: '.NET 10（VB.NET）移行設計案の更新：ギガファイル便送信ツールの単独 EXE 分離',
    target: 'ギガファイル便送信を単独でも利用できるよう、PhotoTools 本体（PhotoTools.exe）とは独立した実行プロジェクト（PhotoTools.GigaFile → GigaFileUploader.exe）へ分離する設計へ改訂。',
    summary:
      'VbNetMigrationPlanSection.tsx のソリューション構成・CLI起動ルーティング・Phase 3 モジュール対応表を更新し、PhotoTools.GigaFile（GigaFileUploader.exe）を独立プロジェクトとして定義。PhotoTools 本体や settings.ini が無い環境でも汎用送信でき、対象フォルダに 写真情報.txt がある場合のみ自動命名・URL自動記録が連動する設計へ整理。',
    files: [
      'src/components/VbNetMigrationPlanSection.tsx',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-46',
    phase: '.NET 10（VB.NET / Windows Forms）移行設計・構成案の策定とプレビュー掲載',
    target: '現行 PowerShell 版（phototools/）には一切触れず、並行検討用の .NET 10（VB.NET）移行設計書（ソリューション構成・単一EXE起動ルーティング・データ互換方針・3段階移行ロードマップ）を作成。',
    summary:
      '① Core / App / Tests の3層分離ソリューション構成（PhotoTools.Core / PhotoTools.App / PhotoTools.Core.Tests）、BAT・VBS・黒画面を撤廃する単一 PhotoTools.exe のCLI引数ルーティング設計、settings.ini・写真情報.txt・履歴JSON・Excel台帳（OpenXML）の100%データ互換方針、およびPhase 1〜3の段階的移行対応表を VbNetMigrationPlanSection.tsx として実装。② 「全体仕様・図解」タブ上部に切替ボタンを追加し、現行仕様・フローチャートと .NET 10 (VB.NET) 移行設計案を切り替え閲覧可能に統合。',
    files: [
      'src/components/VbNetMigrationPlanSection.tsx',
      'src/components/SystemSpecTab.tsx',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-45',
    phase: '修復レポートの整理（不具合解析・修復一覧の削除）および変更履歴 REV-41〜REV-45 の最新化',
    target: '「修復レポート」タブから不要な「不具合解析・修復一覧」を削除し、修正箇所・変更履歴を最新リビジョンまで完全同期。',
    summary:
      '① 修復レポート画面（RepairReportTab.tsx）から「不具合解析・修復一覧」セクションおよび未使用の REPAIR_ITEMS データを削除し、キーワード絞り込み検索ボックスを「修正箇所・変更履歴」ヘッダーへ移設。② REV-40 で停止していた変更履歴に REV-41〜REV-45 を追記し、レポート上部のリビジョン表記も最新履歴へ自動連動するよう改修。',
    files: [
      'src/components/RepairReportTab.tsx',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-44',
    phase: 'ツール関係性フローチャート図解の実装および配布フォルダ名の phototools への統一',
    target: 'プレビュー「全体仕様・図解」タブに全ツールの連携関係を示すインタラクティブなフローチャートを追加し、作業・配布フォルダ名を phototools_fixed から phototools へ統一。',
    summary:
      '① 5層構造のSVGフローチャート（ToolFlowchartDiagram.tsx）を新規実装し、用途別フォーカス切替（全体・日常撮影〜アーカイブ・Master/設定/テスト・MEGA/ギガファイル便/台帳）、ノード選択時の呼び出し元／呼び出し先ハイライト、および対象ソースコードへの直接ジャンプ機能を追加。② フォルダ名を phototools_fixed から phototools へリネームし、server.ts のAPIルート・ZIPファイル名（PhotoTools.zip）・各種参照および不要スクリプトを整理。',
    files: [
      'src/components/ToolFlowchartDiagram.tsx',
      'src/components/SystemSpecTab.tsx',
      'src/App.tsx',
      'server.ts',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-43',
    phase: '設定ファイル編集GUI（SettingsEditor.ps1）の実装および PhotoTools Master からの起動連携',
    target: 'settings.ini および各種履歴JSONを画面上から安全に編集できるGUIツールを新規作成し、Master画面からワンクリックで呼び出せるよう統合。',
    summary:
      '① common/ConfigHelper.ps1 に settings.ini 保存関数 Save-PhotoToolsSettingsIni を追加。② 3タブ構成の WinForms 設定編集画面（editor/SettingsEditor.ps1：フォルダ／ファイル参照＋存在チェック付きパス設定、アーカイブ期分け・拡張子・MEGA設定、settings.ini／scene_history.json／x_history.json 直接編集＋OS登録ランチャー）を実装。③ PhotoToolsMaster.ps1 ヘッダーに「設定編集 (settings.ini 等)」ボタンを配置し、編集終了後に最新設定を即時再読込するよう連携。テストおよび確認項目（#17）も追加。',
    files: [
      'common/ConfigHelper.ps1',
      'editor/SettingsEditor.ps1',
      'PhotoToolsMaster.ps1',
      'tests/ModuleTestCases.ps1',
      'src/components/VerificationChecklistTab.tsx',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-42',
    phase: '開発サーバーのプレビューアクセス許可設定（Vite 8 allowedHosts 対応）',
    target: 'Vite 8 環境におけるプレビューURLからのアクセスブロック（HTTP 403）を解消。',
    summary:
      'vite.config.ts（allowedHosts: true as const）および server.ts（allowedHosts: true）を設定し、プレビュー用ホストからのアクセスが正常に HTTP 200 で応答するよう修正。',
    files: [
      'vite.config.ts',
      'server.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-41',
    phase: '1日1人撮影時の「日付フォルダ直下 写真情報.txt」対応および周辺不具合の修正',
    target: 'サブフォルダを切らずに1日1人分を撮影した場合に、日付フォルダ（YYYY_MM_DD）直下へ直接 写真情報.txt を設定・運用できるよう全面対応。',
    summary:
      '① DailyWorkflow.ps1・PhotoInfoEditor.ps1・OpenFromProtocol.ps1・PhotoToolsMaster.ps1・SyncExcelFromTxt.ps1・ExcelHelper.ps1・send_to_gigafile.ps1 を拡張し、日付フォルダ直下の 写真情報.txt の編集・ツリー表示・Excel台帳同期・ギガファイル便送信に対応。② あわせて WorkflowStep3Helper.ps1 のメタデータtxt誤移動除外、ExcelHelper.ps1 の RelPath 日付二重化と Persons プロパティ判定バグ、send_to_gigafile.ps1 のファイル名生成時の日付重複を修正し、テストおよび確認項目（#16）を追加。',
    files: [
      'workflow/DailyWorkflow.ps1',
      'editor/PhotoInfoEditor.ps1',
      'common/OpenFromProtocol.ps1',
      'common/ExcelHelper.ps1',
      'workflow/SyncExcelFromTxt.ps1',
      'PhotoToolsMaster.ps1',
      'gigafile/send_to_gigafile.ps1',
      'workflow/WorkflowStep3Helper.ps1',
      'tests/ModuleTestCases.ps1',
      'src/components/VerificationChecklistTab.tsx',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-40',
    phase: 'PhotoTools Master 総合マスター管理ツール（PhotoToolsMaster.ps1 & StartPhotoToolsMaster.bat）の実装完了',
    target: '相談終了に伴い、上位マスター管理ツール「PhotoTools Master」のバックエンド実ファイル（PhotoToolsMaster.ps1）および専用ランチャー（StartPhotoToolsMaster.bat）を新規実装。',
    summary:
      '① 独立したマスター司令塔として動作する PhotoTools Master（PhotoToolsMaster.ps1）を実装。作業用・完了後・アーカイブのタブ切替式オンデマンドスキャン、日付スコープ選択からの DailyWorkflow 起動、複数ルート間の不整合診断チェッカー、および ExcelHelper.ps1 による台帳セルフヒーリング（自動補完・仮登録行の自動正規化）を完全網羅。② 起動用バッチ StartPhotoToolsMaster.bat を追加。',
    files: [
      'phototools/PhotoToolsMaster.ps1',
      'phototools/StartPhotoToolsMaster.bat',
      'src/components/SystemSpecTab.tsx',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-39',
    phase: '「取込後」「現像後」の子フォルダ名変更に対応する「子フォルダ名・構造の同期化（リネーム追従）」機能の設計仕様策定・追加',
    target: 'Step 2 以降にモデル名やスタジオ名等に合わせてサブフォルダ名（01 ➔ 01_モデル名等）を変更した際、取込後・現像後・RAWフォルダ間で名前を自動で同期・リネームする仕組みの設計仕様を PhotoTools Master & 将来拡張ロードマップへ統合。',
    summary:
      '① ステップ2以降の運用において、取込後または現像後フォルダ側で子フォルダ名が変更された場合に、他のルート（RAWフォルダやもう片方のフォルダ）の対応サブフォルダ名も自動追従して一括リネーム・同期する「子フォルダ名・構造の同期化（リネーム追従）」の設計仕様を策定。② プレフィックス番号（01, 02...）または内部マニフェストによる紐づけにより、Step 3 の自動振分や Step 4 の統合比較がフォルダ名変更後も一切破綻しない堅牢な設計へ統合。',
    files: [
      'src/components/SystemSpecTab.tsx',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-38',
    phase: 'ギガファイル便ツールのカスタムファイル名入力追加および今後の検討・保留機能（写真情報.txt連携・子フォルダ一括リスト出力）の仕様策定・記載',
    target: 'send_to_gigafile.ps1 に出力ファイル名（任意）入力テキストボックスを実装。さらにユーザー要望に基づく今後の検討・保留機能（写真情報.txtからの命名規則自動化、子フォルダ一括分割アップロード＆リスト出力、写真情報.txtへのURL自動記録、チェックボックスによる有効無効選択）を仕様書（SystemSpecTab.tsx）および履歴レポートへ明記。',
    summary:
      '① ギガファイル便自動アップロードツール（send_to_gigafile.ps1）に任意のカスタムファイル名入力欄を追加し、入力時はその名前（.zip）でアップロード・ZIP生成を行う仕様へ拡張。② ユーザー様よりご提案いただいた「写真情報.txt連携による自動命名（日付_イベント名_名前_キャラ名）」「子フォルダごとの一括分割＆リスト出力」「写真情報.txtへのURL自動記録」「各機能のチェックボックス選択式」についての将来的な検討・保留仕様を SystemSpecTab.tsx および repairData.ts に正式記載。',
    files: [
      'phototools/gigafile/send_to_gigafile.ps1',
      'src/components/SystemSpecTab.tsx',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-37',
    phase: 'Step4 フォルダ別ファイル比較ダイアログへの取込元・現像側ファイルパス表示および「フォルダを開く」ボタンの追加',
    target: 'WorkflowStep4Helper.ps1 の Show-WorkflowStep4Dialog に、取込元フォルダフルパス（$ImportDateFolder）および現像側フォルダフルパス（$devDir）の表示ラベルと、その右側にそれぞれのフォルダをエクスプローラで開くボタン（「取込元を開く」「現像側を開く」）を追加。',
    summary:
      '① Step4 ダイアログの上部に「取込元フォルダ：」および「現像側フォルダ：」のフルパスラベルを配置。② 各パスの右隣に「取込元を開く」「現像側を開く」ボタンを配置し、ワンクリックで該当フォルダ（存在しない場合は自動作成して）をエクスプローラでオープンできるように改善。③ TreeView や他のコントロールの配置座標も自動調整。',
    files: [
      'phototools/workflow/WorkflowStep4Helper.ps1',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-36',
    phase: 'Step4 キャノンカメラ命名規則（8文字ベース名一致）対応および全 .ps1 スクリプトの UTF-8 BOM + CRLF 再正規化',
    target: 'WorkflowStep4Helper.ps1 の Get-CoreImageName 関数を拡張し、キャノンカメラのファイル命名規則（例: IMG_2650.JPG とカメラ内現像の IMG_2650_1.JPG 等、先頭8文字が一致するものを同一写真とみなす）に対応。また phototools 配下の全 .ps1 スクリプトファイルを UTF-8 BOM付き + CRLF へ一括再正規化し、モジバケおよびパーサエラーを完全解消。',
    summary:
      '① キャノンカメラの場合、元画像が IMG_2650.JPG、カメラ内現像によるコピーが IMG_2650_1.JPG のように連番が付くため、WorkflowStep4Helper.ps1 の Get-CoreImageName で先頭8文字（Length >= 8 の場合 Substring(0, 8)）をベース写真名として正規化するように改善。これにより「重複なし」となってしまっていたケースを解消し、正しく現像済み重複として一括削除対象に認定。② 全 .ps1 ファイルの文字コードを UTF-8 BOM（\uFEFF）＋ CRLF（\r\n）に再エンコードし、ログやパーサにおけるモジバケ・構文エラーの懸念を完全に払拭。',
    files: [
      'phototools/workflow/WorkflowStep4Helper.ps1',
      'src/components/SystemSpecTab.tsx',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-35',
    phase: 'Step3 監視モードにおける保留ファイルの重複チェック抑制および保留理由の明記',
    target: 'WorkflowStep3Helper.ps1 の FileCache に保留ステータスと理由（RAW参照なし、同名ファイル存在など）を保持させ、未変更ファイルの重複チェック・ログスパムを完全に抑制。また保留リスト出力時に詳細な保留理由を記載。',
    summary:
      '① 監視モード時、未変更のまま保留となっているファイルが1秒ごとに繰り返しチェック・ログ出力されてしまう問題を解消するため、FileCache にステータス（Pending/Sorted）および保留理由をキャッシュし、変更がない限り再チェックをスキップ。② 保留リスト出力時に具体的な保留理由（「RAW参照なし」や「移送先に同名ファイルが存在するためスキップ（上書きオフ）」等）を明確に記載。',
    files: [
      'workflow/WorkflowStep3Helper.ps1',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-34',
    phase: 'Step3 現像済みJPEG自動振分における「同名ファイル上書き」チェックボックスの追加および起動時監視OFFのデフォルト化',
    target: 'WorkflowStep3Helper.ps1 に「移動先に同名ファイルがある場合上書きする」チェックボックス（$chkOverwrite）を追加し、ダイアログ起動時のデフォルト状態を「監視 OFF」に変更',
    summary:
      '① Step3 進捗GUI内に「移動先に同名ファイルがある場合上書きする」チェックボックスを配置（デフォルト有効）。② チェック状態に応じて自動/手動振分時の上書き有無を切り替え可能に。③ ダイアログ起動時のデフォルト初期状態を「監視 OFF」に変更し、誤動作を防止。',
    files: [
      'workflow/WorkflowStep3Helper.ps1',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-33',
    phase: 'Step3 現像済みJPEG自動振分における既存ファイル上書き移動および保留（未振分）ファイル管理機能の実装',
    target: 'WorkflowStep3Helper.ps1 の振分処理で移動先にファイルが存在する場合も -Force で強制上書きするように変更し、自動/手動振分時の未振分ファイルを「保留」として1ファイル1行でログ出力・解除管理',
    summary:
      '① 移送先に既にファイルが存在する場合でもスキップせず -Force で強制上書き移動するように改善。② 自動振分（監視モード）時、RAW参照が見つからず未振分となったファイルを「保留」として蓄積。③ 「監視 OFF」ボタン押下時に保留されていたすべてのファイルを1ファイル1行ずつ詳細にログ表示してクリア。④ 「今すぐ振分を実行」時も同様に処理完了後に未振分・保留ファイルを1ファイル1行ずつログ出力。',
    files: [
      'workflow/WorkflowStep3Helper.ps1',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-32',
    phase: 'Step3 現像済みJPEG自動振分における詳細チェックログおよびフルパス表示の追加',
    target: 'WorkflowStep3Helper.ps1 の自動振分・監視ロジックに個別ファイルのRAW参照検索結果・移動元→移送先詳細ログおよびダイアログ上部のフルパス表示を追加',
    summary:
      '① Step3 ダイアログ上部の「対象日付フォルダ」の下に「振分対象フォルダフルパス：」および「比較先RAWフォルダフルパス：」の2行を追加。② JPGファイルごとにRAW参照の有無や発見場所を詳細にログ出力。③ 移動実行時に「対象ファイル：（ファイル名）　移動元：（移動元フォルダ）→移送先：（移送先フォルダ）」形式（日付以降の相対パス表記）でウィンドウ内ログに明確に出力。',
    files: [
      'workflow/WorkflowStep3Helper.ps1',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-31',
    phase: 'Step4 フォルダ別ファイル比較・統合リスト表示 ＆ 現像済み取込ファイル一括削除機能の刷新',
    target: 'WorkflowStep4Helper.ps1 の TreeView 比較表示を「現像側 vs 取込元」の統合行形式（現像側：ファイル名 ➔ 取込元：ファイル名）へ高度化',
    summary:
      '① 左右別々に分かれていたツリーノードを、ファイル名一致で「現像側：ファイル名 ➔ 取込元：ファイル名」形式へ統合（片側のみの場合は「なし」と表示）。② ファイル名の最後に「_1」等の連番やスペースが伴う場合もコア名が同一なら同一ファイルとみなす正規化（Get-CoreImageName）を導入。③ 全体集計および各フォルダ単位での現像側・取込元・重複件数を明示。④ 現像済み重複判定となった取込元側ファイルのみを一括削除可能とし、MessageBox の文字列引数による System.Object[] エラーを Show-MsgBox ラッパーにより完全解消。',
    files: [
      'workflow/WorkflowStep4Helper.ps1',
      'common/LogHelper.ps1',
      'workflow/DailyWorkflow.ps1',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-30',
    phase: 'Step4 重複JPG削除ダイアログの「フォルダ別ツリー比較（現像側 vs 取込元）」への高度化',
    target: 'WorkflowStep4Helper.ps1 に TreeView 比較表示（現像側ファイル群 ＆ 取込元ファイル群の対比・重複自動チェック）を実装',
    summary:
      '① Step4（重複JPG削除）のダイアログを従来のシンプルリストから、フォルダごとの「TreeView 比較表示」へ大幅アップグレード。② 各フォルダ階層の下に「[現像側]」ファイル群（現像済み）と「[取込元]」ファイル群（取込データ）を並べて表示。③ 現像側とファイル名が一致する重複JPGは取込元側で自動的にチェックボックスがオンになり、ワンクリックで重複する取込元ファイルを安全に選択削除可能。',
    files: [
      'workflow/WorkflowStep4Helper.ps1',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-29',
    phase: 'Step3 実行成功確認',
    target: 'ユーザーによる実機での Step3（GUI・1秒監視モード・移動ファイルログ表示・ON/OFFボタン）の正常動作確認',
    summary:
      '実機にて DailyWorkflow の Step3（現像後自動振分GUI・1秒監視モード・個別ON/OFFボタン・リアルタイム移動ログ表示）がエラーなく完全に正常動作することを確認。',
    files: [
      'workflow/WorkflowStep3Helper.ps1',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-28',
    phase: 'Step3 監視モード実行中における移動ファイル詳細のウィンドウ内リアルタイムログ表示の実装',
    target: 'WorkflowStep3Helper.ps1 の1秒監視タイマーの Invoke-WorkflowStep3 呼び出しに LogCallback ($script:AddLog) を連携',
    summary:
      'Step3 の1秒自動振分タイマー処理（監視モード）において、これまで `$null` を渡して抑制していたログコールバックを `$script:AddLog` へ変更。これにより、監視モード中の1秒おきの自動振分によってファイルが移動された際にも、移動したファイル名や完了件数がウィンドウ内の進捗ログ（ListBox）へリアルタイムで表示されるように改善。',
    files: [
      'workflow/WorkflowStep3Helper.ps1',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-27',
    phase: 'Step3 1秒おき自動振分・個別「監視ON」「監視OFF」ボタン（状態による有効/無効制御）の実装',
    target: 'WorkflowStep3Helper.ps1 の監視タイマーを1秒おきの自動振分実行に刷新し、個別ON/OFFボタンと排他制御を追加',
    summary:
      '① Step3 進捗GUI内に個別の「監視 ON」ボタンと「監視 OFF」ボタンを配置。② 状態に応じてアクティブな方のボタンを無効化（Enabled = $false）し、直感的なON/OFF状態を明示。③ 監視モードON時は1秒ごとに定期的に自動振分処理（Invoke-WorkflowStep3）を実行し、状態切り替え時および振分実行時はウィンドウ内ログリストへリアルタイムにフィードバック出力。',
    files: [
      'workflow/WorkflowStep3Helper.ps1',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-26',
    phase: 'Step3 監視モードのボタン式 ON/OFF 切替（1秒間隔監視）およびログ通知の実装',
    target: 'WorkflowStep3Helper.ps1 に監視モード切り替えボタンを追加し、1秒タイマー（1000ms）とウィンドウ内ログ表示を実装',
    summary:
      '① Step3 進捗GUI内に「監視モード: ON / OFF」を切り替えるトグルボタンを配置。② 監視間隔を1秒単位（1000ms）へ設定し、新着ファイルを高速に検知。③ 監視モードの有効化・無効化（ON/OFF）が切り替わった際に、ウィンドウ内の進捗ログ（ListBox）へ状態変更メッセージがリアルタイムで表示されるよう実装。',
    files: [
      'workflow/WorkflowStep3Helper.ps1',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-25',
    phase: 'PowerShell 5.1 BeginInvoke デリゲート構文エラーの解消',
    target: 'WorkflowStep3Helper.ps1 の BeginInvoke 呼び出しを汎用非ジェネリック [Action] デリゲートへ修正',
    summary:
      'Step3 GUI 起動時に発生していた BeginInvoke のジェネリック構文エラー（「関数パラメータ一覧に \")\" が存在しません」）を解消するため、WorkflowStep3Helper.ps1 内の UI スレッドディスパッチ処理を PowerShell 5.1 完全互換の [Action] デリゲート呼び出しへ修正。',
    files: [
      'workflow/WorkflowStep3Helper.ps1',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-24',
    phase: 'Step3 現像後振分 の専用GUI化・進捗リスト表示・監視モード（Watch Mode）の実装',
    target: 'WorkflowStep3Helper.ps1 に Show-WorkflowStep3Dialog GUI（リアルタイムログ表示・監視モードトグル）を追加',
    summary:
      '① Step3（現像済みJPEG自動振分）を実行した際に、コンソール処理ではなく専用の進捗確認GUI（Show-WorkflowStep3Dialog）が起動するよう改修。② GUI内には振分・監視の進捗がリアルタイムで流れるスクロール対応ログリスト（ListBox）を配置。③ ファイルシステム監視（FileSystemWatcher）による「ファイル監視モード」を有効化し、現像後フォルダに新着JPEG画像が追加された際に自動検知してリアルタイムに自動振分を実行する機能を追加。',
    files: [
      'workflow/WorkflowStep3Helper.ps1',
      'workflow/DailyWorkflow.ps1',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-23',
    phase: 'Step2 実行成功確認',
    target: 'ユーザーによる実機での Step2（RAW複製移動）の正常動作確認',
    summary:
      '実機にて DailyWorkflow の Step2（RAW複製移動）がエラーなく正常に完了したことを確認。',
    files: [
      'workflow/WorkflowStep2Helper.ps1',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-22',
    phase: 'Step1 実行成功確認・エクセルファイル確認フェーズへ移行',
    target: 'ユーザーによる実機での Step1 仕分けフォルダ作成の正常動作確認',
    summary:
      '実機にて DailyWorkflow の Step1（仕分けフォルダ作成）がエラーなく正常に完了したことを確認。次はご要望の「エクセルファイルの確認」フェーズへ移行。',
    files: [
      'workflow/DailyWorkflow.ps1',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-21',
    phase: 'GUI起動時の黒いコマンド画面（黒い枠）の完全非表示化',
    target: 'StartDailyWorkflow.bat および MakePhotoInfo.bat を LaunchHidden.vbs（wscript経由・STA+Hidden）へ移行',
    summary:
      'DailyWorkflow 起動時に黒いコンソール枠（コマンドプロンプト画面）が残留していた問題に対し、既存の LaunchHidden.vbs（wscript.exe 経由で -STA および -WindowStyle Hidden を付与して非表示起動するVBScriptヘルパー）を経由するようバッチランチャーを修正。これにより、バックグラウンドでの黒い枠の残留を完全に解消しつつ、WinForms 必須の -STA スレッドモデルを維持。',
    files: [
      'StartDailyWorkflow.bat',
      'MakePhotoInfo.bat',
      'common/LaunchHidden.vbs',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-20',
    phase: 'DailyWorkflow パス判定時の正規表現エスケープエラー解消',
    target: 'DailyWorkflow.ps1 の -imatch 文字列リトルのバックスラッシュ不正エスケープ（\写 等）を Test-IsSameOrSubPath および -like へ変更',
    summary:
      'DailyWorkflow.ps1 起動時に発生していた「認識されないエスケープ シーケンス \\写 です」エラー（PowerShell の -imatch がバックラッシュを含むパス文字列 "J:\\写真2\\現像後" を正規表現として誤解釈し不正エスケープ扱いしていた問題）を解消するため、当該箇所を Test-IsSameOrSubPath 関数および -like 演算子による安全なパス比較へ全面修正。',
    files: [
      'workflow/DailyWorkflow.ps1',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-19',
    phase: '全 .ps1 / .ini ファイルの UTF-8 BOM付き + CRLF 再正規化（構文エラー・文字化け完全解消）',
    target: 'phototools 配下の全スクリプトファイルの文字コード・改行コード一括正規化',
    summary:
      'DailyWorkflow.ps1 編集時に発生した文字コードの不一致による PowerShell 5.1 パーサ構文エラー（「メソッド呼び出し内に \")\" が存在しません」および日本語文字化け）を解消するため、phototools 配下のすべての .ps1 および .ini ファイルを明示的な UTF-8 BOM（\\uFEFF）付き ＋ CRLF（\\r\\n）へ一括再正規化。これにより TestManager によるテストスイートも全て正常にパス。',
    files: [
      'workflow/DailyWorkflow.ps1',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-18',
    phase: 'PowerShell 5.1 WinForms 必須 -STA スレッドモデルの導入とサイレント終了対策',
    target: '全バッチランチャー（.bat）への -STA フラグ追加および pause 追加',
    summary:
      '① Windows PowerShell 5.1 環境での Windows Forms GUI（DailyWorkflow / PhotoInfoEditor 等）起動時にマルチスレッドアパートメント（MTA）モードによるサイレント終了（ログもエラーも出ずに即終了）が発生していた原因を特定し、全バッチランチャー（StartDailyWorkflow.bat 等）に -STA （Single Threaded Apartment）フラグを明示追加。② バッチ末尾に pause を追加し、万一のエラー時にもコマンドプロンプトが保持されてエラー内容や出力ログを確認できるように改善。',
    files: [
      'StartDailyWorkflow.bat',
      'SyncExcelFromTxt.bat',
      'RunTestManager.bat',
      'MakePhotoInfo.bat',
      'RegisterContextMenu.bat',
      'RegisterProtocol.bat',
      'UnblockFiles.bat',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-17',
    phase: 'DailyWorkflow 起動時サイレント終了防止・例外ハンドリング強化',
    target: 'DailyWorkflow.ps1 グローバル try-catch ブロック実装（起動時エラーのダイアログ表示化）',
    summary:
      '① DailyWorkflow.ps1 の全初期化・起動プロセスをグローバル try-catch で包括し、万一のパス解決・Config読込・WinForms起動時の例外発生時にもスクリプトがサイレント終了（何も表示されず終了）せず、エラーメッセージ・発生行番号・スタックトレースが詳細にポップアップ表示されるよう改善。② パス解決フォールバックを強化。',
    files: [
      'workflow/DailyWorkflow.ps1',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-16',
    phase: '実機表示改善・GUIかぶり解消＆RAWフォルダ状態同期完了',
    target: 'DailyWorkflow GUI 垂直座標の再配置（かぶり完全解消）、TxtRawFolder 状態同期実装',
    summary:
      '① DailyWorkflow.ps1 のコントロール垂直座標（対象日付 Y=12、カメラ取り込み元 Y=44、RAWフォルダ Y=76、現像後フォルダ Y=108、バッジ Y=140、シーン設定 Y=166、ツリー Y=310、アクションボタン Y=518、Stepボタン Y=558、ログ Y=604）を完全に再計算し、表示かぶりや項目消失を完全解消。② Refresh-LinkedFoldersUIState 内に TxtRawFolder の状態反映（実在時は実パス、未存在時は削減済メッセージ）を実装。③ 修正進捗レポート（repairData.ts）へ進捗を常時明記。',
    files: [
      'workflow/DailyWorkflow.ps1',
      'src/data/repairData.ts',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-15',
    phase: '実機表示改善・RAW探索ルーティング最適化',
    target: 'DailyWorkflow GUI 座標調整（表示かぶり解消）、変更ボタン撤去＆RAWフォルダ常時表示、現像後パス連動RAW探索切替',
    summary:
      '① DailyWorkflow.ps1 のコントロール配置座標を調整し、対象日付ヘッダーとカメラ取り込み元テキストボックスの表示かぶりを完全解消。② 不要となった「取込元変更…」「現像後変更…」ボタンを撤去し、新たに「RAWフォルダ」表示欄（TxtRawFolder）を追加。③ 現像後フォルダのパス（G:\写真\現像後 vs J:\写真2\現像後）に応じて、RAWデータの探索先（H:\写真作業用\作業用RAW または G:\写真raw vs L:\ / RawArchiveRoot）を自動切り替えるスマート探索ロジックを実装。',
    files: [
      'workflow/DailyWorkflow.ps1',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-14',
    phase: '新規改修・テスト強化・実機確認完了',
    target: 'RawSaveRoot2・ImportArchiveRoot 導入、Excelハイパーリンク化、テストログ自動保存、ZIPタイムスタンプ、全.ps1 UTF-8 BOM化',
    summary:
      '① RawSaveRoot2（H:\\写真作業用\\作業用RAW）および ImportArchiveRoot（J:\\写真2\\eos）を ConfigHelper / settings.ini に完全統合し仕分け元に応じた動的切替を実装。② Excel管理台帳（写真管理一覧.xlsx）の「取込フォルダ」「RAWフォルダ」「現像後フォルダ」列を通常・アーカイブ実在パスに基づくハイパーリンク式へ対応。③ ZIPダウンロードに発行日時（PhotoTools_Fixed_YYYYMMDD_HHMMSS.zip）を自動付与。④ TestManager.ps1 実行時に test_run_*.log / test_error_*.log を data\\logs\\ へ自動保存。⑤ 全 .ps1 ファイルを UTF-8 BOM付き + CRLF へ再エンコードし PowerShell 5.1 パーサ構文エラーを完全解消。',
    files: [
      'common/ConfigHelper.ps1',
      'common/ExcelHelper.ps1',
      'workflow/WorkflowStep2Helper.ps1',
      'workflow/WorkflowStep5Helper.ps1',
      'tests/TestManager.ps1',
      'server.ts',
      'settings.ini',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-13',
    phase: '新規改修・実機確認完了（DailyWorkflow）',
    target: '取込元・現像後の両フォルダ選択＆日付自動紐づけ／データ削減（取込・RAW無し）対応',
    summary:
      'DailyWorkflow の画面上部で「カメラ取り込み元」と「現像後フォルダ」を両方個別に選択・表示できるよう改修（同一日付キー YYYY-MM-DD による自動紐づけ）。TreeView による日付階層表示、scene.txt A/Bパターン設定、ダブルクリックでの被写体プロパティ起動、および取込・RAWデータが存在しない削減環境下でも現像後基準で安全に動作するフォールバックを実装。',
    files: [
      'workflow/DailyWorkflow.ps1',
      'workflow/WorkflowStep3Helper.ps1',
      'workflow/WorkflowStep4Helper.ps1',
      'workflow/WorkflowStep5Helper.ps1',
      'common/PhotoEditorLogic.ps1',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-12',
    phase: '実機確認完了（PhotoInfoEditor）',
    target: 'X名前取得の StrictMode .Count 対策＆デバッグファイル検証・画面直接表示',
    summary:
      'Set-StrictMode -Version Latest 下で配列/スカラー混在や非コレクション参照時に発生していた「プロパティ Count が見つかりません」エラー対策として、PhotoInfoEditor（Ensure-PersonsList 導入・RelatedFolders / RemainingArgs の @(...).Count 統一）、XHelper / SceneHelper / PhotoInfoHelper / PhotoEditorLogic の全配列 .Count・IDictionary 判定を全面補強。併せて LogHelper にディレクトリ強制生成・書込実在チェック（[System.IO.File]::Exists）および %TEMP%\\PhotoTools_logs フォールバックを追加し、さらにエラー発生時はログファイルを開く前でも原因箇所が即特定できるよう「発生箇所（ファイル:行番号）・コード・スタック」をエラーダイアログ本体へ直接表示するよう改善。',
    files: [
      'common/LogHelper.ps1',
      'common/XHelper.ps1',
      'common/SceneHelper.ps1',
      'common/PhotoInfoHelper.ps1',
      'common/PhotoEditorLogic.ps1',
      'editor/PhotoInfoEditor.ps1',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-11',
    phase: '実機確認完了（DailyWorkflow / PhotoInfoEditor）',
    target: 'scene.txt 2パターン対応・PhotoInfoEditor ReadOnly化・DailyWorkflow 階層TreeView化 & x_history自動生成',
    summary:
      '① SceneHelper / PhotoEditorLogic：深階層サブフォルダからも日付直下（パターンA）または子フォルダ直下（パターンB）の scene.txt のみを参照するよう修正（エディタ保存時の自動 scene.txt 作成を廃止）。② PhotoInfoEditor：イベント/併せ/スタジオ/場所欄を ReadOnly（選択コピー可・入力不可）へ変更し、scene.txt 未登録時は DailyWorkflow を呼び出す制御を追加。③ DailyWorkflow：取り込み元コンボを廃止して選択フォルダから自動判定（Step1・2はカメラ取り込み元1/2のみ実行可）、開いた日付以下の階層TreeView（写真情報有＝名前・キャラ名・送付済みか／複数人は階層表示／無＝フォルダ名のみ／ダブルクリックで被写体プロパティ起動）、および日付直下／子直下 scene.txt 配置設定・登録を実装。④ XHelper / パッケージ構成：x_history.json を配布パッケージから除外し、未存在時は空配列 [] で自動生成するよう修正。',
    files: [
      'common/SceneHelper.ps1',
      'common/PhotoEditorLogic.ps1',
      'common/XHelper.ps1',
      'editor/PhotoInfoEditor.ps1',
      'workflow/DailyWorkflow.ps1',
      'workflow/WorkflowStep1Helper.ps1',
      'workflow/WorkflowStep2Helper.ps1',
      'common/ConfigHelper.ps1',
      'settings.ini',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-10',
    phase: '実機確認対応',
    target: '「データ送付済み」チェック・Excel同期＆黒画面の完全非表示化',
    summary:
      '写真情報.txt の【データ送付状況】に明示された「未送付」がギガファイル便URL存在時に「送付済」へ自動上書きされてしまう不具合を修正し、テキスト・Excel台帳（データ送付状況列）ともに表記を「送付済み／未送付」へ統一（既存Excel列名の別名移行対応含む）。さらに Windows 11 ターミナル対策として LaunchHidden.vbs（wscript経由）および CreateNoWindow=$true 起動を導入し、プロパティ表示中の黒いコマンド画面を完全に非表示化。',
    files: [
      'editor/PhotoInfoEditor.ps1',
      'common/PhotoInfoHelper.ps1',
      'common/PhotoEditorLogic.ps1',
      'common/ExcelHelper.ps1',
      'common/LaunchHidden.vbs',
      'MakePhotoInfo.bat',
      'RegisterContextMenu.bat',
      'workflow/DailyWorkflow.ps1',
      'common/OpenFromProtocol.ps1',
    ],
    status: '検証済',
  },
  {
    rev: 'REV-09',
    phase: '実機確認対応',
    target: 'X表示名取得時の文字化け（UTF-8デコード修正）',
    summary:
      'PowerShell 5.1 の Invoke-RestMethod / Invoke-WebRequest が charset 未指定の JSON 応答を ISO-8859-1 として解釈し日本語名が文字化けしていた問題を修正。XHelper.ps1 に HttpWebRequest＋UTF-8 StreamReader（gzip/deflate展開対応）の Invoke-XUtf8Get を追加し全4段階の取得処理をUTF-8明示デコードへ統一。',
    files: ['common/XHelper.ps1'],
    status: '検証済',
  },
  {
    rev: 'REV-08',
    phase: '実機確認対応',
    target: '日付フォルダ右クリック起動の分岐修正',
    summary:
      '日付フォルダ（YYYY_MM_DD 等、かつ親が日付フォルダでない場合）で「被写体プロパティ」を起動した際に PhotoInfoEditor ではなく DailyWorkflow.ps1（対象日付を自動選択）を開くよう分岐を追加。DailyWorkflow 側の「被写体プロパティを開く」には -ForceEditor を付与。',
    files: ['editor/PhotoInfoEditor.ps1', 'workflow/DailyWorkflow.ps1'],
    status: '検証済',
  },
  {
    rev: 'REV-07',
    phase: '実ファイルテスト',
    target: 'ギガファイル便 ドラッグ＆ドロップ / 送る起動',
    summary:
      'send_to_gigafile.ps1 に [CmdletBinding(PositionalBinding = $false)] を追加し、第1引数が $CallbackResultFile に誤バインドされず $RemainingPaths に入るよう修正。launch_gigafile.bat でも -CallbackResultFile "" %* を明示指定。',
    files: ['gigafile/send_to_gigafile.ps1', 'gigafile/launch_gigafile.bat'],
    status: '検証済',
  },
  {
    rev: 'REV-06',
    phase: '単体・結合テスト (08)',
    target: '08. PhotoInfoEditor 衣装自動補完・書込空欄',
    summary:
      'Save-AllPhotoInfoAndLedger・Write-PhotoInfoTxt・Find-SameDayCostumeForModel で List[hashtable] を IDictionary / IEnumerable 判定＋ArrayList でフラット展開し、写真情報.txt の【名前】【衣装・キャラ】が空欄になる不具合と ArrayList.Add の戻り値漏れを解消。',
    files: ['common/PhotoEditorLogic.ps1', 'common/PhotoInfoHelper.ps1'],
    status: '検証済',
  },
  {
    rev: 'REV-05',
    phase: '単体・結合テスト (06)',
    target: '06. ExcelHelper PS 5.1 型不一致・行数倍増',
    summary:
      'Write-XlsxRows・Read-XlsxRows・Update-PhotoExcelLedger を ArrayList＋[object[]] ベースへ変更して DLR 型不一致を解消し、すべての ArrayList.Add() に [void] を付与して出力行数倍増（2行→4行）を修正。',
    files: ['common/ExcelHelper.ps1'],
    status: '検証済',
  },
  {
    rev: 'REV-04',
    phase: '単体・結合テスト (05)',
    target: '05. XHelper dates 配列マージ失敗',
    summary:
      'Read-XHistoryList の単項カンマ（,）返却による2次元配列化を解消し、Show-XHistoryDialog 側の呼び出しと合わせてフラット配列に統一。',
    files: ['common/XHelper.ps1'],
    status: '検証済',
  },
  {
    rev: 'REV-03',
    phase: '単体・結合テスト (04)',
    target: '04. SceneHelper PS 5.1 引数型不一致・履歴取得失敗',
    summary:
      'Get-SceneCandidates の .ToArray() 引数エラーを Get-ScenePropStr＋引数なし .ToArray() で解消し、Read-SceneHistory / Find-SameModelFoldersOnDate の単項カンマ返却による2次元配列化を修正。',
    files: ['common/SceneHelper.ps1'],
    status: '検証済',
  },
  {
    rev: 'REV-02',
    phase: 'テスト基盤修正',
    target: 'TestManager 例外ログ可視化・サンドボックスパス残留',
    summary:
      'テスト例外時に WinForms 未処理例外ポップアップで隠れる前に [EXCP] と [TRCE]（行番号・スタック）を出力するよう改善。LogHelper テスト後のログ出力先復元と Write-PhotoLogLineInternal の親ディレクトリ作成を追加。',
    files: ['tests/TestManager.ps1', 'tests/ModuleTestCases.ps1', 'common/LogHelper.ps1'],
    status: '検証済',
  },
  {
    rev: 'REV-01',
    phase: '初期一括修復',
    target: '全モジュール関数整合・文字コード統一・テスト刷新',
    summary:
      '全ワークフロー・共通ヘルパーの未定義関数・Configキー不整合・写真情報.txt 書式分裂を解消。.bat=CP932+CRLF / .ps1,.ini,.json=UTF-8 BOM+CRLF へ統一し、9モジュールの実IOサンドボックス検証を実装。',
    files: [
      'common/ConfigHelper.ps1',
      'common/PhotoInfoHelper.ps1',
      'workflow/DailyWorkflow.ps1',
      'workflow/SyncExcelFromTxt.ps1',
      'UnblockFiles.bat',
      'settings.ini',
    ],
    status: '検証済',
  },
];

export const TEST_MODULES: TestModuleSpec[] = [
  { id: 'LogHelper', name: '01. LogHelper', scope: 'INFO/ERRORログ出力・パス解決検証' },
  { id: 'ConfigHelper', name: '02. ConfigHelper', scope: 'settings.ini 読込・互換キー・期分け計算検証' },
  { id: 'PhotoInfoHelper', name: '03. PhotoInfoHelper', scope: '写真情報.txt 新旧読込/書込・複数人移行検証' },
  { id: 'SceneHelper', name: '04. SceneHelper', scope: 'シーン履歴保存・候補取得・同一モデル検索検証' },
  { id: 'XHelper', name: '05. XHelper', scope: 'X正規化・名前クリーニング・dates配列JSON読込/保存検証' },
  { id: 'ExcelHelper', name: '06. ExcelHelper', scope: 'OpenXML xlsx生成・同一キー上書き・移動追従検証' },
  { id: 'WorkflowHelpers', name: '07. WorkflowHelpers', scope: 'DailyWorkflow・SyncExcel・Step1〜5 サンドボックス結合検証' },
  { id: 'PhotoInfoEditor', name: '08. PhotoInfoEditor', scope: 'ペア解決・双方向同期・同日衣装自動補完・台帳保存検証' },
  { id: 'GigaFileHelper', name: '09. GigaFileHelper', scope: 'GigaFileHelper / send_to_gigafile / OpenFromProtocol 検証' },
];

export const SETTINGS_FIELDS: SettingsFieldSpec[] = [
  {
    section: 'Paths',
    key: 'ImportRoot1',
    label: 'カメラ取り込み元 1',
    hint: 'Step1・Step2を実行できる取り込みフォルダ 1',
    defaultValue: 'G:\\写真\\eos',
  },
  {
    section: 'Paths',
    key: 'ImportRoot2',
    label: 'カメラ取り込み元 2 (作業用)',
    hint: 'Step1・Step2を実行できる取り込みフォルダ 2（サブ作業用ドライブ等）',
    defaultValue: 'H:\\写真作業用\\eos',
  },
  {
    section: 'Paths',
    key: 'RawSaveRoot',
    label: 'RAW現像作業ルート',
    hint: '仕分け直後のRAWファイル配置先',
    defaultValue: 'G:\\写真raw',
  },
  {
    section: 'Paths',
    key: 'DevelopedRoot',
    label: '現像後フォルダルート',
    hint: 'JPG等の現像済みデータと写真情報.txtの格納ルート',
    defaultValue: 'G:\\写真\\現像後',
  },
  {
    section: 'Paths',
    key: 'RawArchiveRoot',
    label: 'RAW長期アーカイブ先',
    hint: 'Step4完了後にRAWを移動する大容量HDD等',
    defaultValue: 'L:\\',
  },
  {
    section: 'Paths',
    key: 'DevelopedArchiveRoot',
    label: '現像後長期アーカイブ先',
    hint: '現像済みデータの長期保管アーカイブ先',
    defaultValue: 'J:\\写真2\\現像後',
  },
  {
    section: 'Paths',
    key: 'ImportArchiveRoot',
    label: '写真アーカイブ先 (取込 eos)',
    hint: 'Step5完了時にカメラ取り込み元2等を移動するアーカイブ先',
    defaultValue: 'J:\\写真2\\eos',
  },
  {
    section: 'Paths',
    key: 'DataDir',
    label: 'JSON/ログ保存ディレクトリ',
    hint: '履歴JSON・テスト状態・ログの出力先',
    defaultValue: 'D:\\PhotoTools\\data',
  },
  {
    section: 'Paths',
    key: 'LedgerFileName',
    label: 'Excel管理台帳ファイル名',
    hint: '現像後ルート配下の管理台帳ファイル名',
    defaultValue: '写真管理一覧.xlsx',
  },
  {
    section: 'Paths',
    key: 'ExcelPath',
    label: 'Excel管理台帳 フルパス',
    hint: '台帳Excelファイルの直接指定パス',
    defaultValue: 'G:\\写真\\現像後\\写真管理一覧.xlsx',
  },
  {
    section: 'Paths',
    key: 'XHistoryPath',
    label: 'Xアカウント履歴 JSONパス',
    hint: 'XHelperが読み書きする履歴JSONファイル',
    defaultValue: 'D:\\PhotoTools\\data\\x_history.json',
  },
  {
    section: 'Paths',
    key: 'SceneHistoryPath',
    label: '撮影シーン履歴 JSONパス',
    hint: 'SceneHelperが読み書きする履歴JSONファイル',
    defaultValue: 'D:\\PhotoTools\\data\\scene_history.json',
  },
  {
    section: 'Paths',
    key: 'GigaFileScriptPath',
    label: 'GigaFile送信スクリプト',
    hint: 'GigaFileアップロード実処理スクリプトパス',
    defaultValue: 'D:\\PhotoTools\\gigafile\\send_to_gigafile.ps1',
  },
  {
    section: 'Paths',
    key: 'MegaSyncRootPath',
    label: 'MEGA同期ローカルルート',
    hint: 'ローカル同期フォルダを使う場合のみ指定（任意）',
    defaultValue: '',
  },
  {
    section: 'ArchivePeriod',
    key: 'Q1_Months',
    label: '1〜3月期 アーカイブ月',
    hint: '四半期フォルダ分類用（カンマ区切り）',
    defaultValue: '1,2,3',
  },
  {
    section: 'ArchivePeriod',
    key: 'Q2_Months',
    label: '4〜6月期 アーカイブ月',
    hint: '四半期フォルダ分類用（カンマ区切り）',
    defaultValue: '4,5,6',
  },
  {
    section: 'ArchivePeriod',
    key: 'Q3_Months',
    label: '7〜9月期 アーカイブ月',
    hint: '四半期フォルダ分類用（カンマ区切り）',
    defaultValue: '7,8,9',
  },
  {
    section: 'ArchivePeriod',
    key: 'Q4_Months',
    label: '10〜12月期 アーカイブ月',
    hint: '四半期フォルダ分類用（カンマ区切り）',
    defaultValue: '10,11,12',
  },
  {
    section: 'Extensions',
    key: 'RawExtensions',
    label: 'RAW拡張子一覧',
    hint: 'カンマ区切り・先頭ドット付き',
    defaultValue: '.ARW,.CR2,.CR3,.NEF,.RAF,.ORF,.RW2,.DNG',
  },
  {
    section: 'Extensions',
    key: 'ImageExtensions',
    label: '画像拡張子一覧',
    hint: 'カンマ区切り・先頭ドット付き',
    defaultValue: '.JPG,.JPEG,.PNG,.TIF,.TIFF',
  },
  {
    section: 'Mega',
    key: 'MegaCmdPath',
    label: 'MEGAcmd 実行フォルダ/EXE',
    hint: '空欄時は標準インストール先を自動検索',
    defaultValue: '',
  },
  {
    section: 'Mega',
    key: 'MegaRemoteRoot',
    label: 'MEGA リモート基準パス',
    hint: 'MEGA上の写真ルートフォルダ',
    defaultValue: '/写真1/現像後',
  },
  {
    section: 'Mega',
    key: 'MegaLogPath',
    label: 'MEGAデバッグログ出力先',
    hint: 'MEGAcmd 実行時の診断ログファイル',
    defaultValue: 'D:\\PhotoTools\\data\\logs\\mega_debug.log',
  },
];

export function parseIniToRecord(iniText: string): Record<string, string> {
  const result: Record<string, string> = {};
  let currentSection = '';
  for (const rawLine of iniText.split(/\r\n|\r|\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith(';') || line.startsWith('#')) continue;
    if (line.startsWith('[') && line.endsWith(']')) {
      currentSection = line.slice(1, -1).trim();
      continue;
    }
    const eqIdx = line.indexOf('=');
    if (eqIdx > 0 && currentSection) {
      const key = line.slice(0, eqIdx).trim();
      const val = line.slice(eqIdx + 1).trim();
      result[`${currentSection}.${key}`] = val;
    }
  }
  return result;
}

export function serializeRecordToIni(values: Record<string, string>): string {
  const sections: Array<'Paths' | 'ArchivePeriod' | 'Extensions' | 'Mega'> = [
    'Paths',
    'ArchivePeriod',
    'Extensions',
    'Mega',
  ];
  const blocks: string[] = [];
  for (const sec of sections) {
    const lines = [`[${sec}]`];
    for (const field of SETTINGS_FIELDS) {
      if (field.section === sec) {
        const val = values[`${sec}.${field.key}`] ?? field.defaultValue;
        lines.push(`${field.key}=${val}`);
      }
    }
    blocks.push(lines.join('\r\n'));
  }
  return blocks.join('\r\n\r\n') + '\r\n';
}