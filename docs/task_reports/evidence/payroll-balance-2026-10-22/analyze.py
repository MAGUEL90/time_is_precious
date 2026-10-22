from pathlib import Path
import json
root=Path(__file__).resolve().parent; rows=[]
def clock(m):
 return f"H{m//1440} {m%1440//60:02d}:{m%60:02d}"
for p in sorted(root.glob('sample-*-write.json')):
 d=json.loads(p.read_text()); ms=d['measurements']; last=ms[-1]
 for m in ms:
  salary=sum(s['amount'] for s in d['settlements'] if s['minute']<=m['minute'])
  assert m['earned']==m['sold_wood']*2+m['sold_bricks']*3,(p,m['stage'],'sale mismatch')
  assert m['inventory'].get('shekel',0)+m['city_cash']==m['earned']-m['paid']-salary,(p,m['stage'],'cash mismatch')
 firstsale=next((m for m in ms if m['earned']>0),None)
 built=next((m for m in ms if m['stage']=='built_paid'),None)
 dried=next((m for m in ms if m['stage']=='dried'),None)
 end=next((m for m in ms if m['stage']=='balance_sale_window_end'),last)
 payroll=sum(s['amount'] for s in d['settlements'])
 rows.append({'sample':int(p.name.split('-')[1]),'status':d['status'],'first_income':clock(firstsale['minute']) if firstsale else None,'first_income_shekel':firstsale['earned'] if firstsale else 0,'paid_days':f"H{last.get('paid_from')}–H{last.get('paid_until')}",'built':clock(built['minute']) if built else None,'first_drying':clock(dried['minute']) if dried else None,'window_end':clock(end['minute']),'checkpoint':clock(next(m['minute'] for m in reversed(ms) if m['stage']=='sleep_checkpoint')),'wood_revenue':last['sold_wood']*2,'brick_revenue':last['sold_bricks']*3,'bricks_sold':last['sold_bricks'],'revenue':last['earned'],'fees':d['fees_paid'],'payroll':payroll,'wallet':last['inventory'].get('shekel',0),'city':last['city_cash'],'dry_remaining':last['inventory'].get('sun_dried_mudbrick',0)+last['workshop_stock'].get('sun_dried_mudbrick',0),'wet_remaining':last['workshop_stock'].get('wet_mudbrick',0),'shapes':d['shaped'],'dryings':d['dried'],'satisfaction':last.get('worker_satisfaction'),'reliability':last.get('worker_reliability'),'harvested_dates':last['harvested'],'eaten_dates':last['eaten'],'gather_actions':sum(m['stage'].startswith('gather_') for m in ms),'walked_pixels':round(last['walked_pixels']),'observed_visits':[v['day'] for v in d['visits']]})
(root/'summary.json').write_text(json.dumps(rows,indent=2));print(json.dumps(rows,indent=2))
