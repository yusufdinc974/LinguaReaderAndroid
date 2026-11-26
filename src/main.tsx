import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import { installApi } from './platform/api';
import '@desktop/index.css';
import './mobile.css';

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
