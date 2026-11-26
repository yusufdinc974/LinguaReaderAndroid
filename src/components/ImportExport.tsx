// The desktop's Import / Export dialog and its Anki import step, together.

import { useEffect, useState } from 'react';
import type { WordList } from '@desktop/types';
import type { AnkiOpenResult } from '@desktop/../electron/ankiTypes';
import ImportExportDialog from '@desktop/components/ImportExportDialog';
import AnkiImportDialog from '@desktop/components/AnkiImportDialog';

interface Props {
    selectedId: number | null;
    onClose: () => void;
    /** A message to show, and the list an Anki import went into */
    onDone: (msg: string, listId?: number) => void;
}

export default function ImportExport({ selectedId, onClose, onDone }: Props) {
    const [lists, setLists] = useState<WordList[] | null>(null);
    const [deck, setDeck] = useState<AnkiOpenResult | null>(null);
    useEffect(() => {
        window.electronAPI.getWordLists().then(setLists);
    }, []);
    if (!lists) return null;
    if (deck) {
        return <AnkiImportDialog deck={deck} lists={lists} onClose={onClose} onDone={(listId, msg) => onDone(msg, listId)} />;
    }
    return (
        <ImportExportDialog
            lists={lists}
            selectedId={selectedId}
            onClose={onClose}
            onAnki={setDeck}
            onImported={() => { }}
            flash={msg => onDone(msg)}
        />
    );
}
