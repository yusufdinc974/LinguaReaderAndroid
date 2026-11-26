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

export interface HttpOptions {
    url: string;
    method?: 'GET' | 'POST';
    headers?: Record<string, string>;
    /** A string is sent as is; anything else is sent as JSON. */
    body?: unknown;
    /** Milliseconds */
    timeout?: number;
}

export async function httpRequest(opts: HttpOptions): Promise<HttpResponse> {
    const method = opts.method ?? 'GET';
    const json = opts.body !== undefined && typeof opts.body !== 'string';
    const headers = { ...(json ? { 'Content-Type': 'application/json' } : {}), ...opts.headers };
    if (isNative) {
        const r = await CapacitorHttp.request({
            url: opts.url, method, headers, data: opts.body, responseType: 'json',
            connectTimeout: opts.timeout, readTimeout: opts.timeout,
        });
        return { status: r.status, data: r.data };
    }
    const ctrl = new AbortController();
    const timer = opts.timeout ? setTimeout(() => ctrl.abort(), opts.timeout) : null;
    const r = await fetch(opts.url, { method, headers, body: json ? JSON.stringify(opts.body) : (opts.body as string | undefined), signal: ctrl.signal })
        .finally(() => timer && clearTimeout(timer));
    const text = await r.text();
    let data: unknown = text;
    try {
        data = JSON.parse(text);
    } catch {
        // not JSON
    }
    return { status: r.status, data };
}
