// Saved words: progress at a glance, lists, and each list's words.
// The phone version of desktop/src/pages/Words.tsx (same features, one column).

import { useCallback, useEffect, useMemo, useState } from 'react';
import { ArrowDownUp, ArrowRightLeft, ChevronLeft, ChevronRight, GraduationCap, MoreVertical, Plus, Search, Trash2, Upload, X } from 'lucide-react';
import { DEFAULT_LIST_COLOR, LEVELS, LIST_COLORS } from '@desktop/lib/words';
import { displayName } from '@desktop/lib/document';
import type { Word, WordList } from '@desktop/types';
import SpeakButton from '@desktop/components/SpeakButton';
import Dialog, { ConfirmDialog } from '@desktop/components/Dialog';
import ImportExport from '../components/ImportExport';
import { useBack } from '../lib/back';
import { listCounts, type ListCounts } from '../lib/reviewCounts';
import { useDataVersion } from '../lib/dataVersion';
import Sheet, { SheetItem } from '../components/Sheet';
import ReviewHost from './ReviewHost';

type Schedule = Awaited<ReturnType<Window['electronAPI']['getReviewSchedule']>>;

/** "Due", "Tomorrow", "In 3 days", "Dec 4" (as the desktop Words page). */
export function nextReviewLabel(iso?: string | null, now = new Date()) {
    if (!iso) return '—';
    const d = new Date(iso);
    const today = new Date(now);
    today.setHours(0, 0, 0, 0);
    const day = new Date(d);
    day.setHours(0, 0, 0, 0);
    const diff = Math.round((day.getTime() - today.getTime()) / 86400000);
    if (diff <= 0) return 'Due';
    if (diff === 1) return 'Tomorrow';
    if (diff < 7) return `In ${diff} days`;
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

/** Reviews over the next 14 days, one bar a day. */
function Upcoming({ days, dueNow }: { days: Schedule['upcomingDays']; dueNow: number }) {
    const data = Array.from({ length: 14 }, (_, i) => {
        const d = new Date();
        d.setDate(d.getDate() + i);
        const key = d.toISOString().split('T')[0];
        const n = days[key] || 0;
        return { key, n: i === 0 ? Math.max(n, dueNow) : n };
    });
    const max = Math.max(1, ...data.map(d => d.n));
    return (
        <div className="flex items-end gap-[3px] h-9" role="img" aria-label="Reviews over the next 14 days">
            {data.map((d, i) => (
                <div
                    key={d.key}
                    className="flex-1 rounded-[2px]"
                    style={{
                        height: `${Math.max(8, (d.n / max) * 100)}%`,
                        background: d.n === 0 ? 'var(--surface-3)' : i === 0 ? 'var(--accent)' : 'var(--text-3)',
                        opacity: d.n === 0 ? 0.6 : 1,
                    }}
                />
            ))}
        </div>
    );
}

type Review = { listId: number | null; listName: string; total: number; due: number };

export default function Words() {
    const version = useDataVersion();
    const [lists, setLists] = useState<ListCounts[] | null>(null);
    const [schedule, setSchedule] = useState<Schedule | null>(null);
    const [openId, setOpenId] = useState<number | null>(null);
    const [words, setWords] = useState<Word[]>([]);
    const [query, setQuery] = useState('');
    const [searching, setSearching] = useState(false);
    const [review, setReview] = useState<Review | null>(null);
    const [creating, setCreating] = useState(false);
    const [listMenu, setListMenu] = useState(false);
    const [rowMenu, setRowMenu] = useState<Word | null>(null);
    const [moving, setMoving] = useState<Word | null>(null);
    const [confirm, setConfirm] = useState<{ title: string; message: string; label: string; run: () => void } | null>(null);
    const [io, setIo] = useState(false);
    const [toast, setToast] = useState<string | null>(null);

    const open = lists?.find(l => l.id === openId) ?? null;

    const loadAll = useCallback(async () => {
        const [c, s] = await Promise.all([listCounts(), window.electronAPI.getReviewSchedule()]);
        setLists(c.lists);
        setSchedule(s);
    }, []);
    const loadWords = useCallback(async (id: number) => setWords(await window.electronAPI.getWordsInList(id)), []);

    useEffect(() => {
        loadAll();
    }, [loadAll, version]);
    useEffect(() => {
        if (openId) loadWords(openId);
        else setWords([]);
        setQuery('');
        setSearching(false);
    }, [openId, loadWords, version]);

    useBack(() => (searching ? (setSearching(false), setQuery('')) : setOpenId(null)), openId !== null && !review);

    const flash = (msg: string) => {
        setToast(msg);
        setTimeout(() => setToast(null), 3000);
    };

    const filtered = useMemo(() => {
        const q = query.trim().toLowerCase();
        if (!q) return words;
        return words.filter(w => w.word.toLowerCase().includes(q) || w.translation.toLowerCase().includes(q));
    }, [words, query]);

    const deleteList = (list: WordList) => setConfirm({
        title: `Delete “${list.name}”?`,
        message: 'The list is removed. Words that are not in any other list are deleted too.',
        label: 'Delete list',
        run: async () => {
            await window.electronAPI.deleteWordList(list.id);
            setOpenId(null);
        },
    });

    const removeWord = (w: Word) => setConfirm({
        title: `Remove “${w.word}”?`,
        message: 'It is removed from this list. If it is not in any other list, it is deleted.',
        label: 'Remove',
        run: async () => {
            if (open) await window.electronAPI.removeWordFromList(w.id, open.id);
        },
    });

    const moveWord = async (w: Word, toId: number) => {
        if (!open) return;
        setMoving(null);
        const r = await window.electronAPI.moveWordToList(w.id, open.id, toId);
        if (!r.success) flash(r.message || 'Could not move the word.');
        else flash(`Moved to ${lists?.find(l => l.id === toId)?.name ?? 'the list'}.`);
    };

    const dueNow = schedule ? schedule.overdue + schedule.dueToday : 0;
    const learned = schedule ? schedule.good + schedule.mastered : 0;
    const totalWords = schedule?.totalWords ?? 0;

    const overlays = (
        <>
            {creating && <NewList onClose={() => setCreating(false)} onCreated={id => { setCreating(false); setOpenId(id); }} />}
            {io && (
                <ImportExport
                    selectedId={openId}
                    onClose={() => setIo(false)}
                    onDone={(msg, listId) => { setIo(false); if (listId) setOpenId(listId); flash(msg); }}
                />
            )}
            {confirm && <ConfirmDialog title={confirm.title} message={confirm.message} confirmLabel={confirm.label} onConfirm={confirm.run} onClose={() => setConfirm(null)} />}
            {review && <ReviewHost {...review} onExit={() => setReview(null)} />}
            {toast && (
                <div className="fixed left-1/2 -translate-x-1/2 bottom-24 z-[200] px-4 py-2.5 rounded-lg text-[13.5px] max-w-[90vw] text-center anim-in" style={{ background: 'var(--text)', color: 'var(--bg)' }} role="status">
                    {toast}
                </div>
            )}
        </>
    );

    // ---------------------------------------------------------------- one list
    if (open) {
        const others = lists?.filter(l => l.id !== open.id) ?? [];
        return (
            <div className="h-full flex flex-col">
                <header className="flex items-center gap-1 px-1 h-[52px] border-b shrink-0" style={{ borderColor: 'var(--border)' }}>
                    <button className="icon-btn tap" onClick={() => setOpenId(null)} aria-label="Back to lists"><ChevronLeft size={20} /></button>
                    {searching ? (
                        <input
                            className="field flex-1 min-w-0"
                            autoFocus
                            placeholder="Search this list"
                            value={query}
                            onChange={e => setQuery(e.target.value)}
                            aria-label="Search this list"
                        />
                    ) : (
                        <>
                            <span className="dot shrink-0" style={{ background: open.color || DEFAULT_LIST_COLOR }} />
                            <h1 className="flex-1 min-w-0 text-[16px] font-semibold truncate ml-1">{open.name}</h1>
                        </>
                    )}
                    {words.length > 0 && (
                        <button className="icon-btn tap" onClick={() => (searching ? (setSearching(false), setQuery('')) : setSearching(true))} aria-label={searching ? 'Close search' : 'Search'}>
                            {searching ? <X size={19} /> : <Search size={19} />}
                        </button>
                    )}
                    <button className="icon-btn tap" onClick={() => setListMenu(true)} aria-label="List options"><MoreVertical size={19} /></button>
                </header>

                <div className="px-4 py-3 flex items-center gap-3 border-b" style={{ borderColor: 'var(--border)' }}>
                    <p className="flex-1 min-w-0 text-[13px] muted truncate">
                        {open.total} {open.total === 1 ? 'word' : 'words'}
                        {open.due > 0 && <> · <span style={{ color: 'var(--accent)' }}>{open.due} due</span></>}
                        {open.description && <> · {open.description}</>}
                    </p>
                    <button className="btn btn-primary h-10" disabled={words.length === 0} onClick={() => setReview({ listId: open.id, listName: open.name, total: open.total, due: open.due })}>
                        <GraduationCap size={16} /> Review
                    </button>
                </div>

                <ul className="flex-1 overflow-auto">
                    {words.length === 0 && (
                        <li className="p-5">
                            <p className="text-[15px] font-semibold">This list is empty</p>
                            <p className="text-[14px] muted mt-1">Open a book, tap a word and choose a list to save it here.</p>
                        </li>
                    )}
                    {words.length > 0 && filtered.length === 0 && <li className="p-5 text-[14px] muted">No words match “{query}”.</li>}
                    {filtered.map(w => {
                        const lvl = LEVELS[w.familiarity_level || 1] ?? LEVELS[1];
                        const next = nextReviewLabel(w.next_review_date);
                        return (
                            <li key={w.id} className="flex items-start gap-2 pl-4 pr-1 py-3 border-b" style={{ borderColor: 'var(--border)' }}>
                                <div className="min-w-0 flex-1">
                                    <div className="flex items-center gap-1">
                                        <p className="serif text-[17px] font-semibold leading-snug break-words">{w.word}</p>
                                        <SpeakButton text={w.word} langs={[w.source_language]} context={w.sentence_context} size={15} className="w-8 h-8 shrink-0" />
                                    </div>
                                    <p className="text-[14px] break-words" style={{ color: 'var(--text-2)' }}>{w.translation}</p>
                                    {w.sentence_context && <p className="serif italic text-[13px] faint mt-0.5 line-clamp-2">{w.sentence_context}</p>}
                                    <p className="text-[12px] faint mt-1 flex items-center gap-1.5 flex-wrap">
                                        <span className="inline-flex items-center gap-1"><span className="w-3 h-[3px] rounded-full" style={{ background: lvl.color }} />{lvl.label}</span>
                                        <span>·</span>
                                        <span style={next === 'Due' ? { color: 'var(--accent)' } : undefined}>{next === 'Due' ? 'Due now' : `Next ${next.toLowerCase().startsWith('in ') ? next.toLowerCase() : next}`}</span>
                                        {w.pdf_name && w.pdf_name !== 'imported' && <><span>·</span><span className="truncate max-w-[160px]">{displayName(w.pdf_name)}</span></>}
                                    </p>
                                </div>
                                <button className="icon-btn tap shrink-0" onClick={() => setRowMenu(w)} aria-label={`Options for ${w.word}`}><MoreVertical size={17} /></button>
                            </li>
                        );
                    })}
                </ul>

                {listMenu && (
                    <Sheet title={open.name} onClose={() => setListMenu(false)}>
                        <SheetItem icon={<Upload size={18} />} onClick={() => { setListMenu(false); setIo(true); }}>Export this list…</SheetItem>
                        <SheetItem icon={<Trash2 size={18} />} danger onClick={() => { setListMenu(false); deleteList(open); }}>Delete list…</SheetItem>
                    </Sheet>
                )}
                {rowMenu && (
                    <Sheet title={rowMenu.word} onClose={() => setRowMenu(null)}>
                        <SheetItem icon={<ArrowRightLeft size={18} />} disabled={others.length === 0} onClick={() => { setMoving(rowMenu); setRowMenu(null); }}>
                            {others.length === 0 ? 'Move to another list (no other lists)' : 'Move to another list…'}
                        </SheetItem>
                        <SheetItem icon={<Trash2 size={18} />} danger onClick={() => { const w = rowMenu; setRowMenu(null); removeWord(w); }}>Remove from this list</SheetItem>
                    </Sheet>
                )}
                {moving && (
                    <Sheet title={`Move “${moving.word}” to`} onClose={() => setMoving(null)}>
                        {others.map(l => (
                            <SheetItem key={l.id} icon={<span className="dot" style={{ background: l.color || DEFAULT_LIST_COLOR }} />} onClick={() => moveWord(moving, l.id)}>{l.name}</SheetItem>
                        ))}
                    </Sheet>
                )}
                {overlays}
            </div>
        );
    }

    // ---------------------------------------------------------------- all lists
    return (
        <div className="h-full overflow-auto">
            <div className="flex items-center justify-between pl-5 pr-2 pt-4 pb-2">
                <h1 className="text-[20px] font-semibold">Words</h1>
                <div className="flex">
                    <button className="icon-btn tap" onClick={() => setIo(true)} aria-label="Import and export"><ArrowDownUp size={19} /></button>
                    <button className="icon-btn tap" onClick={() => setCreating(true)} aria-label="New list"><Plus size={21} /></button>
                </div>
            </div>

            {schedule && totalWords > 0 && (
                <div className="mx-4 mb-2 p-4 rounded-xl border" style={{ borderColor: 'var(--border)', background: 'var(--surface)' }}>
                    <div className="grid grid-cols-3 mb-3">
                        {[
                            { n: dueNow, l: 'Due now', strong: dueNow > 0 },
                            { n: schedule.dueSoon, l: 'Soon' },
                            { n: learned, l: 'Learned' },
                        ].map(s => (
                            <div key={s.l}>
                                <p className="text-[22px] font-semibold tabular-nums leading-none" style={{ color: s.strong ? 'var(--accent)' : 'var(--text)' }}>{s.n}</p>
                                <p className="text-[12px] faint mt-1">{s.l}</p>
                            </div>
                        ))}
                    </div>
                    <Upcoming days={schedule.upcomingDays} dueNow={dueNow} />
                    <p className="text-[11px] faint mt-1.5 flex justify-between"><span>Today</span><span>2 weeks</span></p>
                    <button
                        className={`btn w-full h-11 mt-3 ${dueNow > 0 ? 'btn-primary' : 'btn-outline'}`}
                        onClick={() => setReview({ listId: null, listName: '', total: totalWords, due: dueNow })}
                    >
                        <GraduationCap size={16} /> {dueNow > 0 ? `Review ${dueNow} due` : 'Practise all words'}
                    </button>
                </div>
            )}

            <p className="label px-5 pt-3 pb-1">Lists</p>
            {lists?.length === 0 && (
                <div className="px-5 py-2">
                    <p className="text-[14px] muted">Lists group the words you save while reading, and each one gets its own highlight colour.</p>
                    <button className="btn btn-primary h-11 mt-4" onClick={() => setCreating(true)}><Plus size={16} /> New list</button>
                    <button className="btn btn-ghost h-11 mt-2 block" onClick={() => setIo(true)}><ArrowDownUp size={15} className="inline mr-1" /> Or import an Anki deck or a backup</button>
                </div>
            )}
            <ul className="px-3 pb-6">
                {lists?.map(l => (
                    <li key={l.id}>
                        <button className="w-full flex items-center gap-3 px-2 py-3 rounded-lg text-left active:bg-[var(--surface-2)]" onClick={() => setOpenId(l.id)}>
                            <span className="dot" style={{ background: l.color || DEFAULT_LIST_COLOR }} />
                            <span className="flex-1 min-w-0 truncate text-[15px] font-medium">{l.name}</span>
                            {l.due > 0 && <span className="text-[12.5px] tabular-nums font-medium" style={{ color: 'var(--accent)' }}>{l.due} due</span>}
                            <span className="text-[13px] muted tabular-nums w-7 text-right">{l.total}</span>
                            <ChevronRight size={16} className="faint" />
                        </button>
                    </li>
                ))}
            </ul>
            {overlays}
        </div>
    );
}

function NewList({ onClose, onCreated }: { onClose: () => void; onCreated: (id: number) => void }) {
    const [name, setName] = useState('');
    const [desc, setDesc] = useState('');
    const [color, setColor] = useState(LIST_COLORS[5]);
    const create = async () => {
        if (!name.trim()) return;
        onCreated(await window.electronAPI.createWordList(name.trim(), desc.trim(), color));
    };
    return (
        <Dialog
            title="New list"
            onClose={onClose}
            footer={<><button className="btn btn-ghost" onClick={onClose}>Cancel</button><button className="btn btn-primary" disabled={!name.trim()} onClick={create}>Create</button></>}
        >
            <label className="label block mb-1.5" htmlFor="list-name">Name</label>
            <input id="list-name" className="field" autoFocus value={name} onChange={e => setName(e.target.value)} onKeyDown={e => e.key === 'Enter' && create()} placeholder="e.g. Novel vocabulary" />
            <label className="label block mt-4 mb-1.5" htmlFor="list-desc">Description</label>
            <input id="list-desc" className="field" value={desc} onChange={e => setDesc(e.target.value)} placeholder="Optional" />
            <p className="label mt-4 mb-2">Highlight colour</p>
            <div className="flex flex-wrap gap-2.5">
                {LIST_COLORS.map(c => (
                    <button
                        key={c}
                        onClick={() => setColor(c)}
                        className="w-8 h-8 rounded-full"
                        style={{ background: c, boxShadow: color === c ? `0 0 0 2px var(--surface), 0 0 0 4px ${c}` : 'none' }}
                        aria-label={`Colour ${c}`}
                        aria-pressed={color === c}
                    />
                ))}
            </div>
        </Dialog>
    );
}
