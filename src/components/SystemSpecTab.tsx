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
import { REPAIR_HISTORY } from '../data/repairData';

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
    spec: '①カメラ取り込み元と現像後フォルダを個別選択し撮影日付で自動紐づけ。②階層 TreeView 表示（1日1人時の日付直下表示・子フォルダ名3ルート一括リネーム同期対応）。③Step1〜5（Step3 1秒監視・保留管理・上書き制御／Step4 統合比較・コア名正規化・一括削除）および同日複数フォルダを束ねる「メッセージ作成(まとめ可)」ボタンを統合。',
  },
  {
    category: 'Step3 自動振分・監視',
    name: '1秒監視 & 保留管理・上書き制御',
    file: 'workflow/WorkflowStep3Helper.ps1',
    status: '検証済',
    spec: '起動時デフォルト「監視 OFF」。上書きチェックボックス（$chkOverwrite）を配置。1秒監視モード中、未変更ファイルの重複チェック・ログスパムを FileCache (Ticks + Status + Reason) で完全抑制。未振分・保留となったファイルは「RAW参照なし」「移送先に同名ファイルが存在するためスキップ（上書きオフ）」等の詳細な理由とともに1ファイル1行でログ出力・解除管理（メタデータTXTは自動除外）。',
  },
  {
    category: 'Step4 比較・削除',
    name: '現像済み vs 取込元 統合比較 & カメラ内現像データ削除',
    file: 'workflow/WorkflowStep4Helper.ps1',
    status: '検証済',
    spec: '現像側（現像済み写真）と取込元ファイルをファイル名一致で比較統合（日付直下配置にも対応）。Get-CoreImageName でキャノンカメラの命名規則（8文字ベース名一致：元画像とカメラ内現像データの IMG_2650 vs IMG_2650_1 等）を同一写真とみなして比較し、現像済みとなった取込元側のカメラ内現像データ（重複ファイル）を一括安全削除。取込元・現像側フルパス表示と「フォルダを開く」を搭載。',
  },
  {
    category: '被写体プロパティ',
    name: '写真情報編集・ペア同期',
    file: 'editor/PhotoInfoEditor.ps1 / common/PhotoEditorLogic.ps1',
    status: '検証済',
    spec: '①ImportRoot1/2・RawSaveRoot・DevelopedRoot間でペア解決し同時保存（日付直下1日1人・複数人・同日衣装補完・データ送付済み管理・DLパスワード/保持期限保持）。②仕分けフォルダが深くなっても scene.txt は日付直下(A)か子直下(B)のみを参照。③衣装・キャラ欄横の「写真からキャラ検索」ボタンから6層漏洩対策付きAIキャラ判定ダイアログを、下部「メッセージ作成」ボタンから単体モードの送付メッセージ作成ダイアログを起動可能。',
  },
  {
    category: 'データ形式',
    name: '写真情報.txt パーサ／ライタ',
    file: 'common/PhotoInfoHelper.ps1',
    status: '検証済',
    spec: '【撮影区分】【撮影日】【イベント名】【データ送付状況】【MEGAリンク】【ギガファイル便リンク】【DLパスワード】【保持期限】【メモ】と --- 区切りの人物ブロック（【名前】【衣装・キャラ】【X】(@アカウント名)・【X_URL】(https://x.com/...)・【コメント】）を UTF-8 (BOM付)+CRLF で保存。既存の【X】にURLが記載されているデータもアクセス時に【X】+【X_URL】形式へ自動修正。明示された「未送付」はURLが存在しても自動上書きしない。',
  },
  {
    category: '台帳・Excel',
    name: '写真管理一覧.xlsx OpenXML同期',
    file: 'common/ExcelHelper.ps1 / workflow/SyncExcelFromTxt.ps1',
    status: '検証済',
    spec: 'Excel COM 非依存の OpenXML 直接読み書きにより全18列（撮影日〜最終更新日時、データ送付状況=送付済み／未送付）を更新。一意キーは「現像後フォルダ（または取込フォルダ／相対パス）＋モデル名＋人物連番」。Step5 移動時・子フォルダリネーム時はパス列を自動追従。',
  },
  {
    category: '履歴・外部連携',
    name: 'Xアカウント / シーン / MEGA / GigaFile',
    file: 'common/XHelper.ps1 / SceneHelper.ps1 / MegaHelper.ps1 / gigafile/*',
    status: '検証済',
    spec: 'XHelper は4段階取得＋HttpWebRequest UTF-8明示デコード＋同日フィルタ付き履歴（x_history.json）。SceneHelper は親フォルダ scene.txt 継承＋scene_history.json 学習。GigaFile は自動命名ZIP・子フォルダ一括・DLパスワード/保持期限（yyyy/MM/ddまで）自動保存・完了後メッセージ作成起動に対応。MEGA は MEGAcmd 非同期実行＆ポップアップ内リアルタイム処理ログ表示に対応。',
  },
  {
    category: '送付メッセージ作成',
    name: '定型文・MEGAコメント・まとめ送付ダイアログ',
    file: 'editor/MessageComposerDialog.ps1 / common/MessageTemplateHelper.ps1',
    status: '検証済',
    spec: 'PhotoInfoEditor（単体）・DailyWorkflow（同日まとめ）・ギガファイル便完了画面の3箇所から起動。初期本文は空欄、ギガファイル便／MEGA のどちらか一方を選択し「メッセージを作成」押下で生成。MEGA選択時に未取得フォルダがあれば確認後に MegaHelper 取得＆台帳書き戻し。{データリンク} は複数リンク／複数人時に「個撮リンク１」「複数リンク１＋次行に名前（キャラ名）（3名以上は、区切り）」で出力し、MEGA選択時専用コメント5種切替・コピー後「送付済み」一括更新（既定ON）を搭載。',
  },
  {
    category: 'AIキャラ名検索',
    name: '6層漏洩対策付きAIキャラクター判定',
    file: 'editor/CharacterLookupDialog.ps1 / common/GeminiCharacterHelper.ps1',
    status: '検証済',
    spec: 'PhotoInfoEditor の衣装・キャラ欄から手動2ステップ起動。①送信前プレビューで顔・背景をマウスドラッグで黒塗り／モザイク（マスク0箇所時は確認警告を表示して続行可）。②メモリ上のみで Exif 向き補正＋再描画による全メタデータ除去と長辺縮小（既定640px・一時ファイル非生成）。③モデル名・X・日付・フォルダ名等の個人情報ゼロ送信。④APIキーは Windows DPAPI（CurrentUser）暗号化で data\\gemini_api_key.dat へ保存（x-goog-api-key ヘッダー送信・ZIP配布対象外）。⑤Google Cloud 有料枠（学習不使用）確認チェック必須。⑥候補一覧から既定書式「キャラ名（作品名）」（ほか2書式切替可）で衣装・キャラ欄へ反映。',
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
    name: 'PhotoTools Master & 設定・定型文・AI編集画面',
    file: 'PhotoToolsMaster.ps1 / editor/SettingsEditor.ps1 / StartPhotoToolsMaster.bat',
    status: '検証済',
    spec: '作業用・完了後・アーカイブのタブ切替式オンデマンドスキャン、日付スコープ選択による DailyWorkflow 起動、不整合診断チェッカー、Excel台帳自動補完を統合。右上ボタンから開く SettingsEditor.ps1 は5タブ構成（パス／期分け・拡張子・MEGA／関連JSON直接編集・OS登録／メッセージ定型文＆MEGA共通コメント／AIキャラ判定・DPAPIキー管理・0トークン接続テスト）で即時反映。',
  },
  {
    category: '単独更新支援',
    name: 'PhotoTools 自動更新支援ツール',
    file: 'updater/PhotoToolsUpdater.ps1 / updater/StartPhotoToolsUpdater.vbs',
    status: '検証済',
    spec: '本体および common\\*.ps1 に一切依存しない完全自己完結型 GUI アップデータ（別フォルダへ単体コピーしても起動可能）。ブラウザ連番 (1)(2)... からの最新ZIP自動選択、GitHub最新ブランチZIP取得（公開／PAT非公開対応）、事前バックアップ（直近5世代）、settings.ini 設定維持マージ、data\\（履歴・定型文・AI設定/DPAPI暗号化キー）完全保護、自動ブロック解除、不要ファイル確認削除を一括実行。',
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
              カメラ取り込み、RAW仕分け、現像済みJPEG自動振分（1秒監視・保留理由管理・上書き制御）、重複ファイル削除（統合比較リスト・キャノン8文字コア名正規化）、長期アーカイブ、1日1人時の日付直下を含む写真情報.txt管理、6層漏洩対策付きAIキャラ名検索、定型文＆MEGAコメント対応の送付メッセージ作成、5タブ設定編集GUI、単独自動更新支援ツール、およびExcel台帳（OpenXML）自動同期までを一気通貫で自動化する写真管理ツールキットの全体仕様書です。
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
              写真情報.txt（【X】/【X_URL】・【DLパスワード】・【保持期限】含む）、Excel台帳（写真管理一覧.xlsx）、Xアカウント履歴（x_history.json）、シーン履歴（scene_history.json）、送付定型文（message_templates.json）、およびAIキャラ設定（ai_character_settings.json / DPAPI暗号化キー gemini_api_key.dat）が相互連動し、安全性と省力化を両立します。
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
              <h2 className="text-base font-bold text-slate-900">
                モジュール別仕様・検証ステータス一覧（REV-01 〜 {REPAIR_HISTORY[0]?.rev ?? 'REV-51'}）
              </h2>
              <p className="text-xs text-slate-500 mt-0.5">
                全 {MODULE_SPECS.length} モジュール領域の実装仕様、対象スクリプトファイル、および検証状況の一覧です。
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

      {/* 6. PhotoTools Master & 拡張機能仕様 */}
      <section className="bg-white border border-slate-200 p-6 space-y-4 shadow-xs">
        <div className="flex items-center gap-2 border-b border-slate-200 pb-3">
          <Clock className="w-4 h-4 text-emerald-600" />
          <h2 className="text-sm font-bold text-slate-900">PhotoTools Master & 拡張機能仕様（全7領域・実装済）</h2>
        </div>
        <p className="text-xs text-slate-600 leading-relaxed">
          マスター管理コンソール「PhotoTools Master」＆5タブ設定編集、非同期・安全制御、子フォルダ名3ルート同期＆1日1人対応、ギガファイル便連携拡張、送付メッセージ作成、単独更新支援ツール、および6層漏洩対策付きAIキャラ名検索の統合仕様です。
        </p>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <div className="bg-emerald-50/40 border border-emerald-200 p-4 space-y-2 rounded-sm">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-bold text-emerald-900">1. PhotoTools Master & 設定編集</h3>
              <span className="px-2 py-0.5 text-[10px] font-semibold bg-emerald-100 text-emerald-800 rounded">実装済</span>
            </div>
            <ul className="text-xs text-slate-700 space-y-1.5 leading-relaxed">
              <li>• <strong>切替式ビュー</strong>：作業用/完了後/アーカイブのオンデマンドスキャン。</li>
              <li>• <strong>不整合診断＆台帳補完</strong>：重複日付診断と未登録行の自動復元・正規化。</li>
              <li>• <strong>5タブ設定GUI</strong>：パス・期分け・JSON/OS登録・定型文・AIキャラ判定を統合管理。</li>
            </ul>
          </div>

          <div className="bg-emerald-50/40 border border-emerald-200 p-4 space-y-2 rounded-sm">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-bold text-emerald-900">2. 非同期・安全制御</h3>
              <span className="px-2 py-0.5 text-[10px] font-semibold bg-emerald-100 text-emerald-800 rounded">実装済</span>
            </div>
            <ul className="text-xs text-slate-700 space-y-1.5 leading-relaxed">
              <li>• <strong>アプローチA</strong>：Step2 / Step5 の別プロセス非同期実行。</li>
              <li>• <strong>MEGA非同期</strong>：ポップアップ内リアルタイム処理ログ表示。</li>
              <li>• <strong>閉じガード</strong>：処理中クローズ警告と未保存変更確認。</li>
            </ul>
          </div>

          <div className="bg-emerald-50/40 border border-emerald-200 p-4 space-y-2 rounded-sm">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-bold text-emerald-900">3. フォルダ同期 & 1日1人 / X分離</h3>
              <span className="px-2 py-0.5 text-[10px] font-semibold bg-emerald-100 text-emerald-800 rounded">実装済</span>
            </div>
            <ul className="text-xs text-slate-700 space-y-1.5 leading-relaxed">
              <li>• <strong>3ルート一括リネーム</strong>：取込・現像後・RAW と Excel台帳パスを同時追従。</li>
              <li>• <strong>1日1人日付直下対応</strong>：子フォルダなしで日付直下の写真情報.txtを編集・送信。</li>
              <li>• <strong>【X】/【X_URL】分離</strong>：既存旧形式もアクセス時に更新日時維持のまま自動修正。</li>
            </ul>
          </div>

          <div className="bg-emerald-50/40 border border-emerald-200 p-4 space-y-2 rounded-sm">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-bold text-emerald-900">4. ギガファイル便拡張</h3>
              <span className="px-2 py-0.5 text-[10px] font-semibold bg-emerald-100 text-emerald-800 rounded">実装済</span>
            </div>
            <ul className="text-xs text-slate-700 space-y-1.5 leading-relaxed">
              <li>• <strong>自動命名ZIP</strong>：情報.txt解析で 日付_イベント_名前.zip を自動提案。</li>
              <li>• <strong>子フォルダ一括</strong>：個別分割アップロード＆全URL一覧リスト出力。</li>
              <li>• <strong>自動記録＆連携</strong>：URL・DLパスワード・保持期限(yyyy/MM/ddまで)を記録し完了画面からメッセージ作成を起動。</li>
            </ul>
          </div>

          <div className="bg-emerald-50/40 border border-emerald-200 p-4 space-y-2 rounded-sm">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-bold text-emerald-900">5. 送付メッセージ作成 & 定型文</h3>
              <span className="px-2 py-0.5 text-[10px] font-semibold bg-emerald-100 text-emerald-800 rounded">実装済</span>
            </div>
            <ul className="text-xs text-slate-700 space-y-1.5 leading-relaxed">
              <li>• <strong>3箇所から起動</strong>：単体（被写体プロパティ）／まとめ（日次ワークフロー）／ギガ完了後。</li>
              <li>• <strong>リンク自動整形</strong>：個撮リンク１／複数リンク１＋共演者（名前（キャラ名）、区切り）。</li>
              <li>• <strong>MEGA連動＆送付済み</strong>：未取得確認取得・MEGA共通コメント5種切替・コピー後送付済み更新。</li>
            </ul>
          </div>

          <div className="bg-emerald-50/40 border border-emerald-200 p-4 space-y-2 rounded-sm">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-bold text-emerald-900">6. 単独更新支援ツール</h3>
              <span className="px-2 py-0.5 text-[10px] font-semibold bg-emerald-100 text-emerald-800 rounded">実装済</span>
            </div>
            <ul className="text-xs text-slate-700 space-y-1.5 leading-relaxed">
              <li>• <strong>完全自己完結</strong>：本体非依存で別フォルダ単体コピーからも黒画面ゼロ起動。</li>
              <li>• <strong>最新ZIP取得</strong>：連番 (1)(2)... 最新自動選択＆GitHub公開/非公開リポジトリ対応。</li>
              <li>• <strong>安全保護更新</strong>：直近5世代バックアップ・settings.iniマージ・data\\完全保護・不要削除確認。</li>
            </ul>
          </div>

          <div className="bg-emerald-50/40 border border-emerald-200 p-4 space-y-2 rounded-sm">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-bold text-emerald-900">7. AIキャラ名検索（6層漏洩対策）</h3>
              <span className="px-2 py-0.5 text-[10px] font-semibold bg-emerald-100 text-emerald-800 rounded">実装済</span>
            </div>
            <ul className="text-xs text-slate-700 space-y-1.5 leading-relaxed">
              <li>• <strong>顔マスク＆確認警告</strong>：黒塗り／モザイク編集対応・マスク0箇所時は送信前に確認警告。</li>
              <li>• <strong>完全サニタイズ＆DPAPI</strong>：メモリ上でExif除去＆縮小（既定640px）・個人情報未送信・DPAPI暗号化キー保存・有料枠確認必須。</li>
              <li>• <strong>即反映書式</strong>：既定「キャラ名（作品名）」ほか3書式切替で衣装・キャラ欄へワンクリック反映。</li>
            </ul>
          </div>
        </div>
      </section>
        </div>
      )}
    </div>
  );
}