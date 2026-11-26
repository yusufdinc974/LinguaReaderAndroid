// The phone's word database: SQLite (sql.js, compiled to WebAssembly) with the
// same tables and columns as the desktop app, so backups and Wi-Fi sync can
// move rows between the two without converting them.
//
// sql.js keeps the database in memory; every change is written back to the
// app's storage shortly after (and right away when the app goes to the background).

import initSqlJs, { type Database, type SqlValue } from 'sql.js';
import wasmUrl from 'sql.js/dist/sql-wasm.wasm?url';
import { wordKey } from '@desktop/lib/words';
import { base64ToBytes, bytesToBase64, readFile, writeFile } from './storage';

const DB_FILE = 'linguareader.db';

/** Kept in step with createTables() in desktop/electron/main.ts. */
const SCHEMA = `
    CREATE TABLE IF NOT EXISTS word_lists (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      description TEXT,
      color TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE IF NOT EXISTS words (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      word TEXT NOT NULL,
      translation TEXT NOT NULL,
      source_language TEXT NOT NULL,
      target_language TEXT NOT NULL,
      sentence_context TEXT,
      pdf_name TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      mastery_level INTEGER DEFAULT 0
    );
    CREATE TABLE IF NOT EXISTS word_list_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      word_list_id INTEGER NOT NULL,
      word_id INTEGER NOT NULL,
      added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (word_list_id) REFERENCES word_lists(id) ON DELETE CASCADE,
      FOREIGN KEY (word_id) REFERENCES words(id) ON DELETE CASCADE,
      UNIQUE(word_list_id, word_id)
    );
    CREATE TABLE IF NOT EXISTS quiz_results (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      word_list_id INTEGER NOT NULL,
      score INTEGER NOT NULL,
      total_questions INTEGER NOT NULL,
      quiz_type TEXT NOT NULL,
      completed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (word_list_id) REFERENCES word_lists(id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS user_settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS recent_pdfs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      path TEXT NOT NULL UNIQUE,
      last_opened TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      last_page INTEGER DEFAULT 1,
      page_count INTEGER
    );
    CREATE TABLE IF NOT EXISTS word_familiarity (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      word_lower TEXT NOT NULL UNIQUE,
      familiarity_level INTEGER DEFAULT 1,
      translation TEXT,
      easiness_factor REAL DEFAULT 2.5,
      interval INTEGER DEFAULT 0,
      repetitions INTEGER DEFAULT 0,
      next_review_date TEXT,
      last_review_date TEXT,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
`;

export type Row = Record<string, SqlValue>;
type Params = SqlValue[];

export class Db {
    private saveTimer: ReturnType<typeof setTimeout> | null = null;
    private saving: Promise<void> = Promise.resolve();

    constructor(private db: Database, private persist: (bytes: Uint8Array) => Promise<void>) {
        db.create_function('word_key', (s: string | null) => (s == null ? null : wordKey(s)));
        db.exec('PRAGMA foreign_keys = ON;');
        db.exec(SCHEMA);
    }

    all<T = Row>(sql: string, params: Params = []): T[] {
        const stmt = this.db.prepare(sql);
        try {
            stmt.bind(params);
            const rows: T[] = [];
            while (stmt.step()) rows.push(stmt.getAsObject() as T);
            return rows;
        } finally {
            stmt.free();
        }
    }

    get<T = Row>(sql: string, params: Params = []): T | undefined {
        return this.all<T>(sql, params)[0];
    }

    /** Runs a change and schedules a save. Returns the new row id for inserts. */
    run(sql: string, params: Params = []): { changes: number; lastInsertRowid: number } {
        this.db.run(sql, params);
        const changes = this.db.getRowsModified();
        const id = Number(this.db.exec('SELECT last_insert_rowid()')[0]?.values[0]?.[0] ?? 0);
        this.scheduleSave();
        return { changes, lastInsertRowid: id };
    }

    transaction<T>(fn: () => T): T {
        this.db.exec('BEGIN');
        try {
            const out = fn();
            this.db.exec('COMMIT');
            return out;
        } catch (e) {
            this.db.exec('ROLLBACK');
            throw e;
        }
    }

    private scheduleSave() {
        if (this.saveTimer) clearTimeout(this.saveTimer);
        this.saveTimer = setTimeout(() => void this.flush(), 400);
    }

    /** Writes the database to storage now (also called when the app is backgrounded). */
    flush(): Promise<void> {
        if (this.saveTimer) clearTimeout(this.saveTimer);
        this.saveTimer = null;
        const bytes = this.db.export();
        // export() ends sql.js's open statement state; foreign keys must be turned on again.
        this.db.exec('PRAGMA foreign_keys = ON;');
        this.saving = this.saving.then(() => this.persist(bytes)).catch(e => console.error('Saving the database failed:', e));
        return this.saving;
    }
}

let sqlModule: ReturnType<typeof initSqlJs> | null = null;
/** The sql.js module (one copy of the WebAssembly for the whole app). */
export function sqlJs(wasmBinary?: ArrayBuffer) {
    sqlModule ??= initSqlJs(wasmBinary ? { wasmBinary } : { locateFile: () => wasmUrl });
    return sqlModule;
}

let opened: Promise<Db> | null = null;

export function openDb(): Promise<Db> {
    opened ??= (async () => {
        const SQL = await sqlJs();
        const stored = await readFile(DB_FILE);
        const sqlDb = new SQL.Database(stored ? base64ToBytes(stored) : undefined);
        const db = new Db(sqlDb, bytes => writeFile(DB_FILE, bytesToBase64(bytes)));
        document.addEventListener('visibilitychange', () => {
            if (document.visibilityState === 'hidden') void db.flush();
        });
        return db;
    })();
    return opened;
}

/** For tests: a database that lives only in memory. */
export async function memoryDb(sqlWasm?: ArrayBuffer): Promise<Db> {
    const SQL = await sqlJs(sqlWasm);
    return new Db(new SQL.Database(), async () => { });
}
