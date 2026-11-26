// Read aloud on Android. The desktop's speech code (desktop/src/lib/speech.ts)
// uses the Web Speech API, which Android's WebView doesn't have. This gives
// it one, backed by the phone's own text-to-speech voices (the same ones
// Google Maps or TalkBack use), so the desktop's speak buttons and voice
// settings work unchanged.

import { TextToSpeech } from '@capacitor-community/text-to-speech';

type Voice = SpeechSynthesisVoice & { index: number };

class Utterance extends EventTarget {
    text: string;
    lang = '';
    rate = 1;
    pitch = 1;
    volume = 1;
    voice: SpeechSynthesisVoice | null = null;
    onstart: ((e: Event) => void) | null = null;
    onend: ((e: Event) => void) | null = null;
    onerror: ((e: Event) => void) | null = null;
    constructor(text = '') {
        super();
        this.text = text;
    }
    fire(type: 'start' | 'end' | 'error') {
        const e = new Event(type);
        this.dispatchEvent(e);
        this[`on${type}`]?.(e);
    }
}

export function installNativeSpeech() {
    let voices: Voice[] = [];
    const target = new EventTarget();
    let speaking = false;
    let onvoiceschanged: ((e: Event) => void) | null = null;

    const load = () =>
        TextToSpeech.getSupportedVoices()
            .then(({ voices: list }) => {
                voices = list.map((v, index) => ({ ...v, lang: v.lang.replace('_', '-'), index }) as Voice);
                const e = new Event('voiceschanged');
                target.dispatchEvent(e);
                onvoiceschanged?.(e);
            })
            .catch(err => console.warn('Could not list the phone voices:', err));
    void load();

    const synth = {
        get speaking() { return speaking; },
        pending: false,
        paused: false,
        getVoices: () => voices,
        speak(u: Utterance) {
            const voice = u.voice as Voice | null;
            speaking = true;
            u.fire('start');
            TextToSpeech.speak({
                text: u.text,
                lang: voice?.lang || u.lang || undefined,
                voice: voice && voices.includes(voice) ? voice.index : undefined,
                // The desktop's 0.9 is a little slower than normal; Android's 1.0 is normal
                rate: Math.max(0.1, Math.min(2, u.rate || 1)),
                pitch: u.pitch || 1,
                volume: u.volume ?? 1,
            })
                .then(() => u.fire('end'), err => {
                    console.warn('Speaking failed:', err);
                    u.fire('error');
                })
                .finally(() => (speaking = false));
        },
        cancel() {
            speaking = false;
            void TextToSpeech.stop().catch(() => { });
        },
        pause() { },
        resume() { },
        addEventListener: target.addEventListener.bind(target),
        removeEventListener: target.removeEventListener.bind(target),
        dispatchEvent: target.dispatchEvent.bind(target),
        get onvoiceschanged() { return onvoiceschanged; },
        set onvoiceschanged(fn) { onvoiceschanged = fn; },
        /** Voices change when the person installs one in Android settings */
        refresh: load,
    };

    Object.defineProperty(window, 'speechSynthesis', { value: synth, configurable: true });
    Object.defineProperty(window, 'SpeechSynthesisUtterance', { value: Utterance, configurable: true });
    document.addEventListener('visibilitychange', () => document.visibilityState === 'visible' && void load());
}
