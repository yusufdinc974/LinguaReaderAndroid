// Wi-Fi sync with the desktop app (the phone side of desktop/electron/sync_server.ts).
//
// The desktop shows a QR code holding {ip, port, pin}. The phone checks the
// connection, uploads everything it has (the desktop adds what it's missing),
// then downloads the desktop's data and adds what the phone is missing. Review
// progress that is more recent on the desktop replaces the phone's.

import { exportAll, importBackup, type ImportStats } from './dataIO';
import { openDb } from './db';
import { httpRequest } from './http';

export interface Pairing {
    ip: string;
    port: number;
    pin: string;
}

/** The QR code's text, or what the person typed ("192.168.1.5:51234" and the code). */
export function parsePairing(text: string, code?: string): Pairing | null {
    try {
        const j = JSON.parse(text);
        if (typeof j?.ip === 'string' && Number.isInteger(j?.port) && typeof j?.pin === 'string') return checked({ ip: j.ip, port: j.port, pin: j.pin });
    } catch { /* not JSON */ }
    const m = /^\s*(\d{1,3}(?:\.\d{1,3}){3}):(\d{2,5})\s*$/.exec(text);
    if (m && code?.trim()) return checked({ ip: m[1], port: Number(m[2]), pin: code.trim() });
    return null;
}

/** Only a private network address: the code never goes anywhere else. */
function checked(p: Pairing): Pairing | null {
    const ok = /^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|127\.)/.test(p.ip) && p.ip.split('.').every(n => Number(n) <= 255);
    return ok && p.port > 0 && p.port < 65536 && /^[A-Za-z0-9_-]{4,64}$/.test(p.pin) ? p : null;
}

export type SyncStep = 'connecting' | 'uploading' | 'downloading';

export async function syncWithDesktop(p: Pairing, onStep: (s: SyncStep) => void): Promise<{ sent: { lists: number; words: number }; received: ImportStats }> {
    const base = `http://${p.ip}:${p.port}/sync`;
    const headers = { 'x-auth-pin': p.pin };
    const fail = (status: number, what: string) => {
        if (status === 401) return new Error('The desktop refused the code. Show a new code on the computer and scan it again.');
        if (status === 429) return new Error('Too many tries. Show a new code on the computer.');
        return new Error(`${what} failed (${status || 'no answer'}).`);
    };
    const db = await openDb();

    onStep('connecting');
    let hello;
    try {
        hello = await httpRequest({ url: `${base}/handshake`, headers, timeout: 8000 });
    } catch {
        throw new Error("Couldn't reach the computer. Check that both are on the same Wi-Fi and the code is still showing.");
    }
    if (hello.status !== 200) throw fail(hello.status, 'Connecting');

    onStep('uploading');
    const mine = exportAll(db);
    const up = await httpRequest({ url: `${base}/upload`, method: 'POST', headers, body: mine, timeout: 60_000 });
    const upData = up.data as { success?: boolean; error?: string; imported?: { lists: number; words: number } };
    if (up.status !== 200 || upData?.success === false) throw upData?.error ? new Error(`The desktop couldn't take the phone's data: ${upData.error}`) : fail(up.status, 'Sending');

    onStep('downloading');
    const down = await httpRequest({ url: `${base}/download`, headers, timeout: 60_000 });
    if (down.status !== 200) throw fail(down.status, 'Receiving');
    const r = importBackup(db, down.data, true);
    if (!r.success) throw new Error(`The desktop's data couldn't be read: ${r.error}`);
    await db.flush();
    return { sent: { lists: upData?.imported?.lists ?? 0, words: upData?.imported?.words ?? 0 }, received: r.imported };
}
