// Text in images on a phone: downloads the main, Cyrillic, Arabic and Korean packs (69 MB) and reads samples.
// Usage: adb forward tcp:9222 localabstract:webview_devtools_remote_<pid>, then node scripts/device/ocr.mjs
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
const FILES = [{"name": "det.onnx", "urls": ["https://media.githubusercontent.com/media/PT-Perkasa-Pilar-Utama/ppu-paddle-ocr-models/main/detection/PP-OCRv6_small_det.onnx"], "sha256": "d73e0058b7a8086bbd57f3d10b8bcd4ff95363f67e06e2762b5e814fe9c9410e", "bytes": 9880512}, {"name": "rec-v6.onnx", "urls": ["https://media.githubusercontent.com/media/PT-Perkasa-Pilar-Utama/ppu-paddle-ocr-models/main/recognition/PP-OCRv6_small_rec.onnx"], "sha256": "5435fd747c9e0efe15a96d0b378d5bd157e9492ed8fd80edf08f30d02fa24634", "bytes": 21159378}, {"name": "rec-v6.txt", "urls": ["https://media.githubusercontent.com/media/PT-Perkasa-Pilar-Utama/ppu-paddle-ocr-models/main/recognition/ppocrv6_dict.txt"], "sha256": "41557512862dfe31970cf22407742b629725461dd84c0d8771bde9c87c2202c8", "bytes": 74948}, {"name": "rec-cyrillic.onnx", "urls": ["https://media.githubusercontent.com/media/PT-Perkasa-Pilar-Utama/ppu-paddle-ocr-models/main/recognition/multi/cyrillic/v5/cyrillic_PP-OCRv5_mobile_rec_infer.onnx"], "sha256": "0d91040605ef7bdca6868fad6cad1664840d031e9f6d40d54607df5b50fa280a", "bytes": 8073294}, {"name": "rec-cyrillic.txt", "urls": ["https://media.githubusercontent.com/media/PT-Perkasa-Pilar-Utama/ppu-paddle-ocr-models/main/recognition/multi/cyrillic/v5/ppocrv5_cyrillic_dict.txt"], "sha256": "90822a96058eb83f8e637ace75f90cbd36c41253f9dbdfb88fcf5a2bdd50d669", "bytes": 2782}, {"name": "rec-arabic.onnx", "urls": ["https://media.githubusercontent.com/media/PT-Perkasa-Pilar-Utama/ppu-paddle-ocr-models/main/recognition/multi/arabic/v5/arabic_PP-OCRv5_mobile_rec_infer.onnx"], "sha256": "b58f7d1cc7200566aae1d56ac26c17942881958ed100ac5a07d9a6e67150cbef", "bytes": 8023442}, {"name": "rec-arabic.txt", "urls": ["https://media.githubusercontent.com/media/PT-Perkasa-Pilar-Utama/ppu-paddle-ocr-models/main/recognition/multi/arabic/v5/ppocrv5_arabic_dict.txt"], "sha256": "f6b5baf1335408e6e1fb5cc6e8268a26769f549c2bb37268e72a6804fe269b4c", "bytes": 2370}, {"name": "rec-korean.onnx", "urls": ["https://media.githubusercontent.com/media/PT-Perkasa-Pilar-Utama/ppu-paddle-ocr-models/main/recognition/multi/korean/v5/korean_PP-OCRv5_mobile_rec_infer.onnx"], "sha256": "ee0dfde503d787c91fd0455daae2eb85311b4b5bdcddf85a54d8c1e0adc157de", "bytes": 13443278}, {"name": "rec-korean.txt", "urls": ["https://media.githubusercontent.com/media/PT-Perkasa-Pilar-Utama/ppu-paddle-ocr-models/main/recognition/multi/korean/v5/ppocrv5_korean_dict.txt"], "sha256": "a3792cbb41215a43e555e16ff4a7f7b18db5dd80cd058637098f0d872f2dd9d6", "bytes": 47452}];
show('ocr packs install (main + Cyrillic + Arabic + Korean, 69 MB)', await ev(`
  const t = performance.now();
  const r = await window.Capacitor.Plugins.Ocr.install({ files: ${JSON.stringify(FILES)} });
  return r.files.length + ' files in ' + Math.round((performance.now() - t) / 1000) + ' s'`, 900000));
const SAMPLES = {
  ru: ['Все счастливые семьи похожи друг на друга,', 'каждая несчастливая семья несчастлива по-своему.'],
  ar: ['ذهب الولد إلى المدرسة في الصباح', 'وقرأ كتابا جميلا عن البحر'],
  ko: ['오늘은 날씨가 아주 좋습니다', '우리는 공원에서 책을 읽었어요'],
  ja: ['猫は日なたで眠っている。', '私は毎朝コーヒーを飲みます。'],
  en: ['It was a bright cold day in April,', 'and the clocks were striking thirteen.'],
};
for (const [k, lines] of Object.entries(SAMPLES)) {
  const rtl = k === 'ar';
  show('ocr ' + k, await ev(`
    const c = document.createElement('canvas'); c.width = 1000; c.height = 260; const x = c.getContext('2d');
    x.fillStyle = '#fff'; x.fillRect(0, 0, 1000, 260); x.fillStyle = '#111'; x.font = '40px serif';
    x.direction = '${rtl ? 'rtl' : 'ltr'}'; x.textAlign = '${rtl ? 'right' : 'left'}';
    ${JSON.stringify(lines)}.forEach((l, i) => x.fillText(l, ${rtl ? 950 : 50}, 100 + i * 70));
    const img = x.getImageData(0, 0, 1000, 260);
    const t = performance.now();
    const p = await window.electronAPI.ocrRecognize('devicetest-${k}-' + Date.now(), 1, 'auto', { data: new Uint8Array(img.data.buffer), width: 1000, height: 260 });
    return p.script + ': ' + p.lines.map(l => l.text).join(' | ') + ' in ' + Math.round(performance.now() - t) + ' ms'`, 300000));
}
show('ocr full page (Russian, 1080x1600, 30 lines)', await ev(`
  const c = document.createElement('canvas'); c.width = 1080; c.height = 1600; const x = c.getContext('2d');
  x.fillStyle = '#fff'; x.fillRect(0, 0, 1080, 1600); x.fillStyle = '#111'; x.font = '30px serif';
  const words = 'все счастливые семьи похожи друг на друга каждая несчастливая семья несчастлива по своему'.split(' ');
  for (let i = 0; i < 30; i++) x.fillText(Array.from({ length: 7 }, (_, j) => words[(i * 3 + j) % words.length]).join(' '), 60, 80 + i * 48);
  const img = x.getImageData(0, 0, 1080, 1600);
  let t = performance.now();
  const p = await window.electronAPI.ocrRecognize('devicetest-page-' + Date.now(), 1, 'auto', { data: new Uint8Array(img.data.buffer), width: 1080, height: 1600 });
  const auto = Math.round(performance.now() - t);
  t = performance.now();
  const q = await window.electronAPI.ocrRecognize('devicetest-page2-' + Date.now(), 1, 'cyrillic', { data: new Uint8Array(img.data.buffer), width: 1080, height: 1600 });
  return p.script + ', ' + p.lines.length + ' lines; auto-detect ' + auto + ' ms, script known ' + Math.round(performance.now() - t) + ' ms (' + q.lines.length + ' lines); first: ' + p.lines[0]?.text`, 300000));
show('memory', await ev(`return performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1e6) + ' MB JS heap' : 'n/a'`));
ws.close();
