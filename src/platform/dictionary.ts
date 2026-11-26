// Offline dictionaries on the phone: the same files and lookups as the
// desktop (desktop/electron/dictionary.ts and dictLookup.ts; keep in step).
//
// On Android the files are downloaded, unpacked and queried by the app's own
// native code (android/…/DictionaryPlugin.java), with Android's SQLite, since
// they are far too big for the page's memory. In a browser (development and
// tests) a small file is kept in IndexedDB and queried with sql.js.

import { registerPlugin, type PluginListenerHandle } from '@capacitor/core';
import type { Database } from 'sql.js';
import { wordKey } from '@desktop/lib/words';
import { sqlJs } from './db';
import { httpRequest } from './http';
import { base64ToBytes, bytesToBase64, deleteFile, isNative, readFile, writeFile } from './storage';

const RELEASE = 'https://github.com/yusufdinc974/LinguaReader/releases/download/dictionaries-1/';
const LANG = /^[a-z]{2,3}$/;

export interface DictionaryInfo { lang: string; file: string; bytes: number; sha256: string; entries: number }
export interface Sense { g: string; t?: string[]; e?: { x: string; tr?: string }[]; y?: string[] }
export interface DictEntry {
    word: string; pos: string; ipa?: string; senses: Sense[]; synonyms?: string[]; antonyms?: string[]; formOf?: string[]; viaForm?: string;
}

type Row = Record<string, string | number | null>;
type Query = { sql: string; params?: (string | number)[] };

interface DictionaryPlugin {
    list(): Promise<{ langs: string[] }>;
    remove(o: { lang: string }): Promise<{ langs: string[] }>;
    install(o: { lang: string; url: string; sha256: string; bytes: number }): Promise<{ langs: string[] }>;
    query(o: { lang: string; queries: Query[] }): Promise<{ results: Row[][] }>;
    addListener(e: 'progress', fn: (p: { lang: string; got: number; total: number }) => void): Promise<PluginListenerHandle>;
}
const Native = registerPlugin<DictionaryPlugin>('Dictionary');

// ---------------------------------------------------------------- browser fallback
const WEB_LIST = 'dict/installed.json';
const webOpen = new Map<string, Promise<Database>>();
async function webInstalled(): Promise<string[]> {
    const raw = await readFile(WEB_LIST);
    try {
        return raw ? JSON.parse(new TextDecoder().decode(base64ToBytes(raw))) : [];
    } catch {
        return [];
    }
}
const webSaveList = (l: string[]) => writeFile(WEB_LIST, bytesToBase64(new TextEncoder().encode(JSON.stringify(l))));
function webDb(lang: string) {
    let p = webOpen.get(lang);
    if (!p) {
        p = (async () => {
            const data = await readFile(`dict/${lang}.db`);
            if (!data) throw new Error('not installed');
            return new (await sqlJs()).Database(base64ToBytes(data));
        })();
        webOpen.set(lang, p);
        p.catch(() => webOpen.delete(lang));
    }
    return p;
}

// ---------------------------------------------------------------- the store
let manifest: { at: number; list: DictionaryInfo[] } | null = null;
const progressFns = new Set<(p: { lang: string; got: number; total: number }) => void>();
if (isNative) void Native.addListener('progress', p => progressFns.forEach(f => f(p))).catch(() => { });

async function run(lang: string, queries: Query[]): Promise<Row[][]> {
    if (isNative) return (await Native.query({ lang, queries })).results;
    const db = await webDb(lang);
    return queries.map(q => {
        const st = db.prepare(q.sql);
        try {
            st.bind(q.params ?? []);
            const rows: Row[] = [];
            while (st.step()) rows.push(st.getAsObject() as Row);
            return rows;
        } finally {
            st.free();
        }
    });
}
const q1 = async (lang: string, sql: string, params: (string | number)[] = []) => (await run(lang, [{ sql, params }]))[0];

export const dictionaries = {
    async installed(): Promise<string[]> {
        return isNative ? (await Native.list()).langs : webInstalled();
    },
    async available(): Promise<DictionaryInfo[]> {
        if (manifest && Date.now() - manifest.at < 3600e3) return manifest.list;
        const r = await httpRequest({ url: `${RELEASE}dictionaries.json`, timeout: 20_000 });
        if (r.status !== 200) throw new Error(r.status === 404 ? 'No dictionaries are published yet.' : `Could not load the list of dictionaries (${r.status}).`);
        const raw = (typeof r.data === 'string' ? JSON.parse(r.data) : r.data) as { dictionaries?: unknown[] };
        const list = (Array.isArray(raw?.dictionaries) ? raw.dictionaries : [])
            .map(d => d as Record<string, unknown>)
            .filter(d => LANG.test(String(d.lang)) && /^[a-z]{2,3}\.db\.gz$/.test(String(d.file)) && /^[0-9a-f]{64}$/.test(String(d.sha256)))
            .map(d => ({ lang: String(d.lang), file: String(d.file), bytes: Number(d.bytes) || 0, sha256: String(d.sha256), entries: Number(d.entries) || 0 }));
        manifest = { at: Date.now(), list };
        return list;
    },
    async install(lang: string): Promise<string[]> {
        if (!LANG.test(lang)) throw new Error('Invalid language');
        const info = (await this.available()).find(d => d.lang === lang);
        if (!info) throw new Error('There is no dictionary for this language yet.');
        if (isNative) return (await Native.install({ lang, url: RELEASE + info.file, sha256: info.sha256, bytes: info.bytes })).langs;
        // Browser: small test files only
        const res = await fetch(RELEASE + info.file);
        if (!res.ok || !res.body) throw new Error(`Download failed (${res.status})`);
        const gz = new Uint8Array(await res.arrayBuffer());
        progressFns.forEach(f => f({ lang, got: gz.length, total: gz.length }));
        const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', gz as BufferSource)), b => b.toString(16).padStart(2, '0')).join('');
        if (hash !== info.sha256) throw new Error('The dictionary download was damaged. Please try again.');
        const db = new Uint8Array(await new Response(new Blob([gz as BlobPart]).stream().pipeThrough(new DecompressionStream('gzip'))).arrayBuffer());
        await writeFile(`dict/${lang}.db`, bytesToBase64(db));
        webOpen.delete(lang);
        const list = [...new Set([...(await webInstalled()), lang])];
        await webSaveList(list);
        return list;
    },
    async remove(lang: string): Promise<string[]> {
        if (isNative) return (await Native.remove({ lang })).langs;
        webOpen.delete(lang);
        await deleteFile(`dict/${lang}.db`);
        const list = (await webInstalled()).filter(l => l !== lang);
        await webSaveList(list);
        return list;
    },
    onProgress(fn: (p: { lang: string; got: number; total: number }) => void) {
        progressFns.add(fn);
        return () => progressFns.delete(fn);
    },
    lookup,
    formsOf,
};

// ---------------------------------------------------------------- lookups (desktop/electron/dictLookup.ts)

function toEntry(r: Row, viaForm?: string | null): DictEntry | null {
    try {
        const d = JSON.parse(String(r.data));
        return { word: String(r.word), pos: d.p ?? '', ipa: d.i, senses: Array.isArray(d.s) ? d.s : [], synonyms: d.y, antonyms: d.a, formOf: d.f, viaForm: viaForm ?? undefined };
    } catch {
        return null;
    }
}

const BY_KEY = 'SELECT id, word, data FROM entries WHERE key = ? ORDER BY id LIMIT 8';

/** Entries for `text`: the word itself, the headword of an inflected form, and what a form-of entry points to. */
export async function lookup(lang: string, text: string, limit = 6): Promise<DictEntry[]> {
    const k = wordKey(text);
    if (!LANG.test(lang) || !k || k.length > 100) return [];
    const [exact, viaForms] = await run(lang, [
        { sql: BY_KEY, params: [k] },
        { sql: 'SELECT e.id, e.word, e.data, f.tags FROM forms f JOIN entries e ON e.id = f.entry WHERE f.key = ? ORDER BY e.id LIMIT 8', params: [k] },
    ]);
    const seen = new Set<number>();
    const out: DictEntry[] = [];
    const add = (r: Row, via?: string | null) => {
        if (seen.has(Number(r.id)) || out.length >= limit) return;
        seen.add(Number(r.id));
        const e = toEntry(r, via);
        if (e) out.push(e);
    };
    exact.sort((a, b) => Number(b.word === text.trim()) - Number(a.word === text.trim()));
    for (const r of exact) add(r);
    for (const r of viaForms) add(r, (r.tags as string | null) || 'form');
    const lemmas = [...new Set(out.flatMap(e => e.formOf ?? []).map(l => wordKey(l)))];
    if (lemmas.length) {
        const more = await run(lang, lemmas.map(l => ({ sql: BY_KEY, params: [l] })));
        for (const rows of more) for (const r of rows) add(r);
    }
    return out;
}

const LATIN = /\p{Script=Latin}/u;
const IPA = /[ɐ-ʯʰ-˿]/u;
const NOT_A_FORM = /\b(auxiliary|diminutive|augmentative|noun-from-verb|romanization|historical|obsolete|archaic|dated|abbreviation)\b|^(perfective|imperfective)$/;

export function asPrinted(s: string, lang?: string) {
    if (/\p{Script=Cyrillic}/u.test(s)) return s.normalize('NFD').replace(/[̀́]/g, '').normalize('NFC');
    if (/\p{Script=Arabic}/u.test(s)) return s.replace(/[ً-ٰٟـ]/g, '');
    if (lang === 'it') return s.replace(/[àèéìíòóùú](?=\p{L})/gu, c => c.normalize('NFD')[0]);
    return s;
}

/** Other spellings of `text` to highlight (desktop formsOf). */
export async function formsOf(lang: string, text: string, limit = 150): Promise<string[]> {
    const k = wordKey(text);
    if (!LANG.test(lang) || !k || k.length > 100) return [];
    const ids = new Set<number>();
    const byKey = 'SELECT id, data FROM entries WHERE key = ? ORDER BY id LIMIT 6';
    const [own, heads] = await run(lang, [
        { sql: byKey, params: [k] },
        { sql: "SELECT e.id, e.data FROM forms f JOIN entries e ON e.id = f.entry WHERE f.key = ? AND (f.tags IS NULL OR f.tags NOT LIKE '%auxiliary%') ORDER BY e.id LIMIT 4", params: [k] },
    ]);
    const isForm = own.length === 0 || own.every(r => String(r.data).includes('"f":['));
    const rows = isForm ? [...own, ...heads] : own;
    const lemmas: string[] = [];
    for (const r of rows) {
        ids.add(Number(r.id));
        if (!isForm) continue;
        try {
            for (const l of (JSON.parse(String(r.data)).f ?? []) as string[]) lemmas.push(wordKey(l));
        } catch { /* bad row */ }
    }
    if (lemmas.length) for (const rs of await run(lang, lemmas.map(l => ({ sql: byKey, params: [l] })))) for (const x of rs) ids.add(Number(x.id));
    if (ids.size === 0) return [];
    const first = [...ids].slice(0, 6);
    const alts = await q1(lang, `SELECT key FROM forms WHERE entry IN (${first.map(() => '?').join(',')}) AND tags LIKE '%alternative%' LIMIT 6`, first);
    if (alts.length) for (const rs of await run(lang, alts.map(a => ({ sql: byKey, params: [String(a.key)] })))) for (const x of rs) ids.add(Number(x.id));
    const list = [...ids].slice(0, 10);
    const marks = list.map(() => '?').join(',');
    const [keysRows, formRows] = await run(lang, [
        { sql: `SELECT key FROM entries WHERE id IN (${marks})`, params: list },
        { sql: `SELECT key, tags FROM forms WHERE entry IN (${marks}) LIMIT 600`, params: list },
    ]);
    const keys = [...keysRows, ...formRows.filter(r => !NOT_A_FORM.test(String(r.tags ?? '')))].map(r => asPrinted(String(r.key), lang));
    const multi = k.includes(' ');
    const latin = LATIN.test(k);
    const kanji = /\p{Script=Han}/u.test(k);
    const out = new Set<string>();
    for (const f of keys) {
        if (f === k || (!multi && f.includes(' ')) || [...f].length < 2 || (!latin && LATIN.test(f)) || /\d/.test(f) || IPA.test(f) || (kanji && [...f].length < 3 && /^[\p{Script=Hiragana}\p{Script=Katakana}ー]+$/u.test(f))) continue;
        out.add(f);
        if (out.size >= limit) break;
    }
    return [...out];
}
