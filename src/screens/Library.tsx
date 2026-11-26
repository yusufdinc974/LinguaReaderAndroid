import { useEffect, useState } from 'react';
import { BookOpen, FolderOpen } from 'lucide-react';
import { displayName, getThumbnail } from '@desktop/lib/document';
import Logo from '@desktop/components/Logo';
import type { OpenBook } from './Reader';

function Thumb({ path }: { path: string }) {
    const [url, setUrl] = useState<string | null | undefined>(undefined);
    useEffect(() => {
        let alive = true;
        getThumbnail(path, 120).then(u => alive && setUrl(u));
        return () => {
            alive = false;
        };
    }, [path]);
    return (
        <div className="w-[60px] h-[84px] shrink-0 rounded-[4px] overflow-hidden flex items-center justify-center" style={{ background: 'var(--surface-2)', boxShadow: 'var(--shadow-sm)' }}>
            {url ? <img src={url} alt="" className="w-full h-full object-cover" /> : <BookOpen size={20} className="faint" />}
        </div>
    );
}

export default function Library({ onOpen }: { onOpen: (book: OpenBook) => void }) {
    const [recent, setRecent] = useState<RecentPdf[] | null>(null);
    const [busy, setBusy] = useState(false);
    const [error, setError] = useState<string | null>(null);

    useEffect(() => {
        window.electronAPI.getRecentPdfs().then(setRecent).catch(() => setRecent([]));
    }, []);

    const pick = async () => {
        setBusy(true);
        setError(null);
        try {
            const file = await window.electronAPI.openPdfDialog();
            if (file) onOpen(file);
        } catch (e) {
            console.error(e);
            setError("That file couldn't be opened.");
        } finally {
            setBusy(false);
        }
    };

    const reopen = async (path: string) => {
        const file = await window.electronAPI.openPdfByPath(path);
        if (file) onOpen(file);
        else setError('That book is no longer on this phone. Open it again.');
    };

    return (
        <div className="h-full overflow-auto">
            <div className="px-5 pt-6 pb-4 flex items-center gap-2.5">
                <Logo size={28} />
                <h1 className="text-[20px] font-semibold">LinguaReader</h1>
            </div>

            <div className="px-5">
                <button className="btn btn-primary w-full h-12 text-[15px]" onClick={pick} disabled={busy}>
                    <FolderOpen size={18} /> Open a book
                </button>
                <p className="text-[12.5px] faint mt-2 text-center">PDF, EPUB, CBZ comics or images</p>
                {error && <p className="text-[13px] mt-3 text-center" style={{ color: 'var(--danger)' }}>{error}</p>}
            </div>

            <h2 className="label px-5 mt-7 mb-2">Recent</h2>
            {recent && recent.length === 0 && <p className="px-5 text-[14px] muted">Books you open show up here.</p>}
            <ul className="px-3 pb-6">
                {recent?.map(b => (
                    <li key={b.path}>
                        <button className="w-full flex items-center gap-3 p-2 rounded-lg text-left active:bg-[var(--surface-2)]" onClick={() => reopen(b.path)}>
                            <Thumb path={b.path} />
                            <div className="min-w-0 flex-1">
                                <p className="text-[15px] font-medium leading-snug line-clamp-2">{displayName(b.name)}</p>
                                {b.page_count ? (
                                    <p className="text-[12.5px] muted mt-1">
                                        {Math.round(((b.last_page ?? 1) / b.page_count) * 100)}% · page {b.last_page ?? 1} of {b.page_count}
                                    </p>
                                ) : null}
                            </div>
                        </button>
                    </li>
                ))}
            </ul>
        </div>
    );
}
