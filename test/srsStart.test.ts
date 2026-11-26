import { test } from 'node:test';
import assert from 'node:assert/strict';
import { initialSrs } from '../src/lib/srsStart.ts';

test('a new word is due today, a known one in two weeks', () => {
    const today = new Date().toISOString().split('T')[0];
    assert.equal(initialSrs(1).interval, 0);
    assert.equal(initialSrs(1).nextReviewDate, today);
    assert.equal(initialSrs(5).interval, 14);
    assert.equal(initialSrs(5).ef, 2.7);
});

test('levels match the desktop app', () => {
    assert.deepEqual([1, 2, 3, 4, 5].map(l => initialSrs(l).interval), [0, 1, 3, 7, 14]);
    assert.deepEqual([1, 2, 3, 4, 5].map(l => initialSrs(l).repetitions), [0, 1, 2, 3, 4]);
});
