import { useCallback, useEffect, useState } from 'react';
import { AlertCircle, CheckCircle2, Download } from 'lucide-react';
import RepairReportTab from './components/RepairReportTab';
import SystemSpecTab from './components/SystemSpecTab';
import SettingsCustomizerTab from './components/SettingsCustomizerTab';
import FileExplorerTab, { type PackageFile } from './components/FileExplorerTab';
import VerificationChecklistTab from './components/VerificationChecklistTab';

type ActiveTab = 'verify' | 'report' | 'spec' | 'settings' | 'files';

interface FilesApiResponse {
  files: PackageFile[];
  defaultSettingsIni: string;
}

const NAV_TABS: Array<{ id: ActiveTab; label: string }> = [
  { id: 'verify', label: '機能確認・メモ' },
  { id: 'report', label: '修復レポート' },
  { id: 'spec', label: '全体仕様・図解' },
  { id: 'settings', label: 'settings.ini設定' },
  { id: 'files', label: 'ファイル一覧' },
];

export default function App() {
  const [activeTab, setActiveTab] = useState<ActiveTab>('verify');
  const [files, setFiles] = useState<PackageFile[]>([]);
  const [defaultSettingsIni, setDefaultSettingsIni] = useState('');
  const [settingsIni, setSettingsIni] = useState('');
  const [selectedFilePath, setSelectedFilePath] = useState('settings.ini');
  const [isLoading, setIsLoading] = useState(true);
  const [isDownloading, setIsDownloading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [noticeMessage, setNoticeMessage] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    const loadFiles = async () => {
      try {
        setIsLoading(true);
        setErrorMessage(null);
        const res = await fetch('/api/files');
        if (!res.ok) {
          throw new Error(`サーバーからファイル一覧を取得できませんでした (${res.status})`);
        }
        const data = (await res.json()) as FilesApiResponse;
        if (!active) return;
        setFiles(data.files);
        setDefaultSettingsIni(data.defaultSettingsIni);
        setSettingsIni(data.defaultSettingsIni);
        if (data.files.length > 0 && !data.files.some((f) => f.path === 'settings.ini')) {
          setSelectedFilePath(data.files[0].path);
        }
      } catch (err) {
        if (!active) return;
        setErrorMessage(err instanceof Error ? err.message : '初期化中にエラーが発生しました。');
      } finally {
        if (active) setIsLoading(false);
      }
    };
    loadFiles();
    return () => {
      active = false;
    };
  }, []);

  const handleSelectFileFromReport = useCallback((filePath: string) => {
    setSelectedFilePath(filePath);
    setActiveTab('files');
  }, []);

  const handleDownloadZip = useCallback(async () => {
    try {
      setIsDownloading(true);
      setErrorMessage(null);
      setNoticeMessage(null);
      const res = await fetch('/api/download-zip', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ settingsIni }),
      });
      if (!res.ok) {
        throw new Error(`ZIP生成に失敗しました (${res.status})`);
      }
      const buffer = await res.arrayBuffer();
      const bytes = new Uint8Array(buffer);
      if (bytes.length < 22 || bytes[0] !== 0x50 || bytes[1] !== 0x4b || bytes[2] !== 0x03 || bytes[3] !== 0x04) {
        throw new Error('サーバーから有効なZIPデータを受信できませんでした。ページを再読み込みして再度お試しください。');
      }
      const blob = new Blob([buffer], { type: 'application/zip' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = 'PhotoTools.zip';
      link.style.display = 'none';
      document.body.appendChild(link);
      link.click();
      window.setTimeout(() => {
        link.remove();
        URL.revokeObjectURL(url);
      }, 60000);
      setNoticeMessage('PhotoTools.zip のダウンロードを開始しました（Shift-JIS / UTF-8 BOM・CRLF変換済み）。');
      window.setTimeout(() => setNoticeMessage(null), 5000);
    } catch (err) {
      setErrorMessage(err instanceof Error ? err.message : 'ZIPダウンロード中にエラーが発生しました。');
    } finally {
      setIsDownloading(false);
    }
  }, [settingsIni]);

  const isSettingsCustomized = settingsIni.trim() !== defaultSettingsIni.trim();

  return (
    <div className="min-h-screen bg-slate-50 text-slate-900 flex flex-col">
      <header className="sticky top-0 z-30 bg-white border-b border-slate-200">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 h-14 flex items-center justify-between gap-8">
          <div className="text-sm font-bold text-slate-900 tracking-tight whitespace-nowrap shrink-0">
            PhotoTools 修復・配布スタジオ
          </div>

          <nav className="flex items-center gap-2 overflow-x-auto">
            {NAV_TABS.map((tab) => {
              const active = activeTab === tab.id;
              return (
                <button
                  key={tab.id}
                  type="button"
                  onClick={() => setActiveTab(tab.id)}
                  className={`px-3 py-1.5 text-xs font-medium whitespace-nowrap shrink-0 border-b-2 transition-colors ${
                    active
                      ? 'border-slate-900 text-slate-900 font-semibold'
                      : 'border-transparent text-slate-600 hover:text-slate-900 hover:border-slate-300'
                  }`}
                >
                  {tab.label}
                  {tab.id === 'settings' && isSettingsCustomized && (
                    <span className="ml-1.5 font-mono text-[10px] text-amber-700">*</span>
                  )}
                </button>
              );
            })}
          </nav>

          <button
            type="button"
            onClick={handleDownloadZip}
            disabled={isDownloading || isLoading}
            className="inline-flex items-center gap-2 px-4 py-2 text-xs font-semibold bg-slate-900 text-white hover:bg-slate-800 disabled:opacity-50 whitespace-nowrap shrink-0 transition-colors"
          >
            <Download className="w-3.5 h-3.5" />
            <span>{isDownloading ? 'ZIP作成中...' : '修復版ZIPをダウンロード'}</span>
          </button>
        </div>
      </header>

      <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 py-6 space-y-4">
        {errorMessage && (
          <div className="bg-red-50 border border-red-200 px-4 py-3 flex items-center gap-2.5 text-xs text-red-800">
            <AlertCircle className="w-4 h-4 text-red-600 shrink-0" />
            <span>{errorMessage}</span>
          </div>
        )}

        {noticeMessage && (
          <div className="bg-emerald-50 border border-emerald-200 px-4 py-3 flex items-center gap-2.5 text-xs text-emerald-800">
            <CheckCircle2 className="w-4 h-4 text-emerald-600 shrink-0" />
            <span>{noticeMessage}</span>
          </div>
        )}

        {isLoading ? (
          <div className="bg-white border border-slate-200 p-6 space-y-3">
            <div className="h-5 w-48 bg-slate-200 animate-pulse" />
            <div className="h-4 w-full bg-slate-100 animate-pulse" />
            <div className="h-4 w-5/6 bg-slate-100 animate-pulse" />
            <div className="h-64 w-full bg-slate-50 border border-slate-200 animate-pulse" />
          </div>
        ) : (
          <>
            {activeTab === 'verify' && (
              <VerificationChecklistTab onSelectFile={handleSelectFileFromReport} />
            )}
            {activeTab === 'report' && (
              <RepairReportTab
                totalFiles={files.length}
                onSelectFile={handleSelectFileFromReport}
                onOpenSpec={() => setActiveTab('spec')}
              />
            )}
            {activeTab === 'spec' && <SystemSpecTab onSelectFile={handleSelectFileFromReport} />}
            {activeTab === 'settings' && (
              <SettingsCustomizerTab
                settingsIni={settingsIni}
                defaultSettingsIni={defaultSettingsIni}
                onChangeSettingsIni={setSettingsIni}
                onDownloadZip={handleDownloadZip}
                isDownloading={isDownloading}
              />
            )}
            {activeTab === 'files' && (
              <FileExplorerTab
                files={files}
                selectedPath={selectedFilePath}
                onSelectPath={setSelectedFilePath}
              />
            )}
          </>
        )}
      </main>
    </div>
  );
}
