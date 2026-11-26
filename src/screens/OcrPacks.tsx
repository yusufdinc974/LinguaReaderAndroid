// Settings › Text in images: download the desktop's recognition models, one pack per script.

import { useEffect, useState } from 'react';
import { Check, Download, Loader2, Trash2 } from 'lucide-react';
import { SCRIPTS, type ScriptId } from '@desktop/../electron/ocr/types';
import { installPack, packBytes, removePack } from '../platform/ocrModels';
import { refreshOcrModels } from '../platform/ocr';

const mb = (b: number) => `${Math.round(b / 1e6)} MB`;

export default function OcrPacks() {
    const [have, setHave] = useState<ScriptId[] | null>(null);
    const [busy, setBusy] = useState<{ id: ScriptId; got: number; total: number } | null>(null);
    const [error, setError] = useState('');

    useEffect(() => {
        refreshOcrModels().then(setHave);
    }, []);

    const add = async (id: ScriptId) => {
        setError('');
        setBusy({ id, got: 0, total: 0 });
        try {
            await installPack(id, (got, total) => setBusy({ id, got, total }));
        } catch (e) {
            setError((e as Error).message || 'The download failed. Check the connection and try again.');
        }
        setHave(await refreshOcrModels());
        setBusy(null);
    };

    const remove = async (id: ScriptId) => {
        setError('');
        await removePack(id).catch(e => setError((e as Error).message));
        setHave(await refreshOcrModels());
    };

    if (!have) return null;
    const main = have.includes('v6');
    return (
        <div className="mt-4">
            <p className="text-[13px] muted leading-snug">
                {main
                    ? 'Downloaded languages are read on the phone, without internet. Pages in a downloaded script are found automatically.'
                    : 'Latin alphabets are read without a download. To read other scripts, or for the desktop app\'s accuracy, download them here.'}
            </p>
            <div className="mt-2 grid">
                {SCRIPTS.map(s => {
                    const installed = have.includes(s.id);
                    const running = busy?.id === s.id;
                    // Other scripts also need the main pack; its size is added the first time.
                    const size = packBytes(s.id) + (!main && s.id !== 'v6' ? packBytes('v6') : 0);
                    return (
                        <div key={s.id} className="flex items-center gap-3 py-2.5 border-b last:border-b-0" style={{ borderColor: 'var(--border)' }} data-ocr-pack={s.id}>
                            <div className="flex-1 min-w-0">
                                <div className="text-[14.5px] font-medium">{s.label}</div>
                                <div className="text-[12px] faint leading-snug line-clamp-2">{s.languages}</div>
                                {running && busy.total > 0 && (
                                    <div className="mt-1.5 h-1 rounded-full overflow-hidden" style={{ background: 'var(--border)' }}>
                                        <div className="h-full" style={{ width: `${Math.min(100, (busy.got / busy.total) * 100)}%`, background: 'var(--accent)' }} />
                                    </div>
                                )}
                            </div>
                            {installed ? (
                                <>
                                    <Check size={16} style={{ color: 'var(--accent)' }} aria-label="Downloaded" />
                                    <button className="btn btn-ghost h-9 w-9 p-0" aria-label={`Remove ${s.label}`} onClick={() => remove(s.id)} disabled={!!busy}>
                                        <Trash2 size={16} />
                                    </button>
                                </>
                            ) : (
                                <button className="btn btn-outline h-9 text-[13px] gap-1.5" onClick={() => add(s.id)} disabled={!!busy} aria-label={`Download ${s.label}`}>
                                    {running ? <Loader2 size={14} className="animate-spin" /> : <Download size={14} />}
                                    {running && busy.total > 0 ? `${Math.round((busy.got / busy.total) * 100)}%` : mb(size)}
                                </button>
                            )}
                        </div>
                    );
                })}
            </div>
            {main && <p className="text-[12px] faint mt-2">Removing “{SCRIPTS[0].label}” removes all of them: the others need it to find text.</p>}
            {error && <p className="text-[13px] mt-2" style={{ color: 'var(--danger, #c0392b)' }}>{error}</p>}
        </div>
    );
}
