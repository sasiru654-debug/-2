import { useMemo, useState } from 'react';
import { Check, Copy, Download, FileCode2, FolderOpen } from 'lucide-react';

export interface PackageFile {
  path: string;
  name: string;
  category: string;
  encoding: string;
  bytes: number;
  lines: number;
  content: string;
}

interface FileExplorerTabProps {
  files: PackageFile[];
  selectedPath: string;
  onSelectPath: (path: string) => void;
}

const CATEGORY_ORDER = [
  'バッチランチャー',
  '設定ファイル',
  'common/',
  'editor/',
  'workflow/',
  'gigafile/',
  'updater/',
  'tests/',
  'data/',
];

export default function FileExplorerTab({ files, selectedPath, onSelectPath }: FileExplorerTabProps) {
  const [filterText, setFilterText] = useState('');
  const [copiedPath, setCopiedPath] = useState<string | null>(null);

  const grouped = useMemo(() => {
    const q = filterText.trim().toLowerCase();
    const map = new Map<string, PackageFile[]>();
    for (const cat of CATEGORY_ORDER) {
      map.set(cat, []);
    }
    for (const file of files) {
      if (q && !file.path.toLowerCase().includes(q) && !file.content.toLowerCase().includes(q)) {
        continue;
      }
      const list = map.get(file.category) ?? [];
      list.push(file);
      map.set(file.category, list);
    }
    return Array.from(map.entries()).filter(([, list]) => list.length > 0);
  }, [files, filterText]);

  const activeFile = useMemo(
    () => files.find((f) => f.path === selectedPath) ?? files[0] ?? null,
    [files, selectedPath]
  );

  const handleCopy = async () => {
    if (!activeFile) return;
    try {
      await navigator.clipboard.writeText(activeFile.content);
      setCopiedPath(activeFile.path);
      window.setTimeout(() => setCopiedPath(null), 1800);
    } catch {
      // Clipboard API restricted fallback omitted silently
    }
  };

  const lines = useMemo(() => {
    if (!activeFile) return [];
    return activeFile.content.split(/\r\n|\r|\n/);
  }, [activeFile]);

  return (
    <div className="grid grid-cols-1 lg:grid-cols-12 border border-slate-200 bg-white min-h-[680px]">
      <aside className="lg:col-span-4 xl:col-span-3 border-b lg:border-b-0 lg:border-r border-slate-200 flex flex-col">
        <div className="p-3 border-b border-slate-200 bg-slate-50">
          <input
            type="text"
            value={filterText}
            onChange={(e) => setFilterText(e.target.value)}
            placeholder="ファイル検索 / コード内検索..."
            className="w-full px-2.5 py-1.5 text-xs bg-white border border-slate-200 text-slate-900 placeholder:text-slate-400 focus:outline-none focus:border-slate-400"
          />
        </div>
        <div className="overflow-y-auto max-h-[640px] divide-y divide-slate-100">
          {grouped.length === 0 ? (
            <div className="p-6 text-xs text-slate-500 text-center">該当するファイルがありません。</div>
          ) : (
            grouped.map(([category, list]) => (
              <div key={category} className="py-2">
                <div className="px-3 py-1 flex items-center gap-1.5 text-[11px] font-semibold text-slate-500 uppercase tracking-wider">
                  <FolderOpen className="w-3.5 h-3.5 text-slate-400" />
                  <span>{category}</span>
                  <span className="ml-auto font-mono text-[10px] tabular-nums">{list.length}</span>
                </div>
                <div className="mt-0.5">
                  {list.map((file) => {
                    const isSelected = activeFile?.path === file.path;
                    return (
                      <button
                        key={file.path}
                        type="button"
                        onClick={() => onSelectPath(file.path)}
                        className={`w-full px-3 py-1.5 text-left flex items-center gap-2 text-xs transition-colors ${
                          isSelected
                            ? 'bg-slate-900 text-white font-medium'
                            : 'text-slate-700 hover:bg-slate-50'
                        }`}
                      >
                        <FileCode2
                          className={`w-3.5 h-3.5 shrink-0 ${isSelected ? 'text-slate-300' : 'text-slate-400'}`}
                        />
                        <span className="font-mono text-[11px] truncate">{file.name}</span>
                        <span
                          className={`ml-auto font-mono text-[10px] tabular-nums shrink-0 ${
                            isSelected ? 'text-slate-300' : 'text-slate-400'
                          }`}
                        >
                          {file.lines}L
                        </span>
                      </button>
                    );
                  })}
                </div>
              </div>
            ))
          )}
        </div>
      </aside>

      <div className="lg:col-span-8 xl:col-span-9 flex flex-col min-w-0">
        {activeFile ? (
          <>
            <div className="px-4 py-3 border-b border-slate-200 bg-slate-50 flex flex-wrap items-center justify-between gap-3">
              <div className="min-w-0">
                <div className="font-mono text-xs font-semibold text-slate-900 truncate">
                  D:\PhotoTools\{activeFile.path.replace(/\//g, '\\')}
                </div>
                <div className="mt-1 flex flex-wrap items-center gap-3 text-[11px] text-slate-600 font-mono tabular-nums">
                  <span>文字コード: {activeFile.encoding}</span>
                  <span>サイズ: {activeFile.bytes.toLocaleString()} bytes</span>
                  <span>行数: {activeFile.lines} 行</span>
                </div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={handleCopy}
                  className="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-xs font-medium bg-white border border-slate-200 text-slate-700 hover:bg-slate-100 whitespace-nowrap shrink-0"
                >
                  {copiedPath === activeFile.path ? (
                    <>
                      <Check className="w-3.5 h-3.5 text-emerald-600" />
                      <span>コピー完了</span>
                    </>
                  ) : (
                    <>
                      <Copy className="w-3.5 h-3.5" />
                      <span>全文コピー</span>
                    </>
                  )}
                </button>
                <a
                  href={`/api/file?path=${encodeURIComponent(activeFile.path)}`}
                  download={activeFile.name}
                  className="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-xs font-medium bg-slate-900 text-white hover:bg-slate-800 whitespace-nowrap shrink-0"
                >
                  <Download className="w-3.5 h-3.5" />
                  <span>単体保存</span>
                </a>
              </div>
            </div>

            <div className="flex-1 overflow-auto bg-slate-950 text-slate-100 max-h-[620px]">
              <table className="w-full border-collapse font-mono text-xs leading-5">
                <tbody>
                  {lines.map((line, idx) => (
                    <tr key={idx} className="hover:bg-slate-900/70">
                      <td className="select-none text-right pr-3 pl-3 text-slate-500 border-r border-slate-800 w-12 tabular-nums align-top">
                        {idx + 1}
                      </td>
                      <td className="pl-3 pr-4 whitespace-pre text-slate-100">{line || ' '}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        ) : (
          <div className="p-10 text-center text-xs text-slate-500">左側のツリーからファイルを選択してください。</div>
        )}
      </div>
    </div>
  );
}
