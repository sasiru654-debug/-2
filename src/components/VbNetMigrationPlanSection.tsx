import { useMemo, useState } from 'react';
import {
  ArrowRight,
  CheckCircle2,
  Cpu,
  Database,
  FolderTree,
  Layers,
  Monitor,
  Package,
  ShieldCheck,
  Terminal,
} from 'lucide-react';

interface VbNetMigrationPlanSectionProps {
  onSelectFile?: (filePath: string) => void;
}

type MigrationPhase = 'ALL' | 'PHASE1' | 'PHASE2' | 'PHASE3';

interface ModuleMappingRow {
  phase: Exclude<MigrationPhase, 'ALL'>;
  phaseLabel: string;
  currentPsFile: string;
  targetVbClass: string;
  project: 'PhotoTools.Core' | 'PhotoTools.App' | 'PhotoTools.GigaFile' | 'PhotoTools.Core.Tests';
  notes: string;
}

interface CliRouteRow {
  trigger: string;
  arguments: string;
  targetForm: string;
  replaces: string;
}

interface DataCompatRow {
  asset: string;
  format: string;
  strategy: string;
  coexistence: string;
}

const CLI_ROUTES: CliRouteRow[] = [
  {
    trigger: 'PhotoTools.exe 直接起動',
    arguments: '（引数なし）',
    targetForm: 'MasterForm',
    replaces: 'StartPhotoToolsMaster.bat + LaunchHidden.vbs',
  },
  {
    trigger: '日付フォルダ右クリック / D&D',
    arguments: '--open "<folderPath>"（自動分岐）',
    targetForm: 'DailyWorkflowForm / PhotoInfoEditorForm',
    replaces: 'MakePhotoInfo.bat + 日付フォルダ自動分岐',
  },
  {
    trigger: '日次ワークフロー直接起動',
    arguments: '--workflow "<dateFolderPath>"',
    targetForm: 'DailyWorkflowForm',
    replaces: 'StartDailyWorkflow.bat',
  },
  {
    trigger: '被写体プロパティ強制起動（1日1人対応）',
    arguments: '--editor "<folderPath>" --force-editor',
    targetForm: 'PhotoInfoEditorForm',
    replaces: 'PhotoInfoEditor.ps1 -ForceEditor',
  },
  {
    trigger: '設定編集画面起動',
    arguments: '--settings',
    targetForm: 'SettingsForm',
    replaces: 'SettingsEditor.ps1',
  },
  {
    trigger: '送る (SendTo) / 単独起動 / D&D',
    arguments: 'GigaFileUploader.exe "<folderOrFilePath>"（引数なしでD&D待機）',
    targetForm: 'GigaFileUploadForm（単独 EXE）',
    replaces: 'gigafile/launch_gigafile.bat + send_to_gigafile.ps1',
  },
  {
    trigger: 'Excel台帳ハイパーリンク',
    arguments: '--protocol "phototools://..."',
    targetForm: 'ProtocolRouter → 各フォーム / Explorer',
    replaces: 'RegisterProtocol.bat + OpenFromProtocol.ps1',
  },
  {
    trigger: '台帳一括再同期',
    arguments: '--sync-excel',
    targetForm: 'ExcelSyncProgressDialog',
    replaces: 'SyncExcelFromTxt.bat + SyncExcelFromTxt.ps1',
  },
];

const DATA_COMPAT_ROWS: DataCompatRow[] = [
  {
    asset: 'settings.ini',
    format: 'UTF-8 (BOM付) + CRLF / INI 4セクション',
    strategy: '現行 [Paths] [ArchivePeriod] [Extensions] [Mega] および互換キー名を完全維持して読み書き',
    coexistence: 'PS版・VB.NET版で同一ファイルをそのまま共有可能',
  },
  {
    asset: '写真情報.txt / scene.txt',
    format: 'UTF-8 (BOM付) + CRLF / 【項目】+ --- 人物ブロック',
    strategy: '日付フォルダ直下（1日1人）およびサブフォルダ配置の両対応。【X】(@ID)／【X_URL】分離自動修正・【DLパスワード】・【保持期限】・旧コロン形式互換も継承',
    coexistence: 'どちらで編集・保存しても相互に完全読込可能',
  },
  {
    asset: 'x_history.json / scene_history.json / message_templates.json / ai_character_settings.json',
    format: 'UTF-8 JSON（履歴配列・定型文・AI判定設定）',
    strategy: 'System.Text.Json で現行JSON構造（message_templates.json の定型文＆MEGAコメント5種、ai_character_settings.json のモデル・縮小・書式設定）をそのままデシリアライズ。未存在時のみ初期生成し既存データは上書きしない',
    coexistence: 'D:\\PhotoTools\\data 配下の既存履歴・定型文・AI設定をそのまま継続利用',
  },
  {
    asset: 'data/gemini_api_key.dat',
    format: 'Windows DPAPI 暗号化バイナリ（CurrentUser）',
    strategy: 'System.Security.Cryptography.ProtectedData (DataProtectionScope.CurrentUser) で現行 PS 版と同一フォーマットのまま復号・暗号化。ZIP配布やログへは一切出力しない',
    coexistence: '同一Windowsユーザーであれば PS版・VB.NET版で登録済みAPIキーをそのまま共有可能',
  },
  {
    asset: '写真管理一覧.xlsx',
    format: 'OpenXML (.xlsx) 全18列 / phototools:// リンク',
    strategy: 'Excel COM 非依存を厳守し、OpenXML 直接読み書きで一意キー（パス＋モデル名＋人物連番）と列構造を完全維持',
    coexistence: '既存の台帳ファイルを変換不要でそのまま追記・更新可能',
  },
  {
    asset: 'ログ出力 (data/logs/*.log)',
    format: 'UTF-8 テキスト（タイムスタンプ＋レベル＋詳細）',
    strategy: 'AppLogger.vb で同等の日別ログ・MEGA診断ログ・未処理例外ログを出力',
    coexistence: '同じ data/logs フォルダへ時系列で出力',
  },
];

const MODULE_MAPPINGS: ModuleMappingRow[] = [
  {
    phase: 'PHASE1',
    phaseLabel: 'Phase 1: 基盤・設定・Master',
    currentPsFile: 'common/LogHelper.ps1',
    targetVbClass: 'Infrastructure/AppLogger.vb',
    project: 'PhotoTools.Core',
    notes: 'スレッドセーフな日別ログ出力・例外スタック記録',
  },
  {
    phase: 'PHASE1',
    phaseLabel: 'Phase 1: 基盤・設定・Master',
    currentPsFile: 'common/ConfigHelper.ps1',
    targetVbClass: 'Services/ConfigService.vb + Models/AppConfig.vb',
    project: 'PhotoTools.Core',
    notes: 'settings.ini 読込・保存・四半期判定・互換キー吸収',
  },
  {
    phase: 'PHASE1',
    phaseLabel: 'Phase 1: 基盤・設定・Master',
    currentPsFile: 'common/PhotoInfoHelper.ps1',
    targetVbClass: 'Services/PhotoInfoService.vb + Models/PhotoInfoDocument.vb',
    project: 'PhotoTools.Core',
    notes: '写真情報.txt パーサ／ライタ・日付直下判定・未送付保護',
  },
  {
    phase: 'PHASE1',
    phaseLabel: 'Phase 1: 基盤・設定・Master',
    currentPsFile: 'common/ExcelHelper.ps1',
    targetVbClass: 'Services/ExcelLedgerService.vb',
    project: 'PhotoTools.Core',
    notes: 'Excel COM非依存のOpenXML 18列読み書き・移動パス追従',
  },
  {
    phase: 'PHASE1',
    phaseLabel: 'Phase 1: 基盤・設定・Master',
    currentPsFile: 'editor/SettingsEditor.ps1',
    targetVbClass: 'Forms/SettingsForm.vb + Infrastructure/OsRegistrationService.vb',
    project: 'PhotoTools.App',
    notes: '5タブ設定画面（パス・期分け/MEGA・JSON/OS登録・メッセージ定型文＆MEGAコメント・AIキャラ判定/DPAPIキー）',
  },
  {
    phase: 'PHASE1',
    phaseLabel: 'Phase 1: 基盤・設定・Master',
    currentPsFile: 'PhotoToolsMaster.ps1',
    targetVbClass: 'Forms/MasterForm.vb + Services/DiagnosticsService.vb',
    project: 'PhotoTools.App',
    notes: '3タブ非同期スキャン・不整合診断・台帳自動補完・各画面起動',
  },
  {
    phase: 'PHASE2',
    phaseLabel: 'Phase 2: 日次フロー・エディタ',
    currentPsFile: 'common/SceneHelper.ps1 / XHelper.ps1',
    targetVbClass: 'Services/SceneService.vb + Services/XHistoryService.vb',
    project: 'PhotoTools.Core',
    notes: 'scene.txt 2階層継承・履歴学習・HttpClient UTF-8取得',
  },
  {
    phase: 'PHASE2',
    phaseLabel: 'Phase 2: 日次フロー・エディタ',
    currentPsFile: 'common/PhotoEditorLogic.ps1 / editor/PhotoInfoEditor.ps1',
    targetVbClass: 'Forms/PhotoInfoEditorForm.vb + Services/FolderPairService.vb',
    project: 'PhotoTools.App',
    notes: '3ルートペア解決・日付直下/子フォルダ両対応・複数人編集・未保存確認',
  },
  {
    phase: 'PHASE2',
    phaseLabel: 'Phase 2: 日次フロー・エディタ',
    currentPsFile: 'common/MessageTemplateHelper.ps1 / editor/MessageComposerDialog.ps1',
    targetVbClass: 'Services/MessageTemplateService.vb + Forms/MessageComposerForm.vb',
    project: 'PhotoTools.App',
    notes: '単体/まとめ送付メッセージ作成・個撮/複数リンク＋共演者整形・MEGAコメント切替・送付済み連動',
  },
  {
    phase: 'PHASE2',
    phaseLabel: 'Phase 2: 日次フロー・エディタ',
    currentPsFile: 'workflow/DailyWorkflow.ps1',
    targetVbClass: 'Forms/DailyWorkflowForm.vb',
    project: 'PhotoTools.App',
    notes: '日付自動紐づけ・階層ツリー・子フォルダ3ルートリネーム同期',
  },
  {
    phase: 'PHASE2',
    phaseLabel: 'Phase 2: 日次フロー・エディタ',
    currentPsFile: 'workflow/WorkflowStep1Helper.ps1 / Step2Helper.ps1 / Step5Helper.ps1',
    targetVbClass: 'Services/WorkflowStep1Service.vb / Step2Service.vb / Step5Service.vb',
    project: 'PhotoTools.Core',
    notes: '連番フォルダ作成・RAW/構成複製・四半期長期アーカイブ＆台帳追従',
  },
  {
    phase: 'PHASE2',
    phaseLabel: 'Phase 2: 日次フロー・エディタ',
    currentPsFile: 'workflow/WorkflowStep3Helper.ps1',
    targetVbClass: 'Services/WorkflowStep3Service.vb + Forms/Step3MonitorDialog.vb',
    project: 'PhotoTools.App',
    notes: 'PeriodicTimer非同期1秒監視・上書き制御・保留理由管理・txt除外',
  },
  {
    phase: 'PHASE2',
    phaseLabel: 'Phase 2: 日次フロー・エディタ',
    currentPsFile: 'workflow/WorkflowStep4Helper.ps1',
    targetVbClass: 'Services/WorkflowStep4Service.vb + Forms/Step4CompareDialog.vb',
    project: 'PhotoTools.App',
    notes: 'Canon 8文字コア名正規化・統合比較リスト・フルパス表示＆安全削除',
  },
  {
    phase: 'PHASE3',
    phaseLabel: 'Phase 3: 外部連携・OS統合・テスト',
    currentPsFile: 'common/MegaHelper.ps1',
    targetVbClass: 'Services/MegaService.vb + Forms/MegaProgressDialog.vb',
    project: 'PhotoTools.Core',
    notes: 'MEGAcmd 非同期実行・リアルタイム標準出力ログ・キャンセル対応',
  },
  {
    phase: 'PHASE3',
    phaseLabel: 'Phase 3: 外部連携・OS統合・テスト',
    currentPsFile: 'gigafile/send_to_gigafile.ps1 / common/GigaFileHelper.ps1',
    targetVbClass: 'PhotoTools.GigaFile (GigaFileUploader.exe) + Services/GigaFileService.vb',
    project: 'PhotoTools.GigaFile',
    notes: '単独 EXE として完全分離。本体や settings.ini 無しでも汎用送信でき、写真情報.txt があるフォルダでは自動命名・URL自動記録を自動有効化',
  },
  {
    phase: 'PHASE3',
    phaseLabel: 'Phase 3: 外部連携・OS統合・テスト',
    currentPsFile: 'common/GeminiCharacterHelper.ps1 / editor/CharacterLookupDialog.ps1',
    targetVbClass: 'Services/GeminiCharacterService.vb + Forms/CharacterLookupDialog.vb',
    project: 'PhotoTools.App',
    notes: '6層漏洩対策（顔マスク・未設定警告・メモリ上Exif除去＆縮小・DPAPI暗号化キー・有料枠確認・キャラ名（作品名）反映）',
  },
  {
    phase: 'PHASE3',
    phaseLabel: 'Phase 3: 外部連携・OS統合・テスト',
    currentPsFile: 'common/OpenFromProtocol.ps1 / Register*.ps1',
    targetVbClass: 'Program.vb (ProtocolRouter) + Infrastructure/OsRegistrationService.vb',
    project: 'PhotoTools.App',
    notes: 'HKCUレジストリ登録（右クリック・phototools://）・SendToショートカット直接生成',
  },
  {
    phase: 'PHASE3',
    phaseLabel: 'Phase 3: 外部連携・OS統合・テスト',
    currentPsFile: 'tests/TestManager.ps1 / ModuleTestCases.ps1',
    targetVbClass: 'PhotoTools.Core.Tests/*Tests.vb',
    project: 'PhotoTools.Core.Tests',
    notes: 'xUnit による自動単体・結合テスト（dotnet test で数秒実行）',
  },
];

const SOLUTION_TREE = `PhotoTools.Net/
├── PhotoTools.sln
├── README.md                              # Windows でのビルド・発行手順
├── src/
│   ├── PhotoTools.Core/                   # net10.0 業務ロジック層 (UI非依存・テスト可能)
│   │   ├── PhotoTools.Core.vbproj         # OptionStrict=On / Nullable対策 / OpenXML
│   │   ├── Models/
│   │   │   ├── AppConfig.vb               # settings.ini 全項目モデル
│   │   │   ├── PhotoInfoDocument.vb       # 写真情報.txt (共通項目 + 人物リスト)
│   │   │   ├── FolderPair.vb              # Import1/2・RAW・Developed 3ルート紐づけ
│   │   │   ├── LedgerRow.vb               # 写真管理一覧.xlsx 18列モデル
│   │   │   └── WorkflowModels.vb          # Step3保留情報 / Step4比較結果 / 診断結果
│   │   ├── Services/
│   │   │   ├── ConfigService.vb           # INI 読み書き・四半期計算
│   │   │   ├── PhotoInfoService.vb        # 写真情報.txt 読込/保存 (日付直下・子フォルダ両対応)
│   │   │   ├── SceneService.vb            # scene.txt 2階層継承 + scene_history.json
│   │   │   ├── XHistoryService.vb         # x_history.json + Xアカウント名取得 (HttpClient)
│   │   │   ├── ExcelLedgerService.vb      # OpenXML 直接読み書き (Excel COM非依存)
│   │   │   ├── FolderSyncService.vb       # 子フォルダ名3ルート一括リネーム同期
│   │   │   ├── WorkflowStep1Service.vb    # Step1: 仕分け連番フォルダ作成
│   │   │   ├── WorkflowStep2Service.vb    # Step2: RAW移動 & フォルダ構成複製
│   │   │   ├── WorkflowStep3Service.vb    # Step3: JPEG自動振分 & 保留判定エンジン
│   │   │   ├── WorkflowStep4Service.vb    # Step4: Canon 8文字コア名比較 & 安全削除
│   │   │   ├── WorkflowStep5Service.vb    # Step5: 四半期長期アーカイブ & 台帳パス追従
│   │   │   ├── MegaService.vb             # MEGAcmd 非同期実行 & 共有リンク取得
│   │   │   ├── GigaFileService.vb         # ZipFile作成 + HttpClient ギガファイル便送信
│   │   │   ├── MessageTemplateService.vb  # 送付定型文・リンク整形・MEGAコメント管理
│   │   │   ├── GeminiCharacterService.vb  # DPAPIキー保護・Exif除去縮小・Geminiキャラ判定
│   │   │   └── DiagnosticsService.vb      # 重複日付診断・台帳セルフヒーリング
│   │   └── Infrastructure/
│   │       ├── AppLogger.vb               # スレッドセーフ日別ログ出力
│   │       ├── EncodingHelper.vb          # UTF-8 BOM + CRLF 保証ユーティリティ
│   │       ├── CanonNameNormalizer.vb     # IMG_2650 / IMG_2650_1 ベース名判定
│   │       └── OsRegistrationService.vb   # HKCU 右クリック / phototools:// / SendTo 登録
│   │
│   └── PhotoTools.App/                    # net10.0-windows PhotoTools本体 (PhotoTools.exe)
│       ├── PhotoTools.App.vbproj          # OutputType=WinExe (黒画面ゼロ / BAT不要)
│       ├── Program.vb                     # エントリーポイント・CLI引数ルーティング・例外捕捉
│       └── Forms/
│           ├── MasterForm.vb              # 総合マスター管理 (作業用/完了後/アーカイブ)
│           ├── DailyWorkflowForm.vb       # 日次ワークフロー統括画面 (1日1人ボタン含む)
│           ├── Step3MonitorDialog.vb      # Step3 1秒非同期監視 & 保留リスト管理
│           ├── Step4CompareDialog.vb      # Step4 統合比較 & 一括安全削除ダイアログ
│           ├── PhotoInfoEditorForm.vb     # 被写体プロパティ (写真情報.txt編集)
│           ├── CharacterLookupDialog.vb   # AIキャラ名検索 (顔マスク・6層漏洩対策)
│           ├── MessageComposerForm.vb     # 送付メッセージ作成 (単体/まとめ・MEGA連動)
│           ├── SettingsForm.vb            # settings.ini / JSON / OS登録 / 定型文 / AI 5タブ設定画面
│           └── MegaProgressDialog.vb      # MEGA 処理中リアルタイムログ & キャンセル
│
│   └── PhotoTools.GigaFile/               # net10.0-windows 単独ギガファイル便アプリ (GigaFileUploader.exe)
│       ├── PhotoTools.GigaFile.vbproj     # OutputType=WinExe (本体非依存・単体配布/SendTo対応)
│       ├── Program.vb                     # 引数なしD&D待機 / ファイル・フォルダ引数受付
│       └── Forms/
│           └── GigaFileUploadForm.vb      # 自動命名・カスタム名・子フォルダ一括・URL自動記録
│
└── tests/
    └── PhotoTools.Core.Tests/             # net10.0 xUnit テストプロジェクト
        ├── PhotoTools.Core.Tests.vbproj
        ├── ConfigServiceTests.vb
        ├── PhotoInfoServiceTests.vb       # 日付直下(1日1人)・複数人・未送付保護テスト
        ├── ExcelLedgerServiceTests.vb
        ├── WorkflowStepsTests.vb          # Step1〜5 サンドボックス結合テスト
        └── GigaFileAndSceneTests.vb`;

export default function VbNetMigrationPlanSection({ onSelectFile }: VbNetMigrationPlanSectionProps) {
  const [phaseFilter, setPhaseFilter] = useState<MigrationPhase>('ALL');

  const filteredMappings = useMemo(() => {
    if (phaseFilter === 'ALL') return MODULE_MAPPINGS;
    return MODULE_MAPPINGS.filter((row) => row.phase === phaseFilter);
  }, [phaseFilter]);

  const handleOpenPsFile = (rawFile: string) => {
    if (!onSelectFile) return;
    const firstFile = rawFile.split('/')[0].trim();
    if (rawFile.includes(' / ')) {
      onSelectFile(rawFile.split(' / ')[0].trim());
      return;
    }
    if (!firstFile.includes('*')) {
      onSelectFile(rawFile.trim());
    }
  };

  return (
    <div className="space-y-8">
      {/* 概要サマリー */}
      <section className="bg-white border border-slate-200 p-6 space-y-5">
        <div className="flex flex-col md:flex-row md:items-end justify-between gap-3 border-b border-slate-200 pb-4">
          <div className="space-y-1">
            <div className="text-xs font-mono text-slate-500">
              Target: .NET 10 (LTS) · VB.NET · Windows Forms · 本体 + 単独ギガファイル便 2 EXE構成
            </div>
            <h2 className="text-lg font-bold text-slate-900">
              .NET 10（VB.NET）移行設計・構成案
            </h2>
            <p className="text-xs text-slate-600 leading-relaxed max-w-4xl">
              現行の PowerShell 版（<code className="font-mono">phototools/</code>）をそのまま稼働基準として維持しつつ、
              本体アプリ（<code className="font-mono">PhotoTools.exe</code>）と単独利用可能なギガファイル便送信アプリ（<code className="font-mono">GigaFileUploader.exe</code>）の 2 EXE 構成へ段階的に移行するための設計書です。
            </p>
          </div>
          <div className="text-xs font-mono text-slate-600 tabular-nums whitespace-nowrap shrink-0">
            現行 PS 全スクリプト → Core + 2 EXE 構成
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div className="bg-slate-50 border border-slate-200 p-4 space-y-2">
            <div className="flex items-center gap-2 text-sm font-bold text-slate-900">
              <Terminal className="w-4 h-4 text-teal-700 shrink-0" />
              <span>BAT・VBS・黒画面を完全撤廃</span>
            </div>
            <p className="text-xs text-slate-600 leading-relaxed">
              <code className="font-mono">OutputType=WinExe</code> のネイティブ Windows アプリとして出力するため、
              <code className="font-mono">.bat</code>・<code className="font-mono">LaunchHidden.vbs</code>・ExecutionPolicy・Shift-JIS文字化け・起動時の黒画面が一切発生しません。
            </p>
          </div>

          <div className="bg-slate-50 border border-slate-200 p-4 space-y-2">
            <div className="flex items-center gap-2 text-sm font-bold text-slate-900">
              <Cpu className="w-4 h-4 text-teal-700 shrink-0" />
              <span>Async/Await 非同期 & 厳格型チェック</span>
            </div>
            <p className="text-xs text-slate-600 leading-relaxed">
              <code className="font-mono">Option Strict On</code> によりビルド時に型・プロパティ名の不整合を全検出。フォルダ走査・Step3監視・MEGA・ギガファイル便送信もUIを固めずに並列実行します。
            </p>
          </div>

          <div className="bg-slate-50 border border-slate-200 p-4 space-y-2">
            <div className="flex items-center gap-2 text-sm font-bold text-slate-900">
              <ShieldCheck className="w-4 h-4 text-teal-700 shrink-0" />
              <span>現行データ 100% 互換で並行運用可能</span>
            </div>
            <p className="text-xs text-slate-600 leading-relaxed">
              <code className="font-mono">settings.ini</code>・<code className="font-mono">写真情報.txt</code>・各種JSON・<code className="font-mono">写真管理一覧.xlsx</code> の仕様を完全踏襲するため、現行 PowerShell 版とデータを共有したまま安全に段階移行できます。
            </p>
          </div>
        </div>
      </section>

      {/* 1. プロジェクト・ソリューション構成 */}
      <section className="bg-white border border-slate-200 p-6 space-y-4">
        <div className="flex items-center gap-2 border-b border-slate-200 pb-3">
          <FolderTree className="w-4 h-4 text-teal-700 shrink-0" />
          <div>
            <h3 className="text-base font-bold text-slate-900">1. ソリューション・プロジェクト構成案（Core / App / Tests 3層分離）</h3>
            <p className="text-xs text-slate-500 mt-0.5">
              業務ロジックを UI 非依存の <code className="font-mono">PhotoTools.Core</code> に切り出すことで、将来の画面改修や自動テスト（<code className="font-mono">dotnet test</code>）を容易にします。
            </p>
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
          <div className="lg:col-span-8 bg-slate-950 text-slate-100 border border-slate-800 p-4 overflow-x-auto">
            <pre className="text-[11px] font-mono leading-relaxed whitespace-pre">{SOLUTION_TREE}</pre>
          </div>

          <div className="lg:col-span-4 space-y-4">
            <div className="bg-slate-50 border border-slate-200 p-4 space-y-2">
              <div className="text-xs font-bold text-slate-900">プロジェクト責務の分離</div>
              <dl className="space-y-2.5 text-xs text-slate-700">
                <div>
                  <dt className="font-mono font-semibold text-slate-900">PhotoTools.Core (net10.0)</dt>
                  <dd className="text-slate-600 mt-0.5 leading-relaxed">
                    ファイル操作・INI/JSON/写真情報.txt・OpenXML台帳・Step1〜5処理・MEGA/GigaFile通信を集約。WinFormsに依存しない純粋ライブラリ。
                  </dd>
                </div>
                <div>
                  <dt className="font-mono font-semibold text-slate-900">PhotoTools.App (PhotoTools.exe)</dt>
                  <dd className="text-slate-600 mt-0.5 leading-relaxed">
                    Master・DailyWorkflow・Step3/4・PhotoInfoEditor・SettingsForm を1本に統合。ギガファイル便ボタンからは単独 EXE を呼び出し連携。
                  </dd>
                </div>
                <div>
                  <dt className="font-mono font-semibold text-slate-900">PhotoTools.GigaFile (GigaFileUploader.exe)</dt>
                  <dd className="text-slate-600 mt-0.5 leading-relaxed">
                    単独で起動・D&D・SendTo送信できる独立EXE。写真情報.txt があるフォルダだけ自動で命名＆URL記録を行い、一般フォルダもそのまま送信可能。
                  </dd>
                </div>
                <div>
                  <dt className="font-mono font-semibold text-slate-900">PhotoTools.Core.Tests (xUnit)</dt>
                  <dd className="text-slate-600 mt-0.5 leading-relaxed">
                    現行 <code className="font-mono">ModuleTestCases.ps1</code> の全検証項目（全12モジュール：01〜12）をサンドボックスで自動実行。
                  </dd>
                </div>
              </dl>
            </div>

            <div className="bg-slate-50 border border-slate-200 p-4 space-y-2">
              <div className="text-xs font-bold text-slate-900">想定ビルド・配布方式（Windows側）</div>
              <div className="space-y-2 text-xs text-slate-700 leading-relaxed">
                <p>
                  <strong>通常配布（軽量）</strong>：<code className="font-mono text-[11px]">dotnet publish -c Release -r win-x64 --self-contained false</code>（要 .NET 10 Desktop Runtime / 数MB）
                </p>
                <p>
                  <strong>単体EXE配布</strong>：<code className="font-mono text-[11px]">--self-contained true -p:PublishSingleFile=true</code>（ランタイム不要で即実行可能）
                </p>
                <p className="text-slate-500">
                  ※外部NuGet依存は最小限（標準 <code className="font-mono">System.Text.Json</code> / <code className="font-mono">System.Net.Http</code> / <code className="font-mono">System.IO.Compression</code> + 必要に応じて <code className="font-mono">DocumentFormat.OpenXml</code>）に抑えます。
                </p>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* 2. 画面構成 & 起動ルーティング */}
      <section className="bg-white border border-slate-200 shadow-xs">
        <div className="px-6 py-4 border-b border-slate-200 flex items-center justify-between gap-3">
          <div className="flex items-center gap-2">
            <Monitor className="w-4 h-4 text-teal-700 shrink-0" />
            <div>
              <h3 className="text-base font-bold text-slate-900">2. 画面構成 & 起動引数ルーティング（本体 EXE ＋ 単独ギガファイル便 EXE）</h3>
              <p className="text-xs text-slate-500 mt-0.5">
                PhotoTools 本体は <code className="font-mono">PhotoTools.exe</code> 1本へ集約し、ギガファイル便送信は独立した <code className="font-mono">GigaFileUploader.exe</code> に分離します。
              </p>
            </div>
          </div>
          <span className="font-mono text-xs text-slate-500 tabular-nums whitespace-nowrap">
            全 {CLI_ROUTES.length} ルート
          </span>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="bg-slate-50 border-b border-slate-200 text-[11px] font-semibold text-slate-600 tracking-wider">
                <th className="py-2.5 px-4 w-52">起動トリガー</th>
                <th className="py-2.5 px-4 w-64">コマンドライン引数</th>
                <th className="py-2.5 px-4 w-60">起動する VB.NET 画面</th>
                <th className="py-2.5 px-4">置き換わる現行ファイル</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-200 text-xs">
              {CLI_ROUTES.map((route) => (
                <tr key={route.trigger} className="hover:bg-slate-50/70 align-top">
                  <td className="py-3 px-4 font-medium text-slate-900">{route.trigger}</td>
                  <td className="py-3 px-4 font-mono text-[11px] text-slate-800">{route.arguments}</td>
                  <td className="py-3 px-4 font-mono text-[11px] text-teal-800 font-semibold">{route.targetForm}</td>
                  <td className="py-3 px-4 font-mono text-[11px] text-slate-500">{route.replaces}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      {/* 3. データ互換方針 */}
      <section className="bg-white border border-slate-200 shadow-xs">
        <div className="px-6 py-4 border-b border-slate-200 flex items-center gap-2">
          <Database className="w-4 h-4 text-teal-700 shrink-0" />
          <div>
            <h3 className="text-base font-bold text-slate-900">3. 既存データ互換方針（PowerShell 版との完全共存）</h3>
            <p className="text-xs text-slate-500 mt-0.5">
              移行期間中でも現行 PowerShell 版と VB.NET 版を自由に行き来できるよう、データ形式・文字コード・キー規約を 100% 維持します。
            </p>
          </div>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="bg-slate-50 border-b border-slate-200 text-[11px] font-semibold text-slate-600 tracking-wider">
                <th className="py-2.5 px-4 w-48">対象データ</th>
                <th className="py-2.5 px-4 w-56">ファイル形式・文字コード</th>
                <th className="py-2.5 px-4">VB.NET 側での実装方針</th>
                <th className="py-2.5 px-4 w-60">並行運用時の互換性</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-200 text-xs">
              {DATA_COMPAT_ROWS.map((row) => (
                <tr key={row.asset} className="hover:bg-slate-50/70 align-top">
                  <td className="py-3 px-4 font-mono text-[11px] font-semibold text-slate-900">{row.asset}</td>
                  <td className="py-3 px-4 text-slate-700">{row.format}</td>
                  <td className="py-3 px-4 text-slate-700 leading-relaxed">{row.strategy}</td>
                  <td className="py-3 px-4 text-emerald-800 font-medium">{row.coexistence}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      {/* 4. 段階的移行ロードマップ & モジュール対応表 */}
      <section className="bg-white border border-slate-200 shadow-xs">
        <div className="px-6 py-4 border-b border-slate-200 flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
          <div className="flex items-center gap-2">
            <Layers className="w-4 h-4 text-teal-700 shrink-0" />
            <div>
              <h3 className="text-base font-bold text-slate-900">4. 段階的移行ロードマップ & モジュール対応表</h3>
              <p className="text-xs text-slate-500 mt-0.5">
                安全に検証しながら進める 3 フェーズ構成です。現行ファイル名をクリックすると PowerShell ソースを確認できます。
              </p>
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-1 p-1 bg-slate-100 rounded-md">
            {(
              [
                { id: 'ALL', label: '全フェーズ' },
                { id: 'PHASE1', label: 'Phase 1: 基盤・Master' },
                { id: 'PHASE2', label: 'Phase 2: 日次・編集' },
                { id: 'PHASE3', label: 'Phase 3: 外部・OS' },
              ] as const
            ).map((opt) => (
              <button
                key={opt.id}
                type="button"
                onClick={() => setPhaseFilter(opt.id)}
                className={`px-3 py-1.5 text-xs font-medium rounded-sm whitespace-nowrap shrink-0 transition-colors ${
                  phaseFilter === opt.id
                    ? 'bg-white text-slate-900 shadow-xs'
                    : 'text-slate-600 hover:text-slate-900'
                }`}
              >
                {opt.label}
              </button>
            ))}
          </div>
        </div>

        {/* 3フェーズ概要バー */}
        <div className="grid grid-cols-1 md:grid-cols-3 divide-y md:divide-y-0 md:divide-x divide-slate-200 border-b border-slate-200 bg-slate-50/60">
          <div className="p-4 space-y-1">
            <div className="flex items-center justify-between text-xs">
              <span className="font-mono font-bold text-slate-900">Phase 1 · 最小稼働＆設定基盤</span>
              <span className="text-slate-500">優先度 高</span>
            </div>
            <p className="text-xs text-slate-600 leading-relaxed">
              Core 基盤（Config / PhotoInfo / Excel / Logger）＋ <code className="font-mono">SettingsForm</code> ＋ <code className="font-mono">MasterForm</code> を構築。ビルド・起動・既存データ読込を実機確認。
            </p>
          </div>
          <div className="p-4 space-y-1">
            <div className="flex items-center justify-between text-xs">
              <span className="font-mono font-bold text-slate-900">Phase 2 · 日常ワークフロー本体</span>
              <span className="text-slate-500">優先度 高</span>
            </div>
            <p className="text-xs text-slate-600 leading-relaxed">
              <code className="font-mono">DailyWorkflowForm</code>・Step1〜5（1秒監視・Canon 8文字比較含む）・<code className="font-mono">PhotoInfoEditorForm</code>（1日1人日付直下含む）を移植し日常運用を移行。
            </p>
          </div>
          <div className="p-4 space-y-1">
            <div className="flex items-center justify-between text-xs">
              <span className="font-mono font-bold text-slate-900">Phase 3 · 外部連携・OS統合・完全切替</span>
              <span className="text-slate-500">仕上げ</span>
            </div>
            <p className="text-xs text-slate-600 leading-relaxed">
              MEGA / ギガファイル便ネイティブ送信・右クリック／プロトコル／SendTo の <code className="font-mono">PhotoTools.exe</code> 登録・xUnit 全テスト合格をもって PS 版から切替。
            </p>
          </div>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="bg-slate-50 border-b border-slate-200 text-[11px] font-semibold text-slate-600 tracking-wider">
                <th className="py-2.5 px-4 w-44">フェーズ</th>
                <th className="py-2.5 px-4 w-60">現行 PowerShell モジュール</th>
                <th className="py-2.5 px-4 w-64">移行先 VB.NET クラス</th>
                <th className="py-2.5 px-4 w-36">配置プロジェクト</th>
                <th className="py-2.5 px-4">移行・改善ポイント</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-200 text-xs">
              {filteredMappings.map((row) => (
                <tr key={row.currentPsFile} className="hover:bg-slate-50/70 align-top">
                  <td className="py-3 px-4 font-medium text-slate-800 whitespace-nowrap">{row.phaseLabel}</td>
                  <td className="py-3 px-4">
                    {onSelectFile && !row.currentPsFile.includes('*') ? (
                      <button
                        type="button"
                        onClick={() => handleOpenPsFile(row.currentPsFile)}
                        className="text-left font-mono text-[11px] text-sky-700 hover:text-sky-900 hover:underline"
                      >
                        {row.currentPsFile}
                      </button>
                    ) : (
                      <span className="font-mono text-[11px] text-slate-700">{row.currentPsFile}</span>
                    )}
                  </td>
                  <td className="py-3 px-4 font-mono text-[11px] text-teal-800 font-semibold">{row.targetVbClass}</td>
                  <td className="py-3 px-4 font-mono text-[11px] text-slate-600 whitespace-nowrap">{row.project}</td>
                  <td className="py-3 px-4 text-slate-700 leading-relaxed">{row.notes}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      {/* 5. 着手前の確認事項（決定しておくとスムーズな項目） */}
      <section className="bg-white border border-slate-200 p-6 space-y-4">
        <div className="flex items-center gap-2 border-b border-slate-200 pb-3">
          <Package className="w-4 h-4 text-teal-700 shrink-0" />
          <h3 className="text-sm font-bold text-slate-900">5. 実装着手前に決めておくとスムーズなポイント</h3>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-xs text-slate-700 leading-relaxed">
          <div className="bg-slate-50 border border-slate-200 p-4 space-y-1.5">
            <div className="font-semibold text-slate-900 flex items-center gap-1.5">
              <CheckCircle2 className="w-3.5 h-3.5 text-teal-700 shrink-0" />
              <span>ビルド環境の確認</span>
            </div>
            <p className="text-slate-600">
              Windows PC 側で Visual Studio 2026（または .NET 10 SDK の <code className="font-mono">dotnet build</code>）のどちらを主に使うか。両方に対応する標準 <code className="font-mono">.sln / .vbproj</code> 構成で出力します。
            </p>
          </div>
          <div className="bg-slate-50 border border-slate-200 p-4 space-y-1.5">
            <div className="font-semibold text-slate-900 flex items-center gap-1.5">
              <CheckCircle2 className="w-3.5 h-3.5 text-teal-700 shrink-0" />
              <span>配布形式の選択</span>
            </div>
            <p className="text-slate-600">
              自分のPC中心であれば軽量な「フレームワーク依存（.NET 10 Desktop Runtime利用）」がビルドも高速で扱いやすくおすすめです。
            </p>
          </div>
          <div className="bg-slate-50 border border-slate-200 p-4 space-y-1.5">
            <div className="font-semibold text-slate-900 flex items-center gap-1.5">
              <ArrowRight className="w-3.5 h-3.5 text-teal-700 shrink-0" />
              <span>最初に着手する範囲</span>
            </div>
            <p className="text-slate-600">
              現行 PowerShell 版の仕様が固まり次第、まず <strong>Phase 1（Core基盤＋SettingsForm＋MasterForm）</strong> のプロジェクト一式を別フォルダ（<code className="font-mono">phototools_net/</code> 等）へ生成して動作確認する流れが安全です。
            </p>
          </div>
        </div>
      </section>
    </div>
  );
}
