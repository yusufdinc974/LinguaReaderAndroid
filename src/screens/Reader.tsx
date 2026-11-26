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
import { BookOpenText, Check, ChevronLeft, ChevronRight, GalleryVertical, Hash, Highlighter, Languages, ListTree, Loader2, Maximize2, MoreVertical, ScanText, X } from 'lucide-react';
import { destroyDoc, displayName, openReaderDoc, pageSize, type ReaderDoc } from '@desktop/lib/document';
import { getOcrMode, setOcrMode, type OcrMode } from '@desktop/lib/ocr';
import { getLearnLang, langFamily } from '@desktop/lib/speech';
import { DEFAULT_LIST_COLOR } from '@desktop/lib/words';
import Dialog from '@desktop/components/Dialog';
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
import Sheet, { SheetItem } from '../components/Sheet';

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

type Panel = 'menu' | 'toc' | 'filter' | 'lang' | 'ocr' | 'goto' | null;

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
    /** Other forms of saved words ("mangé" → "manger"), from installed dictionaries */
    const [formOf, setFormOf] = useState<Record<string, string>>({});
    // [] = highlight all lists, [-1] = none, otherwise the chosen ids (as desktop)
    const [shownListIds, setShownListIds] = useState<number[]>([]);
    const [ocrMode, setOcrModeState] = useState<OcrMode>(getOcrMode);
    const [ocrVersion, setOcrVersion] = useState(0);
    /** Images: one long strip (webtoons) rather than a page at a time */
    const [continuous, setContinuous] = useState(true);
    /** Focus: the bars are hidden */
    const [focus, setFocus] = useState(false);
    const [panel, setPanel] = useState<Panel>(null);
    const [gotoValue, setGotoValue] = useState('');

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
    const colorsSeq = useRef(0);
    const pageRef = useRef(page);
    pageRef.current = page;
    /** EPUB: where to scroll once the chapter is drawn */
    const epubScroll = useRef<{ fraction?: number; fragment?: string } | null>(null);

    useEffect(() => localStorage.setItem('epubZoom', String(epubZoom)), [epubZoom]);
    useEffect(() => localStorage.setItem('targetLang', targetLang), [targetLang]);

    const closeCard = useCallback(() => {
        setCard(null);
        window.getSelection()?.removeAllRanges();
    }, []);

    // Back: closes a panel or the word card first, then leaves focus, then closes the book
    useBack(onClose);
    useBack(() => setFocus(false), focus);
    useBack(closeCard, card !== null);

    // ---------- data ----------
    const loadLists = useCallback(async () => setLists(await window.electronAPI.getWordLists()), []);
    const loadFamiliarity = useCallback(async () => {
        const map: Record<string, number> = {};
        for (const f of await window.electronAPI.getAllWordFamiliarity()) map[f.word_lower] = f.familiarity_level;
        setFamiliarity(map);
    }, []);
    // Colours of saved words, and their other forms from the dictionaries (as desktop Reader)
    const loadColors = useCallback(async (ids: number[]) => {
        const rows = await window.electronAPI.getWordColors(ids.length > 0 ? ids : undefined);
        const map: Record<string, string> = {};
        for (const r of rows) map[r.word_lower] ??= r.color;
        setWordColors(map);
        const seq = ++colorsSeq.current;
        const ask: { key: string; lang: string }[] = [];
        const seen = new Set<string>();
        for (const r of rows) {
            const lang = langFamily(r.source_language) ?? langFamily(getLearnLang());
            const langs = lang === 'zh' || lang === 'ja' ? (/^\p{Script=Han}+$/u.test(r.word_lower) ? ['ja', 'zh'] : [lang]) : lang ? [lang] : [];
            for (const l of langs) if (!seen.has(`${l}:${r.word_lower}`)) {
                seen.add(`${l}:${r.word_lower}`);
                ask.push({ key: r.word_lower, lang: l });
            }
        }
        const pairs = ask.length ? await window.electronAPI.dictForms(ask).catch(() => [] as [string, string][]) : [];
        if (seq !== colorsSeq.current) return;
        const forms: Record<string, string> = {};
        for (const [f, b] of pairs) if (!(f in map) && !(f in forms)) forms[f] = b;
        setFormOf(forms);
    }, []);

    useEffect(() => {
        loadLists();
        loadFamiliarity();
    }, [loadLists, loadFamiliarity]);
    useEffect(() => {
        loadColors(shownListIds);
    }, [loadColors, shownListIds]);

    const highlighter = useMemo(() => {
        const all: Record<string, string> = {};
        for (const [f, b] of Object.entries(formOf)) if (wordColors[b]) all[f] = wordColors[b];
        return createHighlighter(Object.assign(all, wordColors));
    }, [wordColors, formOf]);

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
                if (next.kind === 'images') {
                    // Long strips read best as one scroll; comics a page at a time (as desktop)
                    const stored = localStorage.getItem(`continuous:${next.hash}`);
                    const first = await pageSize(next, 1);
                    setContinuous(stored !== null ? stored === '1' : first.height > first.width * 2);
                }
                if (next.kind === 'epub') {
                    const [ch, frac] = (localStorage.getItem(`epubpos:${next.hash}`) ?? '').split(':').map(Number);
                    epubScroll.current = { fraction: ch === last && frac > 0 && frac <= 1 ? frac : 0 };
                }
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
    /** Images shown a page at a time (swipe to turn) */
    const paged = doc?.kind === 'images' && !continuous;
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
        if (!doc || restored.current || doc.kind === 'epub' || paged || (isPdf && !slotH)) return;
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
        if (doc?.kind === 'epub' || paged) restored.current = true;
    }, [doc, paged]);

    // Current page follows the scroll position
    useEffect(() => {
        const el = scrollRef.current;
        if (!el || !doc || paged) return;
        let raf = 0;
        let posTimer: ReturnType<typeof setTimeout> | undefined;
        if (doc.kind === 'epub') {
            // Keep the place inside the chapter, per book (as desktop)
            const onEpubScroll = () => {
                const max = el.scrollHeight - el.clientHeight;
                const value = `${pageRef.current}:${max > 0 ? (el.scrollTop / max).toFixed(4) : 0}`;
                clearTimeout(posTimer);
                posTimer = setTimeout(() => localStorage.setItem(`epubpos:${doc.hash}`, value), 250);
            };
            el.addEventListener('scroll', onEpubScroll, { passive: true });
            return () => {
                el.removeEventListener('scroll', onEpubScroll);
                clearTimeout(posTimer);
            };
        }
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
    }, [doc, pageAt, paged]);

    // Save the reading position
    useEffect(() => {
        if (!doc || !restored.current) return;
        const t = setTimeout(() => window.electronAPI.setPdfProgress(book.path, page, doc.numPages).catch(() => { }), 500);
        return () => clearTimeout(t);
    }, [doc, page, book.path]);

    const goTo = useCallback((n: number, fragment?: string) => {
        if (!doc) return;
        const p = Math.min(Math.max(1, n), doc.numPages);
        closeCard();
        if (doc.kind === 'epub') {
            epubScroll.current = fragment ? { fragment } : { fraction: 0 };
            if (p === page) applyEpubScroll();
            else setPage(p);
        } else if (paged) {
            setPage(p);
            setZoom(1);
            scrollRef.current?.scrollTo({ top: 0, left: 0 });
        } else {
            scrollRef.current?.scrollTo({ top: pageTop(p), behavior: Math.abs(p - page) <= 1 ? 'smooth' : 'auto' });
        }
    }, [doc, page, pageTop, closeCard, paged]);

    /** EPUB: after a chapter is drawn, go to the saved place or the linked spot. */
    function applyEpubScroll() {
        const box = scrollRef.current;
        const p = epubScroll.current;
        if (!box || !p) return;
        epubScroll.current = null;
        if (p.fragment) {
            const el = box.querySelector<HTMLElement>(`#${CSS.escape(`epub-${p.fragment}`)}`);
            if (el) {
                box.scrollTo({ top: el.getBoundingClientRect().top - box.getBoundingClientRect().top + box.scrollTop - 24 });
                return;
            }
        }
        const frac = p.fraction ?? 0;
        const go = () => box.scrollTo({ top: frac * (box.scrollHeight - box.clientHeight) });
        go();
        if (frac > 0) setTimeout(go, 300);
    }

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
        const savedId = existing.status === 'fulfilled' ? existing.value?.id ?? null : null;
        setSavedWordId(savedId);
        // A form of a saved word ("mangé" when "manger" is saved)
        const formBase = savedId === null ? formOf[key] : undefined;
        const savedAs = formBase ? { word: formBase, level: familiarity[formBase] ?? 1 } : undefined;
        setCard(c => c && (result.status === 'fulfilled'
            ? { ...c, loading: false, translation: result.value.translatedText, source: result.value.source, detectedLanguage: result.value.detectedLanguage, savedAs }
            : { ...c, loading: false, failed: true, savedAs }));
    }, [familiarity, targetLang, formOf]);

    const onTouchStart = (e: React.TouchEvent) => {
        const t = e.touches[0];
        touch.current = e.touches.length === 1 && !pinching.current ? { x: t.clientX, y: t.clientY, t: Date.now() } : null;
    };

    const onTouchEnd = (e: React.TouchEvent) => {
        const start = touch.current;
        touch.current = null;
        if (!start || pinching.current) return;
        const t = e.changedTouches[0];
        const dx = t.clientX - start.x, dy = t.clientY - start.y;
        const moved = Math.hypot(dx, dy);
        // Comics a page at a time: a sideways swipe turns the page (when not zoomed in)
        if (paged && zoom <= 1.01 && Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy) * 2 && Date.now() - start.t < 600) {
            goTo(page + (dx < 0 ? 1 : -1));
            return;
        }
        // A tap (not a scroll, and not a long press, which makes its own selection)
        if (moved > 10 || Date.now() - start.t > 350) return;
        // Buttons and links in the book (EPUB "Next chapter", footnotes) keep working
        if ((e.target as Element).closest('button, a')) return;
        const root = (e.target as Element).closest('.pdf-text-layer, .epub-chapter');
        const range = root && selectWordAt(t.clientX, t.clientY, root, doc?.kind === 'epub' ? doc.book.language : undefined);
        if (range) {
            e.preventDefault();
            showCard(range);
        } else if (card) {
            closeCard();
        } else {
            // A tap away from words shows or hides the bars
            setFocus(f => !f);
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
        await loadColors(shownListIds);
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
        await loadColors(shownListIds);
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
                <EpubView doc={doc} chapter={page} scale={epubZoom * EPUB_SCALE} highlighter={highlighter} onNavigate={goTo} onRendered={applyEpubScroll} />
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
                        <PageView doc={doc} pageNum={n} scale={scale} highlighter={highlighter} ocrMode={ocrMode} ocrVersion={ocrVersion} />
                    </div>
                ))}
            </div>
        );
    } else if (paged) {
        // Comics: one page, fit to the width; swipe sideways to turn
        body = (
            <div ref={contentRef} className="flex flex-col items-center" style={{ width: Math.max(viewW, viewW * zoom), padding: `${PAD}px 0` }}>
                <PageView key={`${doc.hash}-${page}`} doc={doc} pageNum={page} scale={((viewW - PAD * 2) / 600) * zoom} highlighter={highlighter} ocrMode={ocrMode} ocrVersion={ocrVersion} seamless />
            </div>
        );
    } else {
        // Long strips: pages of different sizes flow; only ones near the screen load
        body = (
            <div ref={contentRef} className="flex flex-col items-center" style={{ width: Math.max(viewW, viewW * zoom), padding: `${PAD}px 0` }}>
                {Array.from({ length: doc.numPages }, (_, i) => i + 1).map(n => (
                    <PageView key={`${doc.hash}-${n}`} doc={doc} pageNum={n} scale={((viewW - PAD * 2) / 600) * zoom} highlighter={highlighter} ocrMode={ocrMode} ocrVersion={ocrVersion} lazy seamless />
                ))}
            </div>
        );
    }

    const title = displayName(book.name);
    const toc = doc?.kind === 'epub' ? doc.book.toc : [];
    const langName = SUPPORTED_LANGUAGES.find(l => l.code === targetLang)?.name ?? targetLang;
    const isShown = (id: number) => shownListIds.length === 0 || (shownListIds[0] !== -1 && shownListIds.includes(id));
    const toggleShown = (id: number) => {
        const current = lists.filter(l => isShown(l.id)).map(l => l.id);
        const next = current.includes(id) ? current.filter(x => x !== id) : [...current, id];
        setShownListIds(next.length === lists.length ? [] : next.length === 0 ? [-1] : next);
    };
    const filterActive = shownListIds.length > 0;
    const unit = isEpub ? 'Chapter' : 'Page';
    const close = () => setPanel(null);
    const chooseOcr = (m: OcrMode) => {
        setOcrMode(m);
        setOcrModeState(m);
        setOcrVersion(v => v + 1);
        close();
    };
    const submitGoto = () => {
        const n = parseInt(gotoValue, 10);
        if (Number.isFinite(n)) goTo(n);
        close();
    };

    return (
        <div
            className="fixed inset-0 flex flex-col"
            style={{ background: 'var(--reader-bg)', ['--card-bottom' as string]: focus ? 'calc(8px + env(safe-area-inset-bottom))' : 'calc(64px + env(safe-area-inset-bottom))' }}
        >
            {!focus && (
                <header className="reader-top flex items-center gap-0.5 px-1 border-b" style={{ background: 'var(--surface)', borderColor: 'var(--border)' }}>
                    <button className="icon-btn tap" onClick={onClose} aria-label="Back to library">
                        <X size={20} />
                    </button>
                    <p className="flex-1 min-w-0 truncate text-[15px] font-medium ml-1">{title}</p>
                    {toc.length > 0 && (
                        <button className="icon-btn tap" onClick={() => setPanel('toc')} aria-label="Contents"><ListTree size={19} /></button>
                    )}
                    <button className="icon-btn tap relative" onClick={() => setPanel('filter')} aria-label="Highlighted lists">
                        <Highlighter size={19} />
                        {filterActive && <span className="absolute top-2.5 right-2.5 w-1.5 h-1.5 rounded-full" style={{ background: 'var(--accent)' }} />}
                    </button>
                    <button className="icon-btn tap" onClick={() => setPanel('menu')} aria-label="Reader options"><MoreVertical size={19} /></button>
                </header>
            )}

            <div
                ref={scrollRef}
                className="reader-scroll flex-1 overflow-auto overscroll-contain"
                onTouchStart={onTouchStart}
                onTouchEnd={onTouchEnd}
                onContextMenu={e => e.preventDefault()}
            >
                {body}
            </div>

            {!focus && (
                <footer className="reader-bar flex items-center gap-1 px-2 border-t" style={{ background: 'var(--surface)', borderColor: 'var(--border)' }}>
                    <button className="icon-btn tap" onClick={() => goTo(page - 1)} disabled={!doc || page <= 1} aria-label={isEpub ? 'Previous chapter' : 'Previous page'}>
                        <ChevronLeft size={20} />
                    </button>
                    <button
                        className="flex-1 h-11 text-center text-[13px] muted tabular-nums"
                        onClick={() => { setGotoValue(String(page)); setPanel('goto'); }}
                        disabled={!doc}
                        aria-label={`${unit} ${page}. Go to ${unit.toLowerCase()}`}
                    >
                        {doc ? `${unit} ${page} of ${doc.numPages}` : ''}
                    </button>
                    <button className="icon-btn tap" onClick={() => goTo(page + 1)} disabled={!doc || page >= (doc?.numPages ?? 1)} aria-label={isEpub ? 'Next chapter' : 'Next page'}>
                        <ChevronRight size={20} />
                    </button>
                </footer>
            )}

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

            {panel === 'menu' && (
                <Sheet onClose={close}>
                    <SheetItem icon={<Languages size={18} />} onClick={() => setPanel('lang')}>Translate into: {langName}</SheetItem>
                    {doc && <SheetItem icon={<Hash size={18} />} onClick={() => { setGotoValue(String(page)); setPanel('goto'); }}>Go to {unit.toLowerCase()}…</SheetItem>}
                    {doc?.kind === 'images' && (
                        <SheetItem
                            icon={continuous ? <BookOpenText size={18} /> : <GalleryVertical size={18} />}
                            onClick={() => {
                                const next = !continuous;
                                localStorage.setItem(`continuous:${doc.hash}`, next ? '1' : '0');
                                restored.current = false;
                                startPage.current = page;
                                setZoom(1);
                                setContinuous(next);
                                close();
                            }}
                        >
                            {continuous ? 'Show a page at a time' : 'Show as one long strip'}
                        </SheetItem>
                    )}
                    {doc && !isEpub && <SheetItem icon={<ScanText size={18} />} onClick={() => setPanel('ocr')}>Read text in images…</SheetItem>}
                    <SheetItem icon={<Maximize2 size={18} />} onClick={() => { setFocus(true); close(); }}>Hide the bars (tap the page to show them)</SheetItem>
                </Sheet>
            )}
            {panel === 'lang' && (
                <Sheet title="Translate into" onClose={close}>
                    {SUPPORTED_LANGUAGES.map(l => (
                        <SheetItem key={l.code} onClick={() => { setTargetLang(l.code); close(); }} icon={<span className="w-[18px] flex justify-center">{l.code === targetLang && <Check size={16} style={{ color: 'var(--accent)' }} />}</span>}>
                            {l.name}
                        </SheetItem>
                    ))}
                </Sheet>
            )}
            {panel === 'ocr' && (
                <Sheet title="Read text in images" onClose={close}>
                    {([['auto', 'Scanned pages and images'], ['always', 'Every page'], ['off', 'Off']] as [OcrMode, string][]).map(([m, label]) => (
                        <SheetItem key={m} onClick={() => chooseOcr(m)} icon={<span className="w-[18px] flex justify-center">{ocrMode === m && <Check size={16} style={{ color: 'var(--accent)' }} />}</span>}>{label}</SheetItem>
                    ))}
                </Sheet>
            )}
            {panel === 'toc' && (
                <Sheet title="Contents" onClose={close}>
                    {toc.map((t, i) => (
                        <button
                            key={i}
                            className="w-full flex items-center gap-2 min-h-11 py-2 pr-3 rounded-lg text-left text-[15px] active:bg-[var(--surface-2)]"
                            style={{ paddingLeft: 12 + t.depth * 16 }}
                            onClick={() => { close(); goTo(t.chapter + 1, t.fragment); }}
                        >
                            <span className="flex-1 min-w-0">{t.title}</span>
                            {t.chapter + 1 === page && !t.fragment && <span className="dot shrink-0" style={{ background: 'var(--accent)', width: 6, height: 6 }} />}
                        </button>
                    ))}
                </Sheet>
            )}
            {panel === 'filter' && (
                <Sheet title="Highlight words from" onClose={close}>
                    {lists.length === 0 && <p className="text-[14px] faint px-3 py-3">No lists yet.</p>}
                    {lists.map(l => (
                        <label key={l.id} className="flex items-center gap-3 h-12 px-3 rounded-lg text-[15px] active:bg-[var(--surface-2)]">
                            <input type="checkbox" checked={isShown(l.id)} onChange={() => toggleShown(l.id)} style={{ accentColor: 'var(--accent)', width: 18, height: 18 }} />
                            <span className="dot" style={{ background: l.color || DEFAULT_LIST_COLOR }} />
                            <span className="flex-1 min-w-0 truncate">{l.name}</span>
                        </label>
                    ))}
                    {filterActive && <SheetItem onClick={() => setShownListIds([])}><span style={{ color: 'var(--accent)' }}>Show all lists</span></SheetItem>}
                </Sheet>
            )}
            {panel === 'goto' && doc && (
                <Dialog
                    title={`Go to ${unit.toLowerCase()}`}
                    onClose={close}
                    footer={<><button className="btn btn-ghost" onClick={close}>Cancel</button><button className="btn btn-primary" onClick={submitGoto}>Go</button></>}
                >
                    <input
                        className="field"
                        type="number"
                        inputMode="numeric"
                        min={1}
                        max={doc.numPages}
                        autoFocus
                        value={gotoValue}
                        onChange={e => setGotoValue(e.target.value)}
                        onKeyDown={e => e.key === 'Enter' && submitGoto()}
                        aria-label={`${unit} number`}
                    />
                    <p className="text-[12.5px] faint mt-1.5">1 to {doc.numPages}</p>
                </Dialog>
            )}
        </div>
    );
}
