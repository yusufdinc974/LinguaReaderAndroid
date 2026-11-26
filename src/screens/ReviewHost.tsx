// Runs the desktop app's review (desktop/src/pages/Review.tsx) and its setup
// (ReviewSetup) unchanged. Both navigate with react-router, so they get a
// small in-memory router of their own: "/" is the setup, "/review" the session,
// and leaving to "/words" closes this.

import { useEffect } from 'react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import ReviewSetup from '@desktop/components/ReviewSetup';
import Review from '@desktop/pages/Review';
import { useBack } from '../lib/back';

interface Props {
    listId: number | null;
    listName: string;
    total: number;
    due: number;
    onExit: () => void;
}

function Leave({ onExit }: { onExit: () => void }) {
    useEffect(() => onExit(), [onExit]);
    return null;
}

export default function ReviewHost({ listId, listName, total, due, onExit }: Props) {
    useBack(onExit);
    return (
        <MemoryRouter initialEntries={['/']}>
            <Routes>
                <Route
                    path="/"
                    element={
                        <div className="fixed inset-0 z-[150] flex items-end" style={{ background: 'rgba(0,0,0,0.35)' }} onClick={onExit}>
                            <div className="review-setup-sheet w-full rounded-t-2xl p-1 pb-[max(env(safe-area-inset-bottom),8px)] anim-in" style={{ background: 'var(--surface)' }} onClick={e => e.stopPropagation()}>
                                <p className="text-[16px] font-semibold px-4 pt-4">Review {listName}</p>
                                <ReviewSetup listId={listId} listName={listName} total={total} due={due} onClose={onExit} />
                            </div>
                        </div>
                    }
                />
                <Route
                    path="/review"
                    element={
                        <div className="review-host fixed inset-0 z-[150]" style={{ paddingTop: 'env(safe-area-inset-top)', background: 'var(--bg)' }}>
                            <Review />
                        </div>
                    }
                />
                <Route path="*" element={<Leave onExit={onExit} />} />
            </Routes>
        </MemoryRouter>
    );
}
