import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
};

function findEntitlement(
  entitlements: Record<string, any> | undefined,
  expectedName: string,
) {
  const all = entitlements ?? {};

  if (all[expectedName] != null) {
    return { key: expectedName, value: all[expectedName] };
  }

  const expectedLower = expectedName.toLowerCase();
  for (const [key, value] of Object.entries(all)) {
    if (key.toLowerCase() === expectedLower) {
      return { key, value };
    }
  }

  return null;
}

function isEntitlementActive(entitlement: any): boolean {
  if (entitlement == null) return false;
  const expiry = entitlement.expires_date;
  if (expiry == null) return true; // lifetime / manually granted / promotional
  return new Date(expiry) > new Date();
}

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ── 1. Verify Supabase JWT ──────────────────────────────────────────────
    const authorization = req.headers.get("authorization");
    if (!authorization) {
      return new Response(JSON.stringify({
        error: "Unauthorized",
        detail: "Missing authorization header",
      }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const token = authorization.replace(/^Bearer\s+/i, '');

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceRoleKey) {
      return new Response(JSON.stringify({
        error: "Server misconfigured",
        detail: "SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is missing",
      }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const {
      data: { user },
      error: authError,
    } = await supabaseAdmin.auth.getUser(token);
    if (authError || !user) {
      return new Response(JSON.stringify({
        error: "Unauthorized",
        detail: authError?.message ?? "No user found in JWT",
      }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const userId = user.id;

    // ── 2. Check premium via RevenueCat REST API ────────────────────────────
    const revenueCatKey = Deno.env.get("REVENUECAT_SECRET_API_KEY");
    if (!revenueCatKey) {
      return new Response(JSON.stringify({ error: "Server misconfigured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const rcResp = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`,
      {
        headers: {
          Authorization: `Bearer ${revenueCatKey}`,
          "Content-Type": "application/json",
        },
      },
    );

    if (!rcResp.ok) {
      const rcBody = await rcResp.text();
      // If RevenueCat returns an error, deny access to be safe
      return new Response(JSON.stringify({
        error: "premium_required",
        detail: `RevenueCat lookup failed (${rcResp.status}): ${rcBody}`,
      }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const rcData = await rcResp.json();
    const expectedEntitlement = Deno.env.get("REVENUECAT_PREMIUM_ENTITLEMENT") ?? "premium";
    const entitlements = rcData?.subscriber?.entitlements as Record<string, any> | undefined;
    const matched = findEntitlement(entitlements, expectedEntitlement);
    const premiumEntitlement = matched?.value;
    const hasActivePremium = isEntitlementActive(premiumEntitlement);

    if (!hasActivePremium) {
      const allEntitlements = Object.keys(rcData?.subscriber?.entitlements || {}).join(", ");
      return new Response(JSON.stringify({ 
        error: "premium_required", 
        detail: `Expected '${expectedEntitlement}' entitlement not found or expired. Found: [${allEntitlements}]. Matched key: ${matched?.key ?? "none"}. Raw entitlement: ${JSON.stringify(premiumEntitlement)}` 
      }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── 3. Parse request body ───────────────────────────────────────────────
    const { phrase, targetLanguage = "Turkish" } = await req.json();
    if (!phrase || typeof phrase !== "string" || phrase.trim().length === 0) {
      return new Response(JSON.stringify({ error: "phrase is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── 4. Call Gemini 1.5 Flash ────────────────────────────────────────────
    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) {
      return new Response(JSON.stringify({ error: "Server misconfigured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const prompt = `You are a helpful language tutor. Explain the following word or phrase for a language learner.

Word/Phrase: "${phrase.trim()}"

Important:
- Write the ENTIRE response in ${targetLanguage}.
- Use markdown headings and bullet points for readability.

Please provide:
1. **Meaning** - a clear, concise definition
2. **Part of Speech** - (noun, verb, adjective, etc.)
3. **Example Sentences** - 3 natural example sentences in the source language, each followed by a translation in ${targetLanguage}
4. **Common Collocations** - words often used together with this word
5. **Nuances** - any important usage notes, register (formal/informal), or common mistakes

Do not truncate the response halfway. Complete all sections fully.`;

    const geminiModel = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";
    const geminiResp = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${geminiModel}:generateContent`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": geminiKey,
        },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: {
            temperature: 0.7,
            maxOutputTokens: 2048,
          },
        }),
      },
    );

    if (!geminiResp.ok) {
      const errBody = await geminiResp.text();
      let detail = `Gemini API request failed (${geminiResp.status}).`;
      try {
        const parsed = JSON.parse(errBody);
        const message = parsed?.error?.message ?? parsed?.message;
        if (message) {
          detail = `${detail} ${String(message)}`;
        }
      } catch {
        if (errBody.trim().length > 0) {
          detail = `${detail} ${errBody.substring(0, Math.min(errBody.length, 240))}`;
        }
      }
      console.error(`Gemini API error [${geminiResp.status}] model=${geminiModel}: ${errBody}`);
      return new Response(
        JSON.stringify({
          error: `Gemini error: ${geminiResp.status}`,
          detail,
        }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const geminiData = await geminiResp.json();
    const text =
      geminiData?.candidates?.[0]?.content?.parts?.[0]?.text ??
      "No response from Gemini.";

    return new Response(JSON.stringify({ text }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
