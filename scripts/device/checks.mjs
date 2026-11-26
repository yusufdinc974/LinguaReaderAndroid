// Speed and function checks on a phone, over Chrome DevTools (debug builds allow WebView debugging).
// Usage: adb forward tcp:9222 localabstract:webview_devtools_remote_<pid>, then node scripts/device/checks.mjs
// Keep the app in front: Android cuts the network of apps in the background.
const list = await (await fetch('http://localhost:9222/json')).json();
const target = list.find(x => x.type === 'page' && /localhost/.test(x.url)) ?? list[0];
const ws = new WebSocket(target.webSocketDebuggerUrl);
let n = 0; const waiting = new Map();
ws.onmessage = e => { const m = JSON.parse(e.data); waiting.get(m.id)?.(m); waiting.delete(m.id); };
await new Promise(r => (ws.onopen = r));
const ev = (code, timeout = 120000) => new Promise((resolve) => {
  const id = ++n; const t = setTimeout(() => resolve('TIMEOUT'), timeout);
  waiting.set(id, m => { clearTimeout(t); resolve(m.result?.exceptionDetails ? 'ERROR ' + (m.result.exceptionDetails.exception?.description ?? m.result.exceptionDetails.text) : m.result?.result?.value); });
  ws.send(JSON.stringify({ id, method: 'Runtime.evaluate', params: { expression: `(async () => { ${code} })()`, awaitPromise: true, returnByValue: true } }));
});
const show = (k, v) => console.log(`${k}: ${typeof v === 'string' ? v : JSON.stringify(v)}`);

show('app', await ev(`return { version: await window.electronAPI.getAppVersion(), dpr: devicePixelRatio, screen: innerWidth + 'x' + innerHeight, ua: navigator.userAgent.match(/Chrome\\/[\\d.]+/)?.[0] }`));
show('voices', await ev(`await new Promise(r => setTimeout(r, 1500)); const v = speechSynthesis.getVoices(); return v.length + ' voices; fr: ' + v.filter(x => x.lang.startsWith('fr')).length + ', tr: ' + v.filter(x => x.lang.startsWith('tr')).length + ', en: ' + v.filter(x => x.lang.startsWith('en')).length`));
show('speak', await ev(`const u = new SpeechSynthesisUtterance('Bonjour, le chien mange une pomme.'); u.lang = 'fr-FR'; const t = performance.now(); return await new Promise(r => { u.onend = () => r('spoke in ' + Math.round(performance.now() - t) + ' ms'); u.onerror = () => r('speak error'); speechSynthesis.speak(u); setTimeout(() => r('no end event after 10 s'), 10000); })`));
show('translate', await ev(`const t = performance.now(); const r = await window.electronAPI.translateText('chien', 'tr'); return r.translatedText + ' (' + r.source + ') in ' + Math.round(performance.now() - t) + ' ms'`));
show('ocr', await ev(`
  const c = document.createElement('canvas'); c.width = 900; c.height = 220; const x = c.getContext('2d');
  x.fillStyle = '#fff'; x.fillRect(0, 0, 900, 220); x.fillStyle = '#000'; x.font = '44px serif'; x.fillText('Le chien mange une pomme rouge.', 30, 120);
  const img = x.getImageData(0, 0, 900, 220);
  const t = performance.now();
  const p = await window.electronAPI.ocrRecognize('devicetest', 1, 'auto', { data: new Uint8Array(img.data.buffer), width: 900, height: 220 });
  return p.lines.map(l => l.text).join(' | ') + ' in ' + Math.round(performance.now() - t) + ' ms; cuts ok: ' + p.lines.every(l => l.cuts.length === [...l.text].length + 1)`));
show('qr scanner module', await ev(`return (await window.Capacitor.Plugins.BarcodeScanner.isGoogleBarcodeScannerModuleAvailable()).available`));
show('dictionary install fr (28 MB)', await ev(`
  const before = await window.electronAPI.dictStatus();
  const t = performance.now();
  const after = await window.electronAPI.dictInstall('fr');
  return 'installed ' + JSON.stringify(after) + ' (had ' + JSON.stringify(before) + ') in ' + Math.round((performance.now() - t) / 1000) + ' s'`, 600000));
show('dictionary lookup', await ev(`
  let t = performance.now(); const e = await window.electronAPI.dictLookup('fr', 'mangé'); const a = Math.round(performance.now() - t);
  t = performance.now(); const f = await window.electronAPI.dictForms([{ key: 'manger', lang: 'fr' }, { key: 'chien', lang: 'fr' }]); const b = Math.round(performance.now() - t);
  return 'mangé → ' + e.map(x => x.word + ' (' + x.pos + ')').join(', ') + ' in ' + a + ' ms; forms of manger+chien: ' + f.length + ' in ' + b + ' ms'`));
show('database with 1000 words', await ev(`
  const api = window.electronAPI; const t0 = performance.now();
  const l = await api.createWordList('zz-device-test', '', '#888888');
  for (let i = 0; i < 1000; i++) { const id = await api.addWord('mot' + i, 'kelime' + i, 'fr', 'tr', 'Phrase ' + i, 'test.pdf'); await api.addWordToList(id, l); await api.setWordFamiliarity('mot' + i, 1 + (i % 5), 'kelime' + i); }
  const t1 = performance.now();
  const w = await api.getWordsInList(l); const t2 = performance.now();
  const s = await api.getReviewSchedule(); const c = await api.getWordColors(); const t3 = performance.now();
  await api.deleteWordList(l); const t4 = performance.now();
  return 'add 1000: ' + Math.round(t1 - t0) + ' ms; list: ' + w.length + ' in ' + Math.round(t2 - t1) + ' ms; schedule+colours: ' + Math.round(t3 - t2) + ' ms; delete: ' + Math.round(t4 - t3) + ' ms'`, 300000));
show('memory', await ev(`return performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1e6) + ' MB JS heap' : 'n/a'`));
ws.close();
