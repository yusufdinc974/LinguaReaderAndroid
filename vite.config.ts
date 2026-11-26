/// <reference types="vitest/config" />
import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'
import fs from 'fs'

const pkg = JSON.parse(fs.readFileSync(path.resolve(__dirname, 'package.json'), 'utf8'))

// The phone app is built from two folders:
//   src/          phone screens and the phone's data layer (window.electronAPI)
//   desktop/src/  the desktop app's reader, word and review code (git submodule)
// `@desktop/...` imports point into the second one, so both apps run the same code.

// Content-Security-Policy of the built app. Books are untrusted input, so the
// page only runs its own scripts. Translation requests go through Capacitor's
// native HTTP (src/platform/http.ts), so the page itself connects nowhere.
const CSP = [
    "default-src 'none'",
    "script-src 'self' 'wasm-unsafe-eval'",
    "worker-src 'self' blob:",
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
    "font-src 'self' data: https://fonts.gstatic.com",
    "img-src 'self' data: blob:",
    "connect-src 'self' data: blob: capacitor: https://localhost",
    "media-src 'self' blob:",
    "object-src 'none'",
    "frame-src 'none'",
    "base-uri 'none'",
    "form-action 'none'",
].join('; ')

function contentSecurityPolicy(): Plugin {
    return {
        name: 'linguareader-csp',
        apply: 'build',
        transformIndexHtml: html =>
            html.replace('<meta charset="UTF-8" />', `<meta charset="UTF-8" />\n    <meta http-equiv="Content-Security-Policy" content="${CSP}" />`),
    }
}

/** Copies pdf.js data files (CMaps, fonts, decoders) into dist/pdfjs/, as the desktop build does. */
function pdfjsAssets(): Plugin {
    const dirs = ['cmaps', 'standard_fonts', 'wasm', 'iccs']
    return {
        name: 'linguareader-pdfjs-assets',
        apply: 'build',
        writeBundle(options) {
            const out = options.dir ?? path.resolve(__dirname, 'dist')
            for (const d of dirs) {
                const from = path.resolve(__dirname, 'node_modules/pdfjs-dist', d)
                if (fs.existsSync(from)) fs.cpSync(from, path.join(out, 'pdfjs', d), { recursive: true })
            }
        },
    }
}

export default defineConfig({
    plugins: [react(), contentSecurityPolicy(), pdfjsAssets()],
    base: './',
    define: {
        __APP_VERSION__: JSON.stringify(pkg.version),
    },
    resolve: {
        alias: {
            '@desktop': path.resolve(__dirname, 'desktop/src'),
        },
        // Desktop files import react, pdfjs-dist… from desktop/src: use this app's copies.
        dedupe: ['react', 'react-dom', 'pdfjs-dist', 'lucide-react', 'fflate', 'zustand'],
    },
    build: {
        outDir: 'dist',
        emptyOutDir: true,
    },
    test: {
        include: ['test/unit/**/*.test.ts'],
        environment: 'node',
    },
    server: {
        port: 5174,
        fs: { allow: ['.'] },
    },
})
