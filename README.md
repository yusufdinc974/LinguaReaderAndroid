# LinguaReader for Android

Read books in the language you're learning on your phone. Tap a word to translate it, save it to a list, and review it before you forget it.

This app is built on the code of [LinguaReader for desktop](https://github.com/yusufdinc974/LinguaReader): the reader, highlighting, sentence capture, word card and review scheduler are the desktop app's own files, so both apps work the same way and new desktop features reach the phone with little extra work.

> **Status:** early rebuild (v2.0.0 in progress). The previous Flutter app is in this repository's history before this rebuild.

## How it's put together

| Folder | What's in it |
|---|---|
| `desktop/` | The desktop app, as a git submodule. Phone screens import from `desktop/src` with `@desktop/...`. |
| `src/platform/` | The phone's side of `window.electronAPI`: a SQLite database (sql.js) with the desktop's tables, file storage, translation requests. Desktop components call it exactly as they call Electron. |
| `src/screens/` | Phone screens: Library, Reader (tap a word to translate), Words. |
| `android/` | The Capacitor Android project. |
| `supabase/functions/` | Server functions for the paid features (AI explanations). |

## Build

```bash
git clone --recurse-submodules https://github.com/yusufdinc974/LinguaReaderAndroid
npm ci
npm run dev          # try it in a browser at http://localhost:5174 (use the phone view in dev tools)
npm test
npm run android:apk  # needs the Android SDK and Java 21; the APK lands in android/app/build/outputs/apk/debug/
```

Every push builds a debug APK on GitHub Actions: open the run under **Actions** and download **linguareader-debug-apk**.

To pick up new desktop code: `cd desktop && git pull origin main && cd .. && git add desktop`.
