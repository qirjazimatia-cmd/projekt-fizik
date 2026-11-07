#!/usr/bin/env python3
"""ScienceQuest 7: school-owned service; Python 3.11+, standard library only.
No external auth/database vendor. See README.md for TLS, backups and deployment.
"""
import argparse, base64, contextlib, hashlib, hmac, json, math, os, re, secrets, sqlite3, ssl, time, uuid
from decimal import Decimal, InvalidOperation
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import BoundedSemaphore

ROLES = ('Nxënës', 'Mësues', 'Prind')
SUBJECTS = ('Matematikë', 'Fizikë', 'Kimi', 'Biologji')
INVITE_MAX_FAILURES = 5      # gabime të lejuara për një ftesë; pastaj ftesa bllokohet dhe administratori jep një të re
INVITE_DAYS = 7

def uid(): return str(uuid.uuid4())
def digest(value): return hashlib.sha256(value.encode()).hexdigest()
def dumps(value): return json.dumps(value, ensure_ascii=False, allow_nan=False)
def norm_email(value):
    value = str(value).strip().casefold()
    require(len(value) <= 254 and re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', value), 'Emaili nuk është i vlefshëm.')
    return value

def password_hash(password, salt=None):
    require(isinstance(password, str) and 10 <= len(password) <= 128, 'Fjalëkalimi duhet të ketë 10–128 karaktere.')
    salt = salt or secrets.token_bytes(16)
    return salt.hex() + ':' + hashlib.scrypt(password.encode(), salt=salt, n=131072, r=8, p=1, maxmem=256*1024*1024).hex()

def password_ok(password, stored):
    try:
        salt, _ = stored.split(':')
        return hmac.compare_digest(password_hash(password, bytes.fromhex(salt)), stored)
    except (ValueError, Fault): return False

class Fault(Exception):
    def __init__(self, message, status=400): self.message, self.status = message, status

def require(condition, message='Veprimi nuk lejohet.', status=400):
    if not condition: raise Fault(message, status)

def text(body, key, maximum=2000):
    value = body.get(key, '')
    require(isinstance(value, str) and len(value) <= maximum, 'Teksti është shumë i gjatë ose i pavlefshëm.')
    return value.strip()

def integer(body, key, lo, hi, default=None):
    value = body.get(key, default)
    require(type(value) is int and lo <= value <= hi, 'Vlerë numerike e pavlefshme: '+key)
    return value

def numeric(value):
    try:
        parts = str(value).strip().replace(',', '.').replace('−', '-').split('/')
        if len(parts) not in (1, 2): return None
        a = Decimal(parts[0].strip())
        if len(parts) == 2: a /= Decimal(parts[1].strip())
        return a if a.is_finite() else None
    except (InvalidOperation, ZeroDivisionError): return None

def correct(question, answer):
    if question['kind'] == 'number':
        a, b = numeric(answer), numeric(question['answer'])
        return a is not None and b is not None and abs(a-b) <= Decimal(str(question['tolerance'])) + Decimal('1e-12')
    return str(answer).strip().casefold() == question['answer'].strip().casefold()

def question(raw):
    require(isinstance(raw, dict), 'Pyetje e pavlefshme.')
    q = {k:text(raw,k,4000) for k in ('prompt','answer','explanation','unit')}
    q['id'] = uid(); q['kind'] = raw.get('kind', 'number')
    require(q['prompt'] and q['answer'] and q['kind'] in ('number','text'), 'Plotëso pyetjen dhe përgjigjen.')
    q['points'] = integer(raw,'points',1,20,4)
    tol = raw.get('tolerance', 0.005)
    require(type(tol) in (int,float) and math.isfinite(tol) and 0 <= tol <= 1000, 'Tolerancë e pavlefshme.')
    q['tolerance'] = tol
    if q['kind'] == 'number': require(numeric(q['answer']) is not None, 'Përgjigjja duhet të jetë numër ose thyesë.')
    return q

def generated(subject, level):
    """Server-only variants: these answers are never shipped with the client."""
    a,b,c = [secrets.randbelow(8)+2 for _ in range(3)]
    mode = secrets.randbelow(3)
    p, answer, rule, unit = '',0,'',''
    if subject == 'Matematikë':
        if level == 1:
            if mode == 0: p=f'Një çantë kushton {a*20} €. Zbritja është {b*5}%. Sa paguhet?'; answer=a*20*(1-b*.05); rule='Çmimi × (1 − përqindja/100).'; unit='€'
            elif mode == 1: p=f'Zgjidh {a}x + {b} = {a*c+b}.'; answer=c; rule='Zbrit termin konstant, pastaj pjesëto me koeficientin.'
            else: p=f'Trekëndëshi ka bazë {2*a} cm dhe lartësi {b} cm. Gjej sipërfaqen.'; answer=a*b; rule='S = bh/2.'; unit='cm²'
        elif level == 2:
            if mode == 0: p=f'Rrënjët e x² − {a+b}x + {a*b}=0 janë pozitive. Gjej rrënjën më të madhe.'; answer=max(a,b); rule=f'Faktorizo (x−{a})(x−{b}).'
            elif mode == 1: p=f'2x+y={2*a+b} dhe x−y={a-b}. Gjej x.'; answer=a; rule='Mblidh ekuacionet: 3x është shuma e anëve të djathta.'
            else: p=f'f(x)={a}x−{b}. Gjej x kur f(x)={a*c-b}.'; answer=c; rule='Zgjidh ekuacionin linear.'
        elif level == 3:
            if mode == 0: p=f'Gjej log₂({2**a}) + log₂({2**b}).'; answer=a+b; rule='log₂(2^n)=n.'
            elif mode == 1: p=f'Progresioni aritmetik ka a₁={a}, d={b}. Gjej S_{c}.'; answer=c*(2*a+(c-1)*b)/2; rule='Sₙ=n[2a₁+(n−1)d]/2.'
            else: p=f'Nga {a+b} nxënës, zgjidhen 2 pa rend. Sa çifte ka?'; answer=(a+b)*(a+b-1)/2; rule='C(n,2)=n(n−1)/2.'
        elif level == 4:
            if mode == 0: p=f'f(x)={a}x³−{b}x. Gjej f′({c}).'; answer=3*a*c*c-b; rule='f′(x)=3ax²−b.'
            elif mode == 1: p=f'Gjej integralin nga 0 në {c} të ({2*a}x+{b}) dx.'; answer=a*c*c+b*c; rule='Primitivi është ax²+bx; zbrit vlerat në kufij.'
            else: p=f'Gjej lim x→{a} të (x²−{a*a})/(x−{a}).'; answer=2*a; rule='Për x≠a, raporti është x+a. Pastaj kalo në limit.'
        else:
            if mode == 0: p=f'Sa zgjidhje të plota jonegative ka x+y+z={a+b}?'; answer=(a+b+2)*(a+b+1)/2; rule='Metoda yje dhe ndarëse: C(n+2,2).'
            elif mode == 1: p=f'a,b>0 dhe a+b={2*a}. Gjej vlerën maksimale të ab.'; answer=a*a; rule='AM–GM: ab≤((a+b)/2)²; barazia kur a=b.'
            else: p=f'Gjej mbetjen e 2^{4*a+3} kur pjesëtohet me 5.'; answer=3; rule='Fuqitë e 2 modulo 5 kanë periudhë 4; 2³≡3.'
    elif subject == 'Fizikë':
        if level == 1:
            if mode==0: p=f'Trupi përshkon {a*b} m në {b} s. Gjej shpejtësinë mesatare.'; answer=a; rule='v=s/t.'; unit='m/s'
            elif mode==1: p=f'Masa është {a*b} g, vëllimi {b} cm³. Gjej dendësinë.'; answer=a; rule='ρ=m/V.'; unit='g/cm³'
            else: p=f'Vepron forcë {a} N përgjatë një zhvendosjeje {b} m. Gjej punën.'; answer=a*b; rule='W=Fs kur forca ka kahun e zhvendosjes.'; unit='J'
        elif level == 2:
            if mode==0: p=f'Një masë {a} kg lëshohet nga qetësia në lartësi {b} m. Pa fërkim, me g=10 m/s², gjej EK në tokë.'; answer=a*10*b; rule='Ruajtja e energjisë: EK=mgh.'; unit='J'
            elif mode==1: p=f'Susta ka k={a*100} N/m dhe zgjatet {b} cm. Gjej energjinë elastike.'; answer=.5*a*100*(b/100)**2; rule='Kthe cm në m; E=kx²/2.'; unit='J'
            else: p=f'Trupi niset nga qetësia me a={a} m/s² për {b} s. Gjej zhvendosjen.'; answer=.5*a*b*b; rule='s=v₀t+at²/2.'; unit='m'
        elif level == 3:
            if mode==0: p=f'Rezistenca {a} Ω dhe {b} Ω lidhen paralel. Gjej rezistencën ekuivalente.'; answer=a*b/(a+b); rule='R=R₁R₂/(R₁+R₂).'; unit='Ω'
            elif mode==1: p=f'Qarku ka U={a*b} V dhe R={b} Ω. Gjej fuqinë.'; answer=a*a*b; rule='I=U/R; P=UI.'; unit='W'
            else: p=f'Valë me f={a*20} Hz dhe λ={b/10} m. Gjej shpejtësinë.'; answer=a*2*b; rule='v=fλ.'; unit='m/s'
        elif level == 4:
            if mode==0: p=f'Lëkundësi ka m={a} kg, k={a*b*b} N/m. Gjej ω.'; answer=b; rule='ω=√(k/m).'; unit='rad/s'
            elif mode==1: p=f'Gazi merr Q={a*100} J dhe kryen W={b*20} J. Gjej ΔU.'; answer=a*100-b*20; rule='ΔU=Q−W, W puna e kryer nga gazi.'; unit='J'
            else: p=f'Përthyerja nga ajri në n={a/2+1}: me sin(i)=0.5 gjej sin(r).'; answer=.5/(a/2+1); rule='n₁sin(i)=n₂sin(r), n₁≈1.'
        else:
            if mode==0: p=f'Masa {a} kg me v={b} m/s ngjitet me masë {c} kg në qetësi. Pa forcë të jashtme, sa energji kinetike humbet?'; answer=.5*a*b*b-.5*(a+c)*(a*b/(a+c))**2; rule='Ruaj impulsin, gjej shpejtësinë e përbashkët, zbrit EK përfundimtare nga fillestarja.'; unit='J'
            elif mode==1: p=f'Masa {a} kg bie nga lartësia {b/10} m mbi sustë vertikale k={c*100} N/m. Me g=10, gjej ngjeshjen maksimale x (m), duke përfshirë rënien gjatë ngjeshjes.'; m=a; h=b/10; k=c*100; answer=(m*10+math.sqrt((m*10)**2+2*k*m*10*h))/k; rule='mg(h+x)=kx²/2; merret rrënja pozitive.'; unit='m'
            else: p=f'Disku homogjen ka m={a} kg, R={b/10} m dhe ω={c} rad/s. Gjej energjinë rrotulluese.'; answer=.25*a*(b/10)**2*c*c; rule='I=mR²/2 dhe E=Iω²/2.'; unit='J'
    elif subject == 'Kimi':
        if level==1:
            if mode==0: p=f'Atomi neutral ka Z={a+5} dhe A={2*(a+5)+b}. Sa neutrone ka?'; answer=a+5+b; rule='N=A−Z.'
            elif mode==1: p=f'Tret {a} g kripë në {a*9} g ujë. Gjej përqindjen masore të kripës.'; answer=10; rule='m(kripë)/m(tretësirë)×100.'; unit='%'
            else: p=f'Në reaksion të mbyllur bashkohen {a} g dhe {b} g reaktantë plotësisht. Gjej masën e produktit të vetëm.'; answer=a+b; rule='Ruajtja e masës.'; unit='g'
        elif level==2:
            if mode==0: p=f'Sa mol janë {a*18} g H₂O? M(H₂O)=18 g/mol.'; answer=a; rule='n=m/M.'; unit='mol'
            elif mode==1: p=f'Tretësira {a/10} mol/L ka vëllim {b*10} mL dhe hollohet në {b*50} mL. Gjej c₂.'; answer=a/50; rule='c₁V₁=c₂V₂.'; unit='mol/L'
            else: p=f'2H₂+O₂→2H₂O. Ke {a} mol H₂ dhe {b} mol O₂. Sa mol ujë formohen maksimalisht?'; answer=min(a,2*b); rule='Krahaso n/koeficient për të gjetur kufizuesin.'; unit='mol'
        elif level==3:
            if mode==0: p=f'Në 25 °C, [H⁺]=10⁻{a} mol/L. Gjej pOH, duke përdorur pKᵥ=14.'; answer=14-a; rule='pH=a; pOH=14−pH.'
            elif mode==1: p=f'Për A⇌B, [B]={a/10} dhe [A]={b/10} mol/L në ekuilibër. Gjej Kc.'; answer=a/b; rule='Kc=[B]/[A].'
            else: p=f'Shpejtësia v=k[A]². [A] shumëzohet me {a}, të tjerat ruhen. Me çfarë faktori ndryshon v?'; answer=a*a; rule='Rendi 2: faktori është a².'
        elif level==4:
            if mode==0: p=f'Tamponi ka pKa={a}, raportin [A⁻]/[HA]=10^{b-5}. Gjej pH me Henderson–Hasselbalch.'; answer=a+b-5; rule='pH=pKa+log([A⁻]/[HA]).'
            elif mode==1: p=f'ΔH={a*10} kJ/mol, ΔS={b*10} J/(mol K), T=300 K. Gjej ΔG në kJ/mol.'; answer=a*10-3*b; rule='Kthe ΔS në kJ: ΔG=ΔH−TΔS.'; unit='kJ/mol'
            else: p=f'Polimerizohen {a*10} monomere në një zinxhir linear me kondensim; çdo lidhje çliron një H₂O. Sa molekula ujë dalin?'; answer=a*10-1; rule='Një zinxhir me n njësi ka n−1 lidhje mes tyre.'
        else:
            if mode==0: p=f'Tretësirë acidi të dobët HA ka c={a/100} mol/L dhe Ka={b}×10⁻⁵. Gjej [H⁺] pa përafrimin x≪c (neglizho autojonizimin e ujit).'; ka=b*1e-5; cc=a/100; answer=(-ka+math.sqrt(ka*ka+4*ka*cc))/2; rule='Ka=x²/(c−x); rrënja pozitive e kuadratikës.'; unit='mol/L'
            elif mode==1: p=f'Në elektrolizë kalojnë {a*96485} C. Për Cu²⁺+2e⁻→Cu, sa mol Cu depozitohen? F=96485 C/mol.'; answer=a/2; rule='n(Cu)=Q/(2F).'; unit='mol'
            else: p=f'Kripa AB₂ ka Ksp={4*a**3}×10⁻¹². Pa jone të përbashkëta, gjej tretshmërinë s në mol/L.'; answer=a*1e-4; rule='Ksp=s(2s)²=4s³.'; unit='mol/L'
    else:
        if level==1:
            if mode==0: p=f'Mikroskopi ka okular ×{a} dhe objektiv ×{b*10}. Gjej zmadhimin total.'; answer=a*b*10; rule='Shumëzo zmadhimet.'; unit='herë'
            elif mode==1: p=f'Numërohen {a*5} rrahje në 15 sekonda. Sa rrahje/minutë jep ky ritëm?'; answer=a*20; rule='Shumëzo me 60/15.'; unit='rrahje/min'
            else: p=f'Në një kampion me {a*10} fara mbijnë {a*8}. Gjej përqindjen e mbirjes.'; answer=80; rule='Të mbirat/total×100.'; unit='%'
        elif level==2:
            if mode==0: p=f'Nga kryqëzimi Aa×Aa, sa heterozigotë priten mes {a*20} pasardhësve?'; answer=a*10; rule='P(Aa)=1/2; është pritje statistikore, jo garanci.'
            elif mode==1: p=f'Një popullatë me {a*100} qeliza bën {b} dyfishime pa humbje. Gjej numrin përfundimtar.'; answer=a*100*2**b; rule='N=N₀2ⁿ.'
            else: p=f'Organizmi ka 2n={a*4}. Sa kromozome ka një gamet normal pas mejozës?'; answer=a*2; rule='Numri haploid n është gjysma e 2n.'
        elif level==3:
            if mode==0: p=f'ADN dyvargore ka A={a+10}%. Sa është G?'; answer=(100-2*(a+10))/2; rule='A=T dhe G=C; shuma 100%.'; unit='%'
            elif mode==1: p=f'Një segment kodues ka {3*a*10} nukleotide duke përfshirë një kodon STOP. Pa introne, sa aminoacide kodon?'; answer=a*10-1; rule='3 baza/kodon; STOP nuk jep aminoacid.'
            else: p=f'Nefronet filtrojnë {a*10} njësi lënde; ripërthithin {a*7} dhe sekretojnë {b}. Sa ekskretohen?'; answer=a*3+b; rule='Ekskretim=filtrim−ripërthithje+sekretim.'
        elif level==4:
            if mode==0: p=f'Në një nivel trofik ka {a*10000} kJ. Modeli transferon {b}% te niveli pasues. Sa kalojnë?'; answer=a*100*b; rule='Shumëzo energjinë me b/100; përqindja është supozim i modelit.'; unit='kJ'
            elif mode==1: p=f'Në shënim–rikapje shënohen {a*10} individë; kampioni i dytë ka {b*10}, prej tyre {a} të shënuar. Vlerëso N.'; answer=b*100; rule='N≈MC/R; kërkohet popullatë e mbyllur dhe përzierje e mirë.'
            else: p=f'PCR ideale nis me {a} molekula dhe kryen {b} cikle. Sa molekula pas cikleve?'; answer=a*2**b; rule='N=N₀2ⁿ, efikasitet ideal 100%.'
        else:
            if mode==0: p=f'Hardy–Weinberg: q={a/10}. Gjej frekuencën e heterozigotëve.'; q=a/10; answer=2*q*(1-q); rule='p=1−q; heterozigotët=2pq.'
            elif mode==1: p=f'Michaelis–Menten: Vmax={a*10}, [S]={b}, Km={c}, njësi të përputhshme. Gjej v.'; answer=a*10*b/(c+b); rule='v=Vmax[S]/(Km+[S]).'
            else: p=f'Nga {a*100} pasardhës, {a*b} janë rekombinantë. Për largësi të vogla, gjej distancën gjenetike.'; answer=b; rule='RF×100≈cM; rekombinimet e shumëfishta neglizhohen.'; unit='cM'
    tolerance = .005 if abs(answer)>=.01 else max(abs(answer)*.005,1e-10)
    return question(dict(prompt=p,answer=format(answer,'.12g'),explanation=rule,unit=unit,kind='number',points=4,tolerance=tolerance))

SCHEMA = '''
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;
CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY,email TEXT UNIQUE COLLATE NOCASE NOT NULL,hash TEXT NOT NULL,role TEXT NOT NULL,recovery TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS sessions(hash TEXT PRIMARY KEY,user TEXT REFERENCES users(id) ON DELETE CASCADE,expires REAL);
CREATE TABLE IF NOT EXISTS invites(hash TEXT PRIMARY KEY,email TEXT NOT NULL,expires REAL,used INTEGER DEFAULT 0);
CREATE TABLE IF NOT EXISTS classes(id TEXT PRIMARY KEY,owner TEXT REFERENCES users(id) ON DELETE CASCADE,name TEXT,level INTEGER,code TEXT UNIQUE);
CREATE TABLE IF NOT EXISTS members(class TEXT REFERENCES classes(id) ON DELETE CASCADE,user TEXT REFERENCES users(id) ON DELETE CASCADE,approved INTEGER DEFAULT 0,PRIMARY KEY(class,user));
CREATE TABLE IF NOT EXISTS family(parent TEXT REFERENCES users(id) ON DELETE CASCADE,child TEXT REFERENCES users(id) ON DELETE CASCADE,PRIMARY KEY(parent,child));
CREATE TABLE IF NOT EXISTS family_codes(hash TEXT PRIMARY KEY,child TEXT REFERENCES users(id) ON DELETE CASCADE,expires REAL);
CREATE TABLE IF NOT EXISTS exams(id TEXT PRIMARY KEY,class TEXT REFERENCES classes(id) ON DELETE CASCADE,owner TEXT REFERENCES users(id) ON DELETE CASCADE,title TEXT,minutes INTEGER,definition TEXT);
CREATE TABLE IF NOT EXISTS attempts(id TEXT PRIMARY KEY,exam TEXT REFERENCES exams(id) ON DELETE CASCADE,student TEXT REFERENCES users(id) ON DELETE CASCADE,started REAL,deadline REAL,submitted REAL,questions TEXT,answers TEXT DEFAULT '{}',grades TEXT DEFAULT '{}',feedback TEXT DEFAULT '{}',UNIQUE(exam,student));
CREATE TABLE IF NOT EXISTS events(id TEXT PRIMARY KEY,class TEXT REFERENCES classes(id) ON DELETE CASCADE,owner TEXT REFERENCES users(id) ON DELETE CASCADE,title TEXT,date REAL,note TEXT);
CREATE TABLE IF NOT EXISTS progress(user TEXT REFERENCES users(id) ON DELETE CASCADE,key TEXT,value TEXT,version INTEGER DEFAULT 1,PRIMARY KEY(user,key));
CREATE TABLE IF NOT EXISTS rates(key TEXT PRIMARY KEY,started REAL,n INTEGER);
'''

class Service:
    def __init__(self, path):
        self.path = str(path)
        with self.db() as db:
            db.executescript(SCHEMA)
            # Migrim i kontrolluar: shton vetëm kolonën që mungon; nuk prek rreshtat ekzistues.
            if 'failures' not in [r['name'] for r in db.execute('PRAGMA table_info(invites)')]:
                db.execute('ALTER TABLE invites ADD COLUMN failures INTEGER NOT NULL DEFAULT 0')
        self.dummy = password_hash('unusable-dummy-password')
    @contextlib.contextmanager
    def db(self):
        db=sqlite3.connect(self.path, timeout=15); db.row_factory=sqlite3.Row
        db.execute('PRAGMA foreign_keys=ON')
        try:
            db.execute('BEGIN IMMEDIATE'); yield db; db.commit()
        except Exception: db.rollback(); raise
        finally: db.close()
    def rate(self, key, limit, window):
        with self.db() as db:
            now=time.time(); db.execute('DELETE FROM rates WHERE started < ?', (now-86400,))
            r=db.execute('SELECT * FROM rates WHERE key=?',(key,)).fetchone()
            if not r or r['started']+window<=now:
                db.execute('INSERT OR REPLACE INTO rates VALUES(?,?,1)',(key,now)); return
            if r['n']>=limit: raise Fault('Shumë kërkesa. Prit pak dhe provo përsëri.',429)
            db.execute('UPDATE rates SET n=n+1 WHERE key=?',(key,))
    @staticmethod
    def invite_hash(email,code): return digest(email+'\n'+code)
    def invite(self,email,digits=5):
        """Krijon ftesë për një email. digits=5 jep kod 5-shifror; digits=0 jep kod të gjatë. Ftesat e vjetra të pashfrytëzuara për të njëjtin email shfuqizohen."""
        require(digits==0 or 5<=digits<=12,'Gjatësia e kodit duhet të jetë 0 ose 5–12 shifra.')
        email=norm_email(email)
        code=secrets.token_urlsafe(18) if digits==0 else str(secrets.randbelow(10**digits)).zfill(digits)
        with self.db() as db:
            db.execute('DELETE FROM invites WHERE email=? AND used=0',(email,))
            db.execute('INSERT INTO invites(hash,email,expires,used,failures) VALUES(?,?,?,0,0)',(self.invite_hash(email,code),email,time.time()+INVITE_DAYS*86400))
        return code
    def check_invite(self,email,code):
        """Kontrollon ftesën në transaksionin e vet; gabimi shtohet në numërues edhe kur kërkesa dështon.
        Pas INVITE_MAX_FAILURES gabimesh ftesa nuk pranohet më, edhe me kodin e saktë."""
        with self.db() as db:
            row=db.execute('SELECT * FROM invites WHERE email=? AND used=0 AND expires>? ORDER BY expires DESC LIMIT 1',(email,time.time())).fetchone()
            if row is None or row['failures']>=INVITE_MAX_FAILURES: return False
            ok=any(hmac.compare_digest(h,row['hash']) for h in (self.invite_hash(email,code),digest(code)))  # digest(code): ftesat e vjetra
            if not ok: db.execute('UPDATE invites SET failures=failures+1 WHERE hash=?',(row['hash'],))
            return ok
    def session(self, db, user):
        token=secrets.token_urlsafe(32)
        db.execute('DELETE FROM sessions WHERE expires < ?',(time.time(),))
        db.execute('INSERT INTO sessions VALUES(?,?,?)',(digest(token),user['id'],time.time()+30*86400))
        return dict(token=token,user=dict(id=user['id'],email=user['email'],role=user['role']))
    def authenticated(self,db,token):
        u=db.execute('SELECT u.* FROM users u JOIN sessions s ON s.user=u.id WHERE s.hash=? AND s.expires>?',(digest(token),time.time())).fetchone()
        require(u is not None,'Seanca ka mbaruar. Hyr përsëri.',401); return u
    def owned_class(self,db,u,c):
        row=db.execute('SELECT * FROM classes WHERE id=? AND owner=?',(c,u['id'])).fetchone()
        require(row is not None,'Nuk ke të drejtë mbi këtë klasë.',403); return row
    def can_class(self,db,u,c):
        if db.execute('SELECT 1 FROM classes WHERE id=? AND owner=?',(c,u['id'])).fetchone(): return True
        if db.execute('SELECT 1 FROM members WHERE class=? AND user=? AND approved=1',(c,u['id'])).fetchone(): return True
        return bool(db.execute('SELECT 1 FROM family f JOIN members m ON m.user=f.child WHERE f.parent=? AND m.class=? AND m.approved=1',(u['id'],c)).fetchone())
    def expire(self, db):
        db.execute('UPDATE attempts SET submitted=deadline WHERE submitted IS NULL AND deadline<=?',(time.time(),))
    def attempt(self,db,u,aid,teacher=False):
        a=db.execute('SELECT a.*,e.owner,e.title,e.class FROM attempts a JOIN exams e ON a.exam=e.id WHERE a.id=?',(aid,)).fetchone()
        require(a is not None and (a['student']==u['id'] or (teacher and a['owner']==u['id'])),'Testi nuk është i arritshëm.',403)
        return a
    def attempt_view(self,a):
        qs=json.loads(a['questions']); grades=json.loads(a['grades']); answers=json.loads(a['answers'])
        scores={q['id']:grades.get(q['id'],q['points'] if correct(q,answers.get(q['id'],{}).get('value','')) else 0) for q in qs}
        return dict(id=a['id'],exam=a['exam'],title=a['title'],deadline=a['deadline'],serverNow=time.time(),submitted=a['submitted'] is not None,
                    questions=[{k:v for k,v in q.items() if k not in ('answer','explanation')} for q in qs],answers=answers,
                    score=sum(scores.values()) if a['submitted'] else None,maximum=sum(q['points'] for q in qs),feedback=json.loads(a['feedback']) if a['submitted'] else {})
    def dispatch(self,b,token='',ip='local'):
        require(isinstance(b,dict),'Kërkesë e pavlefshme.')
        action=text(b,'action',60)
        self.rate('ip:'+ip,180,60)
        if action in ('register','login','recover'):
            self.rate('auth:'+ip,20,900)
            email=norm_email(b.get('email','')); self.rate('email:'+email,15,900)
            # Slow hashing is bounded by the HTTP concurrency gate, before DB transaction.
            if action=='register':
                if b.get('role')=='Mësues':
                    require(self.check_invite(email,text(b,'teacherCode',100)),'Ftesa e mësuesit nuk është e vlefshme për këtë email, ka skaduar ose është bllokuar. Kërko një ftesë të re nga administratori.',403)
                hashed=password_hash(b.get('password',''))
            with self.db() as db:
                old=db.execute('SELECT * FROM users WHERE email=?',(email,)).fetchone()
                if action=='login':
                    valid=password_ok(b.get('password',''),old['hash'] if old else self.dummy)
                    require(old is not None and valid,'Emaili ose fjalëkalimi nuk është i saktë.',401)
                    return self.session(db,old)
                if action=='recover':
                    valid=old is not None and hmac.compare_digest(digest(text(b,'recovery',100)),old['recovery'])
                    require(valid,'Emaili ose kodi i rikuperimit nuk është i saktë.',401)
                    newhash=password_hash(b.get('password','')); recovery=secrets.token_urlsafe(24)
                    db.execute('UPDATE users SET hash=?,recovery=? WHERE id=?',(newhash,digest(recovery),old['id']))
                    db.execute('DELETE FROM sessions WHERE user=?',(old['id'],))
                    return dict(ok=True,recovery=recovery)
                require(old is None,'Regjistrimi nuk u krye. Nëse ke llogari, përdor Hyr ose Rikupero.',409)
                role=b.get('role'); require(role in ROLES,'Zgjidh rolin.')
                if role=='Mësues':
                    # check_invite() e ka verifikuar kodin; këtu shënohet si i përdorur në të njëjtën transaksion me krijimin e llogarisë.
                    code=text(b,'teacherCode',100)
                    used=db.execute('UPDATE invites SET used=1 WHERE email=? AND used=0 AND expires>? AND failures<? AND hash IN (?,?)',(email,time.time(),INVITE_MAX_FAILURES,self.invite_hash(email,code),digest(code))).rowcount
                    require(used==1,'Ftesa e mësuesit nuk është e vlefshme për këtë email.',403)
                recovery=secrets.token_urlsafe(24); ident=uid()
                db.execute('INSERT INTO users VALUES(?,?,?,?,?)',(ident,email,hashed,role,digest(recovery)))
                result=self.session(db,db.execute('SELECT * FROM users WHERE id=?',(ident,)).fetchone()); result['recovery']=recovery; return result
        with self.db() as db:
            u=self.authenticated(db,token); self.expire(db)
            if action=='logout': db.execute('DELETE FROM sessions WHERE hash=?',(digest(token),)); return dict(ok=True)
            if action=='deleteAccount':
                require(password_ok(b.get('password',''),u['hash']),'Fjalëkalimi nuk është i saktë.',401)
                db.execute('DELETE FROM users WHERE id=?',(u['id'],)); return dict(ok=True)
            if action=='snapshot': return self.snapshot(db,u)
            if action=='classCreate':
                require(u['role']=='Mësues','Vetëm mësuesit krijojnë klasa.',403)
                name=text(b,'name',100); require(name,'Shkruaj emrin e klasës.')
                db.execute('INSERT INTO classes VALUES(?,?,?,?,?)',(uid(),u['id'],name,integer(b,'level',1,5),secrets.token_hex(5).upper())); return dict(ok=True)
            if action=='classJoin':
                require(u['role']=='Nxënës','Vetëm nxënësit kërkojnë anëtarësim.',403)
                row=db.execute('SELECT * FROM classes WHERE code=?',(text(b,'code',30).upper(),)).fetchone()
                require(row is not None,'Kodi i klasës nuk u gjet.')
                db.execute('INSERT OR IGNORE INTO members VALUES(?,?,0)',(row['id'],u['id'])); return dict(ok=True)
            if action in ('approve','removeMember','rotateCode'):
                c=text(b,'classID',50); self.owned_class(db,u,c)
                if action=='rotateCode': db.execute('UPDATE classes SET code=? WHERE id=?',(secrets.token_hex(5).upper(),c))
                elif action=='approve': db.execute('UPDATE members SET approved=1 WHERE class=? AND user=?',(c,text(b,'student',50)))
                else: db.execute('DELETE FROM members WHERE class=? AND user=?',(c,text(b,'student',50)))
                return dict(ok=True)
            if action=='familyCode':
                require(u['role']=='Nxënës','Vetëm nxënësi mund të lidhë profilin e vet.',403)
                code=secrets.token_urlsafe(12)
                db.execute('INSERT INTO family_codes VALUES(?,?,?)',(digest(code),u['id'],time.time()+900)); return dict(code=code)
            if action=='familyJoin':
                require(u['role']=='Prind','Ky veprim është për prindërit.',403)
                r=db.execute('SELECT * FROM family_codes WHERE hash=? AND expires>?',(digest(text(b,'code',100)),time.time())).fetchone()
                require(r is not None,'Kodi ka mbaruar ose nuk është i saktë.')
                db.execute('INSERT OR IGNORE INTO family VALUES(?,?)',(u['id'],r['child'])); db.execute('DELETE FROM family_codes WHERE hash=?',(r['hash'],)); return dict(ok=True)
            if action=='unlinkParent':
                db.execute('DELETE FROM family WHERE child=? AND parent=?',(u['id'],text(b,'parent',50))); return dict(ok=True)
            if action=='examCreate':
                c=self.owned_class(db,u,text(b,'classID',50)); title=text(b,'title',200); require(title,'Shkruaj titullin.')
                subject=b.get('subject'); require(subject in SUBJECTS,'Zgjidh lëndën.')
                raw=b.get('questions',[]); require(isinstance(raw,list) and len(raw)<=30,'Deri në 30 pyetje.')
                qs=[question(q) for q in raw]; count=integer(b,'generated',0,30,0); require(1<=len(qs)+count<=30,'Testi duhet të ketë 1–30 pyetje.')
                definition=dict(subject=subject,level=c['level'],count=count,questions=qs)
                db.execute('INSERT INTO exams VALUES(?,?,?,?,?,?)',(uid(),c['id'],u['id'],title,integer(b,'minutes',1,180,30),dumps(definition))); return dict(ok=True)
            if action=='examStart':
                require(u['role']=='Nxënës','Vetëm nxënësit zgjidhin testin.',403)
                e=db.execute('SELECT * FROM exams WHERE id=?',(text(b,'examID',50),)).fetchone()
                require(e is not None and self.can_class(db,u,e['class']),'Nuk je anëtar i miratuar i kësaj klase.',403)
                a=db.execute('SELECT id FROM attempts WHERE exam=? AND student=?',(e['id'],u['id'])).fetchone()
                if not a:
                    d=json.loads(e['definition']); qs=d['questions']+[generated(d['subject'],d['level']) for _ in range(d['count'])]
                    secrets.SystemRandom().shuffle(qs); aid=uid(); now=time.time()
                    db.execute('INSERT INTO attempts(id,exam,student,started,deadline,questions) VALUES(?,?,?,?,?,?)',(aid,e['id'],u['id'],now,now+60*e['minutes'],dumps(qs)))
                else: aid=a['id']
                return self.attempt_view(self.attempt(db,u,aid))
            if action in ('attempt','answer','finish'):
                a=self.attempt(db,u,text(b,'attemptID',50))
                require(self.can_class(db,u,a['class']),'Anëtarësimi në klasë nuk është aktiv.',403)
                if action=='answer' and a['submitted'] is None:
                    qid=text(b,'questionID',50); qs=json.loads(a['questions']); require(any(q['id']==qid for q in qs),'Pyetje e panjohur.')
                    answers=json.loads(a['answers']); answers[qid]=dict(value=text(b,'value',1000),reasoning=text(b,'reasoning',5000))
                    db.execute('UPDATE attempts SET answers=? WHERE id=?',(dumps(answers),a['id']))
                elif action=='finish' and a['submitted'] is None: db.execute('UPDATE attempts SET submitted=? WHERE id=?',(time.time(),a['id']))
                return self.attempt_view(self.attempt(db,u,a['id']))
            if action=='grade':
                a=self.attempt(db,u,text(b,'attemptID',50),teacher=True)
                require(a['owner']==u['id'] and a['submitted'] is not None,'Testi ende nuk mund të vlerësohet.',403)
                qid=text(b,'questionID',50); q=next((q for q in json.loads(a['questions']) if q['id']==qid),None); require(q is not None)
                grades=json.loads(a['grades']); feedback=json.loads(a['feedback'])
                grades[qid]=integer(b,'points',0,q['points']); feedback[qid]=text(b,'feedback',3000)
                db.execute('UPDATE attempts SET grades=?,feedback=? WHERE id=?',(dumps(grades),dumps(feedback),a['id'])); return dict(ok=True)
            if action=='eventCreate':
                c=text(b,'classID',50); self.owned_class(db,u,c); title=text(b,'title',200); require(title,'Shkruaj titullin.')
                date=b.get('date'); require(type(date) in (int,float) and math.isfinite(date) and 0<date<4102444800,'Datë e pavlefshme.')
                db.execute('INSERT INTO events VALUES(?,?,?,?,?,?)',(uid(),c,u['id'],title,date,text(b,'note',2000))); return dict(ok=True)
            if action=='eventDelete': db.execute('DELETE FROM events WHERE id=? AND owner=?',(text(b,'eventID',50),u['id'])); return dict(ok=True)
            if action=='progressGet': return self.progress(db,u)
            if action=='progressPut':
                changes=b.get('changes',[]); require(isinstance(changes,list) and len(changes)<=1000)
                conflicts=[]
                for change in changes:
                    key=text(change,'key',120); require(key.startswith(('study','mastered','studentLevel','goal','quiz','lab','homeActivity','solvedTopics','spring','practical','chemMixHistory','game','familyReport')),'Ky lloj progresi nuk sinkronizohet.')
                    value=change.get('value'); require(len(dumps(value))<=200000,'Shënim shumë i madh.')
                    old=db.execute('SELECT * FROM progress WHERE user=? AND key=?',(u['id'],key)).fetchone()
                    version=integer(change,'version',0,2**53,0)
                    if (old['version'] if old else 0)!=version: conflicts.append(key); continue
                    db.execute('INSERT INTO progress VALUES(?,?,?,?) ON CONFLICT(user,key) DO UPDATE SET value=excluded.value,version=excluded.version',(u['id'],key,dumps(value),version+1))
                result=self.progress(db,u); result['conflicts']=conflicts; return result
            raise Fault('Veprim i panjohur.',404)
    def progress(self,db,u):
        return dict(entries=[dict(key=r['key'],value=json.loads(r['value']),version=r['version']) for r in db.execute('SELECT * FROM progress WHERE user=?',(u['id'],))])
    def snapshot(self,db,u):
        classes=[]; members=[]; tests=[]; events=[]; results=[]
        for c in db.execute('SELECT * FROM classes ORDER BY name'):
            owns=c['owner']==u['id']; member=db.execute('SELECT approved FROM members WHERE class=? AND user=?',(c['id'],u['id'])).fetchone()
            allowed=self.can_class(db,u,c['id'])
            if not allowed and not member: continue
            classes.append(dict(id=c['id'],name=c['name'],level=c['level'],owner=c['owner'],code=c['code'] if owns else '',approved=allowed))
            if owns:
                members.extend(dict(id=r['id'],email=r['email'],classID=c['id'],approved=bool(r['approved'])) for r in db.execute('SELECT u.id,u.email,m.approved FROM members m JOIN users u ON u.id=m.user WHERE m.class=?',(c['id'],)))
            if not allowed: continue
            for e in db.execute('SELECT * FROM exams WHERE class=? ORDER BY rowid DESC',(c['id'],)):
                d=json.loads(e['definition']); tests.append(dict(id=e['id'],classID=c['id'],title=e['title'],minutes=e['minutes'],count=len(d['questions'])+d['count'],subject=d['subject']))
                for a in db.execute('SELECT a.*,e.title,e.owner,e.class,u.email FROM attempts a JOIN exams e ON e.id=a.exam JOIN users u ON u.id=a.student WHERE a.exam=? AND a.submitted IS NOT NULL',(e['id'],)):
                    is_parent=db.execute('SELECT 1 FROM family WHERE parent=? AND child=?',(u['id'],a['student'])).fetchone()
                    if not (owns or a['student']==u['id'] or is_parent): continue
                    result=self.attempt_view(a); result.update(student=a['email'],className=c['name'])
                    if owns: result['reviewQuestions']=json.loads(a['questions']); result['grades']=json.loads(a['grades'])
                    results.append(result)
            events.extend(dict(id=r['id'],classID=r['class'],owner=r['owner'],title=r['title'],date=r['date'],note=r['note']) for r in db.execute('SELECT * FROM events WHERE class=? ORDER BY date',(c['id'],)))
        parents=[dict(id=r['id'],email=r['email']) for r in db.execute('SELECT u.id,u.email FROM family f JOIN users u ON u.id=f.parent WHERE f.child=?',(u['id'],))]
        return dict(classes=classes,members=members,tests=tests,events=events,results=results,parents=parents)

class Handler(BaseHTTPRequestHandler):
    server_version='ScienceQuest/7'
    def log_message(self,format,*args): pass # Do not log credentials, tokens or student answers.
    def do_POST(self):
        if not self.server.slots.acquire(blocking=False): self.reply(503,dict(error='Shërbimi është i ngarkuar. Provo përsëri.')); return
        try:
            self.connection.settimeout(15)
            require(self.path=='/api','Rrugë e panjohur.',404)
            require(self.headers.get('Content-Type','').split(';')[0]=='application/json','Përdor JSON.',415)
            rawlen=self.headers.get('Content-Length','0'); require(rawlen.isdigit(),'Gjatësi e pavlefshme.')
            size=int(rawlen); require(0<size<=2_000_000,'Kërkesë shumë e madhe.',413)
            body=json.loads(self.rfile.read(size)); token=self.headers.get('Authorization','').removeprefix('Bearer ')
            result=self.server.service.dispatch(body,token,self.client_address[0]); self.reply(200,result)
        except Fault as e: self.reply(e.status,dict(error=e.message))
        except (ValueError,TypeError,KeyError): self.reply(400,dict(error='Kërkesë e pavlefshme.'))
        except Exception: self.reply(500,dict(error='Shërbimi nuk e përfundoi kërkesën. Provo përsëri.'))
        finally: self.server.slots.release()
    def reply(self,status,obj):
        data=dumps(obj).encode(); self.send_response(status)
        self.send_header('Content-Type','application/json; charset=utf-8'); self.send_header('Cache-Control','no-store')
        self.send_header('X-Content-Type-Options','nosniff'); self.send_header('Content-Length',str(len(data))); self.send_header('Connection','close'); self.end_headers()
        try: self.wfile.write(data)
        except (BrokenPipeError,ConnectionResetError): pass

class Server(ThreadingHTTPServer):
    daemon_threads=True; request_queue_size=32
    def __init__(self,address,service):
        self.service=service; self.slots=BoundedSemaphore(4); self.connections=BoundedSemaphore(16); super().__init__(address,Handler)
    def process_request(self,request,address):
        if not self.connections.acquire(blocking=False):
            self.shutdown_request(request); return
        try: super().process_request(request,address)
        except Exception:
            self.connections.release(); raise
    def process_request_thread(self,request,address):
        try: super().process_request_thread(request,address)
        finally: self.connections.release()
    def get_request(self):
        sock,address=super().get_request(); sock.settimeout(15); return sock,address

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--db',default='school.sqlite3'); parser.add_argument('--host',default='127.0.0.1'); parser.add_argument('--port',type=int,default=8443)
    parser.add_argument('--cert'); parser.add_argument('--key'); parser.add_argument('--invite-teacher',metavar='EMAIL'); parser.add_argument('--invite-digits',type=int,default=5,help='5 (parazgjedhje) deri 12 shifra; 0 = kod i gjatë'); parser.add_argument('--allow-lan-demo',action='store_true')
    args=parser.parse_args(); os.umask(0o077); service=Service(args.db)
    if args.invite_teacher:
        try: print(service.invite(args.invite_teacher,args.invite_digits))
        except Fault as e: parser.error(e.message)
        return
    if args.host not in ('127.0.0.1','localhost','::1') and not (args.cert and args.key) and not args.allow_lan_demo: parser.error('Për pajisje të tjera kërkohet TLS (--cert/--key). --allow-lan-demo përdoret vetëm për prova me llogari provë.')
    server=Server((args.host,args.port),service)
    if args.cert and args.key:
        ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.minimum_version=ssl.TLSVersion.TLSv1_2; ctx.load_cert_chain(args.cert,args.key); server.socket=ctx.wrap_socket(server.socket,server_side=True)
    print(f'ScienceQuest: {"https" if args.cert else "http"}://{args.host}:{args.port}/api (Ctrl-C për ndalim)')
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally: server.server_close()
if __name__=='__main__': main()
