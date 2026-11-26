// Bumps whenever words, lists or progress change anywhere (a review, an
// import, a word saved in the reader), so screens can reload.

import { useEffect, useState } from 'react';

export function useDataVersion() {
    const [v, setV] = useState(0);
    useEffect(() => window.electronAPI.onDataUpdated(() => setV(x => x + 1)), []);
    return v;
}
