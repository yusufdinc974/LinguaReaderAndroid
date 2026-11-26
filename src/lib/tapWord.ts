// Tap a word to select it. On a phone, dragging a selection over a word is
// slow, so a single tap selects the whole word under the finger (a long press
// still makes a normal selection, for phrases).

const WORD_CHAR = /[\p{L}\p{M}\p{N}'’\-]/u;

/** The text position under a screen point, if it is inside `root`. */
function caretAt(x: number, y: number, root: Element): { node: Text; offset: number } | null {
    let node: Node | null = null;
    let offset = 0;
    const doc = document as Document & { caretPositionFromPoint?: (x: number, y: number) => { offsetNode: Node; offset: number } | null };
    if (doc.caretPositionFromPoint) {
        const p = doc.caretPositionFromPoint(x, y);
        if (p) ({ offsetNode: node, offset } = p);
    } else if (document.caretRangeFromPoint) {
        const r = document.caretRangeFromPoint(x, y);
        if (r) {
            node = r.startContainer;
            offset = r.startOffset;
        }
    }
    if (!node || node.nodeType !== Node.TEXT_NODE || !root.contains(node)) return null;
    return { node: node as Text, offset };
}

/** Start and end of the word around `offset` in `text`, or null if it isn't on a word. */
export function wordBounds(text: string, offset: number, locale?: string): [number, number] | null {
    if (typeof Intl !== 'undefined' && 'Segmenter' in Intl) {
        const seg = new Intl.Segmenter(locale, { granularity: 'word' });
        for (const s of seg.segment(text)) {
            const end = s.index + s.segment.length;
            // The caret can sit right after the last letter: count that as on the word
            if (offset >= s.index && (offset < end || (offset === end && offset === text.length))) {
                return s.isWordLike ? [s.index, end] : null;
            }
        }
        return null;
    }
    let a = offset;
    let b = offset;
    while (a > 0 && WORD_CHAR.test(text[a - 1])) a--;
    while (b < text.length && WORD_CHAR.test(text[b])) b++;
    return a < b ? [a, b] : null;
}

/**
 * Selects the word under (x, y) inside `root` and returns the selection's range,
 * or null if the tap wasn't on a word.
 */
export function selectWordAt(x: number, y: number, root: Element, locale?: string): Range | null {
    const caret = caretAt(x, y, root);
    if (!caret) return null;
    const bounds = wordBounds(caret.node.data, caret.offset, locale);
    if (!bounds) return null;
    const range = document.createRange();
    range.setStart(caret.node, bounds[0]);
    range.setEnd(caret.node, bounds[1]);
    // The tap must really be on the word, not in the margin beside a line
    const r = range.getBoundingClientRect();
    const slop = 6;
    if (x < r.left - slop || x > r.right + slop || y < r.top - slop || y > r.bottom + slop) return null;
    const sel = window.getSelection();
    sel?.removeAllRanges();
    sel?.addRange(range);
    return range;
}
