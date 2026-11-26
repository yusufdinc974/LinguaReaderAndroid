package com.yusufdinc.linguareader;

import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import org.json.JSONArray;

import java.io.BufferedInputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.zip.GZIPInputStream;

/**
 * Offline dictionaries (the phone side of desktop/electron/dictionary.ts).
 *
 * Each language is one SQLite file built by the desktop's
 * scripts/build-dictionary.mjs. Files are tens to hundreds of megabytes, so
 * they are downloaded, checked and unpacked here, and looked up with Android's
 * own SQLite, instead of being loaded into the page's memory.
 */
@CapacitorPlugin(name = "Dictionary")
public class DictionaryPlugin extends Plugin {
    private static final int SCHEMA = 1;
    private final ExecutorService downloads = Executors.newSingleThreadExecutor();
    private final ExecutorService lookups = Executors.newSingleThreadExecutor();
    private final Map<String, SQLiteDatabase> open = new HashMap<>();

    private File dir() {
        File d = new File(getContext().getFilesDir(), "dictionaries");
        //noinspection ResultOfMethodCallIgnored
        d.mkdirs();
        return d;
    }

    private static boolean validLang(String lang) {
        return lang != null && lang.matches("^[a-z]{2,3}$");
    }

    private JSArray installed() {
        JSArray out = new JSArray();
        File[] files = dir().listFiles();
        if (files == null) return out;
        for (File f : files) {
            String n = f.getName();
            if (n.matches("^[a-z]{2,3}\\.db$")) out.put(n.substring(0, n.length() - 3));
        }
        return out;
    }

    private synchronized SQLiteDatabase handle(String lang) {
        SQLiteDatabase db = open.get(lang);
        if (db != null && db.isOpen()) return db;
        File f = new File(dir(), lang + ".db");
        if (!f.exists()) return null;
        db = SQLiteDatabase.openDatabase(f.getPath(), null, SQLiteDatabase.OPEN_READONLY | SQLiteDatabase.NO_LOCALIZED_COLLATORS);
        open.put(lang, db);
        return db;
    }

    private synchronized void close(String lang) {
        SQLiteDatabase db = open.remove(lang);
        if (db != null) db.close();
    }

    @PluginMethod
    public void list(PluginCall call) {
        JSObject r = new JSObject();
        r.put("langs", installed());
        call.resolve(r);
    }

    @PluginMethod
    public void remove(PluginCall call) {
        String lang = call.getString("lang");
        if (validLang(lang)) {
            close(lang);
            //noinspection ResultOfMethodCallIgnored
            new File(dir(), lang + ".db").delete();
        }
        JSObject r = new JSObject();
        r.put("langs", installed());
        call.resolve(r);
    }

    /** Downloads a .db.gz, checks its SHA-256 and schema, and unpacks it. Sends "progress" events. */
    @PluginMethod
    public void install(PluginCall call) {
        final String lang = call.getString("lang");
        final String url = call.getString("url");
        final String sha256 = call.getString("sha256", "");
        final long size = call.getLong("bytes", 0L);
        if (!validLang(lang) || url == null || !url.startsWith("https://") || !sha256.matches("^[0-9a-f]{64}$")) {
            call.reject("Invalid dictionary");
            return;
        }
        downloads.execute(() -> {
            File part = new File(dir(), lang + ".db.part");
            HttpURLConnection conn = null;
            try {
                conn = (HttpURLConnection) new URL(url).openConnection();
                conn.setInstanceFollowRedirects(true);
                conn.setConnectTimeout(20000);
                conn.setReadTimeout(60000);
                int status = conn.getResponseCode();
                if (status != 200) throw new Exception("Download failed (" + status + ")");
                long total = conn.getContentLengthLong() > 0 ? conn.getContentLengthLong() : size;
                MessageDigest md = MessageDigest.getInstance("SHA-256");
                final long[] got = {0};
                final long[] last = {0};
                InputStream raw = new BufferedInputStream(conn.getInputStream(), 1 << 16) {
                    @Override
                    public synchronized int read(byte[] b, int off, int len) throws java.io.IOException {
                        int n = super.read(b, off, len);
                        if (n > 0) {
                            got[0] += n;
                            if (got[0] - last[0] > 512 * 1024) {
                                last[0] = got[0];
                                JSObject p = new JSObject();
                                p.put("lang", lang);
                                p.put("got", got[0]);
                                p.put("total", total);
                                notifyListeners("progress", p);
                            }
                        }
                        return n;
                    }
                };
                try (InputStream in = new GZIPInputStream(new DigestInputStream(raw, md), 1 << 16);
                     OutputStream out = new FileOutputStream(part)) {
                    byte[] buf = new byte[1 << 16];
                    int n;
                    while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
                }
                StringBuilder hex = new StringBuilder();
                for (byte b : md.digest()) hex.append(String.format(Locale.ROOT, "%02x", b));
                if (!hex.toString().equals(sha256)) throw new Exception("The dictionary download was damaged. Please try again.");

                SQLiteDatabase test = SQLiteDatabase.openDatabase(part.getPath(), null, SQLiteDatabase.OPEN_READWRITE | SQLiteDatabase.NO_LOCALIZED_COLLATORS);
                try {
                    String schema = null;
                    try (Cursor c = test.rawQuery("SELECT v FROM meta WHERE k = 'schema'", null)) {
                        if (c.moveToFirst()) schema = c.getString(0);
                    }
                    if (schema == null || Integer.parseInt(schema) != SCHEMA) throw new Exception("This dictionary needs a newer version of LinguaReader.");
                    // Older files lack the index used to find a word's other forms
                    test.execSQL("CREATE INDEX IF NOT EXISTS forms_entry ON forms (entry)");
                } finally {
                    test.close();
                }
                close(lang);
                File dest = new File(dir(), lang + ".db");
                //noinspection ResultOfMethodCallIgnored
                dest.delete();
                if (!part.renameTo(dest)) throw new Exception("Could not save the dictionary.");
                // SQLite may leave a journal next to the checked file
                //noinspection ResultOfMethodCallIgnored
                new File(dir(), lang + ".db.part-journal").delete();
                JSObject r = new JSObject();
                r.put("langs", installed());
                call.resolve(r);
            } catch (Exception e) {
                //noinspection ResultOfMethodCallIgnored
                part.delete();
                String msg = e.getMessage();
                call.reject(msg != null && !msg.isEmpty() ? msg : "The download failed. Check the connection and try again.");
            } finally {
                if (conn != null) conn.disconnect();
            }
        });
    }

    /** Runs read-only queries on a dictionary: [{sql, params}] → [[row, …], …]. */
    @PluginMethod
    public void query(PluginCall call) {
        final String lang = call.getString("lang");
        final JSArray queries = call.getArray("queries");
        if (!validLang(lang) || queries == null) {
            call.reject("Invalid query");
            return;
        }
        lookups.execute(() -> {
            try {
                SQLiteDatabase db = handle(lang);
                JSArray results = new JSArray();
                for (int i = 0; i < queries.length(); i++) {
                    JSArray rows = new JSArray();
                    if (db != null) {
                        org.json.JSONObject q = queries.getJSONObject(i);
                        String sql = q.getString("sql");
                        String lower = sql.trim().toLowerCase(Locale.ROOT);
                        if (!lower.startsWith("select")) throw new Exception("Only lookups");
                        JSONArray params = q.optJSONArray("params");
                        String[] args = new String[params == null ? 0 : params.length()];
                        for (int j = 0; j < args.length; j++) args[j] = params.get(j).toString();
                        try (Cursor c = db.rawQuery(sql, args)) {
                            String[] cols = c.getColumnNames();
                            while (c.moveToNext()) {
                                JSObject row = new JSObject();
                                for (int k = 0; k < cols.length; k++) {
                                    switch (c.getType(k)) {
                                        case Cursor.FIELD_TYPE_NULL: row.put(cols[k], org.json.JSONObject.NULL); break;
                                        case Cursor.FIELD_TYPE_INTEGER: row.put(cols[k], c.getLong(k)); break;
                                        case Cursor.FIELD_TYPE_FLOAT: row.put(cols[k], c.getDouble(k)); break;
                                        default: row.put(cols[k], c.getString(k));
                                    }
                                }
                                rows.put(row);
                            }
                        }
                    }
                    results.put(rows);
                }
                JSObject r = new JSObject();
                r.put("results", results);
                call.resolve(r);
            } catch (Exception e) {
                call.reject("Lookup failed: " + e.getMessage());
            }
        });
    }
}
