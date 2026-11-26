import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import { installApi } from './platform/api';
import { installBackButton } from './lib/back';
import '@desktop/index.css';
import './mobile.css';

// Pages are drawn at the screen's pixel density, which is 3× or more on many
// phones: 9× the pixels of a plain canvas for little visible gain. Drawing at
// 2× keeps text sharp and page turns fast. (Only scripts read this value; CSS
// layout and text rendering are unaffected.)
const realDpr = window.devicePixelRatio || 1;
Object.defineProperty(window, 'devicePixelRatio', { get: () => Math.min(realDpr, 2), configurable: true });

installBackButton();

// The desktop components read their data through window.electronAPI: install
// the phone's version (SQLite in app storage) before anything renders.
installApi()
    .then(() => {
        ReactDOM.createRoot(document.getElementById('root')!).render(
            <React.StrictMode>
                <App />
            </React.StrictMode>,
        );
    })
    .catch(e => {
        console.error('Starting failed:', e);
        document.getElementById('root')!.textContent = "LinguaReader couldn't start: " + String(e?.message ?? e);
    });
