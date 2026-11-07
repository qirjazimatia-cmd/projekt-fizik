import concurrent.futures, json, math, os, tempfile, threading, time, unittest, urllib.request, urllib.error
from unittest.mock import patch
from server import Service, Server, Fault, SUBJECTS, correct, generated, numeric

class SchoolTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.service=Service(self.tmp.name+'/test.db'); self.seq=0
    def tearDown(self): self.tmp.cleanup()
    def call(self,action,token='',**body):
        self.seq+=1
        return self.service.dispatch(dict(action=action,**body),token,'test-'+str(self.seq))
    def user(self,email='student@example.org',role='Nxënës'):
        extra={}
        if role=='Mësues': extra['teacherCode']=self.service.invite(email)
        return self.call('register',email=email,password='Safe-password-123',role=role,**extra)
    def classroom(self,owner,name='XI B',level=3):
        self.call('classCreate',owner['token'],name=name,level=level)
        return next(c for c in self.call('snapshot',owner['token'])['classes'] if c['name']==name)
    def join(self,teacher,pupil,c):
        self.call('classJoin',pupil['token'],code=c['code'])
        self.call('approve',teacher['token'],classID=c['id'],student=pupil['user']['id'])
    def exam(self,t,c,manual=None):
        self.call('examCreate',t['token'],classID=c['id'],title='Prova',subject='Matematikë',minutes=1,generated=0 if manual else 3,questions=manual or [])
        return self.call('snapshot',t['token'])['tests'][0]
    def test_same_account_two_devices_duplicate_and_bad_password(self):
        a=self.user('Mixed@Example.ORG'); b=self.call('login',email=' mixed@example.org ',password='Safe-password-123')
        self.assertEqual(a['user']['id'],b['user']['id']); self.assertNotEqual(a['token'],b['token'])
        for token in (a['token'],b['token']): self.call('snapshot',token)
        with self.assertRaises(Fault): self.call('register',email='MIXED@example.org',password='Different-pass-123',role='Nxënës')
        with self.assertRaises(Fault): self.call('login',email='mixed@example.org',password='Different-pass-123')
    def test_teacher_invite_bound_to_email_single_use_and_expiry(self):
        invite=self.service.invite('teacher@example.org')
        with self.assertRaises(Fault): self.call('register',email='intruder@example.org',password='Safe-password-123',role='Mësues',teacherCode=invite)
        with self.assertRaises(Fault): self.call('register',email='x@example.org',password='Safe-password-123',role='Mësues',teacherCode='00000')
        t=self.call('register',email='teacher@example.org',password='Safe-password-123',role='Mësues',teacherCode=invite)
        with self.service.db() as db:
            self.assertEqual(db.execute('SELECT used FROM invites').fetchone()[0],1)
        old=self.service.invite('old@example.org')
        with self.service.db() as db: db.execute('UPDATE invites SET expires=0')
        with self.assertRaises(Fault): self.call('register',email='old@example.org',password='Safe-password-123',role='Mësues',teacherCode=old)
    def test_class_membership_and_same_level_isolation(self):
        t=self.user('t@example.org','Mësues'); s=self.user(); other=self.user('other@example.org')
        a=self.classroom(t,'XI A'); b=self.classroom(t,'XI B'); exam=self.exam(t,a)
        self.call('classJoin',s['token'],code=a['code'])
        self.assertEqual(self.call('snapshot',s['token'])['tests'],[])
        with self.assertRaises(Fault): self.call('examStart',s['token'],examID=exam['id'])
        self.join(t,s,a); self.join(t,other,b)
        self.assertEqual(len(self.call('snapshot',s['token'])['tests']),1)
        self.assertEqual(self.call('snapshot',other['token'])['tests'],[])
        with self.assertRaises(Fault): self.call('examStart',other['token'],examID=exam['id'])
        with self.assertRaises(Fault): self.call('approve',s['token'],classID=a['id'],student=other['user']['id'])
    def test_deadline_survives_login_and_reopen_no_answers_leak(self):
        t=self.user('t@example.org','Mësues'); s=self.user(); c=self.classroom(t); self.join(t,s,c); e=self.exam(t,c)
        a=self.call('examStart',s['token'],examID=e['id']); b=self.call('examStart',s['token'],examID=e['id'])
        self.assertEqual(a['id'],b['id']); self.assertEqual(a['deadline'],b['deadline']); self.assertEqual(a['questions'],b['questions'])
        self.assertNotIn('answer',a['questions'][0]); self.assertNotIn('explanation',a['questions'][0]); self.assertIsNone(a['score'])
        with self.service.db() as db: db.execute('UPDATE attempts SET deadline=? WHERE id=?',(time.time()-1,a['id']))
        late=self.call('answer',s['token'],attemptID=a['id'],questionID=a['questions'][0]['id'],value='99',reasoning='Late')
        self.assertTrue(late['submitted']); self.assertEqual(late['answers'],{})
        self.assertEqual(len(self.call('snapshot',t['token'])['results']),1)
    def test_rounding_partial_credit_and_cross_teacher_denial(self):
        t=self.user('t@example.org','Mësues'); rogue=self.user('rogue@example.org','Mësues'); s=self.user(); c=self.classroom(t); self.join(t,s,c)
        e=self.exam(t,c,[dict(prompt='4/3?',answer='4/3',kind='number',tolerance=.005,points=4,explanation='Pjesëto.',unit='')])
        a=self.call('examStart',s['token'],examID=e['id']); q=a['questions'][0]['id']
        self.call('answer',s['token'],attemptID=a['id'],questionID=q,value='1,33',reasoning='4 pjesëtohet me 3.')
        done=self.call('finish',s['token'],attemptID=a['id']); self.assertEqual(done['score'],4)
        with self.assertRaises(Fault): self.call('grade',rogue['token'],attemptID=a['id'],questionID=q,points=0)
        with self.assertRaises(Fault): self.call('grade',s['token'],attemptID=a['id'],questionID=q,points=4)
        self.call('grade',t['token'],attemptID=a['id'],questionID=q,points=3,feedback='Arsyetimi kërkon një hap tjetër.')
        latest=self.call('attempt',s['token'],attemptID=a['id']); self.assertEqual(latest['score'],3); self.assertIn(q,latest['feedback'])
        self.call('answer',s['token'],attemptID=a['id'],questionID=q,value='100')
        self.assertEqual(self.call('attempt',s['token'],attemptID=a['id'])['answers'][q]['value'],'1,33')
    def test_recovery_rotates_code_and_revokes_all_sessions(self):
        s=self.user(); second=self.call('login',email=s['user']['email'],password='Safe-password-123')
        r=self.call('recover',email=s['user']['email'],recovery=s['recovery'],password='New-password-123')
        self.assertNotEqual(r['recovery'],s['recovery'])
        for token in (s['token'],second['token']):
            with self.assertRaises(Fault): self.call('snapshot',token)
        with self.assertRaises(Fault): self.call('recover',email=s['user']['email'],recovery=s['recovery'],password='Another-password')
        self.call('login',email=s['user']['email'],password='New-password-123')
    def test_progress_conflict_cannot_overwrite_other_device(self):
        s=self.user(); token=s['token']
        a=self.call('progressPut',token,changes=[dict(key='studyNotes.LM1-01',value='A',version=0)])
        b=self.call('progressPut',token,changes=[dict(key='studyNotes.LM1-01',value='B',version=0)])
        self.assertEqual(a['entries'][0]['version'],1); self.assertEqual(b['conflicts'],['studyNotes.LM1-01']); self.assertEqual(b['entries'][0]['value'],'A')
        self.assertEqual(self.call('progressGet',self.user('other@example.org')['token'])['entries'],[])
    def test_parent_consent_events_and_revocation(self):
        t=self.user('t@example.org','Mësues'); s=self.user(); p=self.user('p@example.org','Prind'); c=self.classroom(t); self.join(t,s,c)
        self.call('eventCreate',t['token'],classID=c['id'],title='Test',date=time.time(),note='Kap. 2')
        self.assertEqual(self.call('snapshot',p['token'])['events'],[])
        code=self.call('familyCode',s['token'])['code']; self.call('familyJoin',p['token'],code=code)
        self.assertEqual(len(self.call('snapshot',p['token'])['events']),1)
        with self.assertRaises(Fault): self.call('familyJoin',p['token'],code=code)
        with self.assertRaises(Fault): self.call('eventCreate',p['token'],classID=c['id'],title='Bad',date=time.time())
        self.call('unlinkParent',s['token'],parent=p['user']['id']); self.assertEqual(self.call('snapshot',p['token'])['classes'],[])
    def test_removing_account_cascades_and_requires_password(self):
        s=self.user(); self.call('progressPut',s['token'],changes=[dict(key='mastered',value='M1-01',version=0)])
        with self.assertRaises(Fault): self.call('deleteAccount',s['token'],password='Not-the-password')
        self.call('deleteAccount',s['token'],password='Safe-password-123')
        with self.assertRaises(Fault): self.call('snapshot',s['token'])
        with self.service.db() as db:
            self.assertEqual(db.execute('SELECT count(*) FROM progress').fetchone()[0],0)
    def test_concurrent_registration_has_unique_email(self):
        def run(i):
            try: return self.service.dispatch(dict(action='register',email='one@example.org',password='Safe-password-123',role='Nxënës'),ip='race'+str(i))
            except Fault as e: return e.status
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool: results=list(pool.map(run,range(2)))
        self.assertEqual(sum(isinstance(r,dict) for r in results),1); self.assertIn(409,results)
    def test_real_http_two_independent_clients(self):
        server=Server(('127.0.0.1',0),self.service); th=threading.Thread(target=server.serve_forever,daemon=True); th.start()
        def request(body,token=''):
            req=urllib.request.Request(f'http://127.0.0.1:{server.server_port}/api',data=json.dumps(body).encode(),headers={'Content-Type':'application/json','Authorization':'Bearer '+token})
            with urllib.request.urlopen(req,timeout=10) as r: return json.load(r)
        try:
            a=request(dict(action='register',email='http@example.org',password='Safe-password-123',role='Nxënës'))
            b=request(dict(action='login',email='http@example.org',password='Safe-password-123'))
            self.assertEqual(a['user']['id'],b['user']['id']); request(dict(action='snapshot'),a['token']); request(dict(action='snapshot'),b['token'])
            with self.assertRaises(urllib.error.HTTPError): request(dict(action='snapshot'), 'fake')
        finally: server.shutdown(); server.server_close(); th.join()

    def test_five_digit_invite_format_lockout_and_reissue(self):
        code=self.service.invite('t5@example.org')
        self.assertRegex(code,r'^\d{5}$')
        wrong=str((int(code)+1)%100000).zfill(5)
        for _ in range(5):
            with self.assertRaises(Fault): self.call('register',email='t5@example.org',password='Safe-password-123',role='Mësues',teacherCode=wrong)
        # pas 5 gabimeve, edhe kodi i saktë refuzohet (numëruesi ruhet pavarësisht nga rollback i kërkesës)
        with self.assertRaises(Fault): self.call('register',email='t5@example.org',password='Safe-password-123',role='Mësues',teacherCode=code)
        new=self.service.invite('t5@example.org')   # administratori jep ftesë të re; e vjetra shfuqizohet
        with self.assertRaises(Fault): self.call('register',email='t5@example.org',password='Safe-password-123',role='Mësues',teacherCode=code if code!=new else wrong)
        t=self.call('register',email='t5@example.org',password='Safe-password-123',role='Mësues',teacherCode=new)
        self.assertEqual(t['user']['role'],'Mësues')
        with self.assertRaises(Fault): self.call('register',email='t5b@example.org',password='Safe-password-123',role='Mësues',teacherCode=new)
    def test_student_cannot_obtain_teacher_role_any_way(self):
        for code in ('', '00000', '12345', 'x'*50):
            with self.assertRaises(Fault): self.call('register',email='sneaky@example.org',password='Safe-password-123',role='Mësues',teacherCode=code)
        s=self.user('plain@example.org')
        self.assertEqual(s['user']['role'],'Nxënës')
        with self.assertRaises(Fault): self.call('classCreate',s['token'],name='Falso',level=1)
    def test_long_invite_option_and_legacy_unsalted_invite_hash(self):
        long_code=self.service.invite('long@example.org',0); self.assertGreater(len(long_code),20)
        self.call('register',email='long@example.org',password='Safe-password-123',role='Mësues',teacherCode=long_code)
        from server import digest
        import time as _t
        with self.service.db() as db: db.execute('INSERT INTO invites(hash,email,expires,used,failures) VALUES(?,?,?,0,0)',(digest('legacy-code-value'),'legacy@example.org',_t.time()+99))
        self.call('register',email='legacy@example.org',password='Safe-password-123',role='Mësues',teacherCode='legacy-code-value')
    def test_migration_adds_failures_column_without_losing_invites(self):
        import sqlite3
        path=self.tmp.name+'/old.db'; c=sqlite3.connect(path)
        c.execute('CREATE TABLE invites(hash TEXT PRIMARY KEY,email TEXT NOT NULL,expires REAL,used INTEGER DEFAULT 0)')
        c.execute("INSERT INTO invites VALUES('abc','keep@example.org',9999999999,0)"); c.commit(); c.close()
        Service(path)
        c=sqlite3.connect(path); row=c.execute('SELECT hash,failures FROM invites').fetchone(); c.close()
        self.assertEqual(row,('abc',0))

class NumberTests(unittest.TestCase):
    def test_numeric_input(self):
        self.assertEqual(numeric('1,33'),numeric('1.33')); self.assertIsNone(numeric('1/0')); self.assertIsNone(numeric('NaN')); self.assertIsNone(numeric('1/2/3'))
        q=dict(kind='number',answer='4/3',tolerance=.005)
        self.assertTrue(correct(q,'1,33')); self.assertTrue(correct(q,'4/3')); self.assertFalse(correct(q,'1.3'))
    def test_generated_variants_all_subjects_levels(self):
        for subject in SUBJECTS:
            for level in range(1,6):
                prompts=set()
                for _ in range(80):
                    q=generated(subject,level); self.assertTrue(correct(q,q['answer'])); self.assertGreater(q['points'],0); self.assertTrue(q['explanation']); prompts.add(q['prompt'])
                self.assertGreater(len(prompts),12,(subject,level))
if __name__=='__main__': unittest.main(verbosity=2)
