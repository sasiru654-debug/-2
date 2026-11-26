import { useMemo, useState } from 'react';
import { ArrowRight, ExternalLink } from 'lucide-react';

type FlowFocus = 'all' | 'daily' | 'admin' | 'share';

interface FlowNodeDef {
  id: string;
  label: string;
  sublabel: string;
  filePath: string;
  layer: 'entry' | 'hub' | 'step' | 'editor' | 'external' | 'data';
  groups: FlowFocus[];
  x: number;
  y: number;
  w: number;
  h: number;
  role: string;
  calledBy: string[];
  calls: string[];
}

interface FlowEdgeDef {
  id: string;
  from: string;
  to: string;
  label?: string;
  dashed?: boolean;
  groups: FlowFocus[];
  path: string;
  labelX?: number;
  labelY?: number;
}

const FLOW_NODES: FlowNodeDef[] = [
  // Row 1: Entry Points
  {
    id: 'master',
    label: 'PhotoTools Master',
    sublabel: 'PhotoToolsMaster.ps1',
    filePath: 'PhotoToolsMaster.ps1',
    layer: 'entry',
    groups: ['all', 'admin', 'daily'],
    x: 28,
    y: 28,
    w: 200,
    h: 68,
    role: '最上位の総合管理コンソール。作業用／完了後／アーカイブの日付フォルダ一覧、重複不整合診断、Excel台帳の一括補完・正規化、および設定編集画面の起動を担います。',
    calledBy: ['StartPhotoToolsMaster.bat'],
    calls: ['SettingsEditor.ps1', 'DailyWorkflow.ps1', 'ExcelHelper.ps1'],
  },
  {
    id: 'context',
    label: 'エクスプローラー右クリック',
    sublabel: 'MakePhotoInfo.bat / VBS',
    filePath: 'MakePhotoInfo.bat',
    layer: 'entry',
    groups: ['all', 'daily'],
    x: 252,
    y: 28,
    w: 205,
    h: 68,
    role: 'Windows フォルダ右クリックメニュー「被写体プロパティ」からの入口。LaunchHidden.vbs 経由で黒窓を出さずに起動し、日付フォルダは DailyWorkflow へ自動振り分けします（直下に写真情報.txtがある場合は直接編集）。',
    calledBy: ['Windows 右クリックメニュー (RegisterContextMenu.bat)'],
    calls: ['DailyWorkflow.ps1', 'PhotoInfoEditor.ps1'],
  },
  {
    id: 'protocol',
    label: 'Excel URLプロトコル起動',
    sublabel: 'OpenFromProtocol.ps1',
    filePath: 'common/OpenFromProtocol.ps1',
    layer: 'entry',
    groups: ['all', 'share'],
    x: 481,
    y: 28,
    w: 195,
    h: 68,
    role: 'Excel管理台帳内の photoinfo://open?path=... リンクを受信し、対象フォルダ（日付直下・子フォルダ）の被写体プロパティを -ForceEditor 付きで直接開きます。',
    calledBy: ['写真管理一覧.xlsx (ハイパーリンク)', 'RegisterProtocol.bat'],
    calls: ['PhotoInfoEditor.ps1'],
  },
  {
    id: 'sendto',
    label: '送る (SendTo) 起動',
    sublabel: 'launch_gigafile.bat',
    filePath: 'gigafile/launch_gigafile.bat',
    layer: 'entry',
    groups: ['all', 'share'],
    x: 700,
    y: 28,
    w: 195,
    h: 68,
    role: 'Windows の「送る」メニューや D&D からギガファイル便アップローダを直接起動します。複数子フォルダの一括分割アップロードにも対応。',
    calledBy: ['Windows SendTo (install_gigafile_sendto.bat)'],
    calls: ['send_to_gigafile.ps1'],
  },
  {
    id: 'updater',
    label: '単独更新支援ツール',
    sublabel: 'updater/PhotoToolsUpdater.ps1',
    filePath: 'updater/PhotoToolsUpdater.ps1',
    layer: 'entry',
    groups: ['all', 'admin'],
    x: 919,
    y: 28,
    w: 205,
    h: 68,
    role: '本体非依存の完全自己完結型 GUI アップデータ。最新ZIP自動選択・GitHub取得・直近5世代バックアップ・settings.iniマージ・data\\完全保護・ブロック解除・不要ファイル確認削除を一括実行します。',
    calledBy: ['updater/StartPhotoToolsUpdater.vbs'],
    calls: ['D:\\PhotoTools\\ 更新適用', 'settings.ini / data\\ 保護'],
  },

  // Row 2: Config & DailyWorkflow Hub
  {
    id: 'settings-editor',
    label: '設定・定型文・AI編集',
    sublabel: 'editor/SettingsEditor.ps1 (5タブ)',
    filePath: 'editor/SettingsEditor.ps1',
    layer: 'hub',
    groups: ['all', 'admin', 'share'],
    x: 28,
    y: 156,
    w: 230,
    h: 72,
    role: '5タブ構成の環境・定型文・AI設定 GUI。パス・期分け・拡張子・MEGA設定保存（.bak自動作成）、関連JSON直接編集・OS登録、メッセージ定型文＆MEGAコメント5種、およびAIキャラ判定設定（DPAPI暗号化キー保存・有料枠確認・0トークン接続テスト）を一元化します。',
    calledBy: ['PhotoToolsMaster.ps1', 'MessageComposerDialog.ps1', 'CharacterLookupDialog.ps1'],
    calls: ['ConfigHelper.ps1', 'settings.ini', 'message_templates.json / ai_character_settings.json / DPAPIキー'],
  },
  {
    id: 'daily',
    label: '日次ワークフロー統括',
    sublabel: 'workflow/DailyWorkflow.ps1',
    filePath: 'workflow/DailyWorkflow.ps1',
    layer: 'hub',
    groups: ['all', 'daily', 'share'],
    x: 290,
    y: 156,
    w: 470,
    h: 72,
    role: '撮影日フォルダ単位の作業ハブ。取込元・RAW・現像後の3ルート紐づけ、scene.txt 配置、子フォルダ名3ルート一括同期、1日1人時の日付直下プロパティ編集、Step1〜5 呼び出し、および同日複数フォルダ対応の「メッセージ作成(まとめ可)」を統括します。',
    calledBy: ['PhotoToolsMaster.ps1', 'StartDailyWorkflow.bat', 'MakePhotoInfo.bat'],
    calls: ['Step1〜5 Helper', 'PhotoInfoEditor.ps1', 'MessageComposerDialog.ps1', 'GigaFileHelper.ps1', 'ExcelHelper.ps1'],
  },
  {
    id: 'tests',
    label: 'サンドボックス自動テスト',
    sublabel: 'tests/TestManager.ps1 (01〜12)',
    filePath: 'tests/TestManager.ps1',
    layer: 'hub',
    groups: ['all', 'admin'],
    x: 800,
    y: 156,
    w: 324,
    h: 72,
    role: '本番フォルダ・台帳を汚さない一時サンドボックスで全12モジュール（01. LogHelper 〜 12. GeminiCharacterHelper）の構文チェック・単体検証を一括実行するテストマネージャー。',
    calledBy: ['RunTestManager.bat', 'SettingsEditor.ps1'],
    calls: ['tests/ModuleTestCases.ps1 (01〜12)'],
  },

  // Row 3: 5-Step Pipeline
  {
    id: 'step1',
    label: 'Step1 仕分け作成',
    sublabel: 'WorkflowStep1Helper.ps1',
    filePath: 'workflow/WorkflowStep1Helper.ps1',
    layer: 'step',
    groups: ['all', 'daily'],
    x: 28,
    y: 288,
    w: 195,
    h: 64,
    role: '取込元の日付フォルダ配下にモデル数分の連番フォルダ（01, 02...）を一括作成します。',
    calledBy: ['DailyWorkflow.ps1'],
    calls: ['ImportRoot1 / 2'],
  },
  {
    id: 'step2',
    label: 'Step2 RAW複製移動',
    sublabel: 'WorkflowStep2Helper.ps1 (非同期)',
    filePath: 'workflow/WorkflowStep2Helper.ps1',
    layer: 'step',
    groups: ['all', 'daily'],
    x: 252,
    y: 288,
    w: 200,
    h: 64,
    role: 'フォルダ構成を RAW作業先・現像後ルートへ複製し、RAWファイルを別プロセス非同期で安全に移動します。',
    calledBy: ['DailyWorkflow.ps1 (別プロセス起動)'],
    calls: ['RawSaveRoot / DevelopedRoot'],
  },
  {
    id: 'step3',
    label: 'Step3 現像後振分',
    sublabel: 'WorkflowStep3Helper.ps1 (1秒監視)',
    filePath: 'workflow/WorkflowStep3Helper.ps1',
    layer: 'step',
    groups: ['all', 'daily'],
    x: 480,
    y: 288,
    w: 210,
    h: 64,
    role: 'RAW参照と照合して現像済みJPEGを各サブフォルダへ自動振分。1秒監視・上書き制御・保留理由管理を備え、メタデータTXTは除外します。',
    calledBy: ['DailyWorkflow.ps1'],
    calls: ['DevelopedRoot'],
  },
  {
    id: 'step4',
    label: 'Step4 重複JPG削除',
    sublabel: 'WorkflowStep4Helper.ps1',
    filePath: 'workflow/WorkflowStep4Helper.ps1',
    layer: 'step',
    groups: ['all', 'daily'],
    x: 718,
    y: 288,
    w: 195,
    h: 64,
    role: '現像側と取込元をキャノン8文字ベース名一致で統合比較し、現像済みの重複カメラ内JPGを取込元から安全削除します（日付直下も対応）。',
    calledBy: ['DailyWorkflow.ps1'],
    calls: ['ImportRoot1 / 2'],
  },
  {
    id: 'step5',
    label: 'Step5 アーカイブ移動',
    sublabel: 'WorkflowStep5Helper.ps1 (非同期)',
    filePath: 'workflow/WorkflowStep5Helper.ps1',
    layer: 'step',
    groups: ['all', 'daily'],
    x: 942,
    y: 288,
    w: 182,
    h: 64,
    role: '完了済み日付フォルダを期分けアーカイブ先へ別プロセス非同期で移送し、Excel台帳のパス列を自動追従します。',
    calledBy: ['DailyWorkflow.ps1 (別プロセス起動)'],
    calls: ['ArchiveRoot', 'ExcelHelper.ps1'],
  },

  // Row 4: PhotoInfoEditor, AI Lookup, MessageComposer & External Integrations
  {
    id: 'editor',
    label: '被写体プロパティ編集',
    sublabel: 'editor/PhotoInfoEditor.ps1',
    filePath: 'editor/PhotoInfoEditor.ps1',
    layer: 'editor',
    groups: ['all', 'daily', 'share'],
    x: 28,
    y: 416,
    w: 196,
    h: 74,
    role: '日付直下（1日1人）および子・孫フォルダの被写体情報（モデル名・衣装・X・コメント・送付状況）を編集。PhotoEditorLogic 経由で取込元／現像後の両方へ同時保存し、AIキャラ名検索や単体送付メッセージ作成も起動できます。',
    calledBy: ['DailyWorkflow.ps1', 'MakePhotoInfo.bat', 'OpenFromProtocol.ps1'],
    calls: ['PhotoEditorLogic.ps1', 'CharacterLookupDialog.ps1', 'MessageComposerDialog.ps1', 'MegaHelper.ps1', 'GigaFileHelper.ps1', 'ExcelHelper.ps1'],
  },
  {
    id: 'char-lookup',
    label: 'AIキャラ名検索 (6層保護)',
    sublabel: 'CharacterLookupDialog.ps1',
    filePath: 'editor/CharacterLookupDialog.ps1',
    layer: 'external',
    groups: ['all', 'daily', 'share'],
    x: 246,
    y: 416,
    w: 204,
    h: 74,
    role: '6層漏洩対策付きの写真キャラ名・作品名検索ダイアログ。ドラッグ顔マスク（黒塗り/モザイク・未設定時警告）、メモリ上Exif除去＆長辺縮小、個人情報未送信、DPAPI暗号化キー＋有料枠確認必須の Gemini REST 呼び出しにより、既定「キャラ名（作品名）」で衣装・キャラ欄へ反映します。',
    calledBy: ['PhotoInfoEditor.ps1'],
    calls: ['GeminiCharacterHelper.ps1', 'SettingsEditor.ps1 (AI設定)', 'ai_character_settings.json / DPAPIキー'],
  },
  {
    id: 'message-composer',
    label: '送付メッセージ作成',
    sublabel: 'MessageComposerDialog.ps1',
    filePath: 'editor/MessageComposerDialog.ps1',
    layer: 'editor',
    groups: ['all', 'daily', 'share'],
    x: 472,
    y: 416,
    w: 210,
    h: 74,
    role: '定型文と写真情報からDM用送付文面を作成（単体／同日まとめ両対応）。ギガファイル便／MEGAの択一選択、個撮リンク１／複数リンク１＋共演者表記、MEGA未取得確認取得、MEGA共通コメント5種切替、コピー後の「送付済み」一括更新を担います。',
    calledBy: ['PhotoInfoEditor.ps1', 'DailyWorkflow.ps1', 'send_to_gigafile.ps1'],
    calls: ['MessageTemplateHelper.ps1', 'SettingsEditor.ps1', 'MegaHelper.ps1', '写真情報.txt', 'ExcelHelper.ps1'],
  },
  {
    id: 'mega',
    label: 'MEGA 共有リンク取得',
    sublabel: 'MegaHelper.ps1 (非同期)',
    filePath: 'common/MegaHelper.ps1',
    layer: 'external',
    groups: ['all', 'share'],
    x: 704,
    y: 416,
    w: 196,
    h: 74,
    role: 'MEGAcmd (mega-export) をバックグラウンドジョブで非同期実行し、ポップアップ内に処理ログをリアルタイム表示しながら共有リンクを取得します。',
    calledBy: ['PhotoInfoEditor.ps1', 'MessageComposerDialog.ps1'],
    calls: ['MEGAcmd', 'data/logs/mega_debug.log'],
  },
  {
    id: 'gigafile',
    label: 'ギガファイル便連携',
    sublabel: 'gigafile/send_to_gigafile.ps1',
    filePath: 'gigafile/send_to_gigafile.ps1',
    layer: 'external',
    groups: ['all', 'share'],
    x: 922,
    y: 416,
    w: 202,
    h: 74,
    role: '写真情報.txt 解析による自動命名ZIP生成、子フォルダ一括分割送信、発行URL・DLパスワード・保持期限（yyyy/MM/ddまで）と「送付済み」の自動書き戻し、および完了後「送付メッセージ作成」起動を実行します。',
    calledBy: ['DailyWorkflow.ps1', 'PhotoInfoEditor.ps1', 'launch_gigafile.bat'],
    calls: ['GigaFile サーバー', 'MessageComposerDialog.ps1', '写真情報.txt', 'ExcelHelper.ps1'],
  },

  // Row 5: Persistent Data & Ledger
  {
    id: 'config-data',
    label: '設定・履歴・定型文・AI保護',
    sublabel: 'settings.ini / data/*.json / DPAPIキー',
    filePath: 'settings.ini',
    layer: 'data',
    groups: ['all', 'admin', 'share'],
    x: 28,
    y: 558,
    w: 310,
    h: 68,
    role: '全ツール共通の settings.ini、補完用の scene_history.json / x_history.json、定型文 data\\message_templates.json、およびAI設定 data\\ai_character_settings.json と DPAPI暗号化キー data\\gemini_api_key.dat。更新ツールにより完全保護され、キーはZIP配布対象外です。',
    calledBy: ['SettingsEditor.ps1', 'CharacterLookupDialog.ps1', 'MessageComposerDialog.ps1', '全モジュール'],
    calls: ['settings.ini.bak (自動バックアップ)'],
  },
  {
    id: 'photoinfo-txt',
    label: '写真情報.txt / scene.txt',
    sublabel: 'common/PhotoInfoHelper.ps1',
    filePath: 'common/PhotoInfoHelper.ps1',
    layer: 'data',
    groups: ['all', 'daily', 'share'],
    x: 376,
    y: 558,
    w: 350,
    h: 68,
    role: '各フォルダ（日付直下または子・孫）に配置される真実のソース。【X】/【X_URL】自動分離・【DLパスワード】・【保持期限】を含み、取込元と現像後の双方にペア同期されます。',
    calledBy: ['PhotoInfoEditor.ps1', 'MessageComposerDialog.ps1', 'DailyWorkflow.ps1', 'send_to_gigafile.ps1'],
    calls: ['SyncExcelFromTxt.ps1', 'ExcelHelper.ps1'],
  },
  {
    id: 'excel-ledger',
    label: 'Excel 管理台帳 (OpenXML)',
    sublabel: 'common/ExcelHelper.ps1 / SyncExcel',
    filePath: 'common/ExcelHelper.ps1',
    layer: 'data',
    groups: ['all', 'daily', 'admin', 'share'],
    x: 764,
    y: 558,
    w: 360,
    h: 68,
    role: 'Excel 非依存の OpenXML 直接読み書きで 写真管理一覧.xlsx（全18列）を更新。子フォルダリネーム・Step5移動のパス追従、MEGA/送付済み連動、および台帳セルフヒーリングを担当します。',
    calledBy: ['PhotoToolsMaster.ps1', 'DailyWorkflow.ps1', 'PhotoInfoEditor.ps1', 'MessageComposerDialog.ps1', 'SyncExcelFromTxt.ps1'],
    calls: ['写真管理一覧.xlsx (.bak 保護付)'],
  },
];

const FLOW_EDGES: FlowEdgeDef[] = [
  // Master -> SettingsEditor & DailyWorkflow
  {
    id: 'e-master-settings',
    from: 'master',
    to: 'settings-editor',
    label: '設定・定型文編集',
    groups: ['all', 'admin'],
    path: 'M 128 96 L 128 156',
    labelX: 135,
    labelY: 130,
  },
  {
    id: 'e-master-daily',
    from: 'master',
    to: 'daily',
    label: '日付選択起動',
    groups: ['all', 'daily', 'admin'],
    path: 'M 228 66 L 274 66 L 274 184 L 290 184',
    labelX: 230,
    labelY: 130,
  },
  // Context -> DailyWorkflow
  {
    id: 'e-ctx-daily',
    from: 'context',
    to: 'daily',
    label: '日付フォルダ',
    groups: ['all', 'daily'],
    path: 'M 354 96 L 354 156',
    labelX: 362,
    labelY: 130,
  },
  // Protocol -> Editor
  {
    id: 'e-proto-editor',
    from: 'protocol',
    to: 'editor',
    label: '-ForceEditor',
    dashed: true,
    groups: ['all', 'share'],
    path: 'M 578 96 L 578 130 L 780 130 L 780 382 L 155 382 L 155 416',
    labelX: 586,
    labelY: 122,
  },
  // SendTo -> GigaFile
  {
    id: 'e-sendto-giga',
    from: 'sendto',
    to: 'gigafile',
    label: '直接送信',
    dashed: true,
    groups: ['all', 'share'],
    path: 'M 797 96 L 797 128 L 1134 128 L 1134 453 L 1124 453',
    labelX: 804,
    labelY: 122,
  },
  // Updater -> ConfigData (protect & merge)
  {
    id: 'e-updater-config',
    from: 'updater',
    to: 'config-data',
    label: '保護上書き',
    dashed: true,
    groups: ['all', 'admin'],
    path: 'M 1021 96 L 1021 116 L 14 116 L 14 592 L 28 592',
    labelX: 960,
    labelY: 111,
  },
  // SettingsEditor -> ConfigData
  {
    id: 'e-settings-config',
    from: 'settings-editor',
    to: 'config-data',
    label: '保存・反映',
    groups: ['all', 'admin', 'share'],
    path: 'M 28 192 L 18 192 L 18 576 L 28 576',
    labelX: 22,
    labelY: 398,
  },
  // Daily -> Step1..5 bus
  {
    id: 'e-daily-s1',
    from: 'daily',
    to: 'step1',
    groups: ['all', 'daily'],
    path: 'M 525 228 L 525 256 L 125 256 L 125 288',
  },
  {
    id: 'e-daily-s2',
    from: 'daily',
    to: 'step2',
    groups: ['all', 'daily'],
    path: 'M 525 228 L 525 256 L 352 256 L 352 288',
  },
  {
    id: 'e-daily-s3',
    from: 'daily',
    to: 'step3',
    label: 'Step 1〜5 実行',
    groups: ['all', 'daily'],
    path: 'M 525 228 L 525 256 L 585 256 L 585 288',
    labelX: 533,
    labelY: 248,
  },
  {
    id: 'e-daily-s4',
    from: 'daily',
    to: 'step4',
    groups: ['all', 'daily'],
    path: 'M 525 228 L 525 256 L 815 256 L 815 288',
  },
  {
    id: 'e-daily-s5',
    from: 'daily',
    to: 'step5',
    groups: ['all', 'daily'],
    path: 'M 525 228 L 525 256 L 1033 256 L 1033 288',
  },
  // Step1 -> Step2 -> Step3 -> Step4 -> Step5 sequential flow
  {
    id: 'e-s1-s2',
    from: 'step1',
    to: 'step2',
    groups: ['all', 'daily'],
    path: 'M 223 320 L 252 320',
  },
  {
    id: 'e-s2-s3',
    from: 'step2',
    to: 'step3',
    groups: ['all', 'daily'],
    path: 'M 452 320 L 480 320',
  },
  {
    id: 'e-s3-s4',
    from: 'step3',
    to: 'step4',
    groups: ['all', 'daily'],
    path: 'M 690 320 L 718 320',
  },
  {
    id: 'e-s4-s5',
    from: 'step4',
    to: 'step5',
    groups: ['all', 'daily'],
    path: 'M 913 320 L 942 320',
  },
  // Daily -> Editor
  {
    id: 'e-daily-editor',
    from: 'daily',
    to: 'editor',
    label: '日付直下 / 子フォルダ編集',
    groups: ['all', 'daily', 'share'],
    path: 'M 290 202 L 268 202 L 268 256 L 236 256 L 236 376 L 96 376 L 96 416',
    labelX: 38,
    labelY: 370,
  },
  // Daily -> MessageComposer (Combined mode)
  {
    id: 'e-daily-msg',
    from: 'daily',
    to: 'message-composer',
    label: 'まとめメッセージ作成',
    groups: ['all', 'daily', 'share'],
    path: 'M 466 228 L 466 392 L 560 392 L 560 416',
    labelX: 472,
    labelY: 388,
  },
  // Editor -> AI Character Lookup
  {
    id: 'e-editor-char',
    from: 'editor',
    to: 'char-lookup',
    label: 'AI検索',
    groups: ['all', 'daily', 'share'],
    path: 'M 224 453 L 246 453',
    labelX: 218,
    labelY: 444,
  },
  // AI Character Lookup -> ConfigData (DPAPI & AI settings)
  {
    id: 'e-char-config',
    from: 'char-lookup',
    to: 'config-data',
    label: 'DPAPI/AI設定',
    dashed: true,
    groups: ['all', 'daily', 'share', 'admin'],
    path: 'M 315 490 L 315 558',
    labelX: 242,
    labelY: 549,
  },
  // Editor -> MessageComposer
  {
    id: 'e-editor-msg',
    from: 'editor',
    to: 'message-composer',
    label: '単体作成',
    groups: ['all', 'daily', 'share'],
    path: 'M 180 490 L 180 518 L 505 518 L 505 490',
    labelX: 360,
    labelY: 514,
  },
  // MessageComposer -> Mega (unacquired fetch)
  {
    id: 'e-msg-mega',
    from: 'message-composer',
    to: 'mega',
    label: '未取得',
    groups: ['all', 'share'],
    path: 'M 682 453 L 704 453',
    labelX: 676,
    labelY: 444,
  },
  // GigaFile -> MessageComposer (post-upload button)
  {
    id: 'e-giga-msg',
    from: 'gigafile',
    to: 'message-composer',
    label: '完了後メッセージ作成',
    dashed: true,
    groups: ['all', 'share'],
    path: 'M 970 490 L 970 520 L 620 520 L 620 490',
    labelX: 740,
    labelY: 515,
  },
  // Editor -> PhotoInfo.txt
  {
    id: 'e-editor-txt',
    from: 'editor',
    to: 'photoinfo-txt',
    label: 'ペア同期保存',
    groups: ['all', 'daily', 'share'],
    path: 'M 120 490 L 120 536 L 440 536 L 440 558',
    labelX: 356,
    labelY: 549,
  },
  // MessageComposer -> PhotoInfo.txt (MEGA & Sent status)
  {
    id: 'e-msg-txt',
    from: 'message-composer',
    to: 'photoinfo-txt',
    label: '送付済/MEGA更新',
    groups: ['all', 'share'],
    path: 'M 560 490 L 560 558',
    labelX: 566,
    labelY: 542,
  },
  // PhotoInfo.txt -> Excel
  {
    id: 'e-txt-excel',
    from: 'photoinfo-txt',
    to: 'excel-ledger',
    label: 'OpenXML',
    groups: ['all', 'daily', 'admin', 'share'],
    path: 'M 726 592 L 764 592',
    labelX: 722,
    labelY: 583,
  },
  // GigaFile -> Excel
  {
    id: 'e-giga-excel',
    from: 'gigafile',
    to: 'excel-ledger',
    label: 'URL/送付済反映',
    groups: ['all', 'share'],
    path: 'M 1030 490 L 1030 558',
    labelX: 1036,
    labelY: 534,
  },
  // Step5 -> Excel (archive path update)
  {
    id: 'e-s5-excel',
    from: 'step5',
    to: 'excel-ledger',
    label: '移動後パス追従',
    dashed: true,
    groups: ['all', 'daily', 'admin'],
    path: 'M 1085 352 L 1085 388 L 1138 388 L 1138 592 L 1124 592',
    labelX: 1030,
    labelY: 382,
  },
];

const LAYER_STYLES: Record<
  FlowNodeDef['layer'],
  { fill: string; stroke: string; titleColor: string; subColor: string; tagLabel: string }
> = {
  entry: {
    fill: '#0f172a',
    stroke: '#0f172a',
    titleColor: '#ffffff',
    subColor: '#cbd5e1',
    tagLabel: '起動入口',
  },
  hub: {
    fill: '#f0fdfa',
    stroke: '#0f766e',
    titleColor: '#0f172a',
    subColor: '#0f766e',
    tagLabel: '統括・設定GUI',
  },
  step: {
    fill: '#ffffff',
    stroke: '#64748b',
    titleColor: '#0f172a',
    subColor: '#475569',
    tagLabel: '5ステップ処理',
  },
  editor: {
    fill: '#ecfdf5',
    stroke: '#047857',
    titleColor: '#064e3b',
    subColor: '#047857',
    tagLabel: '情報編集GUI',
  },
  external: {
    fill: '#eff6ff',
    stroke: '#1d4ed8',
    titleColor: '#1e3a8a',
    subColor: '#1d4ed8',
    tagLabel: '外部クラウド連携',
  },
  data: {
    fill: '#f8fafc',
    stroke: '#334155',
    titleColor: '#0f172a',
    subColor: '#475569',
    tagLabel: '設定・台帳データ',
  },
};

const FOCUS_OPTIONS: Array<{ id: FlowFocus; label: string }> = [
  { id: 'all', label: '全体フロー表示' },
  { id: 'daily', label: '日常撮影〜アーカイブ' },
  { id: 'admin', label: 'Master・設定・更新・テスト' },
  { id: 'share', label: '送付メッセージ・MEGA・ギガ・台帳' },
];

interface ToolFlowchartDiagramProps {
  onSelectFile?: (filePath: string) => void;
}

export default function ToolFlowchartDiagram({ onSelectFile }: ToolFlowchartDiagramProps) {
  const [selectedId, setSelectedId] = useState<string>('daily');
  const [focus, setFocus] = useState<FlowFocus>('all');

  const selectedNode = useMemo(
    () => FLOW_NODES.find((n) => n.id === selectedId) ?? FLOW_NODES[0],
    [selectedId],
  );

  const connectedIds = useMemo(() => {
    const set = new Set<string>([selectedId]);
    for (const edge of FLOW_EDGES) {
      if (edge.from === selectedId) set.add(edge.to);
      if (edge.to === selectedId) set.add(edge.from);
    }
    return set;
  }, [selectedId]);

  return (
    <section className="bg-white border border-slate-200 p-6 space-y-5">
      <div className="flex flex-col lg:flex-row lg:items-end justify-between gap-4 border-b border-slate-200 pb-4">
        <div className="space-y-1">
          <h2 className="text-base font-bold text-slate-900">
            PhotoTools 全体フローチャート（ツール間の関係性・データ連携図）
          </h2>
          <p className="text-xs text-slate-600">
            各ボックスをクリックすると、呼び出し元・連携先・役割の詳細を確認でき、対象スクリプトのコードへ直接移動できます。
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-1 p-1 bg-slate-100 rounded-md self-start lg:self-auto">
          {FOCUS_OPTIONS.map((opt) => {
            const active = focus === opt.id;
            return (
              <button
                key={opt.id}
                type="button"
                onClick={() => setFocus(opt.id)}
                className={`px-3 py-1.5 text-xs font-medium rounded whitespace-nowrap shrink-0 transition-colors ${
                  active
                    ? 'bg-white text-slate-900 shadow-xs'
                    : 'text-slate-600 hover:text-slate-900'
                }`}
              >
                {opt.label}
              </button>
            );
          })}
        </div>
      </div>

      {/* Legend */}
      <div className="flex flex-wrap items-center gap-x-5 gap-y-2 text-xs text-slate-600">
        <span className="inline-flex items-center gap-1.5">
          <span className="w-3 h-3 bg-slate-900 inline-block" />
          起動入口 (.bat / VBS)
        </span>
        <span className="inline-flex items-center gap-1.5">
          <span className="w-3 h-3 bg-teal-50 border border-teal-700 inline-block" />
          統括・設定 GUI
        </span>
        <span className="inline-flex items-center gap-1.5">
          <span className="w-3 h-3 bg-white border border-slate-500 inline-block" />
          Step 1〜5 パイプライン
        </span>
        <span className="inline-flex items-center gap-1.5">
          <span className="w-3 h-3 bg-emerald-50 border border-emerald-700 inline-block" />
          プロパティ・送付メッセージ
        </span>
        <span className="inline-flex items-center gap-1.5">
          <span className="w-3 h-3 bg-blue-50 border border-blue-700 inline-block" />
          外部クラウド連携
        </span>
        <span className="inline-flex items-center gap-1.5">
          <span className="w-3 h-3 bg-slate-50 border border-slate-700 inline-block" />
          設定・台帳データ
        </span>
      </div>

      {/* Interactive SVG Flowchart */}
      <div className="overflow-x-auto border border-slate-200 bg-slate-50/70">
        <svg
          viewBox="0 0 1150 652"
          className="w-full min-w-[920px] h-auto block select-none"
          role="img"
          aria-label="PhotoTools ツール関係性フローチャート"
        >
          <defs>
            <marker
              id="arrow-default"
              viewBox="0 0 10 10"
              refX="9"
              refY="5"
              markerWidth="6"
              markerHeight="6"
              orient="auto-start-reverse"
            >
              <path d="M 0 1.5 L 10 5 L 0 8.5 z" fill="#64748b" />
            </marker>
            <marker
              id="arrow-active"
              viewBox="0 0 10 10"
              refX="9"
              refY="5"
              markerWidth="7"
              markerHeight="7"
              orient="auto-start-reverse"
            >
              <path d="M 0 1.5 L 10 5 L 0 8.5 z" fill="#0f766e" />
            </marker>
          </defs>

          {/* Subtle Row Band Labels */}
          <text x="16" y="18" fontSize="10" fill="#64748b" fontWeight="600">
            01. 起動入口
          </text>
          <line x1="16" y1="116" x2="1128" y2="116" stroke="#e2e8f0" strokeDasharray="3 3" />
          <text x="16" y="146" fontSize="10" fill="#64748b" fontWeight="600">
            02. 設定・日次ハブ・検証
          </text>
          <line x1="16" y1="244" x2="1128" y2="244" stroke="#e2e8f0" strokeDasharray="3 3" />
          <text x="16" y="278" fontSize="10" fill="#64748b" fontWeight="600">
            03. 日次ワークフロー（Step 1 → Step 5）
          </text>
          <line x1="16" y1="368" x2="1128" y2="368" stroke="#e2e8f0" strokeDasharray="3 3" />
          <text x="16" y="406" fontSize="10" fill="#64748b" fontWeight="600">
            04. 写真情報編集・AIキャラ判定・送付メッセージ作成 ＆ クラウド共有連携
          </text>
          <line x1="16" y1="508" x2="1136" y2="508" stroke="#e2e8f0" strokeDasharray="3 3" />
          <text x="16" y="546" fontSize="10" fill="#64748b" fontWeight="600">
            05. 永続ファイル・定型文・DPAPI保護・Excel 管理台帳
          </text>

          {/* Edges */}
          {FLOW_EDGES.map((edge) => {
            const inFocus = focus === 'all' || edge.groups.includes(focus);
            const isSelectedEdge = edge.from === selectedId || edge.to === selectedId;
            const opacity = !inFocus ? 0.16 : isSelectedEdge ? 1 : 0.65;
            return (
              <g key={edge.id} style={{ opacity, transition: 'opacity 160ms ease' }}>
                <path
                  d={edge.path}
                  fill="none"
                  stroke={isSelectedEdge ? '#0f766e' : '#64748b'}
                  strokeWidth={isSelectedEdge ? 2.2 : 1.5}
                  strokeDasharray={edge.dashed ? '5 4' : undefined}
                  markerEnd={isSelectedEdge ? 'url(#arrow-active)' : 'url(#arrow-default)'}
                />
                {edge.label && edge.labelX !== undefined && edge.labelY !== undefined && (
                  <text
                    x={edge.labelX}
                    y={edge.labelY}
                    fontSize="10"
                    fontWeight={isSelectedEdge ? '700' : '500'}
                    fill={isSelectedEdge ? '#0f766e' : '#475569'}
                  >
                    {edge.label}
                  </text>
                )}
              </g>
            );
          })}

          {/* Nodes */}
          {FLOW_NODES.map((node) => {
            const style = LAYER_STYLES[node.layer];
            const inFocus = focus === 'all' || node.groups.includes(focus);
            const isSelected = node.id === selectedId;
            const isConnected = connectedIds.has(node.id);
            const opacity = !inFocus ? 0.25 : isSelected || isConnected ? 1 : 0.85;

            return (
              <g
                key={node.id}
                onClick={() => setSelectedId(node.id)}
                className="cursor-pointer"
                style={{ opacity, transition: 'opacity 160ms ease' }}
              >
                {isSelected && (
                  <rect
                    x={node.x - 4}
                    y={node.y - 4}
                    width={node.w + 8}
                    height={node.h + 8}
                    rx={6}
                    fill="none"
                    stroke="#0f766e"
                    strokeWidth={2.5}
                  />
                )}
                <rect
                  x={node.x}
                  y={node.y}
                  width={node.w}
                  height={node.h}
                  rx={4}
                  fill={style.fill}
                  stroke={style.stroke}
                  strokeWidth={isSelected ? 2 : 1.4}
                />
                <text
                  x={node.x + node.w / 2}
                  y={node.y + node.h / 2 - 5}
                  textAnchor="middle"
                  fontSize="12.5"
                  fontWeight="700"
                  fill={style.titleColor}
                >
                  {node.label}
                </text>
                <text
                  x={node.x + node.w / 2}
                  y={node.y + node.h / 2 + 14}
                  textAnchor="middle"
                  fontSize="10.5"
                  fontFamily="JetBrains Mono, monospace"
                  fill={style.subColor}
                >
                  {node.sublabel}
                </text>
              </g>
            );
          })}
        </svg>
      </div>

      {/* Selected Node Detail Bar */}
      <div className="border border-slate-200 bg-slate-50 p-4 flex flex-col lg:flex-row lg:items-center justify-between gap-4">
        <div className="space-y-2 max-w-4xl">
          <div className="flex flex-wrap items-center gap-2 text-xs text-slate-500">
            <span className="font-semibold text-teal-800">
              {LAYER_STYLES[selectedNode.layer].tagLabel}
            </span>
            <span aria-hidden="true">·</span>
            <span className="font-mono text-slate-700">phototools/{selectedNode.filePath}</span>
          </div>
          <h3 className="text-sm font-bold text-slate-900">{selectedNode.label}</h3>
          <p className="text-xs text-slate-700 leading-relaxed">{selectedNode.role}</p>
          <div className="flex flex-wrap items-center gap-x-6 gap-y-1 text-xs text-slate-600 pt-1">
            <div>
              <span className="font-semibold text-slate-800">呼び出し元: </span>
              <span>{selectedNode.calledBy.join(' / ')}</span>
            </div>
            <div className="inline-flex items-center gap-1.5">
              <ArrowRight className="w-3.5 h-3.5 text-teal-700 shrink-0" />
              <span className="font-semibold text-slate-800">連携・更新先: </span>
              <span>{selectedNode.calls.join(' / ')}</span>
            </div>
          </div>
        </div>

        {onSelectFile && (
          <button
            type="button"
            onClick={() => onSelectFile(selectedNode.filePath)}
            className="inline-flex items-center justify-center gap-2 px-4 py-2 text-xs font-semibold bg-slate-900 text-white hover:bg-slate-800 whitespace-nowrap shrink-0 transition-colors self-start lg:self-center"
          >
            <ExternalLink className="w-3.5 h-3.5" />
            <span>このコードを開く</span>
          </button>
        )}
      </div>
    </section>
  );
}
