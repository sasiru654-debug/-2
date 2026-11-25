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
    x: 40,
    y: 28,
    w: 220,
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
    x: 330,
    y: 28,
    w: 220,
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
    x: 620,
    y: 28,
    w: 210,
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
    x: 890,
    y: 28,
    w: 210,
    h: 68,
    role: 'Windows の「送る」メニューや D&D からギガファイル便アップローダを直接起動します。複数子フォルダの一括分割アップロードにも対応。',
    calledBy: ['Windows SendTo (install_gigafile_sendto.bat)'],
    calls: ['send_to_gigafile.ps1'],
  },

  // Row 2: Config & DailyWorkflow Hub
  {
    id: 'settings-editor',
    label: '設定編集画面',
    sublabel: 'editor/SettingsEditor.ps1',
    filePath: 'editor/SettingsEditor.ps1',
    layer: 'hub',
    groups: ['all', 'admin'],
    x: 40,
    y: 156,
    w: 220,
    h: 72,
    role: 'Master 右上ボタンから呼び出す環境設定 GUI。パス参照・存在チェック・期分け月・拡張子・MEGA設定の保存（.bak自動作成）と、関連JSON編集・OS登録バッチ実行を一元化します。',
    calledBy: ['PhotoToolsMaster.ps1'],
    calls: ['ConfigHelper.ps1', 'settings.ini', 'scene_history.json / x_history.json'],
  },
  {
    id: 'daily',
    label: '日次ワークフロー統括',
    sublabel: 'workflow/DailyWorkflow.ps1',
    filePath: 'workflow/DailyWorkflow.ps1',
    layer: 'hub',
    groups: ['all', 'daily', 'share'],
    x: 330,
    y: 156,
    w: 440,
    h: 72,
    role: '撮影日フォルダ単位の作業ハブ。取込元・RAW・現像後の3ルート紐づけ、scene.txt 配置、子フォルダ名3ルート一括同期、1日1人時の日付直下プロパティ編集、Step1〜5 呼び出しを統括します。',
    calledBy: ['PhotoToolsMaster.ps1', 'StartDailyWorkflow.bat', 'MakePhotoInfo.bat'],
    calls: ['Step1〜5 Helper', 'PhotoInfoEditor.ps1', 'GigaFileHelper.ps1', 'ExcelHelper.ps1'],
  },
  {
    id: 'tests',
    label: 'サンドボックス自動テスト',
    sublabel: 'tests/TestManager.ps1',
    filePath: 'tests/TestManager.ps1',
    layer: 'hub',
    groups: ['all', 'admin'],
    x: 840,
    y: 156,
    w: 260,
    h: 72,
    role: '本番フォルダ・台帳を汚さない一時サンドボックスで全10モジュール（構文チェック・単体検証）を一括実行するテストマネージャー。',
    calledBy: ['RunTestManager.bat', 'SettingsEditor.ps1'],
    calls: ['tests/ModuleTestCases.ps1 (01〜10)'],
  },

  // Row 3: 5-Step Pipeline
  {
    id: 'step1',
    label: 'Step1 仕分け作成',
    sublabel: 'WorkflowStep1Helper.ps1',
    filePath: 'workflow/WorkflowStep1Helper.ps1',
    layer: 'step',
    groups: ['all', 'daily'],
    x: 40,
    y: 288,
    w: 185,
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
    x: 255,
    y: 288,
    w: 195,
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
    w: 205,
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
    x: 715,
    y: 288,
    w: 185,
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
    x: 930,
    y: 288,
    w: 170,
    h: 64,
    role: '完了済み日付フォルダを期分けアーカイブ先へ別プロセス非同期で移送し、Excel台帳のパス列を自動追従します。',
    calledBy: ['DailyWorkflow.ps1 (別プロセス起動)'],
    calls: ['ArchiveRoot', 'ExcelHelper.ps1'],
  },

  // Row 4: PhotoInfoEditor & External Integrations
  {
    id: 'editor',
    label: '被写体プロパティ編集',
    sublabel: 'editor/PhotoInfoEditor.ps1',
    filePath: 'editor/PhotoInfoEditor.ps1',
    layer: 'editor',
    groups: ['all', 'daily', 'share'],
    x: 170,
    y: 416,
    w: 270,
    h: 74,
    role: '日付直下（1日1人）および子・孫フォルダの被写体情報（モデル名・衣装・X・コメント・送付状況）を編集。PhotoEditorLogic 経由で取込元／現像後の両方へ同時保存します。',
    calledBy: ['DailyWorkflow.ps1', 'MakePhotoInfo.bat', 'OpenFromProtocol.ps1'],
    calls: ['PhotoEditorLogic.ps1', 'MegaHelper.ps1', 'GigaFileHelper.ps1', 'ExcelHelper.ps1'],
  },
  {
    id: 'mega',
    label: 'MEGA 共有リンク取得',
    sublabel: 'common/MegaHelper.ps1 (非同期ログ)',
    filePath: 'common/MegaHelper.ps1',
    layer: 'external',
    groups: ['all', 'share'],
    x: 510,
    y: 416,
    w: 260,
    h: 74,
    role: 'MEGAcmd (mega-export) をバックグラウンドジョブで非同期実行し、ポップアップ内に処理ログをリアルタイム表示しながら共有リンクを取得します。',
    calledBy: ['PhotoInfoEditor.ps1'],
    calls: ['MEGAcmd', 'data/logs/mega_debug.log'],
  },
  {
    id: 'gigafile',
    label: 'ギガファイル便連携',
    sublabel: 'gigafile/send_to_gigafile.ps1',
    filePath: 'gigafile/send_to_gigafile.ps1',
    layer: 'external',
    groups: ['all', 'share'],
    x: 830,
    y: 416,
    w: 270,
    h: 74,
    role: '写真情報.txt 解析による自動命名ZIP生成、子フォルダ一括分割送信、発行URLと「送付済み」ステータスの自動書き戻しを実行します。',
    calledBy: ['DailyWorkflow.ps1', 'PhotoInfoEditor.ps1', 'launch_gigafile.bat'],
    calls: ['GigaFile サーバー', '写真情報.txt', 'ExcelHelper.ps1'],
  },

  // Row 5: Persistent Data & Ledger
  {
    id: 'config-data',
    label: '設定・履歴ファイル群',
    sublabel: 'settings.ini / *_history.json',
    filePath: 'settings.ini',
    layer: 'data',
    groups: ['all', 'admin'],
    x: 40,
    y: 552,
    w: 270,
    h: 68,
    role: '全ツール共通のパス・期分け・拡張子・MEGA設定（settings.ini）と、自動補完用のシーン履歴・Xアカウント履歴JSON。ConfigHelper.ps1 経由で統一参照されます。',
    calledBy: ['SettingsEditor.ps1', '全モジュール (ConfigHelper.ps1)'],
    calls: ['settings.ini.bak (自動バックアップ)'],
  },
  {
    id: 'photoinfo-txt',
    label: '写真情報.txt / scene.txt',
    sublabel: 'common/PhotoInfoHelper.ps1',
    filePath: 'common/PhotoInfoHelper.ps1',
    layer: 'data',
    groups: ['all', 'daily', 'share'],
    x: 375,
    y: 552,
    w: 320,
    h: 68,
    role: '各フォルダ（日付直下または子・孫）に配置される真実のソース。取込元と現像後の双方にペア同期され、SyncExcelFromTxt.ps1 や Master の一括スキャン元になります。',
    calledBy: ['PhotoInfoEditor.ps1', 'DailyWorkflow.ps1', 'send_to_gigafile.ps1'],
    calls: ['SyncExcelFromTxt.ps1', 'ExcelHelper.ps1'],
  },
  {
    id: 'excel-ledger',
    label: 'Excel 管理台帳 (OpenXML)',
    sublabel: 'common/ExcelHelper.ps1 / SyncExcel',
    filePath: 'common/ExcelHelper.ps1',
    layer: 'data',
    groups: ['all', 'daily', 'admin', 'share'],
    x: 760,
    y: 552,
    w: 340,
    h: 68,
    role: 'Excel 非依存の OpenXML 直接読み書きで 写真管理一覧.xlsx（全18列）を更新。子フォルダリネーム・Step5アーカイブ移動時のパス追従や台帳セルフヒーリングも担当します。',
    calledBy: ['PhotoToolsMaster.ps1', 'DailyWorkflow.ps1', 'PhotoInfoEditor.ps1', 'SyncExcelFromTxt.ps1'],
    calls: ['写真管理一覧.xlsx (.bak 保護付)'],
  },
];

const FLOW_EDGES: FlowEdgeDef[] = [
  // Master -> SettingsEditor & DailyWorkflow
  {
    id: 'e-master-settings',
    from: 'master',
    to: 'settings-editor',
    label: '設定編集',
    groups: ['all', 'admin'],
    path: 'M 150 96 L 150 156',
    labelX: 158,
    labelY: 130,
  },
  {
    id: 'e-master-daily',
    from: 'master',
    to: 'daily',
    label: '日付選択起動',
    groups: ['all', 'daily', 'admin'],
    path: 'M 260 66 L 300 66 L 300 184 L 330 184',
    labelX: 266,
    labelY: 118,
  },
  // Context -> DailyWorkflow
  {
    id: 'e-ctx-daily',
    from: 'context',
    to: 'daily',
    label: '日付フォルダ',
    groups: ['all', 'daily'],
    path: 'M 440 96 L 440 156',
    labelX: 448,
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
    path: 'M 725 96 L 725 130 L 800 130 L 800 382 L 365 382 L 365 416',
    labelX: 732,
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
    path: 'M 1100 62 L 1122 62 L 1122 453 L 1100 453',
    labelX: 1038,
    labelY: 124,
  },
  // SettingsEditor -> ConfigData
  {
    id: 'e-settings-config',
    from: 'settings-editor',
    to: 'config-data',
    label: '保存・反映',
    groups: ['all', 'admin'],
    path: 'M 40 192 L 18 192 L 18 586 L 40 586',
    labelX: 24,
    labelY: 400,
  },
  // Daily -> Step1..5 bus
  {
    id: 'e-daily-s1',
    from: 'daily',
    to: 'step1',
    groups: ['all', 'daily'],
    path: 'M 550 228 L 550 256 L 132 256 L 132 288',
  },
  {
    id: 'e-daily-s2',
    from: 'daily',
    to: 'step2',
    groups: ['all', 'daily'],
    path: 'M 550 228 L 550 256 L 352 256 L 352 288',
  },
  {
    id: 'e-daily-s3',
    from: 'daily',
    to: 'step3',
    label: 'Step 1〜5 実行',
    groups: ['all', 'daily'],
    path: 'M 550 228 L 550 288',
    labelX: 558,
    labelY: 248,
  },
  {
    id: 'e-daily-s4',
    from: 'daily',
    to: 'step4',
    groups: ['all', 'daily'],
    path: 'M 550 228 L 550 256 L 807 256 L 807 288',
  },
  {
    id: 'e-daily-s5',
    from: 'daily',
    to: 'step5',
    groups: ['all', 'daily'],
    path: 'M 550 228 L 550 256 L 1015 256 L 1015 288',
  },
  // Step1 -> Step2 -> Step3 -> Step4 -> Step5 sequential flow
  {
    id: 'e-s1-s2',
    from: 'step1',
    to: 'step2',
    groups: ['all', 'daily'],
    path: 'M 225 320 L 255 320',
  },
  {
    id: 'e-s2-s3',
    from: 'step2',
    to: 'step3',
    groups: ['all', 'daily'],
    path: 'M 450 320 L 480 320',
  },
  {
    id: 'e-s3-s4',
    from: 'step3',
    to: 'step4',
    groups: ['all', 'daily'],
    path: 'M 685 320 L 715 320',
  },
  {
    id: 'e-s4-s5',
    from: 'step4',
    to: 'step5',
    groups: ['all', 'daily'],
    path: 'M 900 320 L 930 320',
  },
  // Daily -> Editor (double click date root or subfolder)
  {
    id: 'e-daily-editor',
    from: 'daily',
    to: 'editor',
    label: '日付直下 / 子フォルダ編集',
    groups: ['all', 'daily', 'share'],
    path: 'M 330 202 L 296 202 L 296 256 L 238 256 L 238 382 L 285 382 L 285 416',
    labelX: 120,
    labelY: 376,
  },
  // Editor -> Mega & GigaFile
  {
    id: 'e-editor-mega',
    from: 'editor',
    to: 'mega',
    label: 'リンク取得',
    groups: ['all', 'share'],
    path: 'M 440 453 L 510 453',
    labelX: 446,
    labelY: 444,
  },
  {
    id: 'e-editor-giga',
    from: 'editor',
    to: 'gigafile',
    label: 'URL自動反映',
    groups: ['all', 'share'],
    path: 'M 340 490 L 340 518 L 910 518 L 910 490',
    labelX: 605,
    labelY: 512,
  },
  // Editor -> PhotoInfo.txt
  {
    id: 'e-editor-txt',
    from: 'editor',
    to: 'photoinfo-txt',
    label: 'ペア同期保存',
    groups: ['all', 'daily', 'share'],
    path: 'M 270 490 L 270 532 L 470 532 L 470 552',
    labelX: 335,
    labelY: 545,
  },
  // PhotoInfo.txt -> Excel
  {
    id: 'e-txt-excel',
    from: 'photoinfo-txt',
    to: 'excel-ledger',
    label: 'OpenXML 同期',
    groups: ['all', 'daily', 'admin', 'share'],
    path: 'M 695 586 L 760 586',
    labelX: 698,
    labelY: 577,
  },
  // GigaFile -> Excel
  {
    id: 'e-giga-excel',
    from: 'gigafile',
    to: 'excel-ledger',
    label: '送付済反映',
    groups: ['all', 'share'],
    path: 'M 985 490 L 985 552',
    labelX: 993,
    labelY: 526,
  },
  // Step5 -> Excel (archive path update)
  {
    id: 'e-s5-excel',
    from: 'step5',
    to: 'excel-ledger',
    label: '移動後パス追従',
    dashed: true,
    groups: ['all', 'daily', 'admin'],
    path: 'M 1060 352 L 1060 390 L 1114 390 L 1114 586 L 1100 586',
    labelX: 1018,
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
  { id: 'admin', label: 'Master・設定・テスト' },
  { id: 'share', label: 'MEGA・ギガファイル便・台帳' },
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
          被写体プロパティ編集
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
          viewBox="0 0 1145 645"
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
            04. 写真情報編集 ＆ クラウド共有連携
          </text>
          <line x1="16" y1="506" x2="1128" y2="506" stroke="#e2e8f0" strokeDasharray="3 3" />
          <text x="16" y="542" fontSize="10" fill="#64748b" fontWeight="600">
            05. 永続ファイル・Excel 管理台帳
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
