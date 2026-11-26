// Run with: npm test. The phone's copy of the desktop OCR engine, with recognition
// answered as "best class per step" (what the native plugin sends), reads every
// script the desktop reads, and gives the same lines as the desktop's engine.
// Needs the models: cd desktop && node scripts/fetch-ocr-models.mjs (skipped otherwise).
import { describe, expect, test } from 'vitest';
import { existsSync, readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { PNG } from 'pngjs';
import { OcrEngine as DesktopEngine, type Ort } from '../../desktop/electron/ocr/engine';
import { argmax, OcrEngine } from '../../src/platform/ocrEngine';
import { runnerOrt, type Runner } from '../../src/platform/ocrModels';
import type { ScriptId } from '../../desktop/electron/ocr/types';

const require = createRequire(import.meta.url);
const MODELS = path.resolve(__dirname, '../../desktop/resources/ocr');
const have = existsSync(path.join(MODELS, 'rec-telugu.onnx'));
const ort = (have ? require('onnxruntime-node') : null) as (Ort & { InferenceSession: { create(m: Uint8Array | string): Promise<any> }; Tensor: any }) | null;
const load = async (name: string) => new Uint8Array(readFileSync(path.join(MODELS, name)));

// Stands in for OcrPlugin.java: runs the model, and answers recognition with argmax only.
const sessions = new Map<string, Promise<any>>();
const runner: Runner = async (model, input, dims, wantArgmax) => {
    if (!sessions.has(model)) sessions.set(model, ort!.InferenceSession.create(path.join(MODELS, model)));
    const s = await sessions.get(model)!;
    const out = (await s.run({ [s.inputNames[0]]: new ort!.Tensor('float32', input, dims) }))[s.outputNames[0]];
    const d = out.dims as number[];
    if (!wantArgmax) return { dims: d, data: out.data };
    const C = d[d.length - 1];
    return { dims: d, argmax: argmax(out.data as Float32Array, (out.data as Float32Array).length / C, C) };
};

const image = (name: string) => {
    const png = PNG.sync.read(readFileSync(path.resolve(__dirname, '../fixtures/ocr', name)));
    return { data: new Uint8Array(png.data), width: png.width, height: png.height };
};

/** Share of characters right (1 − edit distance / length), ignoring spaces. */
function accuracy(got: string, want: string) {
    const a = [...got.replace(/\s+/g, '')], b = [...want.replace(/\s+/g, '')];
    let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
    for (let i = 1; i <= a.length; i++) {
        const cur = [i];
        for (let j = 1; j <= b.length; j++) cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
        prev = cur;
    }
    return 1 - prev[b.length] / b.length;
}

const SAMPLES: [string, ScriptId, string][] = [
    ['ru.png', 'cyrillic', 'Все счастливые семьи похожи друг на друга, каждая несчастливая семья несчастлива по-своему.'],
    ['ar.png', 'arabic', 'ذهب الولد إلى المدرسة في الصباح وقرأ كتابا جميلا عن البحر'],
    ['ko.png', 'korean', '오늘은 날씨가 아주 좋습니다 우리는 공원에서 책을 읽었어요'],
    ['el.png', 'greek', 'Η γάτα κοιμάται στον ήλιο και το σκυλί τρώει ψωμί'],
    ['th.png', 'thai', 'วันนี้อากาศดีมาก เราไปอ่านหนังสือที่สวน'],
    ['hi.png', 'devanagari', 'आज मौसम बहुत अच्छा है हम बगीचे में किताब पढ़ते हैं'],
    ['ja.png', 'v6', '猫は日なたで眠っている。私は毎朝コーヒーを飲みます。'],
];

describe.skipIf(!have)('text in images, every script', () => {
    const all: ScriptId[] = ['v6', 'cyrillic', 'korean', 'arabic', 'greek', 'thai', 'devanagari', 'tamil', 'telugu'];
    const phone = new OcrEngine(runnerOrt(runner), async n => (n.endsWith('.onnx') ? new TextEncoder().encode(n) : load(n)), {}, () => all);
    const desktop = have ? new DesktopEngine(ort!, load) : null;

    for (const [file, script, want] of SAMPLES) {
        test(`${file}: finds ${script} and reads it`, async () => {
            const t = performance.now();
            const page = await phone.recognize(image(file), 'auto', 'v6');
            const text = page.lines.map(l => l.text).join(' ');
            const acc = accuracy(text, want);
            console.log(`${file}: ${page.script} ${(acc * 100).toFixed(1)}% in ${Math.round(performance.now() - t)} ms: ${text}`);
            expect(page.script).toBe(script);
            expect(acc).toBeGreaterThan(0.85);
            // Same lines as the desktop's own engine
            const d = await desktop!.recognize(image(file), script);
            expect(page.lines).toEqual(d.lines);
        }, 60000);
    }

    test('only installed scripts are tried', async () => {
        const latinOnly = new OcrEngine(runnerOrt(runner), async n => (n.endsWith('.onnx') ? new TextEncoder().encode(n) : load(n)), {}, () => ['v6']);
        const page = await latinOnly.recognize(image('ru.png'), 'auto', 'v6');
        expect(page.script).toBe('v6');
    }, 60000);
});
