import React, { useState } from 'react';
import {
  Clock,
  Cpu,
  FileText,
  FolderTree,
  Monitor,
  Settings,
  ShieldAlert,
  Terminal,
  Zap,
} from 'lucide-react';
import ToolFlowchartDiagram from './ToolFlowchartDiagram';
import VbNetMigrationPlanSection from './VbNetMigrationPlanSection';

interface SystemSpecTabProps {
  onSelectFile?: (filePath: string) => void;
}

interface ModuleSpecRow {
  category: string;
  name: string;
  file: string;
  status: '検証済' | '確認・調整中';
  spec: string;
}

const MODULE_SPECS: ModuleSpecRow[] = [
  {
    category: '起動・ルーティング',
    name: '右クリック / 非表示起動',
    file: 'RegisterContextMenu.bat / MakePhotoInfo.bat / common/LaunchHidden.vbs',
    status: '検証済',
    spec: 'フォルダ右クリック「被写体プロパティ」から LaunchHidden.vbs (wscript 窓非表示) 経由で PhotoInfoEditor.ps1 を起動。Windows 11 ターミナルの黒画面が残らないよう子GUI起動も ProcessStartInfo (UseShellExecute=$false, CreateNoWindow=$true) で完全統一。',
  },
  {
    category: '起動・ルーティング',
    name: '日付フォルダ自動分岐',
    file: 'editor/PhotoInfoEditor.ps1',
    status: '検証済',
    spec: '対象フォルダ名が日付形式（YYYY_MM_DD / YYYY-MM-DD / YYYYMMDD 等）かつ親フォルダが日付形式でない場合（-ForceEditor 未指定時）は DailyWorkflow.ps1 -TargetPath へ自動転送。撮影サブフォルダ（01 等）の場合は被写体プロパティを起動。',
  },
  {
    category: '日次ワークフロー',
    name: 'DailyWorkflow & Step1〜5 統括GUI',
    file: 'workflow/DailyWorkflow.ps1 / WorkflowStep1〜5Helper.ps1',
    status: '検証済',
    spec: '【REV-35 検証済】①カメラ取り込み元と現像後フォルダを個別選択し撮影日付（YYYY-MM-DD）で自動紐づけ。②階層 TreeView 表示。③Step3（現像済みJPEG自動振分・1秒監視・上書きチェック・保留ファイル管理・保留理由出力）およびStep4（現像側 vs 取込元 統合比較リスト・コア名正規化・一括削除）を完全網羅。',
  },
  {
    category: 'Step3 自動振分・監視',
    name: '1秒監視 & 保留管理・上書き制御',
    file: 'workflow/WorkflowStep3Helper.ps1',
    status: '検証済',
    spec: '【REV-35 最新仕様】起動時デフォルト「監視 OFF」。上書きチェックボックス（$chkOverwrite）を配置。1秒監視モード中、未変更ファイルの重複チェック・ログスパムを FileCache (Ticks + Status + Reason) で完全抑制。未振分・保留となったファイルは「RAW参照なし」「移送先に同名ファイルが存在するためスキップ（上書きオフ）」等の詳細な理由とともに1ファイル1行でログ出力・解除管理。',
  },
  {
    category: 'Step4 比較・削除',
    name: '現像済み vs 取込元 統合比較 & カメラ内現像データ削除',
    file: 'workflow/WorkflowStep4Helper.ps1',
    status: '検証済',
    spec: '【REV-37 検証済】現像側（現像済み写真）と取込元ファイルをファイル名一致で比較統合。Get-CoreImageName でキャノンカメラの命名規則（8文字ベース名一致：元画像とカメラ内現像データの IMG_2650 vs IMG_2650_1 等）を同一写真とみなして比較し、現像済みとなった取込元側のカメラ内現像データ（重複ファイル）を一括安全削除。さらに上部に取込元・現像側フルパス表示ラベルおよび「フォルダを開く」ボタンを搭載。',
  },
  {
    category: '被写体プロパティ',
    name: '写真情報編集・ペア同期',
    file: 'editor/PhotoInfoEditor.ps1 / common/PhotoEditorLogic.ps1',
    status: '検証済',
    spec: '①ImportRoot1/2・RawSaveRoot・DevelopedRoot間でペア解決し同時保存（複数人・同日衣装補完・データ送付済み管理）。②仕分けフォルダが深くなっても scene.txt は日付直下(A)か子直下(B)のみを参照。③イベント・併せ・スタジオ・場所欄は選択コピー可・手入力不可（ReadOnly）へ変更。',
  },
  {
    category: 'データ形式',
    name: '写真情報.txt パーサ／ライタ',
    file: 'common/PhotoInfoHelper.ps1',
    status: '検証済',
    spec: '【撮影区分】【撮影日】【催事・場所名】【データ送付状況】【MEGAリンク】【ギガファイル便リンク】【メモ】と --- 区切りの人物ブロック（【名前】【衣装・キャラ】【Xアカウント】【コメント】）を UTF-8 (BOM付)+CRLF で保存。明示された「未送付」はURLが存在しても自動上書きしない。',
  },
  {
    category: '台帳・Excel',
    name: '写真管理一覧.xlsx OpenXML同期',
    file: 'common/ExcelHelper.ps1 / workflow/SyncExcelFromTxt.ps1',
    status: '検証済',
    spec: 'Excel COM 非依存の OpenXML 直接読み書きにより全18列（撮影日〜最終更新日時、データ送付状況=送付済み／未送付）を更新。一意キーは「現像後フォルダ（または取込フォルダ／相対パス）＋モデル名＋人物連番」。Step5 移動時はパス列を自動追従。',
  },
  {
    category: '履歴・外部連携',
    name: 'Xアカウント / シーン / MEGA / GigaFile',
    file: 'common/XHelper.ps1 / SceneHelper.ps1 / MegaHelper.ps1 / gigafile/*',
    status: '検証済',
    spec: 'XHelper は4段階取得＋HttpWebRequest UTF-8明示デコード＋同日フィルタ付き履歴（x_history.json）。SceneHelper は親フォルダ scene.txt 継承＋scene_history.json 学習。GigaFile は D&D/SendTo/GUIコールバック対応、MEGA は MEGAcmd 共有リンク取得に対応。',
  },
  {
    category: '設定・文字コード',
    name: '設定管理＆文字コード規約',
    file: 'common/ConfigHelper.ps1 / settings.ini / UnblockFiles.bat',
    status: '検証済',
    spec: '取り込み元は ImportRoot1（カメラ取り込み元 1）と ImportRoot2（カメラ取り込み元 2）の2系統。文字コードは .bat=CP932+CRLF、.ps1,.ini,.json/.txt=UTF-8 BOM+CRLF、.vbs=ASCII+CRLF で全ファイル統一。',
  },
  {
    category: '総合マスター管理',
    name: 'PhotoTools Master & 設定編集画面',
    file: 'PhotoToolsMaster.ps1 / editor/SettingsEditor.ps1 / StartPhotoToolsMaster.bat',
    status: '検証済',
    spec: '作業用・完了後・アーカイブのタブ切替式オンデマンドスキャン、日付スコープ選択による DailyWorkflow 起動、複数ルート間の不整合診断チェッカー、Excel台帳の自動補完、および右上ボタンから開く settings.ini／履歴JSON設定編集GUIを統合した最上位司令塔コンソール。',
  },
];

export default function SystemSpecTab({ onSelectFile }: SystemSpecTabProps) {
  const [specView, setSpecView] = useState<'current' | 'vbnet'>('current');

  return (
    <div className="space-y-6 pb-12">
      {/* 1. 総合ステータスヘッダー */}
      <section className="bg-slate-900 text-white p-6 border border-slate-800">
        <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-4">
          <div className="space-y-2">
            <div className="flex items-center gap-2 text-xs text-teal-300 font-mono">
              <span>phototools/</span>
              <span aria-hidden="true">·</span>
              <span>PowerShell 5.1 / WinForms / OpenXML / .NET 10 (VB.NET) 移行設計</span>
            </div>
            <h1 className="text-xl md:text-2xl font-bold tracking-tight text-white">
              PhotoTools（phototools）全体詳細仕様・ツール関係性フローチャート
            </h1>
            <p className="text-xs text-slate-300 max-w-4xl leading-relaxed">
              カメラ取り込み、RAW仕分け、現像済みJPEG自動振分（1秒監視・保留理由管理・上書き制御）、重複ファイル削除（統合比較リスト・キャノン8文字コア名正規化）、長期アーカイブ、1日1人時の日付直下を含む写真情報.txt管理、設定編集GUI、およびExcel台帳（OpenXML）自動同期までを一気通貫で自動化する写真管理ツールキットの全体仕様書です。
            </p>
          </div>

          <div className="flex items-center gap-1 p-1 bg-slate-800 border border-slate-700 rounded-md self-start lg:self-center shrink-0">
            <button
              type="button"
              onClick={() => setSpecView('current')}
              className={`px-3.5 py-2 text-xs font-semibold rounded-sm whitespace-nowrap shrink-0 transition-colors ${
                specView === 'current'
                  ? 'bg-white text-slate-900'
                  : 'text-slate-300 hover:text-white'
              }`}
            >
              現行 PowerShell 仕様・図解
            </button>
            <button
              type="button"
              onClick={() => setSpecView('vbnet')}
              className={`px-3.5 py-2 text-xs font-semibold rounded-sm whitespace-nowrap shrink-0 transition-colors ${
                specView === 'vbnet'
                  ? 'bg-teal-400 text-slate-950'
                  : 'text-slate-300 hover:text-white'
              }`}
            >
              .NET 10 (VB.NET) 移行設計案
            </button>
          </div>
        </div>
      </section>

      {specView === 'vbnet' ? (
        <VbNetMigrationPlanSection onSelectFile={onSelectFile} />
      ) : (
        <div className="space-y-8">
      {/* 1.5 ツール関係性フローチャート */}
      <ToolFlowchartDiagram onSelectFile={onSelectFile} />

      {/* 2. アーキテクチャ概要 & コア設計方針 */}
      <section className="bg-white border border-slate-200 p-6 space-y-6 shadow-xs">
        <div className="flex items-center gap-2 border-b border-slate-200 pb-4">
          <Cpu className="w-5 h-5 text-teal-700 shrink-0" />
          <div>
            <h2 className="text-base font-bold text-slate-900">システムアーキテクチャ & 設計思想</h2>
            <p className="text-xs text-slate-500 mt-0.5">Windows環境における堅牢性・高速性・可読性を最優先に設計されたデュアルレイヤー構成</p>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div className="bg-slate-50 border border-slate-200 p-4 space-y-3">
            <div className="flex items-center gap-2 text-teal-800 font-bold text-sm">
              <Terminal className="w-4 h-4" />
              <span>バックエンド（PowerShell 5.1）</span>
            </div>
            <p className="text-xs text-slate-600 leading-relaxed">
              Windows標準搭載の PowerShell 5.1 をベースに構築。WinForms によるネイティブ GUI、COMオブジェクトに依存しない OpenXML 直接操作、一括ログ出力、厳しい例外ハンドリング（<code className="font-mono">Set-StrictMode</code>）を実装。
            </p>
            <div className="text-[11px] font-mono text-teal-900 bg-teal-50 p-2 border border-teal-200">
              UTF-8 BOM付 + CRLF でモジバケ完全防止
            </div>
          </div>

          <div className="bg-slate-50 border border-slate-200 p-4 space-y-3">
            <div className="flex items-center gap-2 text-teal-800 font-bold text-sm">
              <Monitor className="w-4 h-4" />
              <span>フロントエンド（React / TypeScript）</span>
            </div>
            <p className="text-xs text-slate-600 leading-relaxed">
              Vite + React SPA による管理コンソール。ローカルの <code className="font-mono">phototools/</code> フォルダ構造をリアルタイム解析し、設定ファイルのカスタマイズ、ワンクリックZIPパッケージ生成、仕様確認が可能。
            </p>
            <div className="text-[11px] font-mono text-teal-900 bg-teal-50 p-2 border border-teal-200">
              Tailwind CSS v4 & Lucide Icons
            </div>
          </div>

          <div className="bg-slate-50 border border-slate-200 p-4 space-y-3">
            <div className="flex items-center gap-2 text-teal-800 font-bold text-sm">
              <Settings className="w-4 h-4" />
              <span>データ連携・同期基盤</span>
            </div>
            <p className="text-xs text-slate-600 leading-relaxed">
              写真情報.txt、Excel台帳（写真管理一覧.xlsx）、Xアカウント履歴（x_history.json）、シーン履歴（scene_history.json）が相互に連動し、データ欠損や二重入力のない自動同期ワークフローを実現。
            </p>
            <div className="text-[11px] font-mono text-teal-900 bg-teal-50 p-2 border border-teal-200">
              OpenXML 直接読み書きエンジン搭載
            </div>
          </div>
        </div>
      </section>

      {/* 3. 日次ワークフロー＆5ステップデータフロー詳細図解 */}
      <section className="bg-white border border-slate-200 p-6 space-y-6 shadow-xs">
        <div className="flex items-center gap-2 border-b border-slate-200 pb-4">
          <FolderTree className="w-5 h-5 text-teal-700 shrink-0" />
          <div>
            <h2 className="text-base font-bold text-slate-900">日次ワークフロー＆5ステップデータフロー詳細図解</h2>
            <p className="text-xs text-slate-500 mt-0.5">カメラ撮影データから現像、自動振分、重複削除、長期アーカイブまでの全5ステップの完全なデータフロー</p>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-5 gap-4">
          {/* Step 1 */}
          <div className="bg-slate-50 border border-slate-200 p-4 space-y-3 relative">
            <div className="absolute top-3 right-3 text-xs font-mono font-bold text-slate-400">STEP 1</div>
            <div className="w-8 h-8 rounded bg-teal-100 text-teal-800 flex items-center justify-center font-bold text-sm">1</div>
            <h3 className="text-sm font-bold text-slate-900">仕分けフォルダ作成</h3>
            <p className="text-xs text-slate-600 leading-relaxed">
              カメラ取込元（ImportRoot1/2）の日付フォルダ内に、撮影モデル数に応じた連番サブフォルダ（<code className="font-mono">01</code>, <code className="font-mono">02</code>...）を一括自動生成。
            </p>
            <div className="text-[11px] text-teal-800 font-mono bg-teal-50 p-2 border border-teal-200">
              WorkflowStep1Helper.ps1
            </div>
          </div>

          {/* Step 2 */}
          <div className="bg-slate-50 border border-slate-200 p-4 space-y-3 relative">
            <div className="absolute top-3 right-3 text-xs font-mono font-bold text-slate-400">STEP 2</div>
            <div className="w-8 h-8 rounded bg-teal-100 text-teal-800 flex items-center justify-center font-bold text-sm">2</div>
            <h3 className="text-sm font-bold text-slate-900">RAW複製 & 構成複製</h3>
            <p className="text-xs text-slate-600 leading-relaxed">
              取込元のフォルダ階層をRAW作業ルート（RawSaveRoot/2）および現像後ルート（DevelopedRoot）へ完全複製し、RAWデータのみを安全に移動。
            </p>
            <div className="text-[11px] text-teal-800 font-mono bg-teal-50 p-2 border border-teal-200">
              WorkflowStep2Helper.ps1
            </div>
          </div>

          {/* Step 3 */}
          <div className="bg-teal-50/70 border border-teal-300 p-4 space-y-3 relative shadow-xs">
            <div className="absolute top-3 right-3 text-xs font-mono font-bold text-teal-600">STEP 3</div>
            <div className="w-8 h-8 rounded bg-teal-600 text-white flex items-center justify-center font-bold text-sm">3</div>
            <h3 className="text-sm font-bold text-slate-900">現像済みJPEG自動振分</h3>
            <p className="text-xs text-slate-700 leading-relaxed">
              現像後フォルダ内のJPEGをRAW参照（RAW/取込元）と突き合わせ。<strong>1秒監視モード</strong>、<strong>上書きチェックボックス</strong>、未変更ファイルの重複チェック抑制、および詳細理由付き<strong>保留リスト</strong>を搭載。
            </p>
            <div className="text-[11px] text-teal-900 font-mono bg-teal-100/70 p-2 border border-teal-300">
              WorkflowStep3Helper.ps1 (REV-35)
            </div>
          </div>

          {/* Step 4 */}
          <div className="bg-slate-50 border border-slate-200 p-4 space-y-3 relative">
            <div className="absolute top-3 right-3 text-xs font-mono font-bold text-slate-400">STEP 4</div>
            <div className="w-8 h-8 rounded bg-teal-100 text-teal-800 flex items-center justify-center font-bold text-sm">4</div>
            <h3 className="text-sm font-bold text-slate-900">現像済み vs 取込元 比較・削除</h3>
            <p className="text-xs text-slate-600 leading-relaxed">
              現像側（現像済み写真）と取込元を統合比較。キャノンカメラ仕様（8文字ベース名一致：<code className="font-mono">IMG_2650</code> とカメラ内現像 <code className="font-mono">IMG_2650_1</code> 等）で同一判定し、現像済みとなった取込元側の重複カメラ内現像データを一括安全削除。
            </p>
            <div className="text-[11px] text-teal-800 font-mono bg-teal-50 p-2 border border-teal-200">
              WorkflowStep4Helper.ps1 (REV-37)
            </div>
          </div>

          {/* Step 5 */}
          <div className="bg-slate-50 border border-slate-200 p-4 space-y-3 relative">
            <div className="absolute top-3 right-3 text-xs font-mono font-bold text-slate-400">STEP 5</div>
            <div className="w-8 h-8 rounded bg-teal-100 text-teal-800 flex items-center justify-center font-bold text-sm">5</div>
            <h3 className="text-sm font-bold text-slate-900">長期アーカイブ移動</h3>
            <p className="text-xs text-slate-600 leading-relaxed">
              完了した撮影データを四半期別の長期アーカイブ先へ安全に移送し、Excel台帳のハイパーリンクを自動追従。
            </p>
            <div className="text-[11px] text-teal-800 font-mono bg-teal-50 p-2 border border-teal-200">
              WorkflowStep5Helper.ps1
            </div>
          </div>
        </div>
      </section>

      {/* 4. モジュール別詳細仕様・検証ステータス一覧 */}
      <section className="bg-white border border-slate-200 shadow-xs">
        <div className="px-6 py-4 border-b border-slate-200 flex items-center justify-between gap-3 bg-slate-50/50">
          <div className="flex items-center gap-2">
            <FileText className="w-5 h-5 text-teal-700 shrink-0" />
            <div>
              <h2 className="text-base font-bold text-slate-900">モジュール別仕様・検証ステータス一覧（REV-01 〜 REV-35）</h2>
              <p className="text-xs text-slate-500 mt-0.5">
                各モジュールの実装仕様、対象スクリプトファイル、および検証状況の一覧です。
              </p>
            </div>
          </div>
          <span className="font-mono text-xs text-slate-500 bg-slate-200/80 px-2.5 py-1 rounded-sm">MODULE SPECS</span>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="bg-slate-100/80 border-b border-slate-200 text-[11px] font-semibold text-slate-600 uppercase tracking-wider">
                <th className="py-3 px-4 w-32">カテゴリ</th>
                <th className="py-3 px-4 w-44">モジュール名</th>
                <th className="py-3 px-4 w-60">対象ファイル</th>
                <th className="py-3 px-4 w-24">状態</th>
                <th className="py-3 px-4">仕様詳細</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-200 text-xs">
              {MODULE_SPECS.map((mod, idx) => (
                <tr key={idx} className="hover:bg-slate-50/70 align-top">
                  <td className="py-3.5 px-4 font-semibold text-slate-900">{mod.category}</td>
                  <td className="py-3.5 px-4 font-medium text-slate-900">{mod.name}</td>
                  <td className="py-3.5 px-4 font-mono text-[11px] text-sky-800">{mod.file}</td>
                  <td className="py-3.5 px-4 whitespace-nowrap">
                    <span className="inline-block px-2 py-0.5 text-[10px] font-semibold bg-emerald-50 text-emerald-700 border border-emerald-200 rounded-sm">
                      {mod.status}
                    </span>
                  </td>
                  <td className="py-3.5 px-4 text-slate-700 leading-relaxed">{mod.spec}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      {/* 5. 技術規約・文字コード・安全設計 */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* 文字コード & 実行規約 */}
        <section className="bg-white border border-slate-200 p-6 space-y-4 shadow-xs">
          <div className="flex items-center gap-2 border-b border-slate-200 pb-3">
            <Zap className="w-4 h-4 text-teal-700" />
            <h2 className="text-sm font-bold text-slate-900">文字コード・PowerShell 5.1 実行規約</h2>
          </div>
          <ul className="space-y-3 text-xs text-slate-700 leading-relaxed">
            <li>
              <strong>PowerShell スクリプト (.ps1)</strong>：すべてのスクリプトファイルは、PowerShell 5.1 パーサのモジバケおよび構文エラーを防止するため、<strong>明示的な UTF-8 BOM付き（<code className="font-mono">\uFEFF</code>）＋ CRLF（<code className="font-mono">\r\n</code>）</strong>で完全統一されています。
            </li>
            <li>
              <strong>バッチランチャー (.bat)</strong>：文字コードは <code className="font-mono">CP932 (Shift-JIS) + CRLF</code>。全ランチャーで WinForms 必須のシングルスレッドアパートメント（<code className="font-mono">-STA</code>）フラグを明示し、起動時のサイレント終了を防止。
            </li>
            <li>
              <strong>コンソール非表示化</strong>：GUI起動時は <code className="font-mono">LaunchHidden.vbs</code>（wscript.exe 経由）および <code className="font-mono">CreateNoWindow=$true</code> により、Windows 11 ターミナル上の黒い枠を完全に非表示化。
            </li>
          </ul>
        </section>

        {/* 例外ハンドリング & 安全設計 */}
        <section className="bg-white border border-slate-200 p-6 space-y-4 shadow-xs">
          <div className="flex items-center gap-2 border-b border-slate-200 pb-3">
            <ShieldAlert className="w-4 h-4 text-teal-700" />
            <h2 className="text-sm font-bold text-slate-900">例外ハンドリング & 厳格モード (Strict Mode)</h2>
          </div>
          <ul className="space-y-3 text-xs text-slate-700 leading-relaxed">
            <li>
              <strong>グローバル Try-Catch</strong>：全モジュールのエントリーポイントでグローバル例外捕捉を実装。万一のエラー時もサイレント終了せず、発生ファイル名・行番号・スタックトレース付きのエラー詳細ダイアログを表示。
            </li>
            <li>
              <strong>MsgBox ラッパー</strong>：COM / WinForms の MessageBox 呼び出しにおける引数型不一致や <code className="font-mono">System.Object[]</code> 例外を完全に防ぐ共通ラッパー（<code className="font-mono">Show-MsgBox</code>）を実装。
            </li>
            <li>
              <strong>コレクション安全評価</strong>：<code className="font-mono">Set-StrictMode -Version Latest</code> 下での <code className="font-mono">.Count</code> プロパティエラーや配列アンロール問題を防止するため、全コレクション評価を <code className="font-mono">@(...)</code> で厳密に保護。
            </li>
          </ul>
        </section>
      </div>

      {/* 6. PhotoTools Master & 拡張機能仕様（ギガファイル便連携拡張・MEGA非同期ログ・3ルート同期） */}
      <section className="bg-white border border-slate-200 p-6 space-y-4 shadow-xs">
        <div className="flex items-center gap-2 border-b border-slate-200 pb-3">
          <Clock className="w-4 h-4 text-emerald-600" />
          <h2 className="text-sm font-bold text-slate-900">PhotoTools Master & 拡張機能仕様（すべて実装済）</h2>
        </div>
        <p className="text-xs text-slate-600 leading-relaxed">
          マスター管理コンソール「PhotoTools Master」、非同期・安全制御（MEGAポップアップ内リアルタイム処理ログ表示含む）、子フォルダ名3ルート一括リネーム同期、およびギガファイル便連携拡張の統合仕様です。
        </p>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <div className="bg-emerald-50/40 border border-emerald-200 p-4 space-y-2 rounded-sm">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-bold text-emerald-900">1. PhotoTools Master</h3>
              <span className="px-2 py-0.5 text-[10px] font-semibold bg-emerald-100 text-emerald-800 rounded">実装済</span>
            </div>
            <ul className="text-xs text-slate-700 space-y-1.5 leading-relaxed">
              <li>• <strong>単独起動</strong>：独立したマスター司令塔。</li>
              <li>• <strong>切替式ビュー</strong>：作業用/完了後/アーカイブタブ切替。</li>
              <li>• <strong>日付スコープ</strong>：日付選択して DailyWorkflow起動。</li>
              <li>• <strong>不整合チェック</strong>：重複日付フォルダ一括診断。</li>
              <li>• <strong>台帳自動補完</strong>：情報.txtから未登録行を自動復元。</li>
              <li>• <strong>仮登録正規化</strong>：正式行へ自動昇格。</li>
            </ul>
          </div>

          <div className="bg-emerald-50/40 border border-emerald-200 p-4 space-y-2 rounded-sm">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-bold text-emerald-900">2. 非同期・安全制御</h3>
              <span className="px-2 py-0.5 text-[10px] font-semibold bg-emerald-100 text-emerald-800 rounded">実装済</span>
            </div>
            <ul className="text-xs text-slate-700 space-y-1.5 leading-relaxed">
              <li>• <strong>アプローチA</strong>：Stepヘルパー別プロセス化。</li>
              <li>• <strong>MEGA非同期</strong>：ポップアップ内リアルタイム処理ログ表示。</li>
              <li>• <strong>閉じガード</strong>：処理中クローズ警告と強制終了。</li>
            </ul>
          </div>

          <div className="bg-emerald-50/40 border border-emerald-200 p-4 space-y-2 rounded-sm">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-bold text-emerald-900">3. 子フォルダ名同期</h3>
              <span className="px-2 py-0.5 text-[10px] font-semibold bg-emerald-100 text-emerald-800 rounded">実装済</span>
            </div>
            <ul className="text-xs text-slate-700 space-y-1.5 leading-relaxed">
              <li>• <strong>リネーム追従</strong>：取込後・現像後どちらで変更しても自動同期。</li>
              <li>• <strong>RAW間連動</strong>：RAWフォルダ側も含めて3ルートを一括命名同期。</li>
              <li>• <strong>台帳・パス保護</strong>：パス変更後もStep3/4・Excel台帳を完全維持。</li>
            </ul>
          </div>

          <div className="bg-emerald-50/40 border border-emerald-200 p-4 space-y-2 rounded-sm">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-bold text-emerald-900">4. ギガファイル便拡張</h3>
              <span className="px-2 py-0.5 text-[10px] font-semibold bg-emerald-100 text-emerald-800 rounded">実装済</span>
            </div>
            <ul className="text-xs text-slate-700 space-y-1.5 leading-relaxed">
              <li>• <strong>自動命名ZIP</strong>：情報.txt解析で日付_イベント_名前.zip命名。</li>
              <li>• <strong>子フォルダ一括</strong>：全URL一覧リストを出力。</li>
              <li>• <strong>URL自動記録</strong>：送付状況を「送付済み」へ自動更新。</li>
            </ul>
          </div>
        </div>
      </section>
        </div>
      )}
    </div>
  );
}