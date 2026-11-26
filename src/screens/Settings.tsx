// Settings: the phone version of desktop/src/components/SettingsPanel.tsx.
// Pronunciation and dictionaries are the desktop's own settings components.

import { useEffect, useState, type ReactNode } from 'react';
import { AlertCircle, Check, ChevronLeft } from 'lucide-react';
import type { Theme } from '@desktop/lib/theme';
import { getOcrMode, setOcrMode, type OcrMode } from '@desktop/lib/ocr';
import PronunciationSettings from '@desktop/components/PronunciationSettings';
import DictionarySettings from '@desktop/components/DictionarySettings';
import { useBack } from '../lib/back';
import SyncSettings from './SyncSettings';

function Section({ id, title, description, children }: { id?: string; title: string; description?: string; children: ReactNode }) {
    return (
        <section id={id} className="px-5 py-5 border-b" style={{ borderColor: 'var(--border)' }}>
            <h2 className="text-[15px] font-semibold">{title}</h2>
            {description && <p className="text-[13px] faint mt-0.5 leading-snug">{description}</p>}
            <div className="mt-3">{children}</div>
        </section>
    );
}

interface Props {
    theme: Theme;
    onThemeChange: (t: Theme) => void;
    onClose: () => void;
    onImportExport: () => void;
    /** Scroll to this section when opening ("pronunciation" from a word card) */
    section?: string;
}

export default function Settings({ theme, onThemeChange, onClose, onImportExport, section }: Props) {
    const [apiKey, setApiKey] = useState('');
    const [keyStatus, setKeyStatus] = useState<{ saved: boolean; hint: string }>({ saved: false, hint: '' });
    const [notice, setNotice] = useState<{ type: 'ok' | 'error'; text: string } | null>(null);
    const [busy, setBusy] = useState(false);
    const [version, setVersion] = useState('');
    const [ocr, setOcr] = useState<OcrMode>(getOcrMode);

    useBack(onClose);

    useEffect(() => {
        window.electronAPI.getDeeplKeyStatus().then(setKeyStatus);
        window.electronAPI.getAppVersion().then(setVersion);
    }, []);

    useEffect(() => {
        if (section) document.getElementById(`settings-${section}`)?.scrollIntoView({ block: 'start' });
    }, [section]);

    const flash = (n: { type: 'ok' | 'error'; text: string }) => {
        setNotice(n);
        if (n.type === 'ok') setTimeout(() => setNotice(null), 3500);
    };

    const saveKey = async (key: string) => {
        setBusy(true);
        try {
            if (!(await window.electronAPI.setDeeplKey(key))) throw new Error('rejected');
            setApiKey('');
            setKeyStatus(await window.electronAPI.getDeeplKeyStatus());
            flash({ type: 'ok', text: key ? 'DeepL key saved.' : 'DeepL key removed.' });
        } catch {
            flash({ type: 'error', text: key ? "Could not save the key. Check that it's a DeepL API key." : 'Could not remove the key.' });
        } finally {
            setBusy(false);
        }
    };

    const chooseOcr = (m: OcrMode) => {
        setOcrMode(m);
        setOcr(m);
    };

    return (
        <div className="fixed inset-0 z-[150] flex flex-col" style={{ background: 'var(--bg)' }}>
            <header className="reader-top flex items-center gap-1 px-1 border-b shrink-0" style={{ background: 'var(--surface)', borderColor: 'var(--border)' }}>
                <button className="icon-btn tap" onClick={onClose} aria-label="Back"><ChevronLeft size={20} /></button>
                <h1 className="text-[17px] font-semibold">Settings</h1>
            </header>

            <div className="flex-1 overflow-auto pb-8">
                {notice && (
                    <div className="mx-5 mt-4 flex items-start gap-2 text-[13.5px] px-3 py-2 rounded-md" style={{ background: notice.type === 'ok' ? 'var(--accent-soft)' : 'var(--danger-soft)', color: notice.type === 'ok' ? 'var(--accent)' : 'var(--danger)' }} role="status">
                        {notice.type === 'ok' ? <Check size={15} className="mt-0.5 shrink-0" /> : <AlertCircle size={15} className="mt-0.5 shrink-0" />}
                        <span>{notice.text}</span>
                    </div>
                )}

                <Section title="Appearance">
                    <div className="segmented">
                        <button data-active={theme === 'light'} onClick={() => onThemeChange('light')}>Light</button>
                        <button data-active={theme === 'dark'} onClick={() => onThemeChange('dark')}>Dark</button>
                    </div>
                </Section>

                <Section title="Translation" description="Without a key, the free MyMemory service is used.">
                    <label className="label block mb-1.5" htmlFor="deepl-key">DeepL API key</label>
                    <input
                        id="deepl-key"
                        type="password"
                        className="field"
                        placeholder={keyStatus.saved ? `Saved key ending in ${keyStatus.hint}` : 'Optional'}
                        value={apiKey}
                        autoComplete="off"
                        spellCheck={false}
                        onChange={e => setApiKey(e.target.value)}
                    />
                    <div className="flex gap-2 mt-2">
                        <button className="btn btn-outline h-10" onClick={() => saveKey(apiKey.trim())} disabled={busy || !apiKey.trim()}>
                            {keyStatus.saved ? 'Replace' : 'Save'}
                        </button>
                        {keyStatus.saved && <button className="btn btn-ghost h-10" onClick={() => saveKey('')} disabled={busy}>Remove</button>}
                    </div>
                    <p className="text-[12.5px] faint mt-1.5">Stays on this phone. Never included in backups or sync.</p>
                </Section>

                <Section id="settings-pronunciation" title="Pronunciation" description="Read words aloud with your phone's voices.">
                    <PronunciationSettings />
                </Section>

                <Section id="settings-dictionaries" title="Dictionaries" description="Definitions, examples and synonyms on the word card, offline.">
                    <DictionarySettings />
                </Section>

                <Section title="Text in images" description="Tap words in scanned PDFs, photos and comics.">
                    <div className="grid gap-1">
                        {([['auto', 'Scanned pages and images'], ['always', 'Every page'], ['off', 'Off']] as [OcrMode, string][]).map(([m, label]) => (
                            <label key={m} className="flex items-center gap-3 h-11 text-[15px]">
                                <input type="radio" name="ocr" checked={ocr === m} onChange={() => chooseOcr(m)} style={{ accentColor: 'var(--accent)', width: 18, height: 18 }} />
                                {label}
                            </label>
                        ))}
                    </div>
                    <p className="text-[12.5px] faint mt-1">Reads Latin-alphabet languages (English, Turkish, French, German, Spanish…).</p>
                </Section>

                <Section title="Import and export" description="Backups, Anki decks and CSV files.">
                    <button className="btn btn-outline h-10" onClick={onImportExport}>Open Import / Export</button>
                </Section>

                <Section id="settings-sync" title="Sync with desktop" description="Both devices need to be on the same Wi-Fi.">
                    <SyncSettings />
                </Section>

                <Section title="About">
                    <p className="text-[14px] muted">LinguaReader {version && `v${version}`}</p>
                </Section>
            </div>
        </div>
    );
}
