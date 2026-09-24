import * as T from 'three';
import type {Person} from './world';

// A single continuous camera path. Dialogue is sparse; the village reveal carries the scene.
export class Opening {
  elapsed=0;
  complete=false;
  private caption=document.createElement('div');
  private veil=document.createElement('div');
  private said=new Set<number>();
  constructor(private camera:T.PerspectiveCamera,private lia:Person,private line:(text:string)=>void,private cue:(name:string)=>void){
    this.caption.id='cinematic-caption';this.veil.id='cinematic-veil';document.body.append(this.veil,this.caption);
    this.camera.rotation.order='YXZ';this.lia.root.position.set(-13,0,44);this.lia.activity='opening';
  }
  private once(at:number,text:string){if(this.elapsed>=at&&!this.said.has(at)){this.said.add(at);this.line(text);this.caption.textContent=text}}
  update(dt:number){if(this.complete)return;this.elapsed+=dt;const e=this.elapsed;
    if(e<4){this.veil.style.background='#030507';this.veil.style.opacity='1';this.camera.position.set(-7,.35,65);this.camera.rotation.set(1.2,0,0);if(e>1&&!this.said.has(1)){this.said.add(1);this.cue('city')}return}
    if(e<5.4){this.veil.style.background='#e9fff7';this.veil.style.opacity='1';if(!this.said.has(4)){this.said.add(4);this.cue('flash')}return}
    this.veil.style.background='#030507';this.veil.style.opacity=String(Math.max(0,1-(e-5.4)/5));
    if(e<41){const blink=e<13?Math.max(0,.75-(e-6)*.1):0;this.veil.style.opacity=String(Math.max(Number(this.veil.style.opacity),blink));this.camera.position.set(-7,.38+Math.sin(e*.3)*.015,65);this.camera.rotation.x=T.MathUtils.lerp(1.15,.47,T.MathUtils.smoothstep(e,10,31));this.camera.rotation.y=-.03;
      if(e>15&&e<32){let k=T.MathUtils.smoothstep(e,15,27);this.lia.root.position.set(T.MathUtils.lerp(-13,-7.8,k),0,T.MathUtils.lerp(44,61,k));this.lia.root.rotation.y=2.8;this.lia.left.rotation.x=Math.sin(e*11)*.4;this.lia.right.rotation.x=-Math.sin(e*11)*.4}
      if(e>=32){this.lia.root.position.set(-7.8,0,61);this.lia.root.rotation.y=0;this.lia.root.scale.y=1-T.MathUtils.smoothstep(e,32,37)*.35;this.lia.right.rotation.x=-1.2+Math.sin(e*2)*.1}
      this.once(31,'喂。');this.once(35,'听得见吗？');this.once(40,'……还活着。');
    }else if(e<62){let k=T.MathUtils.smoothstep(e,41,59);this.camera.position.set(-7,T.MathUtils.lerp(.38,1.7,k),65);this.camera.rotation.x=T.MathUtils.lerp(.47,.02,k);this.camera.rotation.y=-.03;this.lia.root.scale.y=T.MathUtils.lerp(.65,1,T.MathUtils.smoothstep(e,44,54));this.lia.right.rotation.x=T.MathUtils.lerp(-1.2,0,k);this.once(51,'河水声。远处有人在说话。');this.cue('reveal')}
    else if(e<75){this.camera.position.set(-7,1.7,65);this.camera.rotation.x=.02;this.camera.rotation.y=-.03;let k=T.MathUtils.smoothstep(e,62,70);this.lia.root.position.set(T.MathUtils.lerp(-7.8,-8,k),0,T.MathUtils.lerp(61,53,k));this.lia.root.scale.y=1;this.lia.root.rotation.y=T.MathUtils.lerp(0,Math.PI,k);this.lia.right.rotation.x=e>69?-.9:0;this.once(66,'能站起来吗？');this.once(71,'先去村里。')}
    else{this.complete=true;this.caption.remove();this.veil.remove();this.lia.activity='guide';this.lia.root.scale.y=1;this.line('')}
  }
}
