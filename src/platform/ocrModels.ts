// The desktop's text recognition models (PaddleOCR, ONNX) on the phone.
// They're downloaded on request, one pack per script, from the same files the
// desktop bundles (desktop/scripts/fetch-ocr-models.mjs; keep in step), and run
// by the native plugin (android/…/OcrPlugin.java) with ONNX Runtime.

import { registerPlugin, type PluginListenerHandle } from '@capacitor/core';
import type { ScriptId } from '@desktop/../electron/ocr/types';
import type { Ort, Output } from './ocrEngine';
import { base64ToBytes, bytesToBase64, isNative } from './storage';

const MIRRORS = [
    'https://media.githubusercontent.com/media/PT-Perkasa-Pilar-Utama/ppu-paddle-ocr-models/main',
    'https://huggingface.co/snowfluke/ppu-paddle-ocr-models/resolve/main',
];

/** name → [path in the model repo, sha256, bytes] */
const FILES: Record<string, [string, string, number]> = {
    'det.onnx': ['detection/PP-OCRv6_small_det.onnx', 'd73e0058b7a8086bbd57f3d10b8bcd4ff95363f67e06e2762b5e814fe9c9410e', 9880512],
    'rec-v6.onnx': ['recognition/PP-OCRv6_small_rec.onnx', '5435fd747c9e0efe15a96d0b378d5bd157e9492ed8fd80edf08f30d02fa24634', 21159378],
    'rec-v6.txt': ['recognition/ppocrv6_dict.txt', '41557512862dfe31970cf22407742b629725461dd84c0d8771bde9c87c2202c8', 74948],
    'rec-cyrillic.onnx': ['recognition/multi/cyrillic/v5/cyrillic_PP-OCRv5_mobile_rec_infer.onnx', '0d91040605ef7bdca6868fad6cad1664840d031e9f6d40d54607df5b50fa280a', 8073294],
    'rec-cyrillic.txt': ['recognition/multi/cyrillic/v5/ppocrv5_cyrillic_dict.txt', '90822a96058eb83f8e637ace75f90cbd36c41253f9dbdfb88fcf5a2bdd50d669', 2782],
    'rec-korean.onnx': ['recognition/multi/korean/v5/korean_PP-OCRv5_mobile_rec_infer.onnx', 'ee0dfde503d787c91fd0455daae2eb85311b4b5bdcddf85a54d8c1e0adc157de', 13443278],
    'rec-korean.txt': ['recognition/multi/korean/v5/ppocrv5_korean_dict.txt', 'a3792cbb41215a43e555e16ff4a7f7b18db5dd80cd058637098f0d872f2dd9d6', 47452],
    'rec-arabic.onnx': ['recognition/multi/arabic/v5/arabic_PP-OCRv5_mobile_rec_infer.onnx', 'b58f7d1cc7200566aae1d56ac26c17942881958ed100ac5a07d9a6e67150cbef', 8023442],
    'rec-arabic.txt': ['recognition/multi/arabic/v5/ppocrv5_arabic_dict.txt', 'f6b5baf1335408e6e1fb5cc6e8268a26769f549c2bb37268e72a6804fe269b4c', 2370],
    'rec-greek.onnx': ['recognition/multi/el/v5/el_PP-OCRv5_mobile_rec_infer.onnx', '54235f471b1ca8e356c48673125e0b14e4823496cd7bb583b24fb8808dbcd9c4', 7833230],
    'rec-greek.txt': ['recognition/multi/el/v5/ppocrv5_el_dict.txt', '17147b8921fbcc7d2bcbc69cb7dbb7ae61cc0808e6dec1b311d746ffe5f6afed', 1104],
    'rec-thai.onnx': ['recognition/multi/th/v5/th_PP-OCRv5_mobile_rec_infer.onnx', '6f07aa2af58713da04b4bdaf1524588d8051fc734db5a1ad7b7a65c1e7c7ec18', 7915510],
    'rec-thai.txt': ['recognition/multi/th/v5/ppocrv5_th_dict.txt', 'eaacae5cf9b0808d9078ce1152c9ea5c6099d1f563750e66b93c12854acea31a', 1768],
    'rec-devanagari.onnx': ['recognition/multi/devanagari/v5/devanagari_PP-OCRv5_mobile_rec_infer.onnx', '932e2d53fafdfd929131c4e20133f49901288e8ec1ba03b18317a4780b21f3ce', 7936806],
    'rec-devanagari.txt': ['recognition/multi/devanagari/v5/ppocrv5_devanagari_dict.txt', '4bfb5fc511c24da3b1f3a582ae4e07ecd16601997b70b864bb34e111fc646cfe', 1944],
    'rec-tamil.onnx': ['recognition/multi/ta/v5/ta_PP-OCRv5_mobile_rec_infer.onnx', '99734f0d198fddc89869dcce54cab4c8330898bac6ab4a192ee5aef4debb023b', 7910186],
    'rec-tamil.txt': ['recognition/multi/ta/v5/ppocrv5_ta_dict.txt', 'ed4c188a82743f6067809d004be1b320b3d2c53c849a9ca83f8e47e7bcd6010f', 1724],
    'rec-telugu.onnx': ['recognition/multi/te/v5/te_PP-OCRv5_mobile_rec_infer.onnx', 'e068d1331426f686bcffa65b04d295359f2615429100119482e7687e91420504', 7923254],
    'rec-telugu.txt': ['recognition/multi/te/v5/ppocrv5_te_dict.txt', '3b4fa5b9a85676c59681df9155612b86d61a407a2abb074f729ae66e41301a57', 1832],
};

/** Files of a script's pack. The main pack (v6) also holds the text finder every pack needs. */
export const packFiles = (s: ScriptId) => (s === 'v6' ? ['det.onnx', 'rec-v6.onnx', 'rec-v6.txt'] : [`rec-${s}.onnx`, `rec-${s}.txt`]);
export const packBytes = (s: ScriptId) => packFiles(s).reduce((a, f) => a + FILES[f][2], 0);

interface OcrNative {
    list(): Promise<{ files: string[] }>;
    remove(o: { names: string[] }): Promise<{ files: string[] }>;
    text(o: { name: string }): Promise<{ text: string }>;
    install(o: { files: { name: string; urls: string[]; sha256: string; bytes: number }[] }): Promise<{ files: string[] }>;
    run(o: { model: string; input: string; dims: number[]; argmax: boolean }): Promise<{ dims: number[]; data?: string; index?: string; score?: string }>;
    addListener(e: 'progress', f: (p: { name: string; got: number; total: number }) => void): Promise<PluginListenerHandle>;
}
const Native = registerPlugin<OcrNative>('Ocr');

let files: Promise<Set<string>> | null = null;
const listFiles = () => (files ??= isNative ? Native.list().then(r => new Set(r.files)).catch(() => new Set<string>()) : Promise.resolve(new Set<string>()));

/** Scripts whose packs are on the phone (none unless the main pack is). */
export async function installedScripts(): Promise<ScriptId[]> {
    const have = await listFiles();
    const all: ScriptId[] = ['v6', 'cyrillic', 'korean', 'arabic', 'greek', 'thai', 'devanagari', 'tamil', 'telugu'];
    if (!packFiles('v6').every(f => have.has(f))) return [];
    return all.filter(s => packFiles(s).every(f => have.has(f)));
}

export async function installPack(s: ScriptId, onProgress?: (got: number, total: number) => void) {
    if (!isNative) throw new Error('Downloading text recognition works in the Android app.');
    // The main pack comes first: every script needs its text finder.
    const want = [...new Set([...packFiles('v6'), ...packFiles(s)])];
    const sub = onProgress ? await Native.addListener('progress', p => onProgress(p.got, p.total)) : null;
    try {
        const r = await Native.install({
            files: want.map(name => ({ name, urls: MIRRORS.map(m => `${m}/${FILES[name][0]}`), sha256: FILES[name][1], bytes: FILES[name][2] })),
        });
        files = Promise.resolve(new Set(r.files));
    } finally {
        void sub?.remove();
    }
}

export async function removePack(s: ScriptId) {
    // Removing the main pack removes everything: the others can't run without it.
    const names = s === 'v6' ? Object.keys(FILES) : packFiles(s);
    const r = await Native.remove({ names });
    files = Promise.resolve(new Set(r.files));
}

// ------------------------------------------------------------- ONNX Runtime
/** Runs one model on one input: what the engine needs from ONNX Runtime. */
export type Runner = (model: string, input: Float32Array, dims: number[], argmax: boolean) => Promise<Output>;

const asFloats = (b64: string) => {
    const b = base64ToBytes(b64);
    return new Float32Array(b.buffer, b.byteOffset, b.byteLength / 4);
};

export const nativeRunner: Runner = async (model, input, dims, argmax) => {
    const r = await Native.run({ model, input: bytesToBase64(new Uint8Array(input.buffer, input.byteOffset, input.byteLength)), dims, argmax });
    if (r.index && r.score) {
        const ib = base64ToBytes(r.index);
        return { dims: r.dims, argmax: { index: new Int32Array(ib.buffer, ib.byteOffset, ib.byteLength / 4), score: asFloats(r.score) } };
    }
    return { dims: r.dims, data: asFloats(r.data ?? '') };
};

/**
 * The engine's view of ONNX Runtime, backed by a runner. "Loading" a model only
 * names it (see loadAsset); recognition models answer with the best class per step.
 */
export function runnerOrt(run: Runner): Ort {
    class Tensor {
        constructor(public type: 'float32', public data: Float32Array, public dims: number[]) { }
    }
    return {
        InferenceSession: {
            async create(model: Uint8Array) {
                const name = new TextDecoder().decode(model);
                return {
                    inputNames: ['x'],
                    outputNames: ['y'],
                    run: async (feeds: Record<string, unknown>) => {
                        const t = feeds.x as Tensor;
                        return { y: await run(name, t.data, t.dims, name.startsWith('rec-')) };
                    },
                };
            },
        },
        Tensor: Tensor as unknown as Ort['Tensor'],
    };
}

/** Models are named, not read (the native side loads them); dictionaries are read. */
export async function loadAsset(name: string): Promise<Uint8Array> {
    if (name.endsWith('.onnx')) return new TextEncoder().encode(name);
    return new TextEncoder().encode((await Native.text({ name })).text);
}
