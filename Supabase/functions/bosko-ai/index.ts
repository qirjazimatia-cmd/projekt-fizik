// Don Bosko Connect · Edge Function `bosko-ai`
// Bosko AI: asistenti i mësimeve me internet. Merr bisedën (dhe një foto opsionale) nga aplikacioni dhe pyet Google Gemini
// (niveli falas i API-së). Çelësi ruhet si SECRET te Supabase (Edge Functions → Secrets → GEMINI_API_KEY), jo këtu dhe jo në Git.
// Opsionale: GEMINI_MODEL (parazgjedhja "gemini-flash-latest").
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
    lesson ? "Tema e bisedës nga mësimet e aplikacionit:\n" + lesson.slice(0, 1500) : "",
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

  // Kur një model është i zënë (503/429/500), provojmë përsëri dhe pastaj një model tjetër falas.
  const primary = clean(Deno.env.get("GEMINI_MODEL")) || "gemini-flash-latest";
  const models = [...new Set([primary, primary, "gemini-flash-lite-latest", "gemini-2.5-flash"])];
  const payload = JSON.stringify({
    systemInstruction: { parts: [{ text: system(body.role ?? "student", body.lesson ?? "") }] },
    contents,
    generationConfig: { temperature: 0.4, maxOutputTokens: 2048 },
  });
  const started = Date.now();
  let result: any = {};
  let status = 0;
  for (const [attempt, model] of [primary, ...models].entries()) {
    if (attempt > 0) await new Promise((r) => setTimeout(r, 700));
    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": key },
      body: payload,
    }).catch((e) => { console.error("bosko-ai: fetch", model, String(e)); return null; });
    status = response?.status ?? 0;
    result = response ? await response.json().catch(() => ({})) : {};
    if (response?.ok) break;
    console.error("bosko-ai: gemini", model, status, JSON.stringify(result).slice(0, 300));
    if (![0, 429, 500, 503, 404].includes(status)) break;
  }
  if (status < 200 || status >= 300) {
    if (status === 429 || status === 503) return reply({ error: "Bosko AI është shumë i zënë tani (shumë njerëz po e përdorin). Provo përsëri pas një minute." }, 503);
    return reply({ error: "Bosko AI nuk u përgjigj (" + status + "). Provo përsëri." }, 502);
  }
  const parts = result?.candidates?.[0]?.content?.parts ?? [];
  const text = parts.map((p: { text?: string }) => p.text ?? "").join("").trim();
  console.log("bosko-ai: ok", { ms: Date.now() - started, image: Boolean(image?.data), chars: text.length });
  if (!text) return reply({ error: "Nuk mund të përgjigjem për këtë. Provo ta pyesësh ndryshe." }, 422);
  return reply({ text });
});
