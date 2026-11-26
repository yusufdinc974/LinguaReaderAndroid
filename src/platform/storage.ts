// Where the phone keeps its files: the word database and copies of opened books.
//
// On Android: the app's private data folder (Capacitor Filesystem, Directory.Data),
// which is removed with the app and isn't readable by other apps.
// In a desktop browser (development): IndexedDB, so the app can be tried without a phone.

import { Capacitor } from '@capacitor/core';
import { Directory, Filesystem } from '@capacitor/filesystem';

export const isNative = Capacitor.isNativePlatform();

// ---------------------------------------------------------------- base64
export function bytesToBase64(bytes: Uint8Array): string {
    let out = '';
    const CHUNK = 0x8000;
    for (let i = 0; i < bytes.length; i += CHUNK) out += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
    return btoa(out);
}

export function base64ToBytes(b64: string): Uint8Array {
    const bin = atob(b64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return bytes;
}

// ---------------------------------------------------------------- IndexedDB (browser)
let idb: Promise<IDBDatabase> | null = null;
function openIdb() {
    idb ??= new Promise((resolve, reject) => {
        const req = indexedDB.open('linguareader', 1);
        req.onupgradeneeded = () => req.result.createObjectStore('files');
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
    });
    return idb;
}

async function idbDo<T>(mode: IDBTransactionMode, fn: (s: IDBObjectStore) => IDBRequest<T>): Promise<T> {
    const db = await openIdb();
    return new Promise((resolve, reject) => {
        const req = fn(db.transaction('files', mode).objectStore('files'));
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
    });
}

// ---------------------------------------------------------------- API
/** Reads a file as base64, or null if it doesn't exist. */
export async function readFile(path: string): Promise<string | null> {
    if (isNative) {
        try {
            const r = await Filesystem.readFile({ path, directory: Directory.Data });
            return typeof r.data === 'string' ? r.data : bytesToBase64(new Uint8Array(await r.data.arrayBuffer()));
        } catch {
            return null;
        }
    }
    const v = await idbDo<string | undefined>('readonly', s => s.get(path));
    return v ?? null;
}

/**
 * Writes a file from base64. On Android it is written next to the target and
 * then renamed over it, so a crash mid-write never leaves half a database.
 */
export async function writeFile(path: string, base64: string): Promise<void> {
    if (isNative) {
        const tmp = `${path}.tmp`;
        await Filesystem.writeFile({ path: tmp, data: base64, directory: Directory.Data, recursive: true });
        await Filesystem.rename({ from: tmp, to: path, directory: Directory.Data, toDirectory: Directory.Data });
        return;
    }
    await idbDo('readwrite', s => s.put(base64, path));
}

export async function deleteFile(path: string): Promise<void> {
    if (isNative) {
        await Filesystem.deleteFile({ path, directory: Directory.Data }).catch(() => { });
        return;
    }
    await idbDo('readwrite', s => s.delete(path));
}
