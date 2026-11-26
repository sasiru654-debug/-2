import { useMemo, useState } from 'react';
import { ArrowRight, BookOpen, History, Search } from 'lucide-react';
import { REPAIR_HISTORY, TEST_MODULES, type RepairHistoryItem } from '../data/repairData';

interface RepairReportTabProps {
  totalFiles: number;
  onSelectFile: (filePath: string) => void;
  onOpenSpec?: () => void;
}

const HISTORY_STATUS_TEXT_STYLE: Record<RepairHistoryItem['status'], string> = {
  検証済: 'text-emerald-700',
  確認待ち: 'text-amber-700',
  '確認・調整中': 'text-amber-800',
};

export default function RepairReportTab({ totalFiles, onSelectFile, onOpenSpec }: RepairReportTabProps) {
  const [query, setQuery] = useState('');

  const filteredHistory = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return REPAIR_HISTORY;
    return REPAIR_HISTORY.filter(
      (h) =>
        h.rev.toLowerCase().includes(q) ||
        h.phase.toLowerCase().includes(q) ||
        h.target.toLowerCase().includes(q) ||
        h.summary.toLowerCase().includes(q) ||
        h.files.some((f) => f.toLowerCase().includes(q))
    );
  }, [query]);

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-px bg-slate-200 border border-slate-200">
        <div className="bg-white p-5">
          <div className="text-xs font-medium text-slate-500">配布パッケージ構成</div>
          <div className="mt-2 flex items-baseline gap-2">
            <span className="text-2xl font-bold text-slate-900 tabular-nums">{totalFiles || 34}</span>
            <span className="text-xs text-slate-500">ファイル</span>
          </div>
          <div className="mt-1 text-xs text-slate-600">D:\PhotoTools\ 階層そのまま収録</div>
        </div>

        <div className="bg-white p-5">
          <div className="text-xs font-medium text-slate-500">修正履歴・対応記録</div>
          <div className="mt-2 flex items-baseline gap-2">
            <span className="text-2xl font-bold text-slate-900 tabular-nums">{REPAIR_HISTORY.length}</span>
            <span className="text-xs text-slate-500">リビジョン</span>
          </div>
          <div className="mt-1 text-xs text-slate-600">初期修復～実機確認までの変更履歴</div>
        </div>

        <div className="bg-white p-5">
          <div className="text-xs font-medium text-slate-500">文字コード・改行正規化</div>
          <div className="mt-2 flex items-baseline gap-2">
            <span className="text-2xl font-bold text-emerald-700 tabular-nums">100%</span>
            <span className="text-xs text-slate-500">CRLF統一</span>
          </div>
          <div className="mt-1 text-xs text-slate-600">.bat=CP932 / .ps1,.ini,.json=UTF-8 BOM / .vbs=ASCII</div>
        </div>

        <div className="bg-white p-5">
          <div className="text-xs font-medium text-slate-500">単体・結合テスト基盤</div>
          <div className="mt-2 flex items-baseline gap-2">
            <span className="text-2xl font-bold text-slate-900 tabular-nums">{TEST_MODULES.length}</span>
            <span className="text-xs text-slate-500">モジュール</span>
          </div>
          <div className="mt-1 text-xs text-slate-600">
            全{TEST_MODULES.length}モジュール構成・最新 {REPAIR_HISTORY[0]?.rev ?? 'REV-51'} まで反映済
          </div>
        </div>
      </div>

      {onOpenSpec && (
        <section className="bg-emerald-50 border border-emerald-300 px-5 py-3.5 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div className="flex items-start gap-2.5 text-xs text-emerald-950">
            <BookOpen className="w-4 h-4 text-emerald-700 shrink-0 mt-0.5" />
            <div>
              <span className="font-bold">
                全体詳細仕様・図解を公開中（最新 {REPAIR_HISTORY[0]?.rev ?? 'REV-51'} 反映済）：
              </span>
              <span className="text-emerald-900">
                ツール関係性フローチャート・起動分岐・Step1〜5データフロー・フォルダ階層・各モジュール仕様を確認できます。
              </span>
            </div>
          </div>
          <button
            type="button"
            onClick={onOpenSpec}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold bg-emerald-900 text-white hover:bg-emerald-800 whitespace-nowrap shrink-0"
          >
            <span>全体仕様・図解を開く</span>
            <ArrowRight className="w-3.5 h-3.5" />
          </button>
        </section>
      )}

      <section className="bg-white border border-slate-200">
        <div className="px-5 py-4 border-b border-slate-200 flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
          <div className="flex items-center gap-2">
            <History className="w-4 h-4 text-slate-700 shrink-0" />
            <div>
              <h2 className="text-base font-semibold text-slate-900">修正箇所・変更履歴（新しい順）</h2>
              <p className="text-xs text-slate-500 mt-0.5">
                テスト・実機確認で修正した箇所の履歴です。ファイル名をクリックするとソースコードを確認できます。
              </p>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-3">
            <div className="relative">
              <Search className="w-3.5 h-3.5 text-slate-400 absolute left-2.5 top-1/2 -translate-y-1/2" />
              <input
                type="text"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="ファイル名・内容で絞り込み..."
                className="pl-8 pr-3 py-1.5 text-xs bg-slate-50 border border-slate-200 text-slate-900 placeholder:text-slate-400 focus:outline-none focus:border-slate-400 w-56"
              />
            </div>
            <span className="font-mono text-[11px] text-slate-500 tabular-nums whitespace-nowrap">
              全 {filteredHistory.length} 件表示
            </span>
          </div>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="bg-slate-50 border-b border-slate-200 text-[11px] font-semibold text-slate-600 tracking-wider">
                <th className="py-2.5 px-4 w-28">履歴 / 状態</th>
                <th className="py-2.5 px-4 w-44">フェーズ / 対象</th>
                <th className="py-2.5 px-4">修正内容の要約</th>
                <th className="py-2.5 px-4 w-60">修正ファイル</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-200 text-xs">
              {filteredHistory.length === 0 ? (
                <tr>
                  <td colSpan={4} className="py-8 text-center text-slate-500">
                    検索キーワードに一致する修正履歴がありません。
                  </td>
                </tr>
              ) : (
                filteredHistory.map((item) => (
                  <tr key={item.rev} className="hover:bg-slate-50/70 align-top">
                    <td className="py-3.5 px-4 whitespace-nowrap">
                      <div className="font-mono text-[11px] font-semibold text-slate-900 tabular-nums">{item.rev}</div>
                      <div className={`mt-1 text-[11px] font-medium ${HISTORY_STATUS_TEXT_STYLE[item.status]}`}>
                        {item.status}
                      </div>
                    </td>
                    <td className="py-3.5 px-4">
                      <div className="text-[11px] font-mono text-slate-500">{item.phase}</div>
                      <div className="font-medium text-slate-900 mt-0.5">{item.target}</div>
                    </td>
                    <td className="py-3.5 px-4 text-slate-700 leading-relaxed">{item.summary}</td>
                    <td className="py-3.5 px-4">
                      <div className="flex flex-col gap-1">
                        {item.files.map((file) => (
                          <button
                            key={file}
                            type="button"
                            onClick={() => onSelectFile(file)}
                            className="text-left font-mono text-[11px] text-sky-700 hover:text-sky-900 hover:underline truncate"
                            title={file}
                          >
                            {file}
                          </button>
                        ))}
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </section>

      <section className="bg-white border border-slate-200">
        <div className="px-5 py-3.5 border-b border-slate-200">
          <h3 className="text-sm font-semibold text-slate-900">刷新されたモジュール結合テスト対象（RunTestManager.bat）</h3>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-3 divide-y md:divide-y-0 md:divide-x divide-slate-200">
          {TEST_MODULES.map((mod, index) => (
            <div
              key={mod.id}
              className={`p-4 ${index >= 3 ? 'border-t border-slate-200' : ''}`}
            >
              <div className="font-mono text-xs font-semibold text-slate-900">{mod.name}</div>
              <div className="mt-1 text-xs text-slate-600 leading-relaxed">{mod.scope}</div>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}
