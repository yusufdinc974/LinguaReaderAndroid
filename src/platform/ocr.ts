// Text in images on the phone: Google's ML Kit text recognition (through
// @pantrist/capacitor-plugin-ml-kit-text-recognition) instead of the desktop's
// own OCR models. Its results are turned into the desktop's OcrPage shape, so
// the desktop's page view draws the same tappable, highlighted text layer.
// Results are kept per book and page, so a page is only read once.

import { CapacitorPluginMlKitTextRecognition as MlKit, type Line, type TextDetectionResult } from '@pantrist/capacitor-plugin-ml-kit-text-recognition';
import type { OcrLine, OcrPage } from '@desktop/../electron/ocr/types';
import { base64ToBytes, bytesToBase64, isNative, readFile, writeFile } from './storage';

/** Bump when the conversion below changes, so old saved pages are read again. */
const VERSION = 1;
const cacheFile = (hash: string, page: number) => `ocr/${hash}-${page}-v${VERSION}.json`;

/** For tests in a browser: window.__mlkit can stand in for ML Kit. */
type Detect = (o: { base64Image: string }) => Promise<TextDetectionResult>;
const detect = (): Detect | null => (window as { __mlkit?: Detect }).__mlkit ?? (isNative ? o => MlKit.detectText(o) : null);

export const ocrAvailable = async () => detect() !== null;

export async function ocrCached(hash: string, page: number): Promise<OcrPage | null> {
    const raw = await readFile(cacheFile(hash, page)).catch(() => null);
    if (!raw) return null;
    try {
        return JSON.parse(new TextDecoder().decode(base64ToBytes(raw)));
    } catch {
        return null;
    }
}

async function toJpeg(image: { data: Uint8Array; width: number; height: number }) {
    const canvas = document.createElement('canvas');
    canvas.width = image.width;
    canvas.height = image.height;
    const ctx = canvas.getContext('2d')!;
    ctx.putImageData(new ImageData(new Uint8ClampedArray(image.data.buffer as ArrayBuffer, image.data.byteOffset, image.data.byteLength), image.width, image.height), 0, 0);
    const blob = await new Promise<Blob>((res, rej) => canvas.toBlob(b => (b ? res(b) : rej(new Error('Could not encode the page'))), 'image/jpeg', 0.92));
    return bytesToBase64(new Uint8Array(await blob.arrayBuffer()));
}

const RTL = /[\p{Script=Arabic}\p{Script=Hebrew}]/u;

/** One ML Kit line → the desktop's line shape (centre, length, thickness, angle, character cuts). */
export function convertLine(line: Line, block: number): OcrLine | null {
    const text = line.text;
    const cps = Array.from(text);
    if (cps.length === 0) return null;
    const c = line.cornerPoints;
    const b = line.boundingBox;
    // Corners give the real slant; fall back to the upright box
    const tl = c?.topLeft ?? { x: b.left, y: b.top };
    const tr = c?.topRight ?? { x: b.right, y: b.top };
    const br = c?.bottomRight ?? { x: b.right, y: b.bottom };
    const bl = c?.bottomLeft ?? { x: b.left, y: b.bottom };
    const angle = Math.atan2(tr.y - tl.y + (br.y - bl.y), tr.x - tl.x + (br.x - bl.x));
    const len = (Math.hypot(tr.x - tl.x, tr.y - tl.y) + Math.hypot(br.x - bl.x, br.y - bl.y)) / 2;
    const thick = (Math.hypot(bl.x - tl.x, bl.y - tl.y) + Math.hypot(br.x - tr.x, br.y - tr.y)) / 2;
    if (!(len > 0 && thick > 0)) return null;
    const cx = (tl.x + tr.x + br.x + bl.x) / 4;
    const cy = (tl.y + tr.y + br.y + bl.y) / 4;
    const rtl = RTL.test(text);

    // Where each word sits along the line, from ML Kit's word boxes
    const cos = Math.cos(angle), sin = Math.sin(angle);
    const along = (x: number, y: number) => ((x - cx) * cos + (y - cy) * sin) / len + 0.5;
    const cuts: number[] = [];
    const words = line.elements ?? [];
    const joined = words.map(w => w.text).join(' ');
    if (words.length > 0 && joined === text) {
        const spans = words.map(w => {
            const e = w.boundingBox;
            const xs = [along(e.left, e.top), along(e.right, e.top), along(e.left, e.bottom), along(e.right, e.bottom)];
            let a = Math.max(0, Math.min(...xs)), z = Math.min(1, Math.max(...xs));
            if (rtl) [a, z] = [1 - z, 1 - a];
            return { a, z, n: Array.from(w.text).length };
        });
        if (rtl) spans.sort((p, q) => p.a - q.a);
        spans.forEach((s, i) => {
            for (let k = 0; k < s.n; k++) cuts.push(s.a + ((s.z - s.a) * k) / s.n);
            // The space after a word runs to the next word
            if (i < spans.length - 1) cuts.push(s.z);
        });
        cuts.push(spans[spans.length - 1].z);
        // Keep them in order even when boxes overlap
        for (let i = 1; i < cuts.length; i++) if (cuts[i] < cuts[i - 1]) cuts[i] = cuts[i - 1];
    }
    return {
        text, conf: 0.9, vertical: false, cx, cy, len, thick, angle, block, rtl: rtl || undefined,
        cuts: cuts.length === cps.length + 1 ? cuts : cps.map((_, i) => i / cps.length).concat(1),
    };
}

export async function ocrRecognize(hash: string, page: number, image: { data: Uint8Array; width: number; height: number }): Promise<OcrPage> {
    const run = detect();
    if (!run) throw new Error('Text recognition is not available here.');
    const result = await run({ base64Image: await toJpeg(image) });
    const lines: OcrLine[] = [];
    result.blocks.forEach((blk, i) => blk.lines.forEach(l => {
        const line = convertLine(l, i);
        if (line) lines.push(line);
    }));
    const out: OcrPage = { width: image.width, height: image.height, script: 'v6', lines };
    void writeFile(cacheFile(hash, page), bytesToBase64(new TextEncoder().encode(JSON.stringify(out)))).catch(() => { });
    return out;
}
