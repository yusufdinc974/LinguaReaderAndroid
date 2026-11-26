package com.yusufdinc.linguareader;

import android.os.Handler;
import android.os.Looper;
import android.util.Base64;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Collections;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import ai.onnxruntime.OnnxTensor;
import ai.onnxruntime.OrtEnvironment;
import ai.onnxruntime.OrtSession;

/**
 * Text recognition models (the phone side of desktop/electron/ocr/worker.ts).
 *
 * Downloads the desktop's PaddleOCR ONNX models and runs them with ONNX
 * Runtime. The pipeline around the models (src/platform/ocrEngine.ts) stays in
 * TypeScript, shared with the desktop; this only loads models and runs them.
 * Recognition outputs come back as the best class per step, not every class's
 * score, which would be hundreds of megabytes for the Chinese/Japanese model.
 */
@CapacitorPlugin(name = "Ocr")
public class OcrPlugin extends Plugin {
    private static final long IDLE_MS = 3 * 60 * 1000;
    private final ExecutorService downloads = Executors.newSingleThreadExecutor();
    private final ExecutorService runs = Executors.newSingleThreadExecutor();
    private final Map<String, OrtSession> sessions = new HashMap<>();
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable release = () -> runs.execute(this::closeAll);

    private File dir() {
        File d = new File(getContext().getFilesDir(), "ocr-models");
        //noinspection ResultOfMethodCallIgnored
        d.mkdirs();
        return d;
    }

    private static boolean validName(String n) {
        return n != null && n.matches("^(det|rec-[a-z0-9]+)\\.(onnx|txt)$");
    }

    private JSArray installed() {
        JSArray out = new JSArray();
        File[] files = dir().listFiles();
        if (files == null) return out;
        for (File f : files) if (validName(f.getName())) out.put(f.getName());
        return out;
    }

    private void closeAll() {
        for (OrtSession s : sessions.values()) {
            try {
                s.close();
            } catch (Exception ignored) {
            }
        }
        sessions.clear();
    }

    private OrtSession session(String name) throws Exception {
        OrtSession s = sessions.get(name);
        if (s != null) return s;
        File f = new File(dir(), name);
        if (!f.exists()) throw new Exception("The text recognition model " + name + " isn't downloaded.");
        OrtSession.SessionOptions o = new OrtSession.SessionOptions();
        o.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT);
        o.setIntraOpNumThreads(Math.max(1, Math.min(4, Runtime.getRuntime().availableProcessors())));
        s = OrtEnvironment.getEnvironment().createSession(f.getPath(), o);
        sessions.put(name, s);
        return s;
    }

    @PluginMethod
    public void list(PluginCall call) {
        JSObject r = new JSObject();
        r.put("files", installed());
        call.resolve(r);
    }

    @PluginMethod
    public void remove(PluginCall call) {
        final JSArray names = call.getArray("names");
        runs.execute(() -> {
            closeAll();
            try {
                for (int i = 0; names != null && i < names.length(); i++) {
                    String n = names.getString(i);
                    //noinspection ResultOfMethodCallIgnored
                    if (validName(n)) new File(dir(), n).delete();
                }
            } catch (Exception ignored) {
            }
            JSObject r = new JSObject();
            r.put("files", installed());
            call.resolve(r);
        });
    }

    @PluginMethod
    public void text(PluginCall call) {
        String name = call.getString("name");
        if (!validName(name) || !name.endsWith(".txt")) {
            call.reject("Invalid file");
            return;
        }
        File f = new File(dir(), name);
        try (InputStream in = new FileInputStream(f)) {
            byte[] b = new byte[(int) f.length()];
            int off = 0;
            while (off < b.length) {
                int n = in.read(b, off, b.length - off);
                if (n < 0) break;
                off += n;
            }
            JSObject r = new JSObject();
            r.put("text", new String(b, 0, off, StandardCharsets.UTF_8));
            call.resolve(r);
        } catch (Exception e) {
            call.reject("Could not read " + name);
        }
    }

    /** files: [{name, urls: [...], sha256, bytes}]. Each file is checked; a file already present with the right hash is kept. */
    @PluginMethod
    public void install(PluginCall call) {
        final JSArray files = call.getArray("files");
        if (files == null) {
            call.reject("Nothing to download");
            return;
        }
        downloads.execute(() -> {
            File part = null;
            try {
                long total = 0;
                for (int i = 0; i < files.length(); i++) total += files.getJSONObject(i).optLong("bytes", 0);
                long done = 0;
                for (int i = 0; i < files.length(); i++) {
                    JSONObject f = files.getJSONObject(i);
                    String name = f.getString("name");
                    String sha = f.getString("sha256");
                    if (!validName(name) || !sha.matches("^[0-9a-f]{64}$")) throw new Exception("Invalid model");
                    File dest = new File(dir(), name);
                    if (dest.exists() && sha.equals(hashOf(dest))) {
                        done += f.optLong("bytes", 0);
                        continue;
                    }
                    part = new File(dir(), name + ".part");
                    JSONArray urls = f.getJSONArray("urls");
                    Exception last = null;
                    boolean ok = false;
                    for (int u = 0; u < urls.length() && !ok; u++) {
                        try {
                            String got = fetch(urls.getString(u), part, name, done, total);
                            if (!got.equals(sha)) throw new Exception("The download was damaged. Please try again.");
                            ok = true;
                        } catch (Exception e) {
                            last = e;
                        }
                    }
                    if (!ok) throw last != null ? last : new Exception("Download failed");
                    //noinspection ResultOfMethodCallIgnored
                    dest.delete();
                    if (!part.renameTo(dest)) throw new Exception("Could not save the model.");
                    part = null;
                    done += f.optLong("bytes", 0);
                }
                JSObject r = new JSObject();
                r.put("files", installed());
                call.resolve(r);
            } catch (Exception e) {
                //noinspection ResultOfMethodCallIgnored
                if (part != null) part.delete();
                String msg = e.getMessage();
                call.reject(msg != null && !msg.isEmpty() ? msg : "The download failed. Check the connection and try again.");
            }
        });
    }

    private String fetch(String url, File out, String name, long before, long total) throws Exception {
        if (!url.startsWith("https://")) throw new Exception("Invalid address");
        HttpURLConnection conn = (HttpURLConnection) new URL(url).openConnection();
        try {
            conn.setInstanceFollowRedirects(true);
            conn.setConnectTimeout(20000);
            conn.setReadTimeout(60000);
            int status = conn.getResponseCode();
            if (status != 200) throw new Exception("Download failed (" + status + ")");
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            long got = 0, last = 0;
            try (InputStream in = conn.getInputStream(); OutputStream o = new FileOutputStream(out)) {
                byte[] buf = new byte[1 << 16];
                int n;
                while ((n = in.read(buf)) > 0) {
                    o.write(buf, 0, n);
                    md.update(buf, 0, n);
                    got += n;
                    if (got - last > 512 * 1024) {
                        last = got;
                        JSObject p = new JSObject();
                        p.put("name", name);
                        p.put("got", before + got);
                        p.put("total", total);
                        notifyListeners("progress", p);
                    }
                }
            }
            return hex(md.digest());
        } finally {
            conn.disconnect();
        }
    }

    private static String hashOf(File f) {
        try (InputStream in = new FileInputStream(f)) {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] buf = new byte[1 << 16];
            int n;
            while ((n = in.read(buf)) > 0) md.update(buf, 0, n);
            return hex(md.digest());
        } catch (Exception e) {
            return "";
        }
    }

    private static String hex(byte[] d) {
        StringBuilder s = new StringBuilder();
        for (byte b : d) s.append(String.format(Locale.ROOT, "%02x", b));
        return s.toString();
    }

    /**
     * Runs a model on one float32 input: {model, input (base64, little-endian), dims, argmax}.
     * Returns {dims, data} or, with argmax, {dims, index, score}: the best class along the last axis.
     */
    @PluginMethod
    public void run(PluginCall call) {
        final String model = call.getString("model");
        final String input = call.getString("input");
        final JSArray dimsArr = call.getArray("dims");
        final boolean argmax = Boolean.TRUE.equals(call.getBoolean("argmax", false));
        if (!validName(model) || !model.endsWith(".onnx") || input == null || dimsArr == null) {
            call.reject("Invalid input");
            return;
        }
        handler.removeCallbacks(release);
        runs.execute(() -> {
            try {
                long[] shape = new long[dimsArr.length()];
                for (int i = 0; i < shape.length; i++) shape[i] = dimsArr.getLong(i);
                byte[] raw = Base64.decode(input, Base64.DEFAULT);
                FloatBuffer fb = toFloats(raw);
                OrtSession s = session(model);
                OrtEnvironment env = OrtEnvironment.getEnvironment();
                String inName = s.getInputNames().iterator().next();
                JSObject r = new JSObject();
                try (OnnxTensor t = OnnxTensor.createTensor(env, fb, shape);
                     OrtSession.Result res = s.run(Collections.singletonMap(inName, t))) {
                    OnnxTensor out = (OnnxTensor) res.get(0);
                    long[] os = out.getInfo().getShape();
                    FloatBuffer ob = out.getFloatBuffer();
                    JSArray od = new JSArray();
                    for (long d : os) od.put(d);
                    r.put("dims", od);
                    if (argmax) {
                        int C = (int) os[os.length - 1];
                        int steps = ob.remaining() / C;
                        ByteBuffer idx = ByteBuffer.allocate(steps * 4).order(ByteOrder.LITTLE_ENDIAN);
                        ByteBuffer sc = ByteBuffer.allocate(steps * 4).order(ByteOrder.LITTLE_ENDIAN);
                        for (int st = 0; st < steps; st++) {
                            int base = st * C;
                            int best = 0;
                            float bp = -Float.MAX_VALUE;
                            for (int c = 0; c < C; c++) {
                                float v = ob.get(base + c);
                                if (v > bp) {
                                    bp = v;
                                    best = c;
                                }
                            }
                            idx.putInt(best);
                            sc.putFloat(bp);
                        }
                        r.put("index", Base64.encodeToString(idx.array(), Base64.NO_WRAP));
                        r.put("score", Base64.encodeToString(sc.array(), Base64.NO_WRAP));
                    } else {
                        ByteBuffer bb = ByteBuffer.allocate(ob.remaining() * 4).order(ByteOrder.LITTLE_ENDIAN);
                        bb.asFloatBuffer().put(ob);
                        r.put("data", Base64.encodeToString(bb.array(), Base64.NO_WRAP));
                    }
                }
                call.resolve(r);
            } catch (Exception e) {
                String msg = e.getMessage();
                call.reject("Text recognition failed: " + (msg != null ? msg : e.getClass().getSimpleName()));
            } catch (OutOfMemoryError e) {
                closeAll();
                call.reject("Text recognition ran out of memory on this page.");
            } finally {
                // The models take a few hundred MB; let them go when unused
                handler.postDelayed(release, IDLE_MS);
            }
        });
    }

    private static FloatBuffer toFloats(byte[] raw) {
        ByteBuffer direct = ByteBuffer.allocateDirect(raw.length).order(ByteOrder.nativeOrder());
        FloatBuffer src = ByteBuffer.wrap(raw).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer();
        FloatBuffer dst = direct.asFloatBuffer();
        dst.put(src);
        dst.rewind();
        return dst;
    }
}
