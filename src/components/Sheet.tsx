// A bottom sheet: the phone's version of the desktop's popover menus.

import type { ReactNode } from 'react';
import { useBack } from '../lib/back';

export default function Sheet({ title, onClose, children }: { title?: string; onClose: () => void; children: ReactNode }) {
    useBack(onClose);
    return (
        <div className="fixed inset-0 z-[170] flex flex-col justify-end" role="dialog" aria-label={title} data-back>
            <div className="absolute inset-0 anim-fade" style={{ background: 'rgba(0,0,0,0.32)' }} onClick={onClose} />
            <div className="sheet relative rounded-t-2xl px-2 pt-2 max-h-[85vh] overflow-auto anim-up" style={{ background: 'var(--surface)', boxShadow: 'var(--shadow-md)' }}>
                <div className="mx-auto mb-1 h-1 w-9 rounded-full" style={{ background: 'var(--surface-3)' }} />
                {title && <p className="label px-3 pt-2 pb-1">{title}</p>}
                {children}
            </div>
        </div>
    );
}

export function SheetItem({ icon, children, onClick, danger, disabled }: { icon?: ReactNode; children: ReactNode; onClick: () => void; danger?: boolean; disabled?: boolean }) {
    return (
        <button
            className="w-full flex items-center gap-3 h-12 px-3 rounded-lg text-left text-[15px] active:bg-[var(--surface-2)] disabled:opacity-40"
            style={danger ? { color: 'var(--danger)' } : undefined}
            onClick={onClick}
            disabled={disabled}
        >
            {icon}
            <span className="flex-1 min-w-0 truncate">{children}</span>
        </button>
    );
}
