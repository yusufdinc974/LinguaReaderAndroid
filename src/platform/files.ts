// Files going in and out of the app: the system file picker, and sharing a
// file out (Android's share sheet lets people save it to Files or Drive, send
// it to their computer, or open it in Anki). In a browser it downloads.

import { Directory, Filesystem } from '@capacitor/filesystem';
import { Share } from '@capacitor/share';
import { bytesToBase64, isNative } from './storage';

/** Opens the system file picker; resolves with the chosen file, or null. */
export function pickFile(accept: string): Promise<File | null> {
    return new Promise(resolve => {
        const input = document.createElement('input');
        input.type = 'file';
        input.accept = accept;
        input.style.display = 'none';
        let done = false;
        const finish = (f: File | null) => {
            if (done) return;
            done = true;
            resolve(f);
            input.remove();
            window.removeEventListener('focus', onFocus);
        };
        // Some WebViews never fire "cancel": coming back without a file means cancelled.
        const onFocus = () => setTimeout(() => finish(input.files?.[0] ?? null), 1000);
        input.onchange = () => finish(input.files?.[0] ?? null);
        input.oncancel = () => finish(null);
        document.body.appendChild(input);
        window.addEventListener('focus', onFocus);
        input.click();
    });
}

/** A file name without characters Android or Windows refuse. */
export function safeFileName(name: string) {
    return name.replace(/[\\/:*?"<>|\x00-\x1f]+/g, '_').trim() || 'file';
}

/**
 * Hands a file to the user: the share sheet on the phone, a download in a browser.
 * Resolves false if they closed the share sheet without choosing anything.
 */
export async function shareFile(name: string, data: Uint8Array | string, mime: string, title?: string): Promise<boolean> {
    const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : data;
    const file = safeFileName(name);
    if (isNative) {
        const path = `exports/${file}`;
        await Filesystem.writeFile({ path, data: bytesToBase64(bytes), directory: Directory.Cache, recursive: true });
        const { uri } = await Filesystem.getUri({ path, directory: Directory.Cache });
        try {
            await Share.share({ title: title ?? file, files: [uri], dialogTitle: title ?? `Save ${file}` });
            return true;
        } catch (e) {
            if (/cancel/i.test(String((e as Error)?.message ?? e))) return false;
            throw e;
        }
    }
    const url = URL.createObjectURL(new Blob([bytes as BlobPart], { type: mime }));
    const a = document.createElement('a');
    a.href = url;
    a.download = file;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 10_000);
    return true;
}
