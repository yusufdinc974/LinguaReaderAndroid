import { wordKey } from '@desktop/lib/words';
import type { WordList } from '@desktop/types';

export interface ListCounts extends WordList {
    total: number;
    due: number;
}

/** Every list with how many words it has and how many are due for review now. */
export async function listCounts(): Promise<{ lists: ListCounts[]; total: number; due: number }> {
    const [lists, dueRows, all] = await Promise.all([
        window.electronAPI.getWordLists(),
        window.electronAPI.getWordsDueForReview(),
        window.electronAPI.getAllWords(),
    ]);
    const due = new Set(dueRows.map(r => r.word_lower));
    const counted = await Promise.all(
        lists.map(async l => {
            const words = await window.electronAPI.getWordsInList(l.id);
            return { ...l, total: words.length, due: words.filter(w => due.has(wordKey(w.word))).length };
        }),
    );
    return { lists: counted, total: all.length, due: all.filter(w => due.has(wordKey(w.word))).length };
}
