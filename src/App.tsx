import { useEffect, useState } from 'react';
import { BookOpen, GraduationCap, Languages } from 'lucide-react';
import { useTheme } from '@desktop/lib/theme';
import { useBack } from './lib/back';
import Library from './screens/Library';
import Words from './screens/Words';
import ReviewTab from './screens/ReviewTab';
import Settings from './screens/Settings';
import Reader, { type OpenBook } from './screens/Reader';
import ImportExport from './components/ImportExport';
import ReviewHost from './screens/ReviewHost';

type Tab = 'library' | 'words' | 'review';

export default function App() {
    const { theme, setTheme } = useTheme();
    const [tab, setTab] = useState<Tab>('library');
    const [book, setBook] = useState<OpenBook | null>(null);
    /** Settings is open (at this section) */
    const [settings, setSettings] = useState<string | null>(null);
    const [io, setIo] = useState(false);
    const [review, setReview] = useState<{ total: number; due: number } | null>(null);
    const [notice, setNotice] = useState<string | null>(null);

    const flash = (msg: string) => {
        setNotice(msg);
        setTimeout(() => setNotice(n => (n === msg ? null : n)), 3500);
    };

    // Desktop components ask for Settings (no voice for a language, no dictionary yet)
    useEffect(() => {
        const onOpen = (e: Event) => setSettings(String((e as CustomEvent).detail ?? '') || 'top');
        window.addEventListener('linguareader:open-settings', onOpen);
        return () => window.removeEventListener('linguareader:open-settings', onOpen);
    }, []);

    // Back on another tab returns to the Library first
    useBack(() => setTab('library'), tab !== 'library' && !book && !settings);

    const toast = notice && (
        <div className="fixed left-1/2 -translate-x-1/2 bottom-24 z-[200] px-4 py-2.5 rounded-lg text-[13.5px] max-w-[90vw] text-center anim-in" style={{ background: 'var(--text)', color: 'var(--bg)', boxShadow: 'var(--shadow-md)' }} role="status">
            {notice}
        </div>
    );
    const overlays = (
        <>
            {settings && (
                <Settings
                    theme={theme}
                    onThemeChange={setTheme}
                    section={settings === 'top' ? undefined : settings}
                    onClose={() => setSettings(null)}
                    onImportExport={() => setIo(true)}
                />
            )}
            {review && <ReviewHost listId={null} listName="" total={review.total} due={review.due} onExit={() => setReview(null)} />}
            {io && <ImportExport selectedId={null} onClose={() => setIo(false)} onDone={msg => { setIo(false); flash(msg); }} />}
            {toast}
        </>
    );

    if (book) return <><Reader book={book} onClose={() => setBook(null)} />{overlays}</>;

    return (
        <div className="h-full flex flex-col" style={{ background: 'var(--bg)' }}>
            <main className="flex-1 min-h-0">
                {tab === 'library' ? <Library
                    onOpen={setBook}
                    onSettings={() => setSettings('top')}
                    onReview={async () => {
                        const s = await window.electronAPI.getReviewSchedule();
                        setReview({ total: s.totalWords, due: s.overdue + s.dueToday });
                    }}
                /> : tab === 'words' ? <Words /> : <ReviewTab />}
            </main>
            <nav className="tab-bar flex border-t" style={{ background: 'var(--surface)', borderColor: 'var(--border)' }}>
                <button className="tab-btn" aria-current={tab === 'library' ? 'page' : undefined} onClick={() => setTab('library')}>
                    <BookOpen size={20} /> Library
                </button>
                <button className="tab-btn" aria-current={tab === 'words' ? 'page' : undefined} onClick={() => setTab('words')}>
                    <Languages size={20} /> Words
                </button>
                <button className="tab-btn" aria-current={tab === 'review' ? 'page' : undefined} onClick={() => setTab('review')}>
                    <GraduationCap size={20} /> Review
                </button>
            </nav>
            {overlays}
        </div>
    );
}
