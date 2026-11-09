#!/usr/bin/env python3
"""Kontroll statik (JO provë e Supabase): çdo veprim që thërret Swift ka funksion api_<veprimi> në SQL,
çdo funksion api_* ka grant/revoke, tabelat në `app` kanë RLS të aktivizuar dhe asnjë sekret/kod nuk është në skedarët e projektit."""
import re, pathlib, sys
root = pathlib.Path(__file__).resolve().parent.parent
sql = "\n".join(p.read_text(encoding="utf-8") for p in sorted((root/"Supabase/migrations").glob("*.sql")))
swift = "\n".join(p.read_text(encoding="utf-8") for p in (root/"App").glob("*.swift"))
errors = []
defined = set(m.lower() for m in re.findall(r"create (?:or replace )?function public\.api_(\w+)\(", sql))
used = set(a.lower() for a in re.findall(r'SchoolAPI\.call(?:<\w+>)?\("(\w+)"', swift))
used |= set(a.lower() for a in re.findall(r'(?:change|model\.change|store\.act)\("(\w+)"', swift))
used |= {"examcreate"}
# veprime që ekzistojnë vetëm te serveri Python ose trajtohen veçmas
ignore = {"login", "register", "recover", "logout"}
for a in sorted(used - defined - ignore): errors.append(f"Swift thërret '{a}' por SQL nuk ka public.api_{a}")
for needle in ("mfaRequired", "api_classDelete", "api_examDelete", "email_key", "mfa_required"):
    if needle not in sql: errors.append(f"SQL nuk përmban '{needle}' (0003)")
for needle in ("internal_issue_login_code", "api_loginCodeVerify", "session_2fa_ok"):
    if needle not in sql: errors.append(f"SQL nuk përmban '{needle}' (0004)")
edge = (root/"Supabase/functions/send-login-code/index.ts").read_text(encoding="utf-8")
if "SMTP_PASS" not in edge or re.search(r"(password|pass)\s*[:=]\s*[\"'][^\"']{6,}", edge, re.I): errors.append("Edge Function: fjalëkalimi SMTP duhet të vijë nga secrets, jo të shkruhet në kod")
ai = (root/"Supabase/functions/bosko-ai/index.ts").read_text(encoding="utf-8")
if 'Deno.env.get("GEMINI_API_KEY")' not in ai or re.search(r"AIza[0-9A-Za-z_-]{20,}", ai): errors.append("Edge Function bosko-ai: çelësi Gemini duhet të vijë nga secrets, jo të shkruhet në kod")
if "emailLogin" not in swift or "loginCodeVerify" not in swift or "send-login-code" not in swift: errors.append("Swift nuk përdor rrjedhën e kodit me email")
if "mfaSetup" not in swift or "classDelete" not in swift or "examDelete" not in swift: errors.append("Swift nuk përdor mfaSetup/classDelete/examDelete")
tables = re.findall(r"create table (?:if not exists )?app\.(\w+)", sql)
for t in tables:
    if not re.search(rf"alter table app\.{t} enable row level security", sql) and f"'{t}'" not in sql:
        errors.append(f"Tabela app.{t} nuk ka RLS të aktivizuar")
# Tabelat `app` arrihen vetëm përmes api_*. Përjashtim: skedarët në kova private (storage.objects),
# ku çdo rregull duhet të kalojë nga kontrollet sq_can_* në server. Kova → kontrollet e lejuara:
buckets = {"submissions": r"public\.sq_can_(upload|read|delete)\(name\)",          # 0006 · dorëzimet e testeve
           "projects": r"public\.sq_can_project_(upload|read)\(name\)"}         # projektet (#6)
for pol in re.findall(r"create policy[^;]*;", sql, re.I | re.S):
    if not re.search(r"on storage\.objects", pol): errors.append("Ka politikë RLS jashtë storage.objects; klienti duhet të përdorë vetëm api_*")
    elif not any(f"bucket_id = '{b}'" in pol and re.search(rx, pol) for b, rx in buckets.items()):
        errors.append("Politika e Storage duhet të kufizohet te një kovë e njohur dhe te kontrollet e saj sq_can_*")
for b in buckets:
    if f"('{b}', '{b}', false" not in sql: errors.append(f"Kova '{b}' duhet të krijohet si private")
if "user_metadata" in re.sub(r"--.*", "", sql).replace("Roli NUK lexohet nga user_metadata", ""): errors.append("SQL përmend user_metadata si burim")
for p in root.rglob("*"):
    if p.is_file() and p.suffix in {".swift", ".sql", ".md", ".py", ".plist", ".yml", ".sh"} and ".git" not in p.parts:
        t = p.read_text(encoding="utf-8", errors="ignore")
        if "service_role" in t and p.name not in {"SUPABASE-SETUP.md", "CLAUDE.md", "PROMPT-DON-BOSKO.md", "check_no_secrets.sh", "check_supabase_contract.py", "SchoolService.swift", "CONTRIBUTING.md", "RAPORTI-8.0.md", "README.md", "0001_auth_roles.sql", "0004_email_2fa.sql"}:
            errors.append(f"service_role përmendet te {p.relative_to(root)}")
print(f"Veprime Swift: {len(used)}, funksione SQL api_*: {len(defined)}, tabela app: {len(tables)}")
if errors: print("\n".join("GABIM: "+e for e in errors)); sys.exit(1)
print("PASS (kontroll statik; nuk është ekzekutim i SQL)")
