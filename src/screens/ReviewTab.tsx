// The Review tab: what's due, and a way into a review for every list.

import { useCallback, useEffect, useState } from 'react';
import { GraduationCap } from 'lucide-react';
import { DEFAULT_LIST_COLOR } from '@desktop/lib/words';
import { listCounts, type ListCounts } from '../lib/reviewCounts';
import ReviewHost from './ReviewHost';

type Target = { listId: number | null; listName: string; total: number; due: number };

export default function ReviewTab() {
    const [data, setData] = useState<{ lists: ListCounts[]; total: number; due: number } | null>(null);
    const [target, setTarget] = useState<Target | null>(null);

    const load = useCallback(() => listCounts().then(setData).catch(() => setData({ lists: [], total: 0, due: 0 })), []);
    useEffect(() => {
        load();
    }, [load]);

    const exit = useCallback(() => {
        setTarget(null);
        load();
    }, [load]);

    return (
        <div className="h-full overflow-auto">
            <h1 className="text-[20px] font-semibold px-5 pt-6 pb-4">Review</h1>

            {data && data.total === 0 ? (
                <p className="px-5 text-[14px] muted">Save words while you read, and they'll come back here for review right before you'd forget them.</p>
            ) : (
                data && (
                    <>
                        <div className="mx-4 p-5 rounded-xl border" style={{ background: 'var(--surface)', borderColor: 'var(--border)' }}>
                            <p className="text-[34px] font-semibold leading-none tabular-nums">{data.due}</p>
                            <p className="muted mt-1.5 text-[14px]">{data.due === 1 ? 'word is' : 'words are'} due now, out of {data.total}</p>
                            <button className="btn btn-primary w-full h-12 mt-4 text-[15px]" onClick={() => setTarget({ listId: null, listName: 'All words', total: data.total, due: data.due })}>
                                <GraduationCap size={18} /> {data.due > 0 ? 'Review due words' : 'Practise all words'}
                            </button>
                        </div>

                        {data.lists.length > 0 && <h2 className="label px-5 mt-7 mb-2">By list</h2>}
                        <ul className="px-3 pb-6">
                            {data.lists.map(l => (
                                <li key={l.id}>
                                    <button
                                        className="w-full flex items-center gap-3 px-2 py-3 rounded-lg text-left active:bg-[var(--surface-2)] disabled:opacity-50"
                                        disabled={l.total === 0}
                                        onClick={() => setTarget({ listId: l.id, listName: l.name, total: l.total, due: l.due })}
                                    >
                                        <span className="dot" style={{ background: l.color || DEFAULT_LIST_COLOR }} />
                                        <span className="flex-1 min-w-0 truncate text-[15px] font-medium">{l.name}</span>
                                        {l.due > 0 && (
                                            <span className="text-[12px] font-medium px-2 py-0.5 rounded-full" style={{ background: 'var(--accent-soft)', color: 'var(--accent)' }}>
                                                {l.due} due
                                            </span>
                                        )}
                                        <span className="text-[13px] muted tabular-nums">{l.total}</span>
                                    </button>
                                </li>
                            ))}
                        </ul>
                    </>
                )
            )}

            {target && <ReviewHost {...target} onExit={exit} />}
        </div>
    );
}
