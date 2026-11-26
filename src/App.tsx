import { useEffect, useState } from 'react';
import { BookOpen, Languages } from 'lucide-react';
import { useTheme } from '@desktop/lib/theme';
import Library from './screens/Library';
import Words from './screens/Words';
import Reader, { type OpenBook } from './screens/Reader';

type Tab = 'library' | 'words';

export default function App() {
    useTheme();
    const [tab, setTab] = useState<Tab>('library');
    const [book, setBook] = useState<OpenBook | null>(null);
    const [notice, setNotice] = useState<string | null>(null);

    // Desktop components send people to Settings for voices and dictionaries;
    // those aren't on the phone yet, so say so instead of doing nothing.
    useEffect(() => {
        let timer: ReturnType<typeof setTimeout>;
        const onOpen = () => {
            setNotice('Offline dictionaries and voices are coming to the phone app soon.');
            clearTimeout(timer);
            timer = setTimeout(() => setNotice(null), 3500);
        };
        window.addEventListener('linguareader:open-settings', onOpen);
        return () => {
            window.removeEventListener('linguareader:open-settings', onOpen);
            clearTimeout(timer);
        };
    }, []);
    const toast = notice && (
        <div className="fixed left-1/2 -translate-x-1/2 bottom-24 z-[200] px-4 py-2.5 rounded-lg text-[13.5px] max-w-[90vw] text-center anim-in" style={{ background: 'var(--text)', color: 'var(--bg)', boxShadow: 'var(--shadow-md)' }} role="status">
            {notice}
        </div>
    );

    // Android back button / gesture closes the book first
    useEffect(() => {
        if (!book) return;
        history.pushState({ reader: true }, '');
        const onPop = () => setBook(null);
        window.addEventListener('popstate', onPop);
        return () => window.removeEventListener('popstate', onPop);
    }, [book]);

    if (book) return <><Reader book={book} onClose={() => history.back()} />{toast}</>;

    return (
        <div className="h-full flex flex-col" style={{ background: 'var(--bg)' }}>
            <main className="flex-1 min-h-0">{tab === 'library' ? <Library onOpen={setBook} /> : <Words />}</main>
            <nav className="tab-bar flex border-t" style={{ background: 'var(--surface)', borderColor: 'var(--border)' }}>
                <button className="tab-btn" aria-current={tab === 'library' ? 'page' : undefined} onClick={() => setTab('library')}>
                    <BookOpen size={20} /> Library
                </button>
                <button className="tab-btn" aria-current={tab === 'words' ? 'page' : undefined} onClick={() => setTab('words')}>
                    <Languages size={20} /> Words
                </button>
            </nav>
            {toast}
        </div>
    );
}
