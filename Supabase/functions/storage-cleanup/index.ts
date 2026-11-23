// BrainSpark · Edge Function `storage-cleanup` (#13)
// Fshin skedarët jetimë (dorëzime testesh dhe skedarë projektesh) që mbetën pasi u fshi klasa, testi, projekti ose llogaria.
// Thirret nga app-i pas fshirjeve dhe një herë në ditë kur hyn një mësues. Kërkon një përdorues të kyçur, por nuk fshin kurrë
// skedarë që i përkasin ende një teste/projekti ekzistues: lista vjen nga `internal_storage_orphans` (vetëm serveri).
import { createClient } from "npm:@supabase/supabase-js@2";

const headers = { "Content-Type": "application/json" };
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });

Deno.serve(async (req) => {
  if (req.method !== "POST") return reply({ error: "Metodë e palejuar." }, 405);
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return reply({ error: "Seanca ka mbaruar." }, 401);
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { data: who, error: authError } = await admin.auth.getUser(jwt);
  if (authError || !who?.user) return reply({ error: "Seanca ka mbaruar." }, 401);

  const { data, error } = await admin.rpc("internal_storage_orphans", { p_limit: 500 });
  if (error) {
    console.error("storage-cleanup: rpc", error.message);
    return reply({ error: "Pastrimi nuk u krye." }, 500);
  }
  const byBucket = new Map<string, string[]>();
  for (const row of (data ?? []) as { bucket: string; name: string }[]) {
    if (row.bucket !== "submissions" && row.bucket !== "projects") continue;
    byBucket.set(row.bucket, [...(byBucket.get(row.bucket) ?? []), row.name]);
  }
  let deleted = 0;
  for (const [bucket, names] of byBucket) {
    for (let i = 0; i < names.length; i += 100) {
      const chunk = names.slice(i, i + 100);
      const { error: removeError } = await admin.storage.from(bucket).remove(chunk);
      if (removeError) console.error("storage-cleanup: remove", bucket, removeError.message);
      else deleted += chunk.length;
    }
  }
  if (deleted > 0) console.log("storage-cleanup: u fshinë", deleted, "skedarë jetimë");
  return reply({ ok: true, deleted });
});
