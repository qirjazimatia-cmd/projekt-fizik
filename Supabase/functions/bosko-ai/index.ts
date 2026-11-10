// Don Bosko Connect · Edge Function `bosko-ai`
// Bosko AI: asistenti i mësimeve me internet. Merr bisedën (dhe një foto opsionale) nga aplikacioni dhe pyet Google Gemini
// (niveli falas i API-së). Çelësi ruhet si SECRET te Supabase (Edge Functions → Secrets → GEMINI_API_KEY), jo këtu dhe jo në Git.
// Opsionale: GEMINI_MODEL (parazgjedhja "gemini-3.5-flash-lite"), GROQ_API_KEY (rezervë falas, shumë e shpejtë), GROQ_MODEL.
import { createClient } from "npm:@supabase/supabase-js@2";

const headers = { "Content-Type": "application/json" };
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });
const clean = (v: string | undefined) => (v ?? "").trim().replace(/^["']+|["']+$/g, "").trim();

type Line = { role: "user" | "model"; text: string };
type Body = { messages?: Line[]; image?: { mime?: string; data?: string }; role?: string; lesson?: string };

const roles: Record<string, string> = {
  student: "Po flet me një nxënës. Shpjego si mësues i durueshëm: hap pas hapi, me shembuj të thjeshtë. Kur të kërkon zgjidhjen e një ushtrimi, jepe të plotë me hapa dhe në fund kontrolloje.",
  parent: "Po flet me një prind që do të ndihmojë fëmijën. Shpjego pa terma të vështirë dhe jep këshilla si ta ndihmojë fëmijën në shtëpi.",
  teacher: "Po flet me një mësues. Mund të ndihmosh me plane mësimi, pyetje për klasën, ushtrime dhe mënyra shpjegimi.",
};

function system(role: string, lesson: string): string {
  return [
    "Je Bosko AI, asistenti i mësimeve i aplikacionit Don Bosko Connect të shkollës Don Bosko.",
    "Përgjigju gjithmonë në shqip standard, të qartë dhe të saktë gramatikisht, përveç rastit kur përdoruesi të shkruan qartë në një gjuhë tjetër.",
    roles[role] ?? roles.student,
    "Lëndët kryesore: matematikë, fizikë, kimi, biologji, por ndihmo edhe me lëndët e tjera të shkollës.",
    "Kur merr një foto: fillimisht shkruaj shkurt çfarë lexon (ushtrimin), pastaj zgjidhe hap pas hapi. Nëse fotoja nuk lexohet, thuaje dhe kërko një foto më të qartë.",
    "Shkruaj tekst të thjeshtë: pa LaTeX dhe pa tituj markdown. Përdor x², √, ·, numra hapash (1., 2., 3.) dhe **të theksuar** vetëm për rezultatin.",
    "Mbaje përgjigjen të shkurtër (zakonisht nën 200 fjalë) dhe në fund bëj një pyetje të vogël ose jep një hap të ardhshëm.",
    "Nëse nuk je i sigurt, thuaje hapur. Mos shpik fakte. Përdoruesit janë kryesisht të mitur: mos fol për tema të papërshtatshme dhe mos kërko të dhëna personale.",
    lesson ? "Materiali i shkollës (mësimet e aplikacionit). Mbështetu te ky material kur i përshtatet pyetjes dhe përdor të njëjtat terma; nëse pyetja është për diçka tjetër, përgjigju normalisht:\n" + lesson.slice(0, 6000) : "",
  ].filter(Boolean).join("\n");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return reply({ error: "Metodë e palejuar." }, 405);
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return reply({ error: "Hyr në llogari që të përdorësh Bosko AI me internet." }, 401);
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { data, error } = await admin.auth.getUser(jwt);
  if (error || !data?.user) return reply({ error: "Seanca ka mbaruar. Hyr përsëri." }, 401);

  const key = clean(Deno.env.get("GEMINI_API_KEY"));
  if (!key) {
    console.error("bosko-ai: mungon GEMINI_API_KEY");
    return reply({ error: "Bosko AI me internet nuk është konfiguruar ende (mungon çelësi te Supabase)." }, 503);
  }
  let body: Body;
  try { body = await req.json(); } catch { return reply({ error: "Kërkesë e pavlefshme." }, 400); }

  const messages = (body.messages ?? [])
    .filter((m) => (m.role === "user" || m.role === "model") && typeof m.text === "string")
    .slice(-16)
    .map((m) => ({ role: m.role, text: m.text.slice(0, 4000) }));
  if (messages.length === 0 || messages[messages.length - 1].role !== "user") return reply({ error: "Mungon pyetja." }, 400);
  // Gemini kërkon që biseda të nisë me përdoruesin.
  while (messages.length && messages[0].role !== "user") messages.shift();

  const contents = messages.map((m) => ({ role: m.role, parts: [{ text: m.text || " " }] as Record<string, unknown>[] }));
  const image = body.image;
  if (image?.data) {
    const mime = ["image/jpeg", "image/png", "image/heic", "image/webp"].includes(image.mime ?? "") ? image.mime! : "image/jpeg";
    if (image.data.length > 7_000_000) return reply({ error: "Fotoja është shumë e madhe." }, 413);
    contents[contents.length - 1].parts.push({ inline_data: { mime_type: mime, data: image.data } });
  }

  const payload = JSON.stringify({
    systemInstruction: { parts: [{ text: system(body.role ?? "student", body.lesson ?? "") }] },
    contents,
    generationConfig: { temperature: 0.4, maxOutputTokens: 2048 },
  });
  const started = Date.now();

  // Një pyetje te një model Gemini, me afat. Kthen tekstin ose null.
  async function gemini(model: string, ms: number, signal?: AbortSignal): Promise<string | null> {
    const timeout = AbortSignal.timeout(ms);
    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": key },
      body: payload,
      signal: signal ? AbortSignal.any([timeout, signal]) : timeout,
    }).catch((e) => { console.error("bosko-ai: fetch", model, String(e).slice(0, 80)); return null; });
    if (!response) return null;
    const result = await response.json().catch(() => ({}));
    if (!response.ok) { console.error("bosko-ai: gemini", model, response.status, JSON.stringify(result).slice(0, 200)); return null; }
    const text = (result?.candidates?.[0]?.content?.parts ?? []).map((p: { text?: string }) => p.text ?? "").join("").trim();
    return text || null;
  }

  // Rezerva opsionale: Groq (falas, shumë i shpejtë), vetëm për tekst. Aktivizohet me secret GROQ_API_KEY.
  async function groq(ms: number): Promise<string | null> {
    const groqKey = clean(Deno.env.get("GROQ_API_KEY"));
    if (!groqKey || image?.data) return null;
    const chat = [{ role: "system", content: system(body.role ?? "student", body.lesson ?? "") },
      ...messages.map((m) => ({ role: m.role === "model" ? "assistant" : "user", content: m.text }))];
    const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: "Bearer " + groqKey },
      body: JSON.stringify({ model: clean(Deno.env.get("GROQ_MODEL")) || "llama-3.3-70b-versatile", messages: chat, temperature: 0.4, max_tokens: 1500 }),
      signal: AbortSignal.timeout(ms),
    }).catch((e) => { console.error("bosko-ai: groq fetch", String(e).slice(0, 80)); return null; });
    if (!response) return null;
    const result = await response.json().catch(() => ({}));
    if (!response.ok) { console.error("bosko-ai: groq", response.status, JSON.stringify(result).slice(0, 200)); return null; }
    return (result?.choices?.[0]?.message?.content ?? "").trim() || null;
  }

  // 1) Dy modelet e shpejta "lite" njëkohësisht: fiton i pari që përgjigjet (zakonisht 1–3 s).
  const primary = clean(Deno.env.get("GEMINI_MODEL")) || "gemini-3.5-flash-lite";
  const fast = [...new Set([primary, "gemini-flash-lite-latest"])];
  const race = new AbortController();
  let text: string | null = await new Promise<string | null>((resolve) => {
    let left = fast.length;
    for (const model of fast) {
      gemini(model, 9_000, race.signal).then((t) => {
        if (t) { race.abort(); resolve(t); } else if (--left === 0) resolve(null);
      });
    }
  });
  let via = "gemini-lite";
  // 2) Nëse Google është i ngarkuar: Groq (nëse ka çelës), pastaj modeli Flash.
  if (!text) { text = await groq(10_000); via = "groq"; }
  if (!text) { text = await gemini("gemini-flash-latest", 15_000); via = "gemini-flash"; }
  console.log("bosko-ai:", text ? "ok" : "fail", { ms: Date.now() - started, via, image: Boolean(image?.data), chars: text?.length ?? 0 });
  if (!text) return reply({ error: "Bosko AI është shumë i zënë tani (shërbimi falas i Google është i ngarkuar). Provo përsëri pas pak." }, 503);
  return reply({ text });
});
