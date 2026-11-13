// Don Bosko Connect · Edge Function `bosko-ai` (v8, #62)
// Bosko AI: asistenti i mësimeve me internet. Merr bisedën (dhe opsionalisht foto ose zë) nga aplikacioni dhe pyet një model AI.
//
// Privatësia (Apple App Review 5.1.2(i) dhe kërkesat §10):
//  • Asgjë nuk dërgohet pa lejen e përdoruesit: `api_aiAllow` kontrollon lejen e ruajtur në server dhe kufirin ditor, me token-in e vetë përdoruesit.
//  • Ofruesi i parë është Groq, që nuk i përdor të dhënat e API-së për trajnim. Gemini (niveli falas) përdoret vetëm si rezervë,
//    dhe kjo i thuhet përdoruesit te ekrani i lejes.
//  • Para dërgimit hiqen emailet dhe numrat e telefonit nga teksti.
//  • App-i e lexon tekstin e fotos në pajisje (Apple Vision); fotoja dërgohet vetëm kur teksti nuk mjafton (p.sh. vizatime).
//
// Zgjuarsia, pa pagesë:
//  • Ushtrimet (numra, njësi, «zgjidh/llogarit») shkojnë te një model që arsyeton hap pas hapi; bisedat e lehta te një model i shpejtë.
//  • Përgjigjet mbështeten te mësimet e shkollës që dërgon app-i dhe tregojnë burimin.
//  • Zëri shkruhet me Whisper te Groq (kupton shqipen), pastaj trajtohet si pyetje me shkrim.
//
// Çelësat ruhen si SECRETS te Supabase (Edge Functions → Secrets), jo këtu dhe jo në Git:
//   GROQ_API_KEY (falas, console.groq.com) · GEMINI_API_KEY (rezervë).
// Opsionale: GROQ_MODEL, GROQ_REASONING_MODEL, GROQ_VISION_MODEL, GROQ_STT_MODEL, GEMINI_MODEL.
import { createClient } from "npm:@supabase/supabase-js@2";

const headers = { "Content-Type": "application/json" };
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });
const clean = (v: string | undefined) => (v ?? "").trim().replace(/^["']+|["']+$/g, "").trim();

type Line = { role: "user" | "model"; text: string };
type Body = { messages?: Line[]; image?: { mime?: string; data?: string }; audio?: { mime?: string; data?: string }; role?: string; lesson?: string; mode?: string };

const roles: Record<string, string> = {
  student: "Po flet me një nxënës. Shpjego si mësues i durueshëm: hap pas hapi, me shembuj të thjeshtë. Kur të kërkon zgjidhjen e një ushtrimi, jepe të plotë me hapa dhe në fund kontrolloje.",
  parent: "Po flet me një prind që do të ndihmojë fëmijën. Shpjego pa terma të vështirë dhe jep këshilla si ta ndihmojë fëmijën në shtëpi.",
  teacher: "Po flet me një mësues. Mund të ndihmosh me plane mësimi, pyetje për klasën, ushtrime dhe mënyra shpjegimi.",
};

const HINTS = "MËNYRA «MOS MA THUAJ PËRGJIGJEN» është e ndezur: mos jep kurrë rezultatin përfundimtar dhe mos e zgjidh ushtrimin deri në fund. Jep vetëm sugjerimin e hapit të radhës (një hap në herë), bëj një pyetje udhëzuese dhe prit që nxënësi të provojë. Nëse nxënësi të jep një përgjigje, thuaj nëse është e saktë dhe ku ka gabuar, pa e zbuluar zgjidhjen.";
const VOICE = "Pyetja e fundit është regjistrim zëri në shqip. Fillimisht shkruaj në një rresht «Dëgjova: …» me pyetjen që kuptove, pastaj përgjigju. Nëse zëri nuk kuptohet, kërko ta përsërisë.";
const PROBLEM = "Kjo është një detyrë/ushtrim. Punoje me kujdes: 1) shkruaj të dhënat me njësitë, 2) formulën, 3) zëvendësimin, 4) rezultatin me njësi. Para se ta japësh, KONTROLLO: zëvendëso rezultatin te ekuacioni, kontrollo njësitë dhe nëse madhësia ka kuptim. Nëse gjen gabim, rregulloje pa e përmendur gabimin e brendshëm.";

function system(role: string, lesson: string, mode = "", voice = false, problem = false): string {
  return [
    "Je Bosko AI, asistenti i mësimeve i aplikacionit Don Bosko Connect të shkollës Don Bosko.",
    "Përgjigju gjithmonë në shqip standard, të qartë dhe të saktë gramatikisht (me ë dhe ç), përveç rastit kur përdoruesi të shkruan qartë në një gjuhë tjetër.",
    "Kupto mirë kërkesën: nëse pyetja është e paqartë ose i mungojnë të dhëna, bëj një pyetje të shkurtër sqaruese në vend që të hamendësosh. Nëse kërkesa ka disa pjesë, përgjigju secilës.",
    roles[role] ?? roles.student,
    mode === "hints" ? HINTS : "",
    voice ? VOICE : "",
    problem && mode !== "hints" ? PROBLEM : "",
    "Lëndët kryesore: matematikë, fizikë, kimi, biologji, por ndihmo edhe me lëndët e tjera të shkollës.",
    "Kur merr tekst nga një foto: fillimisht shkruaj shkurt çfarë kupton (ushtrimin), pastaj zgjidhe hap pas hapi. Nëse teksti është i paqartë, thuaje dhe kërko një foto më të qartë.",
    "Shkruaj tekst të thjeshtë: pa LaTeX dhe pa tituj markdown. Përdor x², √, ·, numra hapash (1., 2., 3.) dhe **të theksuar** vetëm për rezultatin.",
    "Mbaje përgjigjen të shkurtër (zakonisht nën 200 fjalë) dhe në fund bëj një pyetje të vogël ose jep një hap të ardhshëm.",
    "Nëse nuk je i sigurt, thuaje hapur. Mos shpik fakte, formula ose burime. Përdoruesit janë kryesisht të mitur: mos fol për tema të papërshtatshme dhe mos kërko të dhëna personale (emër, adresë, telefon, foto të vetes).",
    lesson
      ? "Materiali i shkollës (mësimet e aplikacionit, secili fillon me «• Titulli»). Mbështetu te ky material kur i përshtatet pyetjes dhe përdor të njëjtat terma. Kur e përdor, shto në fund një rresht «📘 Burimi: <titulli i mësimit>». Nëse pyetja është për diçka tjetër, përgjigju normalisht pa burim:\n" + lesson.slice(0, 6000)
      : "",
  ].filter(Boolean).join("\n");
}

// Heq të dhënat personale të dukshme para se teksti të dalë nga serveri ynë.
function scrub(text: string): string {
  return text
    .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, "[email]")
    .replace(/(?:\+|00)355[\s-]?\d{2}[\s-]?\d{3}[\s-]?\d{3,4}/g, "[telefon]")
    .replace(/\b06[789][\s-]?\d{3}[\s-]?\d{3,4}\b/g, "[telefon]");
}

// A është ushtrim që kërkon arsyetim (numra + veprime/njësi, ose fjalë si «zgjidh», «llogarit»)?
function isProblem(text: string): boolean {
  const t = text.toLowerCase();
  if (/\b(zgjidh|llogarit|gjej|vërteto|verteto|thjeshto|faktorizo|derivo|integro|sa (është|eshte|bën|ben)|ekuacion|inekuacion|problem|ushtrim|detyr)/.test(t)) return true;
  const digits = (t.match(/\d/g) ?? []).length;
  return digits >= 2 && /[=+\-*/×·^√%]|\b(m\/s|km|kg|mol|n\b|j\b|w\b|v\b|°c|cm|mm|ml|l\b)/.test(t);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return reply({ error: "Metodë e palejuar." }, 405);
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return reply({ error: "Hyr në llogari që të përdorësh Bosko AI me internet." }, 401);
  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { data, error } = await admin.auth.getUser(jwt);
  if (error || !data?.user) return reply({ error: "Seanca ka mbaruar. Hyr përsëri." }, 401);

  // 1) Leja dhe kufiri ditor: kontrollohen në bazën e të dhënave me token-in e vetë përdoruesit.
  const asUser = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    auth: { persistSession: false }, global: { headers: { Authorization: "Bearer " + jwt } },
  });
  const allow = await asUser.rpc("api_aiallow", { p_body: {} });
  if (allow.error) {
    console.error("bosko-ai: api_aiallow", allow.error.message);
    return reply({ error: allow.error.message || "Llogaria nuk është gati për Bosko AI." }, 403);
  }
  if (!allow.data?.allowed) {
    const code = allow.data?.code ?? "denied";
    return reply({ error: allow.data?.message ?? "Bosko AI nuk lejohet tani.", code }, code === "consent" ? 403 : 429);
  }

  const groqKey = clean(Deno.env.get("GROQ_API_KEY"));
  const geminiKey = clean(Deno.env.get("GEMINI_API_KEY"));
  if (!groqKey && !geminiKey) {
    console.error("bosko-ai: mungojnë GROQ_API_KEY dhe GEMINI_API_KEY");
    return reply({ error: "Bosko AI me internet nuk është konfiguruar ende (mungon çelësi te Supabase)." }, 503);
  }
  let body: Body;
  try { body = await req.json(); } catch { return reply({ error: "Kërkesë e pavlefshme." }, 400); }

  const messages: Line[] = (body.messages ?? [])
    .filter((m) => (m.role === "user" || m.role === "model") && typeof m.text === "string")
    .slice(-16)
    .map((m) => ({ role: m.role, text: scrub(m.text.slice(0, 4000)) }));
  if (messages.length === 0 || messages[messages.length - 1].role !== "user") return reply({ error: "Mungon pyetja." }, 400);
  while (messages.length && messages[0].role !== "user") messages.shift();

  const image = body.image?.data ? body.image : undefined;
  if (image && image.data!.length > 7_000_000) return reply({ error: "Fotoja është shumë e madhe." }, 413);
  const imageMime = ["image/jpeg", "image/png", "image/heic", "image/webp"].includes(image?.mime ?? "") ? image!.mime! : "image/jpeg";
  let audio = body.audio?.data ? body.audio : undefined;
  if (audio && audio.data!.length > 7_000_000) return reply({ error: "Regjistrimi është shumë i gjatë." }, 413);
  const audioMime = ["audio/mp4", "audio/m4a", "audio/aac", "audio/wav", "audio/mpeg", "audio/ogg", "audio/webm"].includes(audio?.mime ?? "") ? audio!.mime! : "audio/mp4";
  const mode = body.mode === "hints" ? "hints" : "";
  const role = body.role ?? "student";
  const lesson = scrub(body.lesson ?? "");
  const started = Date.now();
  const last = messages[messages.length - 1];

  // 2) Zëri → tekst me Whisper te Groq (pa trajnim). Nëse s'ka Groq ose dështon, zëri i shkon Gemini-t si më parë.
  let heard = "";
  if (audio && groqKey) {
    try {
      const bytes = Uint8Array.from(atob(audio.data!), (c) => c.charCodeAt(0));
      const form = new FormData();
      form.append("file", new Blob([bytes], { type: audioMime }), "pyetja.m4a");
      form.append("model", clean(Deno.env.get("GROQ_STT_MODEL")) || "whisper-large-v3-turbo");
      form.append("language", "sq");
      form.append("response_format", "json");
      const r = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", {
        method: "POST", headers: { Authorization: "Bearer " + groqKey }, body: form, signal: AbortSignal.timeout(20_000),
      });
      const j = await r.json().catch(() => ({}));
      if (r.ok && typeof j?.text === "string" && j.text.trim()) heard = scrub(j.text.trim());
      else console.error("bosko-ai: whisper", r.status, JSON.stringify(j).slice(0, 200));
    } catch (e) { console.error("bosko-ai: whisper", String(e).slice(0, 120)); }
    if (heard) { last.text = heard; audio = undefined; }
  }
  const voice = Boolean(audio);
  const problem = isProblem(messages.slice(-2).map((m) => m.text).join(" ")) || Boolean(image);
  const prompt = system(role, lesson, mode, voice, problem);

  // Groq: API e përputhshme me OpenAI. Fotoja shkon vetëm te modeli i vizionit.
  async function groq(model: string, ms: number, withImage = false): Promise<string | null> {
    if (!groqKey) return null;
    const chat: Record<string, unknown>[] = [{ role: "system", content: prompt }];
    messages.forEach((m, i) => {
      const isLast = i === messages.length - 1;
      if (isLast && withImage && image) {
        chat.push({ role: "user", content: [{ type: "text", text: m.text || "Zgjidhe ushtrimin në foto." },
          { type: "image_url", image_url: { url: `data:${imageMime};base64,${image.data}` } }] });
      } else chat.push({ role: m.role === "model" ? "assistant" : "user", content: m.text });
    });
    const payload: Record<string, unknown> = { model, messages: chat, temperature: problem ? 0.2 : 0.4, max_completion_tokens: 4096 };
    if (model.startsWith("openai/gpt-oss")) payload.reasoning_effort = problem ? "medium" : "low";
    const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST", headers: { "Content-Type": "application/json", Authorization: "Bearer " + groqKey },
      body: JSON.stringify(payload), signal: AbortSignal.timeout(ms),
    }).catch((e) => { console.error("bosko-ai: groq fetch", model, String(e).slice(0, 80)); return null; });
    if (!response) return null;
    const result = await response.json().catch(() => ({}));
    if (!response.ok) { console.error("bosko-ai: groq", model, response.status, JSON.stringify(result).slice(0, 200)); return null; }
    const text = String(result?.choices?.[0]?.message?.content ?? "").replace(/<think>[\s\S]*?<\/think>/g, "").trim();
    return text || null;
  }

  // Gemini (rezervë). Në nivelin falas Google mund t'i përdorë të dhënat; kjo i thuhet përdoruesit te leja.
  async function gemini(model: string, ms: number, signal?: AbortSignal): Promise<string | null> {
    if (!geminiKey) return null;
    const contents = messages.map((m) => ({ role: m.role, parts: [{ text: m.text || " " }] as Record<string, unknown>[] }));
    if (image) contents[contents.length - 1].parts.push({ inline_data: { mime_type: imageMime, data: image.data } });
    if (audio) contents[contents.length - 1].parts.push({ inline_data: { mime_type: audioMime, data: audio.data } });
    const timeout = AbortSignal.timeout(ms);
    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": geminiKey },
      body: JSON.stringify({ systemInstruction: { parts: [{ text: prompt }] }, contents, generationConfig: { temperature: problem ? 0.2 : 0.4, maxOutputTokens: 2048 } }),
      signal: signal ? AbortSignal.any([timeout, signal]) : timeout,
    }).catch((e) => { console.error("bosko-ai: fetch", model, String(e).slice(0, 80)); return null; });
    if (!response) return null;
    const result = await response.json().catch(() => ({}));
    if (!response.ok) { console.error("bosko-ai: gemini", model, response.status, JSON.stringify(result).slice(0, 200)); return null; }
    const text = (result?.candidates?.[0]?.content?.parts ?? []).map((p: { text?: string }) => p.text ?? "").join("").trim();
    return text || null;
  }

  async function geminiFast(): Promise<string | null> {
    const primary = clean(Deno.env.get("GEMINI_MODEL")) || "gemini-3.5-flash-lite";
    const fast = [...new Set([primary, "gemini-flash-lite-latest"])];
    const race = new AbortController();
    return await new Promise<string | null>((resolve) => {
      let left = fast.length;
      for (const model of fast) {
        gemini(model, 9_000, race.signal).then((t) => { if (t) { race.abort(); resolve(t); } else if (--left === 0) resolve(null); });
      }
    });
  }

  // 3) Zinxhiri i ofruesve: fillon me Groq (pa trajnim), pastaj Gemini si rezervë.
  const general = clean(Deno.env.get("GROQ_MODEL")) || "llama-3.3-70b-versatile";
  const reasoning = clean(Deno.env.get("GROQ_REASONING_MODEL")) || "openai/gpt-oss-120b";
  const vision = clean(Deno.env.get("GROQ_VISION_MODEL")) || "meta-llama/llama-4-scout-17b-16e-instruct";
  type Step = [string, () => Promise<string | null>];
  const steps: Step[] = [];
  if (audio) {
    steps.push(["gemini-lite", geminiFast], ["gemini-flash", () => gemini("gemini-flash-latest", 15_000)]);
  } else if (image) {
    steps.push(["groq-vision", () => groq(vision, 25_000, true)], ["gemini-lite", geminiFast], ["gemini-flash", () => gemini("gemini-flash-latest", 15_000)]);
  } else if (problem) {
    steps.push(["groq-reasoning", () => groq(reasoning, 30_000)], ["groq", () => groq(general, 12_000)], ["gemini-flash", () => gemini("gemini-flash-latest", 15_000)], ["gemini-lite", geminiFast]);
  } else {
    steps.push(["groq", () => groq(general, 12_000)], ["groq-reasoning", () => groq(reasoning, 20_000)], ["gemini-lite", geminiFast], ["gemini-flash", () => gemini("gemini-flash-latest", 15_000)]);
  }
  let text: string | null = null;
  let via = "";
  for (const [name, run] of steps) {
    text = await run();
    if (text) { via = name; break; }
  }
  if (text && heard && !/^dëgjova/i.test(text)) text = "Dëgjova: " + heard + "\n\n" + text;
  console.log("bosko-ai:", text ? "ok" : "fail", { ms: Date.now() - started, via, problem, image: Boolean(image), voice: Boolean(body.audio?.data), heard: Boolean(heard), mode, chars: text?.length ?? 0 });
  if (!text) return reply({ error: "Bosko AI është shumë i zënë tani (shërbimet falas janë të ngarkuara). Provo përsëri pas pak." }, 503);
  return reply({ text, via, remaining: allow.data?.remaining ?? null });
});
