// Library: open a book, continue the last one, recent books (desktop/src/pages/Library.tsx on a phone).

import { useEffect, useState } from 'react';
import { ArrowRight, BookOpen, FolderOpen, MoreVertical, Settings as SettingsIcon, Trash2 } from 'lucide-react';
import { displayName, getThumbnail } from '@desktop/lib/document';
import Logo from '@desktop/components/Logo';
import { ConfirmDialog } from '@desktop/components/Dialog';
import Sheet, { SheetItem } from '../components/Sheet';
import { removeBook } from '../platform/books';
import { useDataVersion } from '../lib/dataVersion';
import type { OpenBook } from './Reader';

function Thumb({ path, w = 60 }: { path: string; w?: number }) {
    const [url, setUrl] = useState<string | null | undefined>(undefined);
    useEffect(() => {
        let alive = true;
        getThumbnail(path, 160).then(u => alive && setUrl(u));
        return () => {
            alive = false;
        };
    }, [path]);
    return (
        <div className="shrink-0 rounded-[4px] overflow-hidden flex items-center justify-center" style={{ width: w, height: Math.round(w * 1.4), background: 'var(--surface-2)', boxShadow: 'var(--shadow-sm)' }}>
            {url ? <img src={url} alt="" className="w-full h-full object-cover" /> : <BookOpen size={20} className="faint" />}
        </div>
    );
}

function relativeDate(iso: string) {
    // SQLite's CURRENT_TIMESTAMP is UTC without a zone
    const d = new Date(/Z|[+-]\d\d:?\d\d$/.test(iso) ? iso : `${iso.replace(' ', 'T')}Z`);
    const days = Math.floor((Date.now() - d.getTime()) / 86400000);
    if (days <= 0) return 'Today';
    if (days === 1) return 'Yesterday';
    if (days < 7) return `${days} days ago`;
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: days > 300 ? 'numeric' : undefined });
}

function progressLabel(b: { name?: string; last_page?: number | null; page_count?: number | null }) {
    if (!b.page_count) return null;
    const unit = /\.epub$/i.test(b.name ?? '') ? 'Chapter' : 'Page';
    return `${unit} ${b.last_page ?? 1} of ${b.page_count}`;
}

const pct = (b: RecentPdf) => (b.page_count ? Math.round(((b.last_page ?? 1) / b.page_count) * 100) : 0);

interface Props {
    onOpen: (book: OpenBook) => void;
    onSettings: () => void;
    onReview: () => void;
}

export default function Library({ onOpen, onSettings, onReview }: Props) {
    const version = useDataVersion();
    const [recent, setRecent] = useState<RecentPdf[] | null>(null);
    const [wordTotal, setWordTotal] = useState<number | null>(null);
    const [due, setDue] = useState(0);
    const [busy, setBusy] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [menu, setMenu] = useState<RecentPdf | null>(null);
    const [confirm, setConfirm] = useState<RecentPdf | null>(null);

    const load = () => {
        window.electronAPI.getRecentPdfs().then(setRecent).catch(() => setRecent([]));
        window.electronAPI.getStats().then(s => setWordTotal(s.totalWords)).catch(() => { });
        window.electronAPI.getReviewSchedule().then(s => setDue(s.overdue + s.dueToday)).catch(() => { });
    };
    useEffect(load, [version]);

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

    const reopen = async (b: RecentPdf) => {
        setError(null);
        const file = await window.electronAPI.openPdfByPath(b.path);
        if (file) onOpen(file);
        else setError(`“${displayName(b.name)}” is no longer on this phone. Open it again.`);
    };

    const [latest, ...rest] = recent ?? [];

    return (
        <div className="h-full overflow-auto">
            <div className="pl-5 pr-2 pt-4 pb-3 flex items-center gap-2.5">
                <Logo size={28} />
                <div className="flex-1 min-w-0">
                    <h1 className="text-[20px] font-semibold leading-tight">LinguaReader</h1>
                    <p className="text-[12.5px] muted">
                        {wordTotal === null ? ' ' : wordTotal === 0 ? 'Tap any word while reading to translate it.' : `${wordTotal} saved ${wordTotal === 1 ? 'word' : 'words'}`}
                    </p>
                </div>
                <button className="icon-btn tap" onClick={onSettings} aria-label="Settings"><SettingsIcon size={20} /></button>
            </div>

            <div className="px-5">
                <button className="btn btn-primary w-full h-12 text-[15px]" onClick={pick} disabled={busy}>
                    <FolderOpen size={18} /> Open a book
                </button>
                <p className="text-[12.5px] faint mt-2 text-center">PDF, EPUB, CBZ comics or images</p>
                {error && <p className="text-[13px] mt-3 text-center" style={{ color: 'var(--danger)' }} role="alert">{error}</p>}
            </div>

            {due > 0 && (
                <button
                    onClick={onReview}
                    className="mx-5 mt-5 w-[calc(100%-40px)] flex items-center justify-between gap-3 px-4 h-12 rounded-lg border text-left active:bg-[var(--surface-2)]"
                    style={{ borderColor: 'var(--border)', background: 'var(--surface)' }}
                >
                    <span className="flex items-center gap-3 text-[14px]">
                        <span className="dot" style={{ background: 'var(--accent)' }} />
                        <span><strong className="font-semibold">{due}</strong> {due === 1 ? 'word is' : 'words are'} due</span>
                    </span>
                    <span className="flex items-center gap-1 text-[13.5px] font-medium" style={{ color: 'var(--accent)' }}>Review <ArrowRight size={15} /></span>
                </button>
            )}

            {recent && recent.length === 0 && (
                <p className="px-5 mt-8 text-[14px] muted text-center">Open a book, PDF or comic in the language you're learning. Tap a word to see its translation and save it to a list.</p>
            )}

            {latest && (
                <>
                    <h2 className="label px-5 mt-7 mb-2">Continue reading</h2>
                    <div className="mx-3 flex items-center rounded-xl border active:bg-[var(--surface-2)]" style={{ borderColor: 'var(--border)', background: 'var(--surface)' }}>
                        <button className="flex-1 min-w-0 flex items-center gap-4 p-3 text-left" onClick={() => reopen(latest)}>
                            <Thumb path={latest.path} w={64} />
                            <div className="min-w-0 flex-1">
                                <p className="serif text-[17px] font-semibold leading-snug line-clamp-2">{displayName(latest.name)}</p>
                                <p className="text-[12.5px] faint mt-1">{progressLabel(latest) ? `${progressLabel(latest)} · ` : ''}{relativeDate(latest.last_opened)}</p>
                                {latest.page_count ? (
                                    <div className="h-1 w-full max-w-[200px] rounded-full mt-2.5 overflow-hidden" style={{ background: 'var(--surface-3)' }}>
                                        <div className="h-full rounded-full" style={{ width: `${pct(latest)}%`, background: 'var(--accent)' }} />
                                    </div>
                                ) : null}
                            </div>
                        </button>
                        <button className="icon-btn tap shrink-0" onClick={() => setMenu(latest)} aria-label={`Options for ${displayName(latest.name)}`}><MoreVertical size={17} /></button>
                    </div>
                </>
            )}

            {rest.length > 0 && <h2 className="label px-5 mt-7 mb-2">Recent</h2>}
            <ul className="px-3 pb-6">
                {rest.map(b => (
                    <li key={b.path} className="flex items-center">
                        <button className="flex-1 min-w-0 flex items-center gap-3 p-2 rounded-lg text-left active:bg-[var(--surface-2)]" onClick={() => reopen(b)}>
                            <Thumb path={b.path} />
                            <div className="min-w-0 flex-1">
                                <p className="text-[15px] font-medium leading-snug line-clamp-2">{displayName(b.name)}</p>
                                <p className="text-[12.5px] muted mt-1">{progressLabel(b) ? `${pct(b)}% · ${progressLabel(b)}` : relativeDate(b.last_opened)}</p>
                            </div>
                        </button>
                        <button className="icon-btn tap shrink-0" onClick={() => setMenu(b)} aria-label={`Options for ${displayName(b.name)}`}><MoreVertical size={17} /></button>
                    </li>
                ))}
            </ul>

            {menu && (
                <Sheet title={displayName(menu.name)} onClose={() => setMenu(null)}>
                    <SheetItem icon={<BookOpen size={18} />} onClick={() => { const b = menu; setMenu(null); reopen(b); }}>Open</SheetItem>
                    <SheetItem icon={<Trash2 size={18} />} danger onClick={() => { setConfirm(menu); setMenu(null); }}>Remove from this phone</SheetItem>
                </Sheet>
            )}
            {confirm && (
                <ConfirmDialog
                    title={`Remove “${displayName(confirm.name)}”?`}
                    message="The book's copy on this phone is deleted. Words you saved from it stay in your lists."
                    confirmLabel="Remove"
                    onConfirm={async () => { await removeBook(confirm.path); load(); }}
                    onClose={() => setConfirm(null)}
                />
            )}
        </div>
    );
}
