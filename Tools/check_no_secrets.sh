#!/bin/bash
# Kontroll i thjeshtë për sekrete të përfshira gabimisht. Nuk zëvendëson një skanues të plotë (p.sh. gitleaks).
set -u
cd -- "$(dirname -- "$0")/.."
status=0
pattern='(service_role|SERVICE_ROLE|BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY|sk_live_|AKIA[0-9A-Z]{16}|eyJhbGciOi[A-Za-z0-9_-]{30,}|password *= *"[^"]+")'
if grep -rEn --exclude-dir=.git --exclude-dir=Verification --exclude=check_no_secrets.sh --exclude=check_supabase_contract.py --exclude=SchoolService.swift --exclude=0004_email_2fa.sql --exclude=index.ts --exclude=*.md --exclude=*.png "$pattern" . ; then
  echo "U GJET diçka që duket si sekret (shih më sipër)."; status=1
fi
for f in $(find . -path ./.git -prune -o \( -name '*.sqlite3' -o -name '*.p12' -o -name '*.pem' -o -name '*.mobileprovision' -o -name '.env' -o -name 'Config.xcconfig' \) -print); do
  echo "Skedar që nuk duhet futur në Git: $f"; status=1
done
[ $status -eq 0 ] && echo "Nuk u gjet asnjë sekret i dukshëm."
exit $status
