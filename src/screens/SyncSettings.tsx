// Settings → Sync with desktop: scan the code the desktop shows (Settings →
// Phone sync → Show pairing code), or type its address and code.

import { useState } from 'react';
import { Check, Loader2, QrCode } from 'lucide-react';
import { BarcodeFormat, BarcodeScanner } from '@capacitor-mlkit/barcode-scanning';
import { isNative } from '../platform/storage';
import { parsePairing, syncWithDesktop, type Pairing, type SyncStep } from '../platform/sync';
import { notifyDataChanged } from '../platform/api';

const STEP: Record<SyncStep, string> = {
    connecting: 'Connecting to your computer…',
    uploading: 'Sending this phone’s words…',
    downloading: 'Getting the computer’s words…',
};

export default function SyncSettings() {
    const [step, setStep] = useState<SyncStep | null>(null);
    const [result, setResult] = useState<string | null>(null);
    const [error, setError] = useState<string | null>(null);
    const [manual, setManual] = useState(false);
    const [address, setAddress] = useState('');
    const [code, setCode] = useState('');

    const run = async (p: Pairing) => {
        setError(null);
        setResult(null);
        try {
            const r = await syncWithDesktop(p, setStep);
            notifyDataChanged();
            const got = r.received;
            setResult(
                `Synced. The computer got ${r.sent.words} new ${r.sent.words === 1 ? 'word' : 'words'}; this phone got ${got.words} new ${got.words === 1 ? 'word' : 'words'}` +
                (got.lists ? ` in ${got.lists} new ${got.lists === 1 ? 'list' : 'lists'}` : '') +
                (got.updated ? `, and newer review progress for ${got.updated}` : '') + '.',
            );
        } catch (e) {
            setError(String((e as Error)?.message ?? e));
        } finally {
            setStep(null);
        }
    };

    const scan = async () => {
        setError(null);
        try {
            const { available } = await BarcodeScanner.isGoogleBarcodeScannerModuleAvailable();
            if (!available) {
                await BarcodeScanner.installGoogleBarcodeScannerModule();
                setError('The code scanner is being installed by Google Play. Try again in a moment.');
                return;
            }
            const { barcodes } = await BarcodeScanner.scan({ formats: [BarcodeFormat.QrCode] });
            const text = barcodes[0]?.rawValue;
            if (!text) return;
            const p = parsePairing(text);
            if (!p) setError("That isn't a LinguaReader pairing code.");
            else await run(p);
        } catch (e) {
            const msg = String((e as Error)?.message ?? e);
            if (!/cancel/i.test(msg)) setError(`Couldn't scan: ${msg}`);
        }
    };

    const submitManual = () => {
        const p = parsePairing(address, code);
        if (!p) setError('Type the address as it shows under the code on the computer (like 192.168.1.20:51234), and the code.');
        else run(p);
    };

    return (
        <div>
            <p className="text-[13.5px] muted">On your computer, open LinguaReader → Settings → Phone sync → <strong className="font-medium" style={{ color: 'var(--text)' }}>Show pairing code</strong>.</p>
            <div className="flex flex-wrap gap-2 mt-3">
                {isNative && (
                    <button className="btn btn-primary h-11" onClick={scan} disabled={step !== null}>
                        <QrCode size={16} /> Scan the code
                    </button>
                )}
                {/* The desktop shows the code only inside the QR code; typing it is for testing in a browser */}
                {!isNative && <button className="btn btn-outline h-11" onClick={() => setManual(m => !m)} disabled={step !== null}>Type it instead</button>}
            </div>
            {manual && (
                <div className="grid gap-2 mt-3">
                    <input className="field" placeholder="Address, like 192.168.1.20:51234" value={address} onChange={e => setAddress(e.target.value)} inputMode="url" aria-label="Computer address" autoCapitalize="off" autoCorrect="off" />
                    <input className="field font-mono" placeholder="Code" value={code} onChange={e => setCode(e.target.value)} aria-label="Pairing code" autoCapitalize="off" autoCorrect="off" spellCheck={false} />
                    <button className="btn btn-primary h-11" onClick={submitManual} disabled={step !== null || !address.trim() || !code.trim()}>Sync now</button>
                </div>
            )}
            {step && <p className="mt-3 text-[13.5px] flex items-center gap-2" role="status"><Loader2 size={15} className="animate-spin" /> {STEP[step]}</p>}
            {result && <p className="mt-3 text-[13.5px] flex items-start gap-2" style={{ color: 'var(--ok, var(--accent))' }} role="status"><Check size={15} className="mt-0.5 shrink-0" /> {result}</p>}
            {error && <p className="mt-3 text-[13.5px]" style={{ color: 'var(--danger)' }} role="alert">{error}</p>}
        </div>
    );
}
