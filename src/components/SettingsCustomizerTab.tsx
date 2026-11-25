import { useMemo } from 'react';
import { Download, RotateCcw } from 'lucide-react';
import {
  SETTINGS_FIELDS,
  parseIniToRecord,
  serializeRecordToIni,
  type SettingsFieldSpec,
} from '../data/repairData';

interface SettingsCustomizerTabProps {
  settingsIni: string;
  defaultSettingsIni: string;
  onChangeSettingsIni: (nextIni: string) => void;
  onDownloadZip: () => void;
  isDownloading: boolean;
}

const SECTION_TITLES: Record<SettingsFieldSpec['section'], string> = {
  Paths: 'フォルダ・台帳パス設定 ([Paths])',
  ArchivePeriod: 'アーカイブ四半期分類 ([ArchivePeriod])',
  Extensions: '対象拡張子 ([Extensions])',
  Mega: 'MEGA 連携設定 ([Mega])',
};

export default function SettingsCustomizerTab({
  settingsIni,
  defaultSettingsIni,
  onChangeSettingsIni,
  onDownloadZip,
  isDownloading,
}: SettingsCustomizerTabProps) {
  const parsedValues = useMemo(() => parseIniToRecord(settingsIni), [settingsIni]);
  const isModified = settingsIni.trim() !== defaultSettingsIni.trim();

  const handleFieldChange = (section: SettingsFieldSpec['section'], key: string, value: string) => {
    const nextRecord = { ...parsedValues, [`${section}.${key}`]: value };
    onChangeSettingsIni(serializeRecordToIni(nextRecord));
  };

  const sections: Array<SettingsFieldSpec['section']> = ['Paths', 'ArchivePeriod', 'Extensions', 'Mega'];

  return (
    <div className="grid grid-cols-1 xl:grid-cols-12 gap-6 items-start">
      <div className="xl:col-span-7 bg-white border border-slate-200">
        <div className="px-5 py-4 border-b border-slate-200 flex items-center justify-between gap-4">
          <div>
            <h2 className="text-base font-semibold text-slate-900">settings.ini 環境カスタマイズ</h2>
            <p className="text-xs text-slate-500 mt-0.5">
              ご自身のPC環境に合わせてドライブ文字やフォルダパスを調整したうえで、UTF-8 (BOM付)+CRLF 形式でZIPへ同梱できます。
            </p>
          </div>
          <button
            type="button"
            onClick={() => onChangeSettingsIni(defaultSettingsIni)}
            disabled={!isModified}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium border border-slate-200 text-slate-700 bg-white hover:bg-slate-50 disabled:opacity-40 disabled:cursor-not-allowed whitespace-nowrap shrink-0"
          >
            <RotateCcw className="w-3.5 h-3.5" />
            初期値に戻す
          </button>
        </div>

        <div className="divide-y divide-slate-200">
          {sections.map((section) => {
            const fields = SETTINGS_FIELDS.filter((f) => f.section === section);
            return (
              <div key={section} className="p-5 space-y-4">
                <h3 className="text-xs font-semibold text-slate-800 uppercase tracking-wider">
                  {SECTION_TITLES[section]}
                </h3>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  {fields.map((field) => {
                    const value = parsedValues[`${section}.${field.key}`] ?? field.defaultValue;
                    return (
                      <label key={`${section}.${field.key}`} className="block">
                        <div className="flex items-center justify-between gap-2 mb-1">
                          <span className="text-xs font-medium text-slate-800">{field.label}</span>
                          <span className="font-mono text-[10px] text-slate-400">{field.key}</span>
                        </div>
                        <input
                          type="text"
                          value={value}
                          onChange={(e) => handleFieldChange(section, field.key, e.target.value)}
                          placeholder="（空欄で自動判定または無効）"
                          className="w-full px-2.5 py-1.5 font-mono text-xs bg-slate-50 border border-slate-200 text-slate-900 focus:outline-none focus:bg-white focus:border-slate-500"
                        />
                        <div className="mt-1 text-[11px] text-slate-500">{field.hint}</div>
                      </label>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>
      </div>

      <div className="xl:col-span-5 bg-white border border-slate-200 sticky top-20">
        <div className="px-5 py-4 border-b border-slate-200 flex items-center justify-between gap-3">
          <div>
            <h3 className="text-sm font-semibold text-slate-900">生成される settings.ini プレビュー</h3>
            <p className="text-[11px] text-slate-500 mt-0.5">保存時エンコーディング: UTF-8 (BOM付) + CRLF</p>
          </div>
          <button
            type="button"
            onClick={onDownloadZip}
            disabled={isDownloading}
            className="inline-flex items-center gap-1.5 px-3.5 py-2 text-xs font-semibold bg-slate-900 text-white hover:bg-slate-800 disabled:opacity-50 whitespace-nowrap shrink-0"
          >
            <Download className="w-3.5 h-3.5" />
            {isDownloading ? '生成中...' : 'この設定でZIP取得'}
          </button>
        </div>
        <div className="p-4 bg-slate-950 text-slate-100 overflow-x-auto max-h-[620px]">
          <pre className="font-mono text-xs leading-relaxed whitespace-pre">{settingsIni}</pre>
        </div>
      </div>
    </div>
  );
}
