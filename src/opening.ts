import * as T from 'three';
import {scene, type Person} from './world';

// Short authored shots build the town, the distant duel, and a continuous first-person recovery.
export class Opening {
 elapsed=0;complete=false;
 private veil=document.createElement('div');
 private caption=document.createElement('div');
 private beat=-1;
 private battle=new T.Group();
 private king=new T.Mesh(new T.CapsuleGeometry(.35,1.3,4,6),new T.MeshBasicMaterial({color:0xf8f0dc}));
 private mage=new T.Mesh(new T.CapsuleGeometry(.4,1.4,4,6),new T.MeshBasicMaterial({color:0x172c38}));
 private slash=new T.Mesh(new T.PlaneGeometry(26,.12),new T.MeshBasicMaterial({color:0xfff6db,side:T.DoubleSide,transparent:true,opacity:0}));
 private circle=new T.Mesh(new T.RingGeometry(3.5,4,48),new T.MeshBasicMaterial({color:0x8ad8dc,side:T.DoubleSide,transparent:true,opacity:0}));
 private glow=new T.PointLight(0xbdeffc,0,60);
 constructor(private camera:T.PerspectiveCamera,private lia:Person,private line:(text:string)=>void,private cue:(name:string)=>void){
  this.veil.id='cinematic-veil';this.caption.id='cinematic-caption';document.body.append(this.veil,this.caption);
  this.veil.style.background='#02070a';this.veil.style.opacity='0';this.caption.textContent='';
  this.battle.add(this.king,this.mage,this.slash,this.circle,this.glow);scene.add(this.battle);
  this.battle.position.set(-18,45,-190);this.king.position.set(-5,0,0);this.mage.position.set(5,2,0);
  this.slash.position.z=1;this.circle.position.copy(this.mage.position);this.circle.rotation.x=-.25;
  this.lia.root.position.set(-13,0,44);this.lia.activity='opening';this.camera.rotation.order='YXZ';
 }
 private shot(i:number,p:T.Vector3,target:T.Vector3){if(this.beat!==i){this.beat=i;this.cue('shot-'+i)}this.camera.position.copy(p);this.camera.lookAt(target)}
 private at(x:number,y:number,z:number){return new T.Vector3(x,y,z)}
 update(dt:number){if(this.complete)return;this.elapsed+=dt;const e=this.elapsed;
  this.slash.material.opacity=0;this.circle.material.opacity=0;this.glow.intensity=0;this.veil.style.opacity='0';
  if(e<3)this.shot(1,this.at(-15,.45,72-e*5),this.at(-10,1,32));
  else if(e<6)this.shot(2,this.at(-31,11,29),this.at(-8,4,7));
  else if(e<8.5)this.shot(3,this.at(-22,2.4,32-(e-6)*5),this.at(1,2,3));
  else if(e<11.5)this.shot(4,this.at(-12,3.4,11),this.at(-5,2,2));
  else if(e<14)this.shot(5,this.at(43,3,28-(e-11.5)*8),this.at(34,1,-22));
  else if(e<17)this.shot(6,this.at(-7,6,15),this.at(-25,33,-250));
  else if(e<19){this.shot(7,this.at(-5,8,5),this.at(-18,45,-190));this.slash.material.opacity=.9;this.slash.rotation.z=.3}
  else if(e<21)this.shot(8,this.at(-6,24,-95),this.at(-18,45,-190));
  else if(e<25){let k=(e-21)/4;this.shot(9,this.at(-9+k*5,40,-145),this.at(-18,45,-190));this.king.position.x=-5+k*10;this.slash.material.opacity=e<22.4||e>24.3?0:1;this.slash.scale.x=.25+k*.7;this.circle.material.opacity=e>22.3?.65:0;this.glow.intensity=e>22.3?5:0}
  else if(e<29){this.shot(10,this.at(-10,34,-135),this.at(-18,45,-190));this.circle.material.opacity=.7;this.circle.scale.setScalar(1+(e-25)*.25);this.glow.intensity=4}
  else if(e<33){this.shot(11,this.at(-20,18,-110),this.at(-18,45,-190));this.king.position.set(-5-(e-29)*3,(e-29)*2,0);this.circle.material.opacity=.95;this.glow.intensity=8}
  else if(e<37){this.shot(12,this.at(-28,8,-92),this.at(-29,24,-265));this.slash.material.opacity=e<34.5?1:0;this.slash.position.set(-6,3,1);this.slash.scale.set(1.8,.7,1)}
  else if(e<40)this.shot(13,this.at(2,3,11),this.at(-25,24,-260));
  else if(e<44){this.shot(14,this.at(-7,12,-40),this.at(-18,45,-190));this.circle.material.opacity=.6;this.circle.scale.setScalar(1+(e-40)*.55);this.glow.intensity=8+(e-40)*5}
  else if(e<46){this.shot(15,this.at(-5,8,22),this.at(-18,45,-190));this.veil.style.background='#edfff7';this.veil.style.opacity=String(Math.min(1,(e-44)*2))}
  else if(e<49){this.shot(16,this.at(-7,.25,65),this.at(-7,8,40));this.veil.style.background='#02070a';this.veil.style.opacity=String(Math.max(0,1-(e-46)/3))}
  else if(e<58){let k=T.MathUtils.smoothstep(e,49,57);this.shot(17,this.at(-7,T.MathUtils.lerp(.3,1.7,k),65),this.at(-7,T.MathUtils.lerp(8,1.7,k),39));this.camera.rotation.z=Math.sin(k*Math.PI)*-.055;this.veil.style.background='#02070a';this.veil.style.opacity=String(Math.max(0,.55-(e-49)*.12))}
  else{this.complete=true;scene.remove(this.battle);this.caption.remove();this.veil.remove();this.lia.activity='guide';this.lia.root.position.set(-8,0,53);this.line('');this.camera.position.set(-7,1.7,65);this.camera.rotation.set(0,0,0)}
 }
}
