// Run with: npm test. Backups, shared lists, Anki and the review schedule on the phone.
import { beforeAll, expect, test, vi } from 'vitest';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { unzipSync } from 'fflate';
import { memoryDb, type Db } from '../../src/platform/db';
import { buildApkg, guidFor, readApkg, wordsFrom, guessFields, wordsCsv } from '../../src/platform/anki';
import { exportAll, importBackup, reviewSchedule, dataApi } from '../../src/platform/dataIO';

vi.mock('../../src/platform/files', () => ({ pickFile: vi.fn(), shareFile: vi.fn(async () => true), safeFileName: (s: string) => s }));

let wasm: ArrayBuffer;
beforeAll(() => {
    const require = createRequire(import.meta.url);
    const buf = readFileSync(require.resolve('sql.js/dist/sql-wasm.wasm'));
    wasm = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
});
const fresh = () => memoryDb(wasm);
const NOW = new Date('2026-11-26T12:00:00Z');

function seed(db: Db) {
    const list = db.run("INSERT INTO word_lists (name, description, color) VALUES ('French', 'novel', '#3f8f84')").lastInsertRowid;
    const chien = db.run("INSERT INTO words (word, translation, source_language, target_language, sentence_context, pdf_name) VALUES ('chien', 'köpek', 'fr', 'tr', 'Le chien dort.', 'book.pdf')").lastInsertRowid;
    const chat = db.run("INSERT INTO words (word, translation, source_language, target_language, sentence_context, pdf_name) VALUES ('Chat', 'kedi', 'fr', 'tr', '', 'book.pdf')").lastInsertRowid;
    db.run('INSERT INTO word_list_items (word_list_id, word_id) VALUES (?, ?), (?, ?)', [list, chien, list, chat]);
    db.run("INSERT INTO word_familiarity (word_lower, familiarity_level, translation, easiness_factor, interval, repetitions, next_review_date, last_review_date) VALUES ('chien', 3, 'köpek', 2.3, 10, 4, '2026-12-03', '2026-11-23')");
    db.run("INSERT INTO word_familiarity (word_lower, familiarity_level, translation, next_review_date) VALUES ('chat', 1, 'kedi', '2026-11-20')");
    return list;
}

test('Anki ids match the desktop app (node:crypto there, @noble/hashes here)', () => {
    const desktop = (...v: string[]) => {
        let n = createHash('sha256').update(v.join('__')).digest().readBigUInt64BE(0);
        const B = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&()*+,-./:;<=>?@[]^_`{|}~';
        let out = '';
        while (n > 0n) { out = B[Number(n % 91n)] + out; n /= 91n; }
        return out;
    };
    for (const w of [['linguareader', '先生', 'teacher'], ['linguareader', 'chien', 'köpek'], ['x']]) expect(guidFor(...w)).toBe(desktop(...w));
});

test('an Anki deck goes out and comes back with progress', async () => {
    await fresh();
    const file = await buildApkg('French', [
        { word: 'chien', translation: 'köpek', sentence: 'Le chien dort.', lang: 'fr', interval: 10, easinessFactor: 2.3, repetitions: 4, nextReview: '2026-12-03' },
        { word: 'chat', translation: 'kedi' },
    ], NOW);
    expect(Object.keys(unzipSync(file)).sort()).toEqual(['collection.anki2', 'media']);
    const pkg = await readApkg(file);
    expect(pkg.decks.map(d => [d.name, d.notes])).toEqual([['French', 2]]);
    const map = guessFields(pkg.noteTypes[0].fields);
    const words = wordsFrom(pkg, { [pkg.noteTypes[0].id]: map }, null, true, NOW);
    expect(words.map(w => [w.word, w.translation, w.sentence])).toEqual([['chien', 'köpek', 'Le chien dort.'], ['chat', 'kedi', '']]);
    expect(words[0].srs).toEqual({ interval: 10, easinessFactor: 2.3, repetitions: 4, nextReview: '2026-12-03', level: 3 });
});

test('a full backup restores into an empty phone, and twice adds nothing', async () => {
    const a = await fresh();
    seed(a);
    const backup = JSON.parse(JSON.stringify(exportAll(a)));
    const b = await fresh();
    expect(importBackup(b, backup)).toEqual({ success: true, imported: { lists: 1, words: 2, familiarity: 2, updated: 0 } });
    expect(importBackup(b, backup)).toEqual({ success: true, imported: { lists: 0, words: 0, familiarity: 0, updated: 0 } });
    expect(b.get('SELECT interval FROM word_familiarity WHERE word_lower = ?', ['chien'])).toEqual({ interval: 10 });
    expect(b.all('SELECT word_list_id FROM word_list_items').length).toBe(2);
});

test('sync takes review progress that is newer, a restore does not', async () => {
    const phone = await fresh();
    seed(phone);
    const desktop = await fresh();
    seed(desktop);
    desktop.run("UPDATE word_familiarity SET interval = 25, last_review_date = '2026-11-25' WHERE word_lower = 'chien'");
    const data = JSON.parse(JSON.stringify(exportAll(desktop)));
    importBackup(phone, data);
    expect(phone.get<{ interval: number }>("SELECT interval FROM word_familiarity WHERE word_lower = 'chien'")?.interval).toBe(10);
    const r = importBackup(phone, data, true);
    expect(r.success && r.imported.updated).toBe(1);
    expect(phone.get<{ interval: number }>("SELECT interval FROM word_familiarity WHERE word_lower = 'chien'")?.interval).toBe(25);
    // Older progress never replaces newer
    desktop.run("UPDATE word_familiarity SET interval = 1, last_review_date = '2026-11-01' WHERE word_lower = 'chien'");
    importBackup(phone, JSON.parse(JSON.stringify(exportAll(desktop))), true);
    expect(phone.get<{ interval: number }>("SELECT interval FROM word_familiarity WHERE word_lower = 'chien'")?.interval).toBe(25);
});

test('a bad backup is refused', async () => {
    const db = await fresh();
    expect(importBackup(db, { hello: 1 })).toEqual({ success: false, error: 'Invalid backup file format' });
});

test('words move between lists without losing progress', async () => {
    const db = await fresh();
    const list = seed(db);
    const other = db.run("INSERT INTO word_lists (name) VALUES ('Other')").lastInsertRowid;
    const api = dataApi(db, () => { });
    const chien = db.get<{ id: number }>("SELECT id FROM words WHERE word = 'chien'")!.id;
    expect(await api.moveWordToList!(chien, list, other)).toEqual({ success: true });
    expect(await api.moveWordToList!(chien, list, other)).toEqual({ success: false, message: 'Word already exists in the target list' });
    expect(db.get('SELECT interval FROM word_familiarity WHERE word_lower = ?', ['chien'])).toEqual({ interval: 10 });
});

test('the review schedule counts overdue, today and the next two weeks', () => {
    const s = reviewSchedule([
        { next_review_date: null }, { next_review_date: '2026-11-20' }, { next_review_date: '2026-11-26' },
        { next_review_date: '2026-11-28' }, { next_review_date: '2026-12-02' }, { next_review_date: '2027-02-01' },
    ], new Date('2026-11-26T12:00:00'));
    expect([s.overdue, s.dueToday, s.dueSoon, s.good, s.mastered, s.totalWords]).toEqual([1, 2, 1, 1, 1, 6]);
});

test('CSV has a BOM and escapes formulas', () => {
    const csv = wordsCsv([{ word: '=SUM(A1)', translation: 'a, b' }]);
    expect(csv.startsWith('﻿Word,')).toBe(true);
    expect(csv).toContain(`"'=SUM(A1)","a, b"`);
});
