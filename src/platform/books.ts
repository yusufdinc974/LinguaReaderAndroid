// Books kept on the phone (copies made when they were opened; see openPdfDialog in api.ts).

import { openDb } from './db';
import { deleteFile } from './storage';

/** Deletes a book's copy and takes it out of the Library. Saved words stay. */
export async function removeBook(path: string) {
    if (!path.startsWith('books/')) return;
    const db = await openDb();
    db.run('DELETE FROM recent_pdfs WHERE path = ?', [path]);
    await deleteFile(path);
    for (const k of Object.keys(localStorage)) if (k.startsWith('thumb:') && k.includes(path)) localStorage.removeItem(k);
}
