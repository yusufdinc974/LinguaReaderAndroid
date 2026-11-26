// HTTP requests to outside services (translation).
//
// On Android they go through the phone's own HTTP stack (CapacitorHttp), so the
// page's Content-Security-Policy can stay closed and CORS doesn't apply.
// In a browser they are plain fetch() calls.

import { CapacitorHttp } from '@capacitor/core';
import { isNative } from './storage';

export interface HttpResponse {
    status: number;
    data: unknown;
}

export async function httpRequest(opts: { url: string; method?: 'GET' | 'POST'; headers?: Record<string, string>; body?: string }): Promise<HttpResponse> {
    const method = opts.method ?? 'GET';
    if (isNative) {
        const r = await CapacitorHttp.request({ url: opts.url, method, headers: opts.headers ?? {}, data: opts.body, responseType: 'json' });
        return { status: r.status, data: r.data };
    }
    const r = await fetch(opts.url, { method, headers: opts.headers, body: opts.body });
    const text = await r.text();
    let data: unknown = text;
    try {
        data = JSON.parse(text);
    } catch {
        // not JSON
    }
    return { status: r.status, data };
}
