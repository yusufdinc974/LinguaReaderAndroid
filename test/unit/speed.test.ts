// Run with: npm test. Big word collections stay quick (the phone measured 12 s to delete 1000 words before).
import { beforeAll, expect, test, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { memoryDb } from '../../src/platform/db';
import { createApi } from '../../src/platform/api';

vi.mock('../../src/platform/files', () => ({ pickFile: vi.fn(), shareFile: vi.fn(async () => true), safeFileName: (s: string) => s }));
vi.mock('../../src/platform/ocr', () => ({}));
vi.mock('../../src/platform/dictionary', () => ({ dictionaries: {} }));

let wasm: ArrayBuffer;
beforeAll(() => {
    const require = createRequire(import.meta.url);
    const buf = readFileSync(require.resolve('sql.js/dist/sql-wasm.wasm'));
    wasm = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
});

test('3000 words: add, read and delete a list quickly, keeping words other lists still use', async () => {
    const api = createApi(await memoryDb(wasm)) as unknown as Record<string, (...a: unknown[]) => Promise<any>>;
    const keep = await api.createWordList('Keep', '', '#111111');
    const big = await api.createWordList('Big', '', '#222222');
    let t = performance.now();
    for (let i = 0; i < 3000; i++) {
        const id = await api.addWord('mot' + i, 'kelime' + i, 'fr', 'tr', 'Phrase ' + i, 't.pdf');
        await api.addWordToList(id, big);
        if (i < 5) await api.addWordToList(id, keep);
        await api.setWordFamiliarity('mot' + i, 2, 'kelime' + i);
    }
    const add = performance.now() - t;
    t = performance.now();
    expect((await api.getWordsInList(big)).length).toBe(3000);
    await api.getReviewSchedule();
    await api.getWordColors();
    const read = performance.now() - t;
    t = performance.now();
    await api.deleteWordList(big);
    const del = performance.now() - t;
    console.log(`add 3000: ${Math.round(add)} ms, read: ${Math.round(read)} ms, delete: ${Math.round(del)} ms`);
    expect((await api.getWordsInList(keep)).length).toBe(5);
    expect(Object.keys(await api.getWordColors()).length).toBeGreaterThanOrEqual(5);
    expect(del).toBeLessThan(1500);
}, 120000);
