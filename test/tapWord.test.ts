import { test } from 'node:test';
import assert from 'node:assert/strict';
import { wordBounds } from '../src/lib/tapWord.ts';

test('a tap inside a word selects the whole word', () => {
    const text = 'Le petit chat dort';
    assert.deepEqual(wordBounds(text, 10), [9, 13]);
    assert.equal(text.slice(...wordBounds(text, 9)!), 'chat');
});

test('a tap on a space or punctuation selects nothing', () => {
    assert.equal(wordBounds('chat, dort', 4), null);
    assert.equal(wordBounds('chat  dort', 5), null);
});

test('the caret right after the last letter of the text still counts', () => {
    assert.deepEqual(wordBounds('chat', 4), [0, 4]);
});

test('apostrophes and accents stay inside the word', () => {
    const text = "aujourd'hui était";
    assert.equal(text.slice(...wordBounds(text, 2)!), "aujourd'hui");
    assert.equal(text.slice(...wordBounds(text, 14)!), 'était');
});

test('Japanese and Chinese are split into words, not whole lines', () => {
    const ja = '私は学校に行きます';
    const [a, b] = wordBounds(ja, 3, 'ja')!;
    assert.ok(b - a < ja.length, `got the whole line: ${ja.slice(a, b)}`);
    assert.ok(ja.slice(a, b).includes('校'));
});
