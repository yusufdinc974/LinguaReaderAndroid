// The phone reader. Pages scroll vertically, like other phone PDF readers;
// pinch with two fingers to zoom; tap a word to translate it, or long-press
// to select a phrase.
//
// Pages, highlighting, sentence capture and the word card are the desktop
// app's own components and helpers (desktop/src), so they behave the same.
//
// Only the pages near the screen are drawn (a few above and below); the rest
// are empty slots of the right size, so long books open fast and scroll smoothly.

import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { ChevronLeft, ChevronRight, Loader2, X } from 'lucide-react';
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
import { useBack } from '../lib/back';

export interface OpenBook {
    name: string;
    path: string;
    data: string;
}

interface Props {
    book: OpenBook;
    onClose: () => void;
}

/** Space around and between pages, in screen pixels. */
const PAD = 8;
const GAP = 8;
/** Pages drawn on each side of the one on screen. */
const AHEAD = 2;
const ZOOM_MIN = 1;
const ZOOM_MAX = 4;
/** EPUB text size at zoom 1 (the desktop's 13px × this). */
const EPUB_SCALE = 1.35;

/** Where the word card goes: centred, just above the bottom bar. */
function bottomAnchor() {
    const bar = document.querySelector('.reader-bar')?.getBoundingClientRect();
    const top = bar ? bar.top : window.innerHeight;
    return { left: 0, width: window.innerWidth, top, bottom: window.innerHeight + 1000 };
}

const dist = (a: Touch, b: Touch) => Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY);

export default function Reader({ book, onClose }: Props) {
    const [doc, setDoc] = useState<ReaderDoc | null>(null);
    const [error, setError] = useState<string | null>(null);
    const [page, setPage] = useState(1);
    /** Size of page 1 at scale 1: every PDF page gets a slot this shape. */
    const [base, setBase] = useState<{ width: number; height: number } | null>(null);
    const [viewW, setViewW] = useState(0);
    const [zoom, setZoom] = useState(1);
    const [epubZoom, setEpubZoom] = useState(() => Number(localStorage.getItem('epubZoom')) || 1);
    const [targetLang, setTargetLang] = useState(() => localStorage.getItem('targetLang') || 'tr');

    const [lists, setLists] = useState<WordList[]>([]);
    const [familiarity, setFamiliarity] = useState<Record<string, number>>({});
    const [wordColors, setWordColors] = useState<Record<string, string>>({});

    const [card, setCard] = useState<WordCardState | null>(null);
    const [level, setLevel] = useState(1);
    const [savedWordId, setSavedWordId] = useState<number | null>(null);

    const scrollRef = useRef<HTMLDivElement>(null);
    const contentRef = useRef<HTMLDivElement>(null);
    const seq = useRef(0);
    const restored = useRef(false);
    const startPage = useRef(1);
    const touch = useRef<{ x: number; y: number; t: number } | null>(null);
    /** Scroll position to apply right after a zoom change is drawn. */
    const pendingScroll = useRef<{ left: number; top: number } | null>(null);
    const pinching = useRef(false);

    useEffect(() => localStorage.setItem('epubZoom', String(epubZoom)), [epubZoom]);
    useEffect(() => localStorage.setItem('targetLang', targetLang), [targetLang]);

    const closeCard = useCallback(() => {
        setCard(null);
        window.getSelection()?.removeAllRanges();
    }, []);

    // Back: closes the word card first, then the book
    useBack(onClose);
    useBack(closeCard, card !== null);

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
                if (next.kind === 'pdf') setBase(await pageSize(next, 1));
                const last = Math.min(Math.max(1, progress?.last_page ?? 1), next.numPages);
                startPage.current = last;
                setPage(last);
                setDoc(next);
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

    // Screen width (changes when the phone turns)
    useLayoutEffect(() => {
        const el = scrollRef.current;
        if (!el) return;
        const ro = new ResizeObserver(() => setViewW(el.clientWidth));
        ro.observe(el);
        setViewW(el.clientWidth);
        return () => ro.disconnect();
    }, [doc]);

    const isPdf = doc?.kind === 'pdf';
    const fit = base && viewW ? (viewW - PAD * 2) / base.width : 1;
    const scale = fit * zoom;
    const slotW = base ? base.width * scale : 0;
    const slotH = base ? base.height * scale : 0;

    // ---------- page positions ----------
    const pageTop = useCallback((n: number) => {
        if (isPdf) return PAD + (n - 1) * (slotH + GAP);
        const el = contentRef.current?.querySelector<HTMLElement>(`[data-page="${n}"]`);
        return el ? el.offsetTop : 0;
    }, [isPdf, slotH]);

    const pageAt = useCallback((y: number) => {
        if (!doc) return 1;
        if (isPdf) return Math.min(doc.numPages, Math.max(1, Math.floor((y - PAD) / (slotH + GAP)) + 1));
        let found = 1;
        contentRef.current?.querySelectorAll<HTMLElement>('[data-page]').forEach(el => {
            if (el.offsetTop <= y) found = Number(el.dataset.page);
        });
        return found;
    }, [doc, isPdf, slotH]);

    // Open where the reader left off
    useLayoutEffect(() => {
        if (!doc || restored.current || doc.kind === 'epub' || (isPdf && !slotH)) return;
        const el = scrollRef.current;
        if (!el) return;
        el.scrollTop = pageTop(startPage.current);
        // Image pages take their size once loaded: try again then
        if (!isPdf && startPage.current > 1 && el.scrollTop === 0) {
            const t = setTimeout(() => {
                el.scrollTop = pageTop(startPage.current);
                restored.current = true;
            }, 400);
            return () => clearTimeout(t);
        }
        restored.current = true;
    }, [doc, isPdf, slotH, pageTop]);

    useEffect(() => {
        if (doc?.kind === 'epub') restored.current = true;
    }, [doc]);

    // Current page follows the scroll position
    useEffect(() => {
        const el = scrollRef.current;
        if (!el || !doc || doc.kind === 'epub') return;
        let raf = 0;
        const onScroll = () => {
            if (raf) return;
            raf = requestAnimationFrame(() => {
                raf = 0;
                if (pinching.current) return;
                setPage(pageAt(el.scrollTop + el.clientHeight * 0.4));
            });
        };
        el.addEventListener('scroll', onScroll, { passive: true });
        return () => {
            el.removeEventListener('scroll', onScroll);
            cancelAnimationFrame(raf);
        };
    }, [doc, pageAt]);

    // Save the reading position
    useEffect(() => {
        if (!doc || !restored.current) return;
        const t = setTimeout(() => window.electronAPI.setPdfProgress(book.path, page, doc.numPages).catch(() => { }), 500);
        return () => clearTimeout(t);
    }, [doc, page, book.path]);

    const goTo = useCallback((n: number) => {
        if (!doc) return;
        const p = Math.min(Math.max(1, n), doc.numPages);
        closeCard();
        if (doc.kind === 'epub') {
            setPage(p);
            scrollRef.current?.scrollTo({ top: 0 });
        } else {
            scrollRef.current?.scrollTo({ top: pageTop(p), behavior: Math.abs(p - page) <= 1 ? 'smooth' : 'auto' });
        }
    }, [doc, page, pageTop, closeCard]);

    // ---------- pinch to zoom ----------
    // While the fingers move, the drawn pages are only stretched (cheap); when
    // they lift, the pages are drawn again, sharp, at the new size.
    const isEpub = doc?.kind === 'epub';
    const zoomRef = useRef({ zoom, epubZoom, isEpub });
    zoomRef.current = { zoom, epubZoom, isEpub };

    useEffect(() => {
        const el = scrollRef.current;
        const content = contentRef.current;
        if (!el || !content || !doc) return;
        let start: { d: number; cx: number; cy: number; fx: number; fy: number } | null = null;
        let k = 1;

        const onStart = (e: TouchEvent) => {
            if (e.touches.length !== 2) return;
            const [a, b] = [e.touches[0], e.touches[1]];
            const box = el.getBoundingClientRect();
            const fx = (a.clientX + b.clientX) / 2 - box.left;
            const fy = (a.clientY + b.clientY) / 2 - box.top;
            start = { d: dist(a, b), fx, fy, cx: el.scrollLeft + fx, cy: el.scrollTop + fy };
            k = 1;
            pinching.current = true;
            touch.current = null;
            content.style.transformOrigin = `${start.cx}px ${start.cy}px`;
            content.style.willChange = 'transform';
        };
        const onMove = (e: TouchEvent) => {
            if (!start || e.touches.length !== 2) return;
            e.preventDefault();
            const { zoom, epubZoom, isEpub } = zoomRef.current;
            const z = isEpub ? epubZoom : zoom;
            const lo = isEpub ? 0.7 : ZOOM_MIN;
            const hi = isEpub ? 2.5 : ZOOM_MAX;
            k = Math.min(hi / z, Math.max(lo / z, dist(e.touches[0], e.touches[1]) / start.d));
            content.style.transform = `scale(${k})`;
        };
        const onEnd = (e: TouchEvent) => {
            if (!start || e.touches.length >= 2) return;
            const s = start;
            start = null;
            const { zoom, epubZoom, isEpub } = zoomRef.current;
            if (Math.abs(k - 1) < 0.02) {
                content.style.transform = '';
                content.style.willChange = '';
                pinching.current = false;
                return;
            }
            if (isEpub) {
                // Text reflows: keep the same place in the chapter
                const ratio = el.scrollHeight ? (el.scrollTop + s.fy) / el.scrollHeight : 0;
                pendingScroll.current = { left: 0, top: -ratio };
                setEpubZoom(Math.round(epubZoom * k * 100) / 100);
            } else {
                pendingScroll.current = { left: s.cx * k - s.fx, top: s.cy * k - s.fy };
                setZoom(Math.round(zoom * k * 1000) / 1000);
            }
        };

        el.addEventListener('touchstart', onStart, { passive: true });
        el.addEventListener('touchmove', onMove, { passive: false });
        el.addEventListener('touchend', onEnd, { passive: true });
        el.addEventListener('touchcancel', onEnd, { passive: true });
        return () => {
            el.removeEventListener('touchstart', onStart);
            el.removeEventListener('touchmove', onMove);
            el.removeEventListener('touchend', onEnd);
            el.removeEventListener('touchcancel', onEnd);
        };
    }, [doc]);

    // After a zoom: drop the stretch and keep the spot under the fingers in place
    useLayoutEffect(() => {
        const el = scrollRef.current;
        const content = contentRef.current;
        const p = pendingScroll.current;
        if (!el || !content || !p) return;
        pendingScroll.current = null;
        content.style.transform = '';
        content.style.willChange = '';
        if (p.top < 0) el.scrollTop = -p.top * el.scrollHeight - el.clientHeight * 0.3;
        else {
            el.scrollLeft = p.left;
            el.scrollTop = p.top;
        }
        pinching.current = false;
        setPage(prev => (doc?.kind === 'epub' ? prev : pageAt(el.scrollTop + el.clientHeight * 0.4)));
    }, [zoom, epubZoom, doc, pageAt]);

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
        touch.current = e.touches.length === 1 && !pinching.current ? { x: t.clientX, y: t.clientY, t: Date.now() } : null;
    };

    const onTouchEnd = (e: React.TouchEvent) => {
        const start = touch.current;
        touch.current = null;
        if (!start || pinching.current) return;
        const t = e.changedTouches[0];
        const moved = Math.hypot(t.clientX - start.x, t.clientY - start.y);
        // A tap (not a scroll, and not a long press, which makes its own selection)
        if (moved > 10 || Date.now() - start.t > 350) return;
        // Buttons and links in the book (EPUB "Next chapter", footnotes) keep working
        if ((e.target as Element).closest('button, a')) return;
        const root = (e.target as Element).closest('.pdf-text-layer, .epub-chapter');
        const range = root && selectWordAt(t.clientX, t.clientY, root, doc?.kind === 'epub' ? doc.book.language : undefined);
        if (range) {
            e.preventDefault();
            showCard(range);
        } else {
            closeCard();
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
        closeCard();
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
        closeCard();
    };

    const onLevel = async (l: number) => {
        setLevel(l);
        // A saved word's level changes right away, as on desktop
        if (card && savedWordId) {
            await window.electronAPI.setWordFamiliarity(wordKey(card.text), l, card.translation);
            setFamiliarity(prev => ({ ...prev, [wordKey(card.text)]: l }));
        }
    };

    // ---------- pages ----------
    let body: React.ReactNode = null;
    if (error) {
        body = (
            <div className="h-full flex items-center justify-center px-8 text-center">
                <p className="text-[15px]">{error}</p>
            </div>
        );
    } else if (!doc || (isPdf && !viewW)) {
        body = (
            <div className="h-full flex items-center justify-center gap-2 muted">
                <Loader2 size={18} className="animate-spin" /> Opening…
            </div>
        );
    } else if (doc.kind === 'epub') {
        body = (
            <div ref={contentRef} className="px-3 py-4 origin-top-left" style={{ background: 'var(--surface)', minHeight: '100%' }}>
                <EpubView doc={doc} chapter={page} scale={epubZoom * EPUB_SCALE} highlighter={highlighter} onNavigate={c => goTo(c)} />
            </div>
        );
    } else if (doc.kind === 'pdf') {
        const total = PAD * 2 + doc.numPages * slotH + (doc.numPages - 1) * GAP;
        const pages: number[] = [];
        for (let n = Math.max(1, page - AHEAD); n <= Math.min(doc.numPages, page + AHEAD); n++) pages.push(n);
        body = (
            <div ref={contentRef} className="relative" style={{ width: Math.max(viewW, slotW + PAD * 2), height: total }}>
                {pages.map(n => (
                    <div
                        key={`${doc.hash}-${n}`}
                        className="absolute flex justify-center"
                        style={{ top: PAD + (n - 1) * (slotH + GAP), left: PAD, width: slotW, height: slotH }}
                    >
                        <PageView doc={doc} pageNum={n} scale={scale} highlighter={highlighter} ocrMode="off" ocrVersion={0} />
                    </div>
                ))}
            </div>
        );
    } else {
        // Images and comics: pages of different sizes, so they flow; only ones near the screen load
        body = (
            <div ref={contentRef} className="flex flex-col items-center" style={{ width: Math.max(viewW, viewW * zoom), padding: `${PAD}px 0` }}>
                {Array.from({ length: doc.numPages }, (_, i) => i + 1).map(n => (
                    <PageView key={`${doc.hash}-${n}`} doc={doc} pageNum={n} scale={((viewW - PAD * 2) / 600) * zoom} highlighter={highlighter} ocrMode="off" ocrVersion={0} lazy seamless />
                ))}
            </div>
        );
    }

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
                className="reader-scroll flex-1 overflow-auto overscroll-contain"
                onTouchStart={onTouchStart}
                onTouchEnd={onTouchEnd}
                onContextMenu={e => e.preventDefault()}
            >
                {body}
            </div>

            <footer className="reader-bar flex items-center gap-1 px-2 border-t" style={{ background: 'var(--surface)', borderColor: 'var(--border)' }}>
                <button className="icon-btn tap" onClick={() => goTo(page - 1)} disabled={!doc || page <= 1} aria-label={isEpub ? 'Previous chapter' : 'Previous page'}>
                    <ChevronLeft size={20} />
                </button>
                <div className="flex-1 text-center text-[13px] muted tabular-nums">
                    {doc ? `${isEpub ? 'Chapter' : 'Page'} ${page} of ${doc.numPages}` : ''}
                </div>
                <button className="icon-btn tap" onClick={() => goTo(page + 1)} disabled={!doc || page >= (doc?.numPages ?? 1)} aria-label={isEpub ? 'Next chapter' : 'Next page'}>
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
                    onClose={closeCard}
                    bookLang={doc?.kind === 'epub' ? doc.book.language : undefined}
                />
            )}
        </div>
    );
}
