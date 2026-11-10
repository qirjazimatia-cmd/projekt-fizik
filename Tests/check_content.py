#!/usr/bin/env python3
"""Deterministic integrity/numeric checks, no third-party Python packages."""
import ast,collections,json,math,plistlib,re
from pathlib import Path
root=Path(__file__).resolve().parents[1];app=root/'App'
lessons=json.loads((app/'Lessons.json').read_text());exercises=json.loads((app/'Exercises.json').read_text())
N=len(lessons);assert N==len(exercises) and N>=600 and N%5==0
index={x['id']:x for x in exercises};assert len(index)==N
assert len({x['id'] for x in lessons})==N
assert len({x['chapterID'] for x in lessons})==N//5
assert len({tuple(x['objectives']) for x in lessons})==N
assert all(sum(x['chapterID']==c for x in lessons)==5 for c in {x['chapterID'] for x in lessons})
for subject in ('Matematikë','Fizikë','Kimi','Biologji'):
 for level in range(1,6):
  n=sum(x['subject']==subject and x['level']==level for x in lessons)
  assert n>=30 and n%5==0 and sum(x['subject']==subject and x['level']==level for x in exercises)==n
ops={ast.Add:lambda a,b:a+b,ast.Sub:lambda a,b:a-b,ast.Mult:lambda a,b:a*b,ast.Div:lambda a,b:a/b,ast.Pow:lambda a,b:a**b,ast.Mod:lambda a,b:a%b}
fns={k:getattr(math,k) for k in ('sqrt','sin','cos','log','log10','exp','comb','factorial')};fns.update(abs=abs,sum=sum,min=min,max=max)
def evaluate(n):
 if isinstance(n,ast.Constant):return n.value
 if isinstance(n,ast.Name) and n.id=='pi':return math.pi
 if isinstance(n,ast.UnaryOp):return -evaluate(n.operand) if isinstance(n.op,ast.USub) else evaluate(n.operand)
 if isinstance(n,ast.BinOp):return ops[type(n.op)](evaluate(n.left),evaluate(n.right))
 if isinstance(n,(ast.List,ast.Tuple)):return [evaluate(a) for a in n.elts]
 if isinstance(n,ast.Call):return fns[n.func.id](*[evaluate(a) for a in n.args])
 raise AssertionError('Unsupported expression')
numeric=0
for row in lessons:
 assert row['example']['steps'] and row['diagram']['nodes'] and row['chapterIntroduction']
 assert all(s['title']!='Si arsyetojmë' for s in row['sections'])
 assert 0<=row['check']['correct']<len(row['check']['options'])
 assert len(set(row['check']['options']))==len(row['check']['options'])
 for ref in row['exerciseIDs']:
  assert ref in index and index[ref]['subject']==row['subject'] and index[ref]['level']==row['level']
 if 'verification' in row:
  v=row['verification']
  for field,target in [('expression','value'),('check_expression','check_value')]:
   assert math.isclose(evaluate(ast.parse(v[field],mode='eval').body),v[target],rel_tol=1e-10,abs_tol=1e-12),(row['id'],field)
  numeric+=1
for row in exercises:
 assert row['accuracy'] and math.isfinite(row['tolerance']) and row['tolerance']>=0
 assert row['answers'] and row['why'] and row['prompt']
 if row['choices']: assert set(row['answers']).issubset(set(row['choices']))
for file in app.glob('*.plist'):plistlib.loads(file.read_bytes())
plistlib.loads((app/'PrivacyInfo.xcprivacy').read_bytes())
s=(root/'ScienceQuest.xcodeproj/project.pbxproj').read_text()
for file in app.glob('*.swift'):assert 'path = '+file.name+';' in s,file.name
print(f'PASS: {N} lessons, {N} exercises, {N//5} chapters; {N} distinct objective sets; {numeric} worked/check numeric pairs verified; links, grading metadata and project resources valid.')
print('Illustrations:',dict(collections.Counter(x['diagram']['kind'] for x in lessons)))
