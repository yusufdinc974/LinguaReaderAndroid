// Stats, the review schedule, moving words, and every way in and out of the
// app (backups, shared lists, CSV, Anki). Ported from the ipcMain handlers in
// desktop/electron/main.ts; keep them in step. Where the desktop shows a save
// dialog, the phone opens the share sheet (see files.ts).

import { wordKey } from '@desktop/lib/words';
import { parseBackup, type Backup } from '@desktop/../electron/backup';
import type { AnkiImportOptions, AnkiOpenResult, FieldMap } from '@desktop/../electron/ankiTypes';
import { ankiText, buildApkg, guessFields, readApkg, wordsCsv, wordsFrom, type AnkiPackage } from './anki';
import type { Db } from './db';
import { pickFile, safeFileName, shareFile } from './files';

type Api = Window['electronAPI'];

/** Settings that may travel in a backup or a sync (desktop: PORTABLE_SETTINGS). */
const PORTABLE_SETTINGS = new Set(['target_language', 'theme']);

const today = () => new Date().toISOString().split('T')[0];
const errText = (e: unknown) => String((e as Error)?.message ?? e);

// ---------------------------------------------------------------- export

/** Everything, in the desktop's backup format (also what Wi-Fi sync sends). */
export function exportAll(db: Db) {
    return {
        version: 1,
        exportedAt: new Date().toISOString(),
        wordLists: db.all('SELECT * FROM word_lists'),
        words: db.all('SELECT * FROM words'),
        wordListItems: db.all('SELECT * FROM word_list_items'),
        quizResults: db.all('SELECT * FROM quiz_results'),
        userSettings: db.all<{ key: string; value: string }>('SELECT key, value FROM user_settings').filter(r => PORTABLE_SETTINGS.has(r.key)),
        wordFamiliarity: db.all('SELECT * FROM word_familiarity'),
    };
}

// ---------------------------------------------------------------- import

export interface ImportStats { lists: number; words: number; familiarity: number; updated?: number }

/**
 * Adds a backup's lists, words and progress (desktop: runImportTransaction).
 * Lists match by name and words by word + translation, so importing twice adds nothing.
 * With `newerProgress` (Wi-Fi sync), review progress that is more recent in the
 * backup also replaces the phone's; a restore only fills in what's missing.
 */
export function importBackup(db: Db, raw: unknown, newerProgress = false): { success: true; imported: ImportStats } | { success: false; error: string } {
    let data: Backup;
    try {
        data = parseBackup(raw);
    } catch (e) {
        return { success: false, error: errText(e) };
    }
    const stats: ImportStats = { lists: 0, words: 0, familiarity: 0, updated: 0 };
    db.transaction(() => {
        const listIds = new Map<number, number>();
        for (const list of data.wordLists) {
            const existing = db.get<{ id: number }>('SELECT id FROM word_lists WHERE name = ?', [list.name]);
            if (existing) {
                listIds.set(list.id, existing.id);
                if (list.color) db.run('UPDATE word_lists SET color = ? WHERE id = ?', [list.color, existing.id]);
            } else {
                const id = db.run('INSERT INTO word_lists (name, description, color, created_at) VALUES (?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP))', [
                    list.name, list.description, list.color || null, list.created_at,
                ]).lastInsertRowid;
                listIds.set(list.id, id);
                stats.lists++;
            }
        }
        const wordIds = new Map<number, number>();
        for (const w of data.words) {
            const existing = db.get<{ id: number }>('SELECT id FROM words WHERE word = ? AND translation = ?', [w.word, w.translation]);
            if (existing) wordIds.set(w.id, existing.id);
            else {
                const id = db.run(
                    'INSERT INTO words (word, translation, source_language, target_language, sentence_context, pdf_name, created_at, mastery_level) VALUES (?, ?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP), ?)',
                    [w.word, w.translation, w.source_language, w.target_language, w.sentence_context, w.pdf_name, w.created_at, w.mastery_level],
                ).lastInsertRowid;
                wordIds.set(w.id, id);
                stats.words++;
            }
        }
        for (const item of data.wordListItems) {
            const l = listIds.get(item.word_list_id);
            const w = wordIds.get(item.word_id);
            if (l && w) db.run('INSERT OR IGNORE INTO word_list_items (word_list_id, word_id) VALUES (?, ?)', [l, w]);
        }
        for (const f of data.wordFamiliarity) {
            const key = wordKey(f.word_lower);
            const existing = db.get<{ last_review_date: string | null }>('SELECT last_review_date FROM word_familiarity WHERE word_lower = ?', [key]);
            const values = [f.familiarity_level, f.translation, f.easiness_factor, f.interval, f.repetitions, f.next_review_date, f.last_review_date];
            if (!existing) {
                db.run(
                    `INSERT INTO word_familiarity (word_lower, familiarity_level, translation, easiness_factor, interval, repetitions, next_review_date, last_review_date, updated_at)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`,
                    [key, ...values],
                );
                stats.familiarity++;
            } else if (newerProgress && f.last_review_date && (!existing.last_review_date || f.last_review_date > existing.last_review_date)) {
                db.run(
                    `UPDATE word_familiarity SET familiarity_level = ?, translation = COALESCE(?, translation), easiness_factor = ?, interval = ?, repetitions = ?,
                        next_review_date = ?, last_review_date = ?, updated_at = CURRENT_TIMESTAMP WHERE word_lower = ?`,
                    [...values, key],
                );
                stats.updated!++;
            }
        }
        for (const s of data.userSettings) {
            if (PORTABLE_SETTINGS.has(s.key)) db.run('INSERT OR IGNORE INTO user_settings (key, value) VALUES (?, ?)', [s.key, s.value]);
        }
    });
    return { success: true, imported: stats };
}

type SharedWord = {
    word: string; translation: string; source_language?: string; target_language?: string;
    familiarity_level?: number; easiness_factor?: number; interval?: number; repetitions?: number; next_review_date?: string | null;
};

/** Words into a list, with their progress when the file has it (desktop: import-words-to-list). */
function importWords(db: Db, listId: number, words: SharedWord[]) {
    const stats = { words: 0, familiarity: 0 };
    db.transaction(() => {
        for (const w of words) {
            if (typeof w?.word !== 'string' || !w.word.trim()) continue;
            const word = w.word.slice(0, 500);
            const translation = typeof w.translation === 'string' ? w.translation.slice(0, 2000) : '';
            const existing = db.get<{ id: number }>('SELECT id FROM words WHERE word = ? AND translation = ?', [word, translation]);
            let id = existing?.id;
            if (!id) {
                id = db.run(
                    "INSERT INTO words (word, translation, source_language, target_language, sentence_context, pdf_name, created_at, mastery_level) VALUES (?, ?, ?, ?, '', 'imported', CURRENT_TIMESTAMP, 0)",
                    [word, translation, typeof w.source_language === 'string' ? w.source_language : 'auto', typeof w.target_language === 'string' ? w.target_language : 'en'],
                ).lastInsertRowid;
                stats.words++;
            }
            db.run('INSERT OR IGNORE INTO word_list_items (word_list_id, word_id) VALUES (?, ?)', [listId, id]);
            const key = wordKey(word);
            if (!db.get('SELECT 1 FROM word_familiarity WHERE word_lower = ?', [key])) {
                const n = (v: unknown, d: number) => (typeof v === 'number' && Number.isFinite(v) ? v : d);
                const next = typeof w.next_review_date === 'string' && /^\d{4}-\d{2}-\d{2}/.test(w.next_review_date) ? w.next_review_date : today();
                db.run(
                    'INSERT INTO word_familiarity (word_lower, familiarity_level, translation, easiness_factor, interval, repetitions, next_review_date, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)',
                    [key, Math.min(5, Math.max(1, Math.round(n(w.familiarity_level, 1)))), translation, n(w.easiness_factor, 2.5), Math.max(0, Math.round(n(w.interval, 0))), Math.max(0, Math.round(n(w.repetitions, 0))), next],
                );
                stats.familiarity++;
            }
        }
    });
    return stats;
}

const LIST_COLORS = ['#c8553d', '#d08a3a', '#c9a83b', '#5f9a5a', '#3f8f84', '#4f7fb0', '#6c6fc2', '#9467b8', '#b65f8f'];
const nextColor = (db: Db) => LIST_COLORS[(db.get<{ n: number }>('SELECT COUNT(*) AS n FROM word_lists')?.n ?? 0) % LIST_COLORS.length];

/** A list shared as a "words only" or "with progress" file goes into a list of that name. */
function importSharedList(db: Db, data: { listName?: unknown; listDescription?: unknown; words: SharedWord[] }) {
    const name = (typeof data.listName === 'string' && data.listName.trim() ? data.listName.trim() : 'Imported words').slice(0, 120);
    const existing = db.get<{ id: number }>('SELECT id FROM word_lists WHERE name = ?', [name]);
    let created = 0;
    const listId = existing?.id ?? (created = 1, db.run('INSERT INTO word_lists (name, description, color) VALUES (?, ?, ?)', [
        name, typeof data.listDescription === 'string' ? data.listDescription.slice(0, 1000) : '', nextColor(db),
    ]).lastInsertRowid);
    const s = importWords(db, listId, data.words.slice(0, 200_000));
    return { lists: created, ...s };
}

// ---------------------------------------------------------------- the handlers

export function dataApi(db: Db, changed: () => void): Partial<Api> {
    let anki: AnkiPackage | null = null;

    const openAnki = async (file: File): Promise<AnkiOpenResult> => {
        try {
            const pkg = await readApkg(new Uint8Array(await file.arrayBuffer()));
            if (pkg.notes.length === 0) return { success: false, error: 'This deck has no cards.' };
            anki = pkg;
            return {
                success: true,
                fileName: file.name.replace(/(\.(apkg|colpkg|anki2|anki21|zip))+$/i, ''),
                decks: pkg.decks,
                noteTypes: pkg.noteTypes.map(t => {
                    const samples = pkg.notes.filter(n => n.noteType === t.id).slice(0, 20).map(n => n.fields);
                    return { ...t, guess: guessFields(t.fields, samples), samples: samples.slice(0, 3).map(f => f.map(v => ankiText(v).slice(0, 160))) };
                }),
                studied: pkg.notes.filter(n => n.card && n.card.type !== 0).length,
            };
        } catch (e) {
            console.error('Anki open error:', e);
            return { success: false, error: errText(e) };
        }
    };

    const exportRows = (listId: number) => db.all<{
        word: string; translation: string; sentence_context: string | null; source_language: string; target_language: string;
        pdf_name: string | null; created_at: string; familiarity_level: number | null; easiness_factor: number | null;
        interval: number | null; repetitions: number | null; next_review_date: string | null;
    }>(
        `SELECT w.word, w.translation, w.sentence_context, w.source_language, w.target_language, w.pdf_name, w.created_at,
                wf.familiarity_level, wf.easiness_factor, wf.interval, wf.repetitions, wf.next_review_date
         FROM words w
         JOIN word_list_items wli ON w.id = wli.word_id
         LEFT JOIN word_familiarity wf ON wf.word_lower = word_key(w.word)
         WHERE wli.word_list_id = ?
         ORDER BY wli.added_at`,
        [listId],
    );

    return {
        moveWordToList: async (wordId, fromListId, toListId) => {
            if (db.get('SELECT 1 FROM word_list_items WHERE word_id = ? AND word_list_id = ?', [wordId, toListId])) {
                return { success: false, message: 'Word already exists in the target list' };
            }
            db.run('UPDATE word_list_items SET word_list_id = ? WHERE word_id = ? AND word_list_id = ?', [toListId, wordId, fromListId]);
            changed();
            return { success: true };
        },
        updateWordMastery: async (wordId, level) => {
            db.run('UPDATE words SET mastery_level = ? WHERE id = ?', [level, wordId]);
            return true;
        },
        getQuizResults: async listId =>
            (listId
                ? db.all('SELECT * FROM quiz_results WHERE word_list_id = ? ORDER BY completed_at DESC', [listId])
                : db.all('SELECT * FROM quiz_results ORDER BY completed_at DESC')) as never,
        getStats: async () => ({
            totalWords: db.get<{ n: number }>('SELECT COUNT(*) AS n FROM words')?.n ?? 0,
            totalLists: db.get<{ n: number }>('SELECT COUNT(*) AS n FROM word_lists')?.n ?? 0,
            totalQuizzes: db.get<{ n: number }>('SELECT COUNT(*) AS n FROM quiz_results')?.n ?? 0,
            averageScore: db.get<{ avg: number | null }>('SELECT AVG(CAST(score AS FLOAT) / total_questions * 100) AS avg FROM quiz_results')?.avg ?? 0,
            masteryDistribution: db.all('SELECT mastery_level, COUNT(*) as count FROM words GROUP BY mastery_level') as never,
            recentQuizzes: db.all(
                `SELECT qr.*, wl.name as list_name FROM quiz_results qr JOIN word_lists wl ON qr.word_list_id = wl.id
                 ORDER BY completed_at DESC LIMIT 10`,
            ) as never,
        }),
        getReviewSchedule: async () => reviewSchedule(db.all<{ next_review_date: string | null }>('SELECT next_review_date FROM word_familiarity')),

        exportData: async () => {
            try {
                const ok = await shareFile(`linguareader-backup-${today()}.json`, JSON.stringify(exportAll(db), null, 2), 'application/json', 'LinguaReader backup');
                return ok ? { success: true, path: 'the place you chose' } : { success: false, error: 'Export cancelled' };
            } catch (e) {
                return { success: false, error: errText(e) };
            }
        },
        importData: async () => {
            const file = await pickFile('.json,.apkg,.colpkg,application/json,application/octet-stream,application/zip');
            if (!file) return { success: false, error: 'Import cancelled' };
            if (!/\.json$/i.test(file.name) && file.type !== 'application/json') {
                const r = await openAnki(file);
                return r.success ? { success: false, anki: r } : { success: false, error: r.error };
            }
            let raw: unknown;
            try {
                raw = JSON.parse(await file.text());
            } catch {
                return { success: false, error: 'The file is not valid JSON' };
            }
            const obj = raw as { wordLists?: unknown; words?: unknown };
            // A list someone shared ("words only" or "with progress") rather than a full backup
            if (obj && !Array.isArray(obj.wordLists) && Array.isArray(obj.words)) {
                const s = importSharedList(db, raw as never);
                changed();
                return { success: true, imported: s };
            }
            const r = importBackup(db, raw);
            if (r.success) changed();
            return r;
        },
        importParsedBackup: async data => {
            const r = importBackup(db, data);
            if (r.success) changed();
            return r;
        },
        parseImportFile: async () => {
            const file = await pickFile('.json,application/json');
            if (!file) return { success: false, cancelled: true };
            try {
                const d = JSON.parse(await file.text());
                if (d.version && d.wordLists && d.words) return { success: true, type: 'full-backup', data: d };
                if (Array.isArray(d.words)) return { success: true, type: 'words-only', listName: d.listName || null, listDescription: d.listDescription || '', words: d.words };
                return { success: false, error: 'Unknown file format' };
            } catch (e) {
                return { success: false, error: errText(e) };
            }
        },
        importWordsToList: async (listId, words) => {
            const s = importWords(db, listId, Array.isArray(words) ? words : []);
            changed();
            return { success: true, imported: s };
        },
        exportList: async (listId, includeProgress) => {
            const list = db.get<{ name: string; description: string }>('SELECT name, description FROM word_lists WHERE id = ?', [listId]);
            if (!list) return { success: false, error: 'List not found' };
            const rows = exportRows(listId);
            const data = includeProgress
                ? {
                    listName: list.name, listDescription: list.description, exportedAt: new Date().toISOString(),
                    words: rows.map(r => ({
                        word: r.word, translation: r.translation, source_language: r.source_language, target_language: r.target_language,
                        familiarity_level: r.familiarity_level || 1, easiness_factor: r.easiness_factor || 2.5, interval: r.interval || 0,
                        repetitions: r.repetitions || 0, next_review_date: r.next_review_date || null,
                    })),
                }
                : { listName: list.name, words: rows.map(r => ({ word: r.word, translation: r.translation })) };
            const name = `${list.name.replace(/[^\p{L}\p{N}]+/gu, '_')}${includeProgress ? '-with-progress' : ''}.json`;
            try {
                const ok = await shareFile(name, JSON.stringify(data, null, 2), 'application/json', `Export “${list.name}”`);
                return ok ? { success: true, path: name, wordCount: rows.length } : { success: false, error: 'Export cancelled' };
            } catch (e) {
                return { success: false, error: errText(e) };
            }
        },
        exportListFile: async (listId, format) => {
            if (!Number.isInteger(listId) || (format !== 'apkg' && format !== 'csv')) return { success: false, error: 'Invalid request' };
            const list = db.get<{ name: string }>('SELECT name FROM word_lists WHERE id = ?', [listId]);
            if (!list) return { success: false, error: 'List not found' };
            const rows = exportRows(listId);
            try {
                const ok = format === 'apkg'
                    ? await shareFile(`${safeFileName(list.name)}.apkg`, await buildApkg(list.name, rows.map(r => ({
                        word: r.word,
                        translation: r.translation,
                        sentence: r.sentence_context,
                        source: r.pdf_name && r.pdf_name !== 'imported' ? r.pdf_name.replace(/\.(pdf|epub|cbz|zip|png|jpe?g|webp|gif|bmp|avif)$/i, '') : '',
                        lang: r.source_language,
                        interval: r.interval,
                        easinessFactor: r.easiness_factor,
                        repetitions: r.repetitions,
                        nextReview: r.next_review_date,
                    }))), 'application/octet-stream', `Export “${list.name}” to Anki`)
                    : await shareFile(`${safeFileName(list.name)}.csv`, wordsCsv(rows), 'text/csv', `Export “${list.name}”`);
                return ok ? { success: true, path: list.name, wordCount: rows.length } : { success: false, cancelled: true };
            } catch (e) {
                console.error('Export list file error:', e);
                return { success: false, error: errText(e) };
            }
        },
        ankiOpen: async () => {
            const file = await pickFile('.apkg,.colpkg,.anki2,.anki21,.zip,application/octet-stream,application/zip');
            if (!file) return { success: false, cancelled: true };
            return openAnki(file);
        },
        ankiImport: async (raw: AnkiImportOptions) => {
            try {
                if (!anki) return { success: false, error: 'Choose the deck again.' };
                const int = (v: unknown) => (Number.isInteger(v) ? (v as number) : null);
                const field = (v: unknown) => { const n = int(v); return n !== null && n >= -1 && n < 1000 ? n : -1; };
                if (!raw || typeof raw !== 'object' || !raw.maps || typeof raw.maps !== 'object') return { success: false, error: 'Invalid request' };
                const maps: Record<number, FieldMap> = {};
                for (const [k, m] of Object.entries(raw.maps)) {
                    if (m && typeof m === 'object') maps[Number(k)] = { word: Math.max(0, field(m.word)), translation: field(m.translation), sentence: field(m.sentence) };
                }
                const decks = Array.isArray(raw.decks) ? raw.decks.map(int).filter((d): d is number => d !== null) : null;
                const lang = typeof raw.lang === 'string' && /^[a-z]{2,3}(-[A-Za-z0-9]+)?$|^auto$/.test(raw.lang) ? raw.lang : 'auto';
                const words = wordsFrom(anki, maps, decks, raw.keepProgress === true);
                if (words.length === 0) return { success: false, error: 'No words found in the chosen fields.' };
                const stats = { added: 0, existing: 0, progress: 0, listId: 0 };
                db.transaction(() => {
                    let listId = int(raw.listId);
                    if (!listId || !db.get('SELECT 1 FROM word_lists WHERE id = ?', [listId])) {
                        listId = db.run('INSERT INTO word_lists (name, description, color) VALUES (?, ?, ?)', [
                            (typeof raw.listName === 'string' && raw.listName ? raw.listName : 'Anki').slice(0, 120), 'Imported from Anki', nextColor(db),
                        ]).lastInsertRowid;
                    }
                    stats.listId = listId;
                    const day = today();
                    for (const w of words) {
                        const key = wordKey(w.word);
                        const existing = db.get<{ id: number; sentence_context: string | null }>('SELECT id, sentence_context FROM words WHERE word_key(word) = ? LIMIT 1', [key]);
                        let id: number;
                        if (existing) {
                            id = existing.id;
                            if (w.sentence && !existing.sentence_context) db.run('UPDATE words SET sentence_context = ? WHERE id = ?', [w.sentence, id]);
                            stats.existing++;
                        } else {
                            id = db.run("INSERT INTO words (word, translation, source_language, target_language, sentence_context, pdf_name) VALUES (?, ?, ?, 'auto', ?, ?)", [
                                w.word, w.translation, lang, w.sentence, w.deck ? `Anki: ${w.deck}` : 'Anki',
                            ]).lastInsertRowid;
                            stats.added++;
                        }
                        db.run('INSERT OR IGNORE INTO word_list_items (word_list_id, word_id) VALUES (?, ?)', [listId, id]);
                        if (!db.get('SELECT 1 FROM word_familiarity WHERE word_lower = ?', [key])) {
                            const s = w.srs;
                            db.run(
                                `INSERT INTO word_familiarity (word_lower, familiarity_level, translation, easiness_factor, interval, repetitions, next_review_date, updated_at)
                                 VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`,
                                [key, s?.level ?? 1, w.translation, s?.easinessFactor ?? 2.5, s?.interval ?? 0, s?.repetitions ?? 0, s?.nextReview ?? day],
                            );
                            if (s) stats.progress++;
                        }
                    }
                });
                anki = null;
                changed();
                return { success: true, ...stats };
            } catch (e) {
                console.error('Anki import error:', e);
                return { success: false, error: errText(e) };
            }
        },
    };
}

/** How many words are due when (desktop: get-review-schedule). */
export function reviewSchedule(rows: { next_review_date: string | null }[], now = new Date()) {
    const t = new Date(now);
    t.setHours(0, 0, 0, 0);
    const todayStr = t.toISOString().split('T')[0];
    let overdue = 0, dueToday = 0, dueSoon = 0, good = 0, mastered = 0;
    const upcomingDays: Record<string, number> = {};
    const bump = (k: string) => (upcomingDays[k] = (upcomingDays[k] || 0) + 1);
    for (const w of rows) {
        if (!w.next_review_date) {
            dueToday++;
            bump(todayStr);
            continue;
        }
        const d = new Date(w.next_review_date);
        d.setHours(0, 0, 0, 0);
        const diff = Math.floor((d.getTime() - t.getTime()) / 86400000);
        const key = w.next_review_date.split('T')[0];
        if (diff < 0) {
            overdue++;
            bump(todayStr);
        } else if (diff === 0) {
            dueToday++;
            bump(todayStr);
        } else if (diff <= 3) {
            dueSoon++;
            bump(key);
        } else if (diff <= 7) {
            good++;
            bump(key);
        } else {
            mastered++;
            if (diff <= 14) bump(key);
        }
    }
    return { overdue, dueToday, dueSoon, good, mastered, totalWords: rows.length, upcomingDays };
}
