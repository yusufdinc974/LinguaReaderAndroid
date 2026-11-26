// window.electronAPI for the phone.
//
// The desktop app's screens and components talk to their data through
// window.electronAPI (on desktop, Electron's main process answers). The phone
// app answers the same calls here, from its own SQLite database, so the desktop
// components (reader page, word card, highlighting…) run unchanged.
//
// The queries are ported from the ipcMain handlers in desktop/electron/main.ts;
// keep them in step. Calls the phone can't do yet reject with NOT_YET, or answer
// "nothing installed" where the desktop UI expects that (OCR, voices, dictionaries).

import { wordKey } from '@desktop/lib/words';
import { initialSrs } from '../lib/srsStart';
import { openDb, type Db } from './db';
import { httpRequest } from './http';
import { bytesToBase64, readFile, writeFile } from './storage';
import { pickFile } from './files';
import { dataApi } from './dataIO';
import { dictionaries } from './dictionary';
import * as ocr from './ocr';

type Api = Window['electronAPI'];

export const NOT_YET = 'Not available on Android yet';

const LIST_COLORS = [
    '#ef4444', '#f97316', '#eab308', '#22c55e', '#10b981',
    '#14b8a6', '#06b6d4', '#0ea5e9', '#3b82f6', '#6366f1',
    '#8b5cf6', '#a855f7', '#d946ef', '#ec4899', '#f43f5e',
];

/** Settings the page may read and write (desktop: RENDERER_SETTINGS in electron/secrets.ts). */
const PAGE_SETTINGS = new Set(['targetLang', 'theme', 'learnLang', 'deepl_api_key_saved']);

const DEEPL_KEY = 'deepl_api_key';

// ---------------------------------------------------------------- words

/** Deletes words that are in no list any more, with their review progress (desktop: deleteOrphanWords). */
function deleteOrphanWords(db: Db, onlyIds: number[]) {
    if (onlyIds.length === 0) return;
    const orphans = db.all<{ id: number; word: string }>(
        `SELECT w.id, w.word FROM words w
         WHERE NOT EXISTS (SELECT 1 FROM word_list_items wli WHERE wli.word_id = w.id)
         AND w.id IN (${onlyIds.map(() => '?').join(',')})`,
        onlyIds,
    );
    if (orphans.length === 0) return;
    // Keys still used by the words that stay (one pass, not one scan per word)
    const gone = new Set(orphans.map(o => o.id));
    const kept = new Set<string>();
    for (const w of db.all<{ id: number; word: string }>('SELECT id, word FROM words')) if (!gone.has(w.id)) kept.add(wordKey(w.word));
    for (const o of orphans) {
        const key = wordKey(o.word);
        if (!kept.has(key)) db.run('DELETE FROM word_familiarity WHERE word_lower = ?', [key]);
        db.run('DELETE FROM words WHERE id = ?', [o.id]);
    }
}

// ---------------------------------------------------------------- translation

export async function translate(db: Db, text: string, targetLang: string) {
    if (typeof text !== 'string' || typeof targetLang !== 'string' || !/^[A-Za-z-]{2,8}$/.test(targetLang)) {
        throw new Error('Invalid translation request');
    }
    const key = db.get<{ value: string }>('SELECT value FROM user_settings WHERE key = ?', [DEEPL_KEY])?.value;
    if (key) {
        try {
            const host = key.endsWith(':fx') ? 'api-free.deepl.com' : 'api.deepl.com';
            const r = await httpRequest({
                url: `https://${host}/v2/translate`,
                method: 'POST',
                headers: { Authorization: `DeepL-Auth-Key ${key}`, 'Content-Type': 'application/x-www-form-urlencoded' },
                body: new URLSearchParams({ text, target_lang: targetLang.toUpperCase() }).toString(),
            });
            const t = (r.data as { translations?: { text: string; detected_source_language: string }[] })?.translations?.[0];
            if (r.status === 200 && t) return { translatedText: t.text, detectedLanguage: t.detected_source_language, source: 'DeepL' };
        } catch (e) {
            console.error('DeepL error:', e);
        }
        // Fall through to MyMemory
    }
    const url = `https://api.mymemory.translated.net/get?q=${encodeURIComponent(text)}&langpair=${encodeURIComponent(`autodetect|${targetLang}`)}`;
    const r = await httpRequest({ url });
    const data = r.data as { responseStatus?: number; responseDetails?: string; responseData?: { translatedText: string; detectedLanguage: string } };
    if (r.status !== 200 || data?.responseStatus !== 200 || !data.responseData) throw new Error(data?.responseDetails || `MyMemory failed: ${r.status}`);
    return { translatedText: data.responseData.translatedText, detectedLanguage: data.responseData.detectedLanguage, source: 'MyMemory (Free)' };
}

// ---------------------------------------------------------------- books

/** Opened books are copied into the app's storage, so they can be reopened from the Library. */
const BOOKS = 'books';

async function fileId(bytes: Uint8Array) {
    const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes as BufferSource));
    return Array.from(hash.subarray(0, 8), b => b.toString(16).padStart(2, '0')).join('');
}

const BOOK_TYPES = '.pdf,.epub,.cbz,.zip,.png,.jpg,.jpeg,.webp,.gif,.bmp,.avif,application/pdf,application/epub+zip,image/*';

// ---------------------------------------------------------------- the API

const listeners = new Set<() => void>();
/** Tells every screen that words, lists or progress changed (they reload). */
export const notifyDataChanged = () => listeners.forEach(l => l());

/** Other forms of saved words, per language and word (dictionaries don't change while the app runs). */
const formsCache = new Map<string, string[]>();

export function createApi(db: Db): Api {
    const changed = notifyDataChanged;

    const impl: Partial<Api> = {
        // Books
        openPdfDialog: async () => {
            const file = await pickFile(BOOK_TYPES);
            if (!file) return null;
            const bytes = new Uint8Array(await file.arrayBuffer());
            const data = bytesToBase64(bytes);
            const safe = file.name.replace(/[^\p{L}\p{N}._ -]+/gu, '_').slice(-80);
            const path = `${BOOKS}/${await fileId(bytes)}-${safe}`;
            await writeFile(path, data);
            return { name: file.name, path, data };
        },
        openPdfByPath: async path => {
            if (typeof path !== 'string' || !path.startsWith(`${BOOKS}/`)) return null;
            const data = await readFile(path);
            const row = db.get<{ name: string }>('SELECT name FROM recent_pdfs WHERE path = ?', [path]);
            return data ? { name: row?.name ?? path.slice(BOOKS.length + 18), path, data } : null;
        },
        getRecentPdfs: async () => db.all<RecentPdf>('SELECT * FROM recent_pdfs ORDER BY last_opened DESC LIMIT 30'),
        addRecentPdf: async (name, path) => {
            db.run(
                `INSERT INTO recent_pdfs (name, path, last_opened) VALUES (?, ?, CURRENT_TIMESTAMP)
                 ON CONFLICT(path) DO UPDATE SET last_opened = CURRENT_TIMESTAMP, name = excluded.name`,
                [name, path],
            );
            return true;
        },
        getLastPdfPath: async () => db.get<{ path: string }>('SELECT path FROM recent_pdfs ORDER BY last_opened DESC LIMIT 1')?.path,
        getPdfProgress: async path => db.get<{ last_page: number | null; page_count: number | null }>('SELECT last_page, page_count FROM recent_pdfs WHERE path = ?', [path]) ?? null,
        setPdfProgress: async (path, page, pageCount) => {
            if (!Number.isInteger(page) || page < 1) return false;
            db.run('UPDATE recent_pdfs SET last_page = ?, page_count = ? WHERE path = ?', [page, pageCount || null, path]);
            return true;
        },

        // Word lists
        getWordLists: async () => db.all('SELECT * FROM word_lists ORDER BY created_at DESC, id DESC') as never,
        createWordList: async (name, description, color) => {
            const c = color || LIST_COLORS[Math.floor(Math.random() * LIST_COLORS.length)];
            const id = db.run('INSERT INTO word_lists (name, description, color) VALUES (?, ?, ?)', [name, description ?? '', c]).lastInsertRowid;
            changed();
            return id;
        },
        updateWordList: async (id, name, description) => {
            db.run('UPDATE word_lists SET name = ?, description = ? WHERE id = ?', [name, description, id]);
            changed();
            return true;
        },
        deleteWordList: async id => {
            db.transaction(() => {
                const ids = db.all<{ word_id: number }>('SELECT word_id FROM word_list_items WHERE word_list_id = ?', [id]).map(r => r.word_id);
                db.run('DELETE FROM word_list_items WHERE word_list_id = ?', [id]);
                deleteOrphanWords(db, ids);
                db.run('DELETE FROM word_lists WHERE id = ?', [id]);
            });
            changed();
            return true;
        },

        // Words
        getWordsInList: async listId =>
            db.all(
                `SELECT w.*, wf.familiarity_level, wf.easiness_factor, wf.next_review_date
                 FROM words w
                 JOIN word_list_items wli ON w.id = wli.word_id
                 LEFT JOIN word_familiarity wf ON wf.word_lower = word_key(w.word)
                 WHERE wli.word_list_id = ?
                 ORDER BY wli.added_at DESC, wli.id DESC`,
                [listId],
            ) as never,
        getAllWords: async () =>
            db.all(
                `SELECT w.*, wf.familiarity_level, wf.easiness_factor, wf.next_review_date
                 FROM words w
                 LEFT JOIN word_familiarity wf ON wf.word_lower = word_key(w.word)
                 ORDER BY w.created_at DESC, w.id DESC`,
            ) as never,
        addWord: async (word, translation, sourceLang, targetLang, context, pdfName) => {
            const sentence = typeof context === 'string' ? context.slice(0, 1000) : '';
            const existing = db.get<{ id: number; sentence_context: string | null }>('SELECT id, sentence_context FROM words WHERE word_key(word) = ? LIMIT 1', [wordKey(word)]);
            if (existing) {
                if (sentence && !existing.sentence_context) {
                    db.run("UPDATE words SET sentence_context = ?, pdf_name = COALESCE(NULLIF(pdf_name, ''), ?) WHERE id = ?", [sentence, pdfName, existing.id]);
                }
                return existing.id;
            }
            const id = db.run(
                'INSERT INTO words (word, translation, source_language, target_language, sentence_context, pdf_name) VALUES (?, ?, ?, ?, ?, ?)',
                [word, translation, sourceLang, targetLang, sentence, pdfName],
            ).lastInsertRowid;
            changed();
            return id;
        },
        addWordToList: async (wordId, listId) => {
            try {
                db.run('INSERT INTO word_list_items (word_id, word_list_id) VALUES (?, ?)', [wordId, listId]);
                changed();
                return true;
            } catch {
                return false; // already in the list
            }
        },
        removeWordFromList: async (wordId, listId) => {
            db.transaction(() => {
                db.run('DELETE FROM word_list_items WHERE word_id = ? AND word_list_id = ?', [wordId, listId]);
                deleteOrphanWords(db, [wordId]);
            });
            changed();
            return true;
        },
        deleteWord: async id => {
            const w = db.get<{ word: string }>('SELECT word FROM words WHERE id = ?', [id]);
            if (w) db.run('DELETE FROM word_familiarity WHERE word_lower = ?', [wordKey(w.word)]);
            db.run('DELETE FROM words WHERE id = ?', [id]);
            changed();
            return true;
        },
        getWordByLower: async wordLower => db.get<{ id: number }>('SELECT id FROM words WHERE word_key(word) = ? LIMIT 1', [wordKey(wordLower)]) ?? null,
        getWordColors: async listIds => {
            let sql = `SELECT word_key(w.word) as word_lower, l.color, w.source_language
                       FROM words w
                       JOIN word_list_items wli ON w.id = wli.word_id
                       JOIN word_lists l ON wli.word_list_id = l.id`;
            const params = listIds && listIds.length > 0 ? listIds : [];
            if (params.length) sql += ` WHERE l.id IN (${params.map(() => '?').join(', ')})`;
            sql += ' ORDER BY l.created_at DESC, l.id DESC';
            return db.all(sql, params) as never;
        },

        // Review progress
        getWordFamiliarity: async wordLower => db.get<WordFamiliarity>('SELECT * FROM word_familiarity WHERE word_lower = ?', [wordKey(wordLower)]) ?? null,
        getAllWordFamiliarity: async () => db.all<WordFamiliarity>('SELECT * FROM word_familiarity'),
        setWordFamiliarity: async (rawKey, level, translation, ef = 2.5) => {
            const key = wordKey(rawKey);
            const current = db.get<{ familiarity_level: number }>('SELECT familiarity_level FROM word_familiarity WHERE word_lower = ?', [key]);
            // Adding a word to a second list at the same level keeps its schedule
            if (current && current.familiarity_level === level) return true;
            const s = initialSrs(level, ef);
            db.run(
                `INSERT INTO word_familiarity (word_lower, familiarity_level, translation, easiness_factor, interval, repetitions, next_review_date, updated_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                 ON CONFLICT(word_lower) DO UPDATE SET
                    familiarity_level = excluded.familiarity_level,
                    translation = excluded.translation,
                    easiness_factor = excluded.easiness_factor,
                    interval = excluded.interval,
                    repetitions = excluded.repetitions,
                    next_review_date = excluded.next_review_date,
                    updated_at = CURRENT_TIMESTAMP`,
                [key, level, translation, s.ef, s.interval, s.repetitions, s.nextReviewDate],
            );
            changed();
            return true;
        },
        updateWordSRS: async (rawKey, ef, interval, repetitions, nextReviewDate, familiarityLevel) => {
            db.run(
                `UPDATE word_familiarity SET easiness_factor = ?, interval = ?, repetitions = ?, next_review_date = ?,
                    last_review_date = CURRENT_TIMESTAMP, familiarity_level = ?, updated_at = CURRENT_TIMESTAMP
                 WHERE word_lower = ?`,
                [ef, interval, repetitions, nextReviewDate, familiarityLevel, wordKey(rawKey)],
            );
            changed();
            return true;
        },
        getWordsDueForReview: async () => {
            const today = new Date().toISOString().split('T')[0];
            return db.all<WordFamiliarity>(
                'SELECT * FROM word_familiarity WHERE next_review_date IS NULL OR DATE(next_review_date) <= DATE(?) ORDER BY next_review_date ASC',
                [today],
            );
        },

        // Reviews
        saveQuizResult: async (listId, score, total, quizType) =>
            db.run('INSERT INTO quiz_results (word_list_id, score, total_questions, quiz_type) VALUES (?, ?, ?, ?)', [listId, score, total, quizType]).lastInsertRowid,

        // Settings
        getSetting: async key => (PAGE_SETTINGS.has(key) ? db.get<{ value: string }>('SELECT value FROM user_settings WHERE key = ?', [key])?.value : undefined),
        setSetting: async (key, value) => {
            if (!PAGE_SETTINGS.has(key) || typeof value !== 'string' || value.length > 1000) return false;
            db.run('INSERT OR REPLACE INTO user_settings (key, value) VALUES (?, ?)', [key, value]);
            return true;
        },
        getDeeplKeyStatus: async () => {
            const key = db.get<{ value: string }>('SELECT value FROM user_settings WHERE key = ?', [DEEPL_KEY])?.value;
            return { saved: !!key, hint: key ? key.slice(-4) : '' };
        },
        setDeeplKey: async key => {
            const k = typeof key === 'string' ? key.trim() : '';
            if (k) db.run('INSERT OR REPLACE INTO user_settings (key, value) VALUES (?, ?)', [DEEPL_KEY, k]);
            else db.run('DELETE FROM user_settings WHERE key = ?', [DEEPL_KEY]);
            return true;
        },
        translateText: (text, targetLang = 'en') => translate(db, text, targetLang),

        ...dataApi(db, changed),

        // Text in images: ML Kit (one model for Latin-alphabet languages)
        ocrAvailable: () => ocr.ocrAvailable(),
        ocrGetDoc: async hash => ocr.ocrGetDoc(hash),
        ocrSetDocScript: async (hash, script) => ocr.ocrSetDocScript(hash, script),
        ocrCached: (hash, page, script) => ocr.ocrCached(hash, page, script),
        ocrRecognize: (hash, page, script, image) => ocr.ocrRecognize(hash, page, script, image),
        // Downloaded natural voices aren't on the phone: its own voices are used (platform/speech.ts)
        ttsStatus: async () => ({ supported: false, engine: false, voices: [] }),

        // Offline dictionaries (desktop: electron/dictionary.ts)
        dictStatus: () => dictionaries.installed(),
        dictAvailable: () => dictionaries.available(),
        dictInstall: lang => (formsCache.clear(), dictionaries.install(lang)),
        dictRemove: lang => (formsCache.clear(), dictionaries.remove(lang)),
        dictLookup: async (lang, text) => {
            if (typeof lang !== 'string' || typeof text !== 'string' || !(await dictionaries.installed()).includes(lang)) return null;
            try {
                return await dictionaries.lookup(lang, text);
            } catch (e) {
                console.error('Dictionary lookup failed:', e);
                return [];
            }
        },
        dictForms: async words => {
            if (!Array.isArray(words)) return [];
            const have = new Set(await dictionaries.installed());
            const out: [string, string][] = [];
            for (const w of words.slice(0, 20000)) {
                if (!w || typeof w.key !== 'string' || !have.has(w.lang)) continue;
                const cacheKey = `${w.lang}:${w.key}`;
                let forms = formsCache.get(cacheKey);
                if (!forms) {
                    forms = await dictionaries.formsOf(w.lang, w.key).catch(() => []);
                    formsCache.set(cacheKey, forms);
                }
                for (const f of forms) out.push([f, w.key]);
            }
            return out;
        },
        onDictProgress: cb => dictionaries.onProgress(cb),
        getAppVersion: async () => __APP_VERSION__,
        onDataUpdated: cb => {
            listeners.add(cb);
            return () => listeners.delete(cb);
        },
        onSyncStatus: () => () => { },
        onUpdateStatus: () => () => { },
        onTtsProgress: () => () => { },
    };

    return new Proxy(impl as Api, {
        get(target, prop) {
            if (prop in target) return target[prop as keyof Api];
            return () => Promise.reject(new Error(`${NOT_YET}: ${String(prop)}`));
        },
    });
}

/** Opens the database and installs window.electronAPI. Call before rendering the app. */
export async function installApi() {
    const db = await openDb();
    window.electronAPI = createApi(db);
    return db;
}
