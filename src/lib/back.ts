// The Android back button (or back gesture) steps back inside the app.
//
// Screens register what "back" means for them while they're shown: close the
// word card, close the book, leave a review… The most recently registered one
// runs. With nothing registered (the main tabs), the app goes to the background
// like other Android apps, instead of closing.

import { useEffect, useRef } from 'react';
import { App } from '@capacitor/app';
import { isNative } from '../platform/storage';

type Handler = () => void;
const stack: { fn: React.RefObject<Handler> }[] = [];

export function handleBack(): boolean {
    const top = stack[stack.length - 1];
    if (!top) return false;
    top.fn.current?.();
    return true;
}

let installed = false;
/** Call once at startup. */
export function installBackButton() {
    if (installed) return;
    installed = true;
    if (isNative) {
        App.addListener('backButton', () => {
            if (!handleBack()) void App.minimizeApp();
        });
    } else {
        // In a browser, Escape stands in for the back button
        window.addEventListener('keydown', e => {
            if (e.key === 'Escape' && handleBack()) e.preventDefault();
        });
    }
}

/** While `active`, the back button runs `fn` (newest registration wins). */
export function useBack(fn: Handler, active = true) {
    const ref = useRef(fn);
    ref.current = fn;
    useEffect(() => {
        if (!active) return;
        const entry = { fn: ref };
        stack.push(entry);
        return () => {
            const i = stack.lastIndexOf(entry);
            if (i >= 0) stack.splice(i, 1);
        };
    }, [active]);
}
