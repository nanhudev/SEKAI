"""Offline SA3 SFX regeneration. Generate to E:, then explicitly install reviewed takes."""
from pathlib import Path
import os,sys,json,hashlib,wave,math,argparse,shutil,struct
ROOT=Path(__file__).resolve().parents[2]
OUT=Path('E:/SEKAI-SwordFeelV2-20261012/audio')
os.environ['HF_HOME']=str(OUT/'cache')
os.environ['HF_HUB_OFFLINE']='1'
os.environ['TRANSFORMERS_OFFLINE']='1'
os.environ['PYTHONDONTWRITEBYTECODE']='1'
# Let PyTorch use the processor's available instruction set.
os.environ['OMP_NUM_THREADS']='1'
os.environ['MKL_NUM_THREADS']='1'
sys.path.insert(0,'F:/SEKAI-WT/audio-dev/audio_source/tools')
sys.path.insert(0,'F:/SEKAI-AUDIO/stable-audio-3')
import numpy as np
JOBS=[
 ('draw','Real steel katana blade drawn from a close wooden scabbard, short scraping metal friction, tiny hollow air release, dry close microphone, one action, no music no voices',.44),
 ('swing_a1','Single precise light katana cut, short sharp dry thin air cut with a subtle steel flick, quick controlled wrist action, no music no voices',.22),
 ('swing_a2','Single heavy steel sword return cut across the body, dense displaced air and a restrained low metal resonance, dry close sound, no music no voices',.34),
 ('swing_a3','Single rising uppercut with a weighted steel sword, ascending air rush, compact arm and cloth pull, dry realistic close recording, no music no voices',.39),
 ('swing_a4','Single broad finishing sweep with a heavy katana, wide air pressure followed by a short resonant steel tail, forceful controlled cut, no explosion no music no voices',.52),
 ('hit_metal','One steel katana contacting a metal plate, bright short clang, sharp attack and dry metallic ringing tail, no music no voices',.32),
 ('hit_body','One blunt close impact against dense flesh and padded leather, compact low thud with a restrained cutting contact, dry foley, no music no voices',.24),
 ('hit_stone','One sharp heavy steel blade strike against rough stone, hard dense click and tiny gritty fragments, dry short resonant body, no explosion no music no voices',.36),
 ('hit_wood','One steel blade cutting a dry wooden training post, short hard wood crack and fibrous contact, close dry foley, no music no voices',.28),
 ('iaido_cut','One extremely fast steel sword draw and cut, brief hard metallic transient followed by a tight dry slicing snap, controlled precise sound effect, no music no voices',.23),
 ('iaido_pressure','One short low frequency spatial pressure fracture, taut deep wooden creak breaking into a compact low thud, subtle air vacuum, no explosion no music no voices',.38),
 ('sheath_slide','Steel katana blade slowly sliding into lacquered wooden scabbard, close dry metallic friction and hollow wooden air texture, controlled single insertion, no music no voices',.52),
 ('sheath_click','One katana hilt fully seating against wooden scabbard mouth, crisp small wooden clack with a tiny dry metal latch tick, satisfying single closure, no ringing no music no voices',.15),
 ('parry','Single steel blade deflecting another steel blade, sharp bright tight metallic clash and a very short ringing edge, dry close microphone, no music no voices',.27),
]

def read_wav(path):
 with wave.open(str(path)) as w:
  if w.getsampwidth()!=2: raise ValueError('PCM16 required')
  sr=w.getframerate();channels=w.getnchannels()
  data=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').astype(np.float32).reshape(-1,channels)/32768
 return sr,data

def process(raw,target,duration):
 sr,data=read_wav(raw)
 peak=float(np.max(np.abs(data))); clipped=float(np.mean(np.abs(data)>=.999))
 if peak<.001 or clipped>.05: raise ValueError(f'unusable take peak={peak} clipping={clipped}')
 # Choose the first clear action, preserve attack lead and remove DC, not the timbre.
 mono=np.max(np.abs(data),axis=1)
 window=max(1,int(.008*sr)); env=np.convolve(mono,np.ones(window)/window,'same')
 active=np.flatnonzero(env>max(.004,float(env.max())*.14))
 start=max(0,int(active[0])-int(.012*sr)) if active.size else int(env.argmax())
 count=int(duration*sr); start=min(start,max(0,len(data)-count))
 data=data[start:start+count].copy();data-=data.mean(axis=0)
 if len(data)<count:data=np.pad(data,((0,count-len(data)),(0,0)))
 data*=min(3.0,.50/max(float(np.max(np.abs(data))),1e-6))
 fade_in=min(len(data)//4,int(.004*sr));fade_out=min(len(data)//3,int(.045*sr))
 data[:fade_in]*=np.linspace(0,1,fade_in)[:,None]
 data[-fade_out:]*=np.linspace(1,0,fade_out)[:,None]
 target.parent.mkdir(parents=True,exist_ok=True)
 with wave.open(str(target),'wb') as w:
  w.setnchannels(data.shape[1]);w.setsampwidth(2);w.setframerate(sr);w.writeframes((data*32767).astype('<i2').tobytes())
 fft=np.abs(np.fft.rfft(data.mean(axis=1)))**2;freq=np.fft.rfftfreq(len(data),1/sr)
 return {'trim_start':start/sr,'processed_duration':duration,'raw_peak':peak,'raw_clipped_fraction':clipped,
         'peak_db':20*math.log10(max(float(np.max(np.abs(data))),1e-8)),
         'rms_db':20*math.log10(max(float(np.sqrt(np.mean(data*data))),1e-8)),
         'energy_below_200hz':float(fft[freq<200].sum()/max(fft.sum(),1e-9)),
         'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}

def generate():
 import torch
 from sfx_provider import get_provider
 torch.set_num_threads(4)
 torch.set_default_dtype(torch.bfloat16)
 torch.backends.mkldnn.enabled=False
 # The installed Windows bridge cannot load this >2GB checkpoint as one
 # storage/bytes object. Read each declared tensor instead; weights are unchanged.
 import safetensors.torch as safetensors_torch
 def load_cpu_bytes(filename,device='cpu',**kwargs):
  state={}
  dtypes={'F32':'<f4','F16':'<f2','BF16':'<u2','F64':'<f8','I64':'<i8','I32':'<i4','I16':'<i2','I8':'i1','U8':'u1','BOOL':'?'}
  with open(filename,'rb') as weights:
   size=struct.unpack('<Q',weights.read(8))[0];header=json.loads(weights.read(size));base=8+size
   for key,info in header.items():
    if key=='__metadata__':continue
    start,end=info['data_offsets'];weights.seek(base+start)
    array=np.frombuffer(weights.read(end-start),dtype=dtypes[info['dtype']]).copy().reshape(info['shape'])
    value=torch.from_numpy(array)
    if info['dtype']=='BF16':value=value.view(torch.bfloat16)
    state[key]=value if str(device)=='cpu' else value.to(device)
  return state
 safetensors_torch.load_file=load_cpu_bytes
 import stable_audio_3.loading_utils as loading_utils
 loading_utils.load_file=load_cpu_bytes
 provider=get_provider('stable-audio-3-small-sfx',device='cpu',mirror=Path('F:/SEKAI-AUDIO/models'))
 # Build in reduced precision to avoid the native Windows allocation failure,
 # then run CPU inference in FP32 with native vector kernels.
 provider.load()
 provider._model.model.to(torch.float32)
 torch.set_default_dtype(torch.float32)
 torch.backends.mkldnn.enabled=True
 for conditioner in provider._model.model.conditioner.conditioners.values():
  external=getattr(conditioner,'model',None)
  if external is not None: external.to(torch.float32)
 print('CPU inference precision: float32',flush=True)
 OUT.mkdir(parents=True,exist_ok=True)
 manifest=OUT/'manifest.json';entries=json.loads(manifest.read_text()) if manifest.exists() else []
 for index,(name,prompt,duration) in enumerate(JOBS):
  if any(row['name']==name and Path(row['processed_path']).exists() for row in entries):continue
  for attempt in range(2):
   seed=20261012+index*137+attempt*41
   raw=OUT/'raw'/f'{name}_{seed}.wav';target=OUT/'processed'/f'{name}.wav'
   print('GENERATE',name,seed,flush=True)
   entry=provider.generate('TrackType: SFX, '+prompt,2.0,seed,raw)
   try:entry.update(process(raw,target,duration))
   except ValueError as exc:
    print('REJECT',name,str(exc),flush=True);continue
   entry.update({'name':name,'processed_path':str(target),'selected':True,'review':'signal checked; perceptual review pending','inference_precision':'float32; bfloat16 construction'})
   entries.append(entry);manifest.write_text(json.dumps(entries,indent=2),encoding='utf-8')
   print('READY',name,'wall_seconds',entry['seconds_wall'],flush=True);break
  else:raise RuntimeError('No usable take for '+name)

def install():
 entries=json.loads((OUT/'manifest.json').read_text())
 if len(entries)!=len(JOBS):raise RuntimeError('Full bank not generated')
 dest=ROOT/'godot/audio/sfx/weapons/sword/feel_v2';dest.mkdir(parents=True,exist_ok=True)
 rows=[]
 for entry in entries:
  name=entry['name'];shutil.copy2(entry['processed_path'],dest/(name+'.wav'))
  rows.append({'id':'feel_v2_'+name,'file':name+'.wav','dir':'res://audio/sfx/weapons/sword/feel_v2/',
               'category':'sword','role':name,'group':'feel_v2_'+name,'peak':entry['peak_db'],
               'loudness':entry['rms_db'],'pitch_min':.99,'pitch_max':1.01,
               'note':'Local Stable Audio 3 SFX; seed '+str(entry['seed'])})
 # JSON is data, read by the existing registry rather than another playback system.
 (dest/'manifest.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
 print('INSTALLED',len(rows),'local generated sounds',flush=True)

if __name__=='__main__':
 args=argparse.ArgumentParser();args.add_argument('--install',action='store_true');options=args.parse_args()
 install() if options.install else generate()

