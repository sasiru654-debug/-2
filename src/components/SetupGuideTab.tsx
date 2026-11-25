import { CheckSquare, Terminal } from 'lucide-react';

interface SetupStep {
  step: string;
  title: string;
  command?: string;
  detail: string;
}

const SETUP_STEPS: SetupStep[] = [
  {
    step: '01',
    title: '既存フォルダのバックアップと修復版ZIPの展開',
    detail:
      '既存の D:\\PhotoTools\\ を念のため別名（例: D:\\PhotoTools_backup\\）へ退避するか、上書き展開してください。ZIPのルート直下に settings.ini や各 .bat・フォルダが格納されているため、展開先を D:\\PhotoTools\\ に指定するとそのまま配置されます。',
  },
  {
    step: '02',
    title: 'Windows インターネットブロック（Zone.Identifier）の一括解除',
    command: 'D:\\PhotoTools\\UnblockFiles.bat',
    detail:
      'ブラウザからダウンロードしたZIP内の .ps1 は Windows の SmartScreen / ExecutionPolicy により実行ブロックされる場合があります。最初に UnblockFiles.bat を実行し、全 PowerShell スクリプトのブロックを解除してください。',
  },
  {
    step: '03',
    title: 'モジュール結合テストランチャーの実行（01〜09 検証）',
    command: 'D:\\PhotoTools\\RunTestManager.bat',
    detail:
      'TestManager GUI が起動します。「全モジュールテスト実行」を押すと、実際の本番ドライブやExcel台帳を汚さない一時サンドボックスフォルダ上で 01_LogHelper 〜 09_GigaFileHelper が順番に検証され、結果が data\\test_passed_state.json に記録されます。',
  },
  {
    step: '04',
    title: '右クリックメニュー・URLプロトコル・SendTo 連携の再登録',
    command: 'RegisterContextMenu.bat / RegisterProtocol.bat / gigafile\\install_gigafile_sendto.bat',
    detail:
      'D:\\PhotoTools\\ 以外のドライブへ配置した場合でも、各バッチは %~dp0 相対基準でパスを自動解決してレジストリ／SendToへ登録します。環境を移行した際はこれらを再実行してください。',
  },
  {
    step: '05',
    title: '実運用フローの起動確認',
    command: 'StartDailyWorkflow.bat / MakePhotoInfo.bat / SyncExcelFromTxt.bat',
    detail:
      '日次ワークフロー（Step1〜5）、写真情報.txt エディタ、一括Excel台帳同期のいずれも文字化けや未定義関数エラーなしで起動することを確認できます。',
  },
];

const VERIFICATION_CHECKLIST = [
  'settings.ini のドライブ文字（G:\\, H:\\, J:\\, L:\\）が現在のPC環境と一致しているか',
  'x_history.json はパッケージ非同梱（既存データ保護のため）。未存在時は起動・履歴読込時に data\\x_history.json が自動作成されるか',
  'RunTestManager.bat で 01〜09 の全テストが「合格 (PASSED)」になるか',
  'Excel（Microsoft Excel）がインストールされており、ExcelHelper テストが COM 自動検出で通過するか',
  'MEGA同期を使う場合、MEGAcmd がインストール済み、または settings.ini の MegaCmdPath が設定されているか',
];

export default function SetupGuideTab() {
  return (
    <div className="space-y-6">
      <section className="bg-white border border-slate-200">
        <div className="px-5 py-4 border-b border-slate-200">
          <h2 className="text-base font-semibold text-slate-900">Windows 実機への導入・テスト検証手順</h2>
          <p className="text-xs text-slate-500 mt-0.5">
            ZIPをダウンロード後、以下の手順で D:\PhotoTools\ へ展開して動作確認を行ってください。
          </p>
        </div>

        <div className="divide-y divide-slate-200">
          {SETUP_STEPS.map((item) => (
            <div key={item.step} className="p-5 flex flex-col md:flex-row gap-4">
              <div className="w-12 shrink-0">
                <span className="font-mono text-sm font-bold text-slate-900 tabular-nums">
                  STEP {item.step}
                </span>
              </div>
              <div className="flex-1 space-y-2">
                <h3 className="text-sm font-semibold text-slate-900">{item.title}</h3>
                <p className="text-xs text-slate-600 leading-relaxed">{item.detail}</p>
                {item.command && (
                  <div className="inline-flex items-center gap-2 px-3 py-1.5 bg-slate-950 text-slate-100 font-mono text-xs">
                    <Terminal className="w-3.5 h-3.5 text-slate-400 shrink-0" />
                    <span>{item.command}</span>
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      </section>

      <section className="bg-white border border-slate-200">
        <div className="px-5 py-3.5 border-b border-slate-200">
          <h3 className="text-sm font-semibold text-slate-900">実機確認チェックリスト</h3>
        </div>
        <div className="divide-y divide-slate-200">
          {VERIFICATION_CHECKLIST.map((line, idx) => (
            <div key={idx} className="px-5 py-3 flex items-start gap-3 text-xs text-slate-700">
              <CheckSquare className="w-4 h-4 text-slate-400 shrink-0 mt-0.5" />
              <span>{line}</span>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}
