import express from 'express';
import type { Request, Response } from 'express';
import fs from 'node:fs';
import path from 'node:path';
import iconv from 'iconv-lite';
import JSZip from 'jszip';

interface PackageFileEntry {
  path: string;
  name: string;
  category: string;
  encoding: string;
  bytes: number;
  lines: number;
  content: string;
}

const PORT = 3000;
const ROOT_DIR = process.cwd();
const PACKAGE_DIR = path.resolve(ROOT_DIR, 'phototools');

function getCategory(relPath: string): string {
  const parts = relPath.split('/');
  if (parts.length === 1) {
    return relPath.toLowerCase().endsWith('.bat') ? 'バッチランチャー' : '設定ファイル';
  }
  return `${parts[0]}/`;
}

function getEncodingLabel(relPath: string, raw: Buffer): string {
  const ext = path.extname(relPath).toLowerCase();
  const hasCrlf = raw.includes(Buffer.from('\r\n'));
  const lineEnding = hasCrlf ? 'CRLF' : 'LF';
  if (ext === '.bat') {
    return `CP932 (Shift-JIS) + ${lineEnding}`;
  }
  const hasBom = raw.length >= 3 && raw[0] === 0xef && raw[1] === 0xbb && raw[2] === 0xbf;
  return `${hasBom ? 'UTF-8 (BOM付)' : 'UTF-8'} + ${lineEnding}`;
}

function decodeBuffer(relPath: string, raw: Buffer): string {
  const ext = path.extname(relPath).toLowerCase();
  if (ext === '.bat') {
    return iconv.decode(raw, 'cp932');
  }
  let text = raw.toString('utf8');
  if (text.charCodeAt(0) === 0xfeff) {
    text = text.slice(1);
  }
  return text;
}

function walkPackageFiles(dir: string, baseDir: string): string[] {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const results: string[] = [];
  for (const entry of entries) {
    if (entry.name.startsWith('.')) continue;
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...walkPackageFiles(fullPath, baseDir));
    } else if (entry.isFile()) {
      const rel = path.relative(baseDir, fullPath).replace(/\\/g, '/');
      results.push(rel);
    }
  }
  return results;
}

function sortRelPaths(paths: string[]): string[] {
  return [...paths].sort((a, b) => {
    const aDepth = a.includes('/') ? 1 : 0;
    const bDepth = b.includes('/') ? 1 : 0;
    if (aDepth !== bDepth) return aDepth - bDepth;
    return a.localeCompare(b, 'en');
  });
}

function encodeUtf8BomCrlf(text: string): Buffer {
  const normalized = text.replace(/^\uFEFF/, '').replace(/\r\n/g, '\n').replace(/\r/g, '\n').replace(/\n/g, '\r\n');
  const bom = Buffer.from([0xef, 0xbb, 0xbf]);
  return Buffer.concat([bom, Buffer.from(normalized, 'utf8')]);
}

async function startServer(): Promise<void> {
  const app = express();
  app.use(express.json({ limit: '2mb' }));

  app.get('/api/files', (_req: Request, res: Response) => {
    try {
      if (!fs.existsSync(PACKAGE_DIR)) {
        res.status(404).json({ error: 'phototools ディレクトリが見つかりません。' });
        return;
      }
      const relPaths = sortRelPaths(walkPackageFiles(PACKAGE_DIR, PACKAGE_DIR));
      const files: PackageFileEntry[] = relPaths.map((relPath) => {
        const fullPath = path.join(PACKAGE_DIR, relPath);
        const raw = fs.readFileSync(fullPath);
        const content = decodeBuffer(relPath, raw);
        const lines = content.length === 0 ? 0 : content.split(/\r\n|\r|\n/).length;
        return {
          path: relPath,
          name: path.basename(relPath),
          category: getCategory(relPath),
          encoding: getEncodingLabel(relPath, raw),
          bytes: raw.length,
          lines,
          content,
        };
      });

      const settingsEntry = files.find((f) => f.path === 'settings.ini');
      res.json({
        files,
        defaultSettingsIni: settingsEntry ? settingsEntry.content : '',
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : 'ファイル一覧の取得に失敗しました。';
      res.status(500).json({ error: message });
    }
  });

  app.get('/api/file', (req: Request, res: Response) => {
    try {
      const requested = typeof req.query.path === 'string' ? req.query.path : '';
      if (!requested) {
        res.status(400).json({ error: 'path パラメータが必要です。' });
        return;
      }
      const resolved = path.resolve(PACKAGE_DIR, requested);
      if (!resolved.startsWith(PACKAGE_DIR + path.sep) || !fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
        res.status(404).json({ error: '指定されたファイルが見つかりません。' });
        return;
      }
      const raw = fs.readFileSync(resolved);
      const fileName = path.basename(resolved);
      res.setHeader('Content-Type', 'application/octet-stream');
      res.setHeader('Content-Disposition', `attachment; filename*=UTF-8''${encodeURIComponent(fileName)}`);
      res.send(raw);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'ファイルのダウンロードに失敗しました。';
      res.status(500).json({ error: message });
    }
  });

  const handleDownloadZip = async (req: Request, res: Response) => {
    try {
      if (!fs.existsSync(PACKAGE_DIR)) {
        res.status(404).json({ error: 'phototools ディレクトリが見つかりません。' });
        return;
      }
      const customSettings = typeof req.body?.settingsIni === 'string' ? req.body.settingsIni : null;
      const relPaths = sortRelPaths(walkPackageFiles(PACKAGE_DIR, PACKAGE_DIR));
      const zip = new JSZip();

      for (const relPath of relPaths) {
        if (relPath === 'settings.ini' && customSettings !== null && customSettings.trim().length > 0) {
          zip.file(relPath, encodeUtf8BomCrlf(customSettings));
        } else {
          const fullPath = path.join(PACKAGE_DIR, relPath);
          const raw = fs.readFileSync(fullPath);
          zip.file(relPath, raw);
        }
      }

      const zipBuffer = await zip.generateAsync({
        type: 'nodebuffer',
        platform: 'DOS',
        compression: 'DEFLATE',
        compressionOptions: { level: 6 },
      });

      if (zipBuffer.length < 22 || zipBuffer[0] !== 0x50 || zipBuffer[1] !== 0x4b) {
        throw new Error('生成されたZIPデータの検証に失敗しました。');
      }

      const now = new Date();
      const pad = (n: number) => String(n).padStart(2, '0');
      const timestamp = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}_${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
      const zipFilename = `PhotoTools_${timestamp}.zip`;

      res.status(200);
      res.setHeader('Content-Type', 'application/zip');
      res.setHeader('Content-Disposition', `attachment; filename="${zipFilename}"`);
      res.setHeader('Content-Length', String(zipBuffer.length));
      res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, private');
      res.setHeader('Pragma', 'no-cache');
      res.setHeader('X-Content-Type-Options', 'nosniff');
      res.end(zipBuffer);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'ZIP生成に失敗しました。';
      res.status(500).json({ error: message });
    }
  };

  app.post('/api/download-zip', handleDownloadZip);
  app.get('/api/download-zip', handleDownloadZip);

  if (process.env.NODE_ENV !== 'production') {
    const { createServer: createViteServer } = await import('vite');
    const vite = await createViteServer({
      server: { middlewareMode: true, allowedHosts: true },
      appType: 'spa',
    });
    app.use(vite.middlewares);
  } else {
    const distDir = path.resolve(ROOT_DIR, 'dist');
    app.use(express.static(distDir));
    app.get('*', (_req: Request, res: Response) => {
      res.sendFile(path.join(distDir, 'index.html'));
    });
  }

  app.listen(PORT, '0.0.0.0', () => {
    console.log(`PhotoTools Repair Studio running at http://0.0.0.0:${PORT}`);
  });
}

startServer();
