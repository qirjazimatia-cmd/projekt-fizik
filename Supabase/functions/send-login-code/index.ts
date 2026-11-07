// ScienceQuest · Edge Function `send-login-code`
// Dërgon kodin 6-shifror të hyrjes te emaili i llogarisë së kyçur (faktori i dytë). Kodi gjenerohet dhe ruhet (si hash) nga baza e të dhënave;
// kjo funksion vetëm e dërgon. Të dhënat e Gmail ruhen si SECRETS te Supabase (Edge Functions → Secrets), jo këtu dhe jo në Git.
// Secrets të nevojshme: SMTP_USER (adresa Gmail), SMTP_PASS (fjalëkalimi i aplikacionit të Google, 16 shkronja). Opsionale: SMTP_HOST (parazgjedhja smtp.gmail.com).
import { createClient } from "npm:@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

const headers = { "Content-Type": "application/json" };
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });

function sessionId(jwt: string): string | null {
  try {
    const part = jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const claims = JSON.parse(atob(part + "=".repeat((4 - (part.length % 4)) % 4)));
    return typeof claims.session_id === "string" ? claims.session_id : null;
  } catch { return null; }
}

// Heq hapësirat dhe thonjëzat që ngjiten rastësisht bashkë me sekretin.
const clean = (v: string | undefined) => (v ?? "").trim().replace(/^["']+|["']+$/g, "").trim();

Deno.serve(async (req) => {
  if (req.method !== "POST") return reply({ error: "Metodë e palejuar." }, 405);
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return reply({ error: "Seanca ka mbaruar. Hyr përsëri." }, 401);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { data, error } = await admin.auth.getUser(jwt);
  const user = data?.user;
  const session = sessionId(jwt);
  if (error || !user || !user.email || !session) {
    console.error("send-login-code: seancë e pavlefshme", error?.message ?? "pa përdorues/session_id");
    return reply({ error: "Seanca ka mbaruar. Hyr përsëri." }, 401);
  }
  if (!user.email_confirmed_at) return reply({ error: "Emaili nuk është konfirmuar." }, 403);

  const smtpUser = clean(Deno.env.get("SMTP_USER")).toLowerCase();
  // Google e shfaq fjalëkalimin e aplikacionit me hapësira ("abcd efgh ijkl mnop"); i heqim.
  const smtpPass = clean(Deno.env.get("SMTP_PASS")).replace(/\s+/g, "");
  if (!smtpUser || !smtpPass) {
    console.error("send-login-code: mungojnë SMTP_USER ose SMTP_PASS");
    return reply({ error: "Dërgimi i emailit nuk është konfiguruar nga administratori." }, 500);
  }

  const issued = await admin.rpc("internal_issue_login_code", { p_user: user.id, p_session: session });
  if (issued.error) {
    console.error("send-login-code: rpc", issued.error.message);
    return reply({ error: "Kodi nuk u krijua. Provo përsëri." }, 500);
  }
  if (issued.data?.error) return reply({ error: issued.data.error }, 429);
  const code: string = issued.data.code;

  const host = clean(Deno.env.get("SMTP_HOST")) || "smtp.gmail.com";
  // Porta 465 me TLS të plotë (Supabase bllokon portat 25 dhe 587).
  const client = new SMTPClient({
    connection: { hostname: host, port: 465, tls: true, auth: { username: smtpUser, password: smtpPass } },
  });
  try {
    await client.send({
      from: `ScienceQuest <${smtpUser}>`,
      to: user.email,
      subject: "Kodi i hyrjes ScienceQuest",
      content: `Kodi yt i hyrjes është: ${code}\nVlen 10 minuta. Nëse nuk po hyn ti, injoroje këtë email dhe ndrysho fjalëkalimin.`,
      html: `<h2>Kodi i hyrjes</h2><p>Kodi yt për ScienceQuest është:</p><p style="font-size:28px;font-weight:bold;letter-spacing:4px">${code}</p><p>Vlen 10 minuta. Nëse nuk po hyn ti, injoroje këtë email dhe ndrysho fjalëkalimin.</p>`,
    });
  } catch (e) {
    // Diagnozë pa zbuluar sekretin: adresa e maskuar, gjatësia e fjalëkalimit dhe nëse ka formën e fjalëkalimit të aplikacionit (16 shkronja a-z).
    const at = smtpUser.indexOf("@");
    const masked = at > 3 ? smtpUser.slice(0, 3) + "***" + smtpUser.slice(at) : "***" + (at >= 0 ? smtpUser.slice(at) : " (pa @)");
    console.error("send-login-code: SMTP dështoi", host, "user=" + masked, "userLen=" + smtpUser.length,
      "passLen=" + smtpPass.length, "appPasswordShape=" + /^[a-z]{16}$/.test(smtpPass),
      (e as Error)?.message ?? String(e));
    return reply({ error: "Emaili nuk u dërgua. Provo përsëri pas pak." }, 502);
  } finally {
    try { await client.close(); } catch (_) { /* injoro */ }
  }
  return reply({ ok: true });
});
