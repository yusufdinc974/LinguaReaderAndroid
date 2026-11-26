// Saved words, by list, with a review button for each list.

import { useCallback, useEffect, useState } from 'react';
import { ChevronLeft, ChevronRight, GraduationCap, Trash2 } from 'lucide-react';
import { DEFAULT_LIST_COLOR, LEVELS } from '@desktop/lib/words';
import type { Word, WordList } from '@desktop/types';
import { useBack } from '../lib/back';
import { listCounts, type ListCounts } from '../lib/reviewCounts';
import ReviewHost from './ReviewHost';

export default function Words() {
    const [lists, setLists] = useState<ListCounts[]>([]);
    const [open, setOpen] = useState<WordList | null>(null);
    const [words, setWords] = useState<Word[]>([]);
    const [reviewing, setReviewing] = useState(false);

    const loadLists = useCallback(async () => setLists((await listCounts()).lists), []);

    useBack(() => setOpen(null), open !== null);

    const loadWords = useCallback(async (list: WordList) => setWords(await window.electronAPI.getWordsInList(list.id)), []);

    useEffect(() => {
        loadLists();
    }, [loadLists]);

    useEffect(() => {
        if (open) loadWords(open);
    }, [open, loadWords]);

    const remove = async (w: Word) => {
        if (!open) return;
        await window.electronAPI.removeWordFromList(w.id, open.id);
        await loadWords(open);
        await loadLists();
    };

    if (open) {
        return (
            <div className="h-full flex flex-col">
                <header className="flex items-center gap-1 px-2 h-[52px] border-b" style={{ borderColor: 'var(--border)' }}>
                    <button className="icon-btn tap" onClick={() => setOpen(null)} aria-label="Back to lists">
                        <ChevronLeft size={20} />
                    </button>
                    <span className="dot" style={{ background: open.color || DEFAULT_LIST_COLOR }} />
                    <h1 className="flex-1 min-w-0 text-[16px] font-semibold truncate">{open.name}</h1>
                    {words.length > 0 && (
                        <button className="btn btn-outline h-9 mr-1" onClick={() => setReviewing(true)}>
                            <GraduationCap size={16} /> Review
                        </button>
                    )}
                </header>
                <ul className="flex-1 overflow-auto divide-y" style={{ borderColor: 'var(--border)' }}>
                    {words.length === 0 && <li className="p-5 text-[14px] muted">No words in this list yet.</li>}
                    {words.map(w => (
                        <li key={w.id} className="flex items-start gap-3 px-4 py-3">
                            <span className="w-2 h-2 rounded-full mt-2 shrink-0" style={{ background: LEVELS[w.familiarity_level ?? 1]?.color }} title={LEVELS[w.familiarity_level ?? 1]?.label} />
                            <div className="min-w-0 flex-1">
                                <p className="serif text-[17px] font-semibold leading-snug break-words">{w.word}</p>
                                <p className="text-[14px] break-words" style={{ color: 'var(--text-2)' }}>{w.translation}</p>
                                {w.sentence_context && <p className="text-[12.5px] faint mt-1 line-clamp-2">{w.sentence_context}</p>}
                            </div>
                            <button className="icon-btn tap -mr-2" onClick={() => remove(w)} aria-label={`Remove ${w.word} from this list`}>
                                <Trash2 size={16} />
                            </button>
                        </li>
                    ))}
                </ul>
                {reviewing && (
                    <ReviewHost
                        listId={open.id}
                        listName={open.name}
                        total={words.length}
                        due={lists.find(l => l.id === open.id)?.due ?? 0}
                        onExit={() => {
                            setReviewing(false);
                            loadWords(open);
                            loadLists();
                        }}
                    />
                )}
            </div>
        );
    }

    return (
        <div className="h-full overflow-auto">
            <h1 className="text-[20px] font-semibold px-5 pt-6 pb-4">Words</h1>
            {lists.length === 0 && <p className="px-5 text-[14px] muted">Tap a word while reading and save it to a list. Your lists show up here.</p>}
            <ul className="px-3 pb-6">
                {lists.map(l => (
                    <li key={l.id}>
                        <button className="w-full flex items-center gap-3 px-2 py-3 rounded-lg text-left active:bg-[var(--surface-2)]" onClick={() => setOpen(l)}>
                            <span className="dot" style={{ background: l.color || DEFAULT_LIST_COLOR }} />
                            <span className="flex-1 min-w-0 truncate text-[15px] font-medium">{l.name}</span>
                            <span className="text-[13px] muted tabular-nums">{l.total}</span>
                            <ChevronRight size={16} className="faint" />
                        </button>
                    </li>
                ))}
            </ul>
        </div>
    );
}
