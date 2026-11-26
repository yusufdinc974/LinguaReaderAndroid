// The phone reader: one page (or EPUB chapter) at a time, fitted to the screen
// width. Tap a word to translate it; a long press selects a phrase.
//
// Pages, highlighting, sentence capture and the word card are the desktop
// app's own components and helpers (desktop/src), so they behave the same.

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ChevronLeft, ChevronRight, Loader2, Minus, Plus, X } from 'lucide-react';
import { destroyDoc, displayName, openReaderDoc, pageSize, type ReaderDoc } from '@desktop/lib/document';
import { createHighlighter } from '@desktop/lib/highlight';
import { cleanSelection, wordKey } from '@desktop/lib/words';
import { selectionContext } from '@desktop/lib/context';
import { translateText, SUPPORTED_LANGUAGES } from '@desktop/services/translationService';
import PageView from '@desktop/components/PageView';
import EpubView from '@desktop/components/EpubView';
import WordCard, { type WordCardState } from '@desktop/components/WordCard';
import type { WordList } from '@desktop/types';
import { selectWordAt } from '../lib/tapWord';

export interface OpenBook {
    name: string;
    path: string;
    data: string;
}

interface Props {
    book: OpenBook;
    onClose: () => void;
}

const SIDE_PAD = 8;

/** Where the word card goes: centred, just above the bottom bar. */
function bottomAnchor() {
    const bar = document.querySelector('.reader-bar')?.getBoundingClientRect();
    const top = bar ? bar.top : window.innerHeight;
    return { left: 0, width: window.innerWidth, top, bottom: window.innerHeight + 1000 };
}

export default function Reader({ book, onClose }: Props) {
    const [doc, setDoc] = useState<ReaderDoc | null>(null);
    const [error, setError] = useState<string | null>(null);
    const [page, setPage] = useState(1);
    const [fit, setFit] = useState(1);
    const [zoom, setZoom] = useState(() => Number(localStorage.getItem('mobileZoom')) || 1);
    const [targetLang, setTargetLang] = useState(() => localStorage.getItem('targetLang') || 'tr');

    const [lists, setLists] = useState<WordList[]>([]);
    const [familiarity, setFamiliarity] = useState<Record<string, number>>({});
    const [wordColors, setWordColors] = useState<Record<string, string>>({});

    const [card, setCard] = useState<WordCardState | null>(null);
    const [level, setLevel] = useState(1);
    const [savedWordId, setSavedWordId] = useState<number | null>(null);

    const scrollRef = useRef<HTMLDivElement>(null);
    const seq = useRef(0);
    const restored = useRef(false);
    const touch = useRef<{ x: number; y: number; t: number } | null>(null);

    useEffect(() => localStorage.setItem('mobileZoom', String(zoom)), [zoom]);
    useEffect(() => localStorage.setItem('targetLang', targetLang), [targetLang]);

    // ---------- data ----------
    const loadLists = useCallback(async () => setLists(await window.electronAPI.getWordLists()), []);
    const loadFamiliarity = useCallback(async () => {
        const map: Record<string, number> = {};
        for (const f of await window.electronAPI.getAllWordFamiliarity()) map[f.word_lower] = f.familiarity_level;
        setFamiliarity(map);
    }, []);
    const loadColors = useCallback(async () => {
        const map: Record<string, string> = {};
        for (const r of await window.electronAPI.getWordColors()) map[r.word_lower] ??= r.color;
        setWordColors(map);
    }, []);

    useEffect(() => {
        loadLists();
        loadFamiliarity();
        loadColors();
    }, [loadLists, loadFamiliarity, loadColors]);

    const highlighter = useMemo(() => createHighlighter(wordColors), [wordColors]);

    // ---------- document ----------
    useEffect(() => {
        let alive = true;
        let opened: ReaderDoc | null = null;
        restored.current = false;
        (async () => {
            try {
                const [next, progress] = await Promise.all([openReaderDoc(book), window.electronAPI.getPdfProgress(book.path).catch(() => null)]);
                if (!alive) return destroyDoc(next);
                opened = next;
                await window.electronAPI.addRecentPdf(book.name, book.path);
                const last = progress?.last_page ?? 1;
                setPage(Math.min(Math.max(1, last), next.numPages));
                setDoc(next);
                restored.current = true;
            } catch (e) {
                console.error('Opening the book failed:', e);
                if (alive) setError("This file couldn't be opened.");
            }
        })();
        return () => {
            alive = false;
            destroyDoc(opened);
        };
    }, [book]);

    // Save the reading position
    useEffect(() => {
        if (!doc || !restored.current) return;
        const t = setTimeout(() => window.electronAPI.setPdfProgress(book.path, page, doc.numPages).catch(() => { }), 300);
        return () => clearTimeout(t);
    }, [doc, page, book.path]);

    // Fit the page to the screen width
    useEffect(() => {
        if (!doc || doc.kind === 'epub') return;
        let alive = true;
        const measure = async () => {
            const el = scrollRef.current;
            if (!el) return;
            const s = await pageSize(doc, page);
            if (alive) setFit(Math.max(0.2, (el.clientWidth - SIDE_PAD * 2) / s.width));
        };
        measure();
        window.addEventListener('resize', measure);
        return () => {
            alive = false;
            window.removeEventListener('resize', measure);
        };
    }, [doc, page]);

    const goTo = useCallback((n: number) => {
        if (!doc) return;
        const p = Math.min(Math.max(1, n), doc.numPages);
        if (p === page) return;
        setCard(null);
        window.getSelection()?.removeAllRanges();
        setPage(p);
        scrollRef.current?.scrollTo({ top: 0 });
    }, [doc, page]);

    // ---------- selection → translation (as desktop Reader's onMouseUp) ----------
    const showCard = useCallback(async (range: Range) => {
        const text = cleanSelection(range.toString());
        if (!text) return;
        const context = selectionContext(range);
        const n = ++seq.current;
        const key = wordKey(text);
        setLevel(familiarity[key] ?? 1);
        setCard({ text, translation: '', loading: true, failed: false, context, anchor: bottomAnchor() });
        const [existing, result] = await Promise.allSettled([window.electronAPI.getWordByLower(key), translateText(text, targetLang)]);
        if (n !== seq.current) return;
        setSavedWordId(existing.status === 'fulfilled' ? existing.value?.id ?? null : null);
        setCard(c => c && (result.status === 'fulfilled'
            ? { ...c, loading: false, translation: result.value.translatedText, source: result.value.source, detectedLanguage: result.value.detectedLanguage }
            : { ...c, loading: false, failed: true }));
    }, [familiarity, targetLang]);

    const onTouchStart = (e: React.TouchEvent) => {
        const t = e.touches[0];
        touch.current = e.touches.length === 1 ? { x: t.clientX, y: t.clientY, t: Date.now() } : null;
    };

    const onTouchEnd = (e: React.TouchEvent) => {
        const start = touch.current;
        touch.current = null;
        if (!start) return;
        const t = e.changedTouches[0];
        const dx = t.clientX - start.x;
        const dy = t.clientY - start.y;
        const dt = Date.now() - start.t;
        // Swipe sideways: turn the page (only when the page isn't zoomed in to scroll sideways)
        const el = scrollRef.current;
        const canScrollX = el ? el.scrollWidth > el.clientWidth + 2 : false;
        if (!canScrollX && Math.abs(dx) > 70 && Math.abs(dx) > Math.abs(dy) * 1.5 && dt < 600) {
            goTo(page + (dx < 0 ? 1 : -1));
            return;
        }
        // A tap (not a long press, which makes its own selection)
        if (Math.abs(dx) < 10 && Math.abs(dy) < 10 && dt < 350) {
            // Buttons and links in the book (EPUB "Next chapter", footnotes) keep working
            if ((e.target as Element).closest('button, a')) return;
            const root = (e.target as Element).closest('.pdf-text-layer, .epub-chapter');
            if (!root) {
                setCard(null);
                window.getSelection()?.removeAllRanges();
                return;
            }
            const range = selectWordAt(t.clientX, t.clientY, root, doc?.kind === 'epub' ? doc.book.language : undefined);
            if (range) {
                e.preventDefault();
                showCard(range);
            } else {
                setCard(null);
            }
        }
    };

    // Long press → the phone's own selection handles; translate once it settles
    useEffect(() => {
        let timer: ReturnType<typeof setTimeout> | null = null;
        const onChange = () => {
            if (timer) clearTimeout(timer);
            timer = setTimeout(() => {
                const sel = window.getSelection();
                if (!sel || sel.rangeCount === 0 || sel.isCollapsed) return;
                const range = sel.getRangeAt(0);
                if (!scrollRef.current?.contains(range.commonAncestorContainer)) return;
                const text = cleanSelection(sel.toString());
                if (text && text !== card?.text) showCard(range);
            }, 450);
        };
        document.addEventListener('selectionchange', onChange);
        return () => {
            document.removeEventListener('selectionchange', onChange);
            if (timer) clearTimeout(timer);
        };
    }, [showCard, card?.text]);

    // ---------- saving (as desktop Reader) ----------
    const saveToList = async (listId: number) => {
        if (!card || card.loading || !card.translation) return;
        const key = wordKey(card.text);
        const source = card.detectedLanguage || (doc?.kind === 'epub' && doc.book.language) || 'auto';
        const wordId = await window.electronAPI.addWord(card.text, card.translation, source, targetLang, card.context ?? '', book.name);
        await window.electronAPI.addWordToList(wordId, listId);
        await window.electronAPI.setWordFamiliarity(key, level, card.translation);
        setFamiliarity(prev => ({ ...prev, [key]: level }));
        setSavedWordId(wordId);
        await loadColors();
        setCard(null);
        window.getSelection()?.removeAllRanges();
    };

    const createListAndSave = async (name: string) => {
        const id = await window.electronAPI.createWordList(name, '');
        await loadLists();
        await saveToList(id);
    };

    const removeWord = async () => {
        if (!savedWordId || !card) return;
        await window.electronAPI.deleteWord(savedWordId);
        const key = wordKey(card.text);
        setFamiliarity(prev => {
            const next = { ...prev };
            delete next[key];
            return next;
        });
        setSavedWordId(null);
        await loadColors();
        setCard(null);
    };

    const onLevel = async (l: number) => {
        setLevel(l);
        // A saved word's level changes right away, as on desktop
        if (card && savedWordId) {
            await window.electronAPI.setWordFamiliarity(wordKey(card.text), l, card.translation);
            setFamiliarity(prev => ({ ...prev, [wordKey(card.text)]: l }));
        }
    };

    const scale = fit * zoom;
    const title = displayName(book.name);

    return (
        <div className="fixed inset-0 flex flex-col" style={{ background: 'var(--reader-bg)' }}>
            <header className="reader-top flex items-center gap-1 px-2 border-b" style={{ background: 'var(--surface)', borderColor: 'var(--border)' }}>
                <button className="icon-btn tap" onClick={onClose} aria-label="Back to library">
                    <X size={20} />
                </button>
                <p className="flex-1 min-w-0 truncate text-[15px] font-medium">{title}</p>
                <select
                    className="field h-9 w-auto text-[13px] px-2"
                    value={targetLang}
                    onChange={e => setTargetLang(e.target.value)}
                    aria-label="Translate into"
                >
                    {SUPPORTED_LANGUAGES.map(l => (
                        <option key={l.code} value={l.code}>→ {l.name}</option>
                    ))}
                </select>
            </header>

            <div
                ref={scrollRef}
                className="flex-1 overflow-auto overscroll-contain"
                onTouchStart={onTouchStart}
                onTouchEnd={onTouchEnd}
                onContextMenu={e => e.preventDefault()}
            >
                {error ? (
                    <div className="h-full flex items-center justify-center px-8 text-center">
                        <p className="text-[15px]">{error}</p>
                    </div>
                ) : !doc ? (
                    <div className="h-full flex items-center justify-center gap-2 muted">
                        <Loader2 size={18} className="animate-spin" /> Opening…
                    </div>
                ) : doc.kind === 'epub' ? (
                    <div className="px-4 py-5" style={{ background: 'var(--surface)', minHeight: '100%' }}>
                        <EpubView doc={doc} chapter={page} scale={zoom * 1.35} highlighter={highlighter} onNavigate={c => goTo(c)} />
                    </div>
                ) : (
                    <div className="w-max min-w-full flex justify-center" style={{ padding: SIDE_PAD }}>
                        <PageView key={`${doc.hash}-${page}`} doc={doc} pageNum={page} scale={scale} highlighter={highlighter} ocrMode="off" ocrVersion={0} />
                    </div>
                )}
            </div>

            <footer className="reader-bar flex items-center gap-1 px-2 border-t" style={{ background: 'var(--surface)', borderColor: 'var(--border)' }}>
                <button className="icon-btn tap" onClick={() => setZoom(z => Math.max(0.6, Math.round((z - 0.15) * 100) / 100))} aria-label="Smaller">
                    <Minus size={18} />
                </button>
                <button className="icon-btn tap" onClick={() => setZoom(z => Math.min(3, Math.round((z + 0.15) * 100) / 100))} aria-label="Bigger">
                    <Plus size={18} />
                </button>
                <div className="flex-1 text-center text-[13px] muted tabular-nums">
                    {doc ? `${doc.kind === 'epub' ? 'Chapter' : 'Page'} ${page} of ${doc.numPages}` : ''}
                </div>
                <button className="icon-btn tap" onClick={() => goTo(page - 1)} disabled={!doc || page <= 1} aria-label="Previous page">
                    <ChevronLeft size={20} />
                </button>
                <button className="icon-btn tap" onClick={() => goTo(page + 1)} disabled={!doc || page >= (doc?.numPages ?? 1)} aria-label="Next page">
                    <ChevronRight size={20} />
                </button>
            </footer>

            {card && (
                <WordCard
                    card={card}
                    level={level}
                    onLevel={onLevel}
                    lists={lists}
                    saved={savedWordId !== null}
                    onSave={saveToList}
                    onCreateList={createListAndSave}
                    onRemove={removeWord}
                    onClose={() => {
                        setCard(null);
                        window.getSelection()?.removeAllRanges();
                    }}
                    bookLang={doc?.kind === 'epub' ? doc.book.language : undefined}
                />
            )}
        </div>
    );
}
