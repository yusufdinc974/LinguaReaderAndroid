// Kept in step with set-word-familiarity in desktop/electron/main.ts.

/** Starting review schedule for the level picked on the word card (desktop: set-word-familiarity). */
export function initialSrs(level: number, ef = 2.5) {
    const table: Record<number, [number, number, number]> = {
        1: [2.5, 0, 0],
        2: [2.5, 1, 1],
        3: [2.5, 3, 2],
        4: [2.6, 7, 3],
        5: [2.7, 14, 4],
    };
    const [e, interval, repetitions] = table[level] ?? [ef, 0, 0];
    const next = new Date();
    next.setDate(next.getDate() + interval);
    return { ef: e, interval, repetitions, nextReviewDate: next.toISOString().split('T')[0] };
}
