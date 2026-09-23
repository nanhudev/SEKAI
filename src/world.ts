import * as T from 'three';
export type Person={id:string;name:string;root:T.Group;home:T.Vector3;phase:number;left:T.Group;right:T.Group;head:T.Object3D;activity:string};
export type Foe={root:T.Group;home:T.Vector3;hp:number;frost:number;frozen:number;burn:number;alive:boolean;attack:number};
export const scene=new T.Scene(); scene.background=new T.Color(0x9ac1bd);scene.fog=new T.FogExp2(0x9ac1bd,.008);
export const people:Person[]=[];export const foes:Foe[]=[];export const interactables:{name:string;position:T.Vector3;action:string}[]=[];
export const trainingDummy=new T.Group();const miraStones:T.Mesh[]=[];
export const spellProps={fire:new T.Group(),frost:new T.Group(),wind:new T.Group()};
export const observer=new T.Group();
export const solids:{minX:number;maxX:number;minZ:number;maxZ:number}[]=[];
const smoke:T.Mesh[]=[];const clouds:T.Mesh[]=[];
const mat=(c:number,roughness=1)=>new T.MeshStandardMaterial({color:c,roughness,flatShading:true});
const grass=mat(0x718960),earth=mat(0x987e5d),stone=mat(0x929990),wood=mat(0x634b37),roof=mat(0x6a5655),leaf=mat(0x496f55),water=new T.MeshStandardMaterial({color:0x5a9fad,roughness:.2,metalness:.1,transparent:true,opacity:.8});
function mesh(g:T.BufferGeometry,m:T.Material,x:number,y:number,z:number,parent:T.Object3D=scene){let a=new T.Mesh(g,m);a.position.set(x,y,z);a.castShadow=true;a.receiveShadow=true;parent.add(a);return a}
function box(w:number,h:number,d:number,m:T.Material,x:number,y:number,z:number,p:T.Object3D=scene){return mesh(new T.BoxGeometry(w,h,d),m,x,y,z,p)}
function cyl(rt:number,rb:number,h:number,m:T.Material,x:number,y:number,z:number,p:T.Object3D=scene){return mesh(new T.CylinderGeometry(rt,rb,h,7),m,x,y,z,p)}
function ball(r:number,m:T.Material,x:number,y:number,z:number,p:T.Object3D=scene){return mesh(new T.IcosahedronGeometry(r,1),m,x,y,z,p)}
function seeded(n:number){let x=n;return()=>{x=(x*1664525+1013904223)>>>0;return x/4294967296}}
const rand=seeded(2718);
export function buildWorld(){
 const sky=new T.Mesh(new T.SphereGeometry(500,32,16),new T.ShaderMaterial({side:T.BackSide,depthWrite:false,uniforms:{},vertexShader:'varying vec3 vPos;void main(){vPos=position;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}',fragmentShader:'varying vec3 vPos;void main(){float h=clamp(normalize(vPos).y*.65+.5,0.,1.);vec3 low=vec3(.73,.82,.79);vec3 high=vec3(.35,.60,.70);gl_FragColor=vec4(mix(low,high,smoothstep(.1,.95,h)),1.);}'}));scene.add(sky);
 for(let i=0;i<15;i++){let c=new T.Mesh(new T.IcosahedronGeometry(7+rand()*9,1),new T.MeshBasicMaterial({color:0xe4eee7,transparent:true,opacity:.22,depthWrite:false}));c.position.set((rand()-.5)*290,85+rand()*50,-90-rand()*190);c.scale.set(2.8,.2,1);scene.add(c);clouds.push(c)}
 scene.add(new T.HemisphereLight(0xcce7e8,0x54664d,2));let sun=new T.DirectionalLight(0xffe3ab,2.2);sun.position.set(-50,95,55);sun.castShadow=true;sun.shadow.mapSize.set(2048,2048);sun.shadow.camera.left=-120;sun.shadow.camera.right=120;sun.shadow.camera.top=120;sun.shadow.camera.bottom=-120;scene.add(sun);
 box(640,.6,640,grass,0,-.4,0); // north is negative z
 const road=mat(0xb59d76);for(let z=-115;z<160;z+=6)box(6,.03,6.1,road,0,.01,z);
 for(let x=-95;x<100;x+=7)box(7,.03,4,road,x,.02,15);
 let river=mesh(new T.PlaneGeometry(12,480),water,35,.04,0);river.rotation.x=-Math.PI/2;box(14,.1,480,earth,35,-.15,0);
 for(let z=-220;z<250;z+=8){let x=35+Math.sin(z*.025)*3;let a=mesh(new T.PlaneGeometry(11,8),water,x,.06,z);a.rotation.x=-Math.PI/2}
 // bridge and wheel
 box(18,.5,6,wood,35,.4,15);for(let i=0;i<7;i++){box(.25,1,6,wood,27+i*2.6,1,15)}let wheel=cyl(3,3,.5,wood,43,2,10);wheel.rotation.z=Math.PI/2;wheel.userData.wheel=true;
 for(let i=0;i<16;i++){let x=-190+i*25;let h=25+rand()*26;cyl(h*.16,h*.3,h,mat(0x688077),x,h/2,-210-rand()*20)}
 for(let i=0;i<10;i++){let x=-210+i*46,h=35+rand()*26;let m=mesh(new T.ConeGeometry(34,h,5),mat(0x7f9c93),x,h*.35,-285-rand()*30);m.rotation.y=rand()*2}
 const house=(x:number,z:number,w:number,d:number,label:string,enter=false)=>{let g=new T.Group();g.position.set(x,0,z);scene.add(g);let plaster=mat(0xb8a887);if(enter){box(w,.14,d,wood,0,.07,0,g);box(w,4,.28,plaster,0,2,-d/2,g);box(.28,4,d,plaster,-w/2,2,0,g);box(.28,4,d,plaster,w/2,2,0,g);box((w-2)/2,4,.28,plaster,-(w+2)/4,2,d/2,g);box((w-2)/2,4,.28,plaster,(w+2)/4,2,d/2,g);box(w,1.2,.28,plaster,0,3.4,d/2,g);box(2,.16,1.2,wood,-w*.25,.65,-d*.15,g);box(1.7,.75,1,wood,w*.23,.4,-d*.2,g);box(.3,1,.3,wood,0,.5,-d*.35,g);interactables.push({name:label,position:new T.Vector3(x,0,z+d/2+1.5),action:'place'});let wall=(cx:number,cz:number,ww:number,dd:number)=>solids.push({minX:x+cx-ww/2,maxX:x+cx+ww/2,minZ:z+cz-dd/2,maxZ:z+cz+dd/2});wall(0,-d/2,w,.28);wall(-w/2,0,.28,d);wall(w/2,0,.28,d);wall(-(w+2)/4,d/2,(w-2)/2,.28);wall((w+2)/4,d/2,(w-2)/2,.28)}else{box(w,4,d,plaster,0,2,0,g);solids.push({minX:x-w/2,maxX:x+w/2,minZ:z-d/2,maxZ:z+d/2})}let r=mesh(new T.ConeGeometry(Math.max(w,d)*.75,3,4),roof,0,5.5,0,g);r.rotation.y=Math.PI/4;for(let sx of [-1,1])box(.8,.8,.14,mat(0xdac9a1),sx*w*.3,2.5,d/2+.09,g);return g};
 house(-17,-10,11,9,'旅馆',true);house(15,4,9,8,'铁匠铺',true);house(-12,34,8,7,'暂住的小屋',true);house(-29,15,8,7,'杂货铺');house(17,-28,8,7,'仓库');house(-36,-19,8,7,'民居');house(18,35,8,7,'民居');house(-64,9,9,8,'老剑士住所');
 for(let i=0;i<6;i++){let m=ball(.55+rand()*.35,new T.MeshBasicMaterial({color:0xc5c7b7,transparent:true,opacity:.16,depthWrite:false}),15,6+i*.8,4);smoke.push(m)}
 // A deliberately framed training court: worn ground, sword rack, banner, and a reactive post.
 box(28,.04,21,mat(0x967e60),-52,.02,22);for(let i=0;i<5;i++){box(.18,1.3,.18,wood,-66+i*7,.65,11);box(.18,1.3,.18,wood,-66+i*7,.65,33)}
 trainingDummy.position.set(-52,0,11);scene.add(trainingDummy);cyl(.4,.52,2,wood,0,1,0,trainingDummy);ball(.48,mat(0x967e61),0,2.1,0,trainingDummy);box(1.8,.16,.2,wood,0,1.55,0,trainingDummy);box(.2,2.3,.2,wood,0,1.15,0,trainingDummy);trainingDummy.userData.lastHit=0;
 box(2.3,.15,.5,wood,-58,1,14);for(let i=0;i<3;i++){let blade=box(.08,1.2,.08,mat(0xb1c4c4),-59+i*.8,1.7,14);blade.rotation.z=.2}box(.12,4,.12,wood,-64,2,20);box(2.2,1.3,.04,mat(0x8c6e65),-62.8,3.2,20);
 // Mira's stones form a calm, readable magical landmark.
 for(let i=0;i<3;i++){let m=ball(.38,mat(0x8ba8ad,.45),7+Math.cos(i*2.1)*1.6,2.8, -28+Math.sin(i*2.1)*1.6);miraStones.push(m)}
 let runeMat=new T.MeshStandardMaterial({color:0x7cb9c8,emissive:0x64adbd,emissiveIntensity:1.5});for(let i=0;i<8;i++)ball(.055,runeMat,7+Math.cos(i*.79)*2,.8+Math.sin(i*.79)*.4,-28+Math.sin(i*.79)*2);
 spellProps.fire.position.set(12,0,-23);scene.add(spellProps.fire);cyl(.35,.4,1.4,mat(0xb69b62),0,.8,0,spellProps.fire);ball(.65,mat(0xc4ad75),0,1.65,0,spellProps.fire);
 spellProps.frost.position.set(3,0,-24);scene.add(spellProps.frost);cyl(.4,.5,.8,stone,0,.55,0,spellProps.frost);ball(.4,runeMat,0,1.2,0,spellProps.frost);
 spellProps.wind.position.set(1,0,-31);scene.add(spellProps.wind);for(let i=0;i<3;i++)box(.9,.9,.9,wood,i*.9,.5,0,spellProps.wind);
 // Riverbank stones and reeds add a readable edge to the water.
 for(let i=0;i<100;i++){let z=(rand()-.5)*300;let side=i%2?1:-1;let x=35+side*(6.3+rand()*2);ball(.25+rand()*.35,stone,x,.15,z);if(i%3===0)for(let j=0;j<3;j++)cyl(.015,.025,1.1+rand()*.5,mat(0x819d6c),x+j*.15,.7,z+j*.1)}
 cyl(1.7,1.9,1.5,stone,-7,.75,5);cyl(1.25,1.25,.07,mat(0x253b3a),-7,1.53,5);box(4,.3,.6,wood,-7,3,5);
 for(let i=0;i<40;i++){let x=58+(i%8)*5,z=-55+Math.floor(i/8)*9;box(3,.06,6,mat(0x785e42),x,.02,z);for(let j=0;j<4;j++)ball(.25,mat(0x809764),x-1+j*.65,.45,z)}
 for(let i=0;i<14;i++){let x=-93+(i%4)*4,z=-50+Math.floor(i/4)*7;cyl(.14,.2,7,mat(0x6d916c),x,3.5,z);ball(1.2,mat(0x789b6f),x,6.7,z)}
 // paths and ecological tree bands
 const trunk=new T.CylinderGeometry(.3,.5,5,5),crown=new T.IcosahedronGeometry(2.6,0);let tm=new T.InstancedMesh(trunk,wood,500),cm=new T.InstancedMesh(crown,leaf,500);let dummy=new T.Object3D(),count=0;
 for(let i=0;i<620&&count<500;i++){let x=(rand()-.5)*430,z=(rand()-.5)*440;let away=Math.hypot(x,z);if(away<42||Math.abs(x)<5||Math.abs(x-35)<10||x>52&&x<105&&z>-65&&z<5)continue;let north=z< -80;if(!north&&rand()>.45)continue;let s=.6+rand()*.75;dummy.position.set(x,2.3*s,z);dummy.scale.set(s,s,s);dummy.updateMatrix();tm.setMatrixAt(count,dummy.matrix);dummy.position.y=5*s;dummy.updateMatrix();cm.setMatrixAt(count,dummy.matrix);count++}tm.count=cm.count=count;tm.castShadow=true;cm.castShadow=true;scene.add(tm,cm);
 for(let i=0;i<140;i++){let x=(rand()-.5)*220,z=(rand()-.5)*200;if(Math.abs(x)<6||Math.hypot(x,z)<15)continue;let lush=Math.abs(x-35)<23;ball((lush?.6:.35)+rand()*.3,mat(lush?0x54745b:0x81966a),x,.25,z)}
 const flowerGeo=new T.IcosahedronGeometry(.1,0),flowerMat=mat(0xe9dba8),flowers=new T.InstancedMesh(flowerGeo,flowerMat,500),fd=new T.Object3D();for(let i=0;i<500;i++){let x=(rand()-.5)*170,z=(rand()-.5)*190;if(Math.abs(x)<6)x+=8;if(Math.abs(x-35)<7)x+=8;fd.position.set(x,.12,z);fd.scale.setScalar(.7+rand()*.8);fd.updateMatrix();flowers.setMatrixAt(i,fd.matrix)}scene.add(flowers);
 for(let i=0;i<22;i++){let x=-130+rand()*260,z=-135-rand()*65;cyl(1+rand()*2,4+rand()*5,5+rand()*9,stone,x,4,z)}
 observer.position.set(-47,0,-72);scene.add(observer);cyl(.23,.3,2.1,mat(0x141c20),0,1.1,0,observer);ball(.24,mat(0x10171a),0,2.35,0,observer);observer.visible=false;
 // furniture and human traces
 for(let i=0;i<18;i++){let x=-37+(i%6)*12,z=-35+Math.floor(i/6)*30;box(2,1,.2,wood,x,.5,z);box(.2,1,2,wood,x-1,.5,z);box(.2,1,2,wood,x+1,.5,z)}
 for(let i=0;i<12;i++){let x=-25+rand()*50,z=-36+rand()*70;box(.9,.9,.9,wood,x,.45,z)}
 for(let i=0;i<10;i++){let z=-35+i*11;box(.25,3,.25,wood,5,1.5,z);ball(.23,mat(0xffce75),5,3.15,z)}
 function npc(id:string,name:string,x:number,z:number,color:number){let g=new T.Group();g.position.set(x,0,z);scene.add(g);cyl(.45,.52,1.45,mat(color),0,1.05,0,g);let head=ball(.38,mat(0xd0a783),0,2.05,0,g);box(.9,.12,.2,mat(0x3b3634),0,2.35,0,g);let left=new T.Group(),right=new T.Group();left.position.set(-.52,1.65,0);right.position.set(.52,1.65,0);g.add(left,right);cyl(.13,.15,1.05,mat(color),0,-.43,0,left);cyl(.13,.15,1.05,mat(color),0,-.43,0,right);ball(.15,mat(0xd0a783),0,-.96,0,left);ball(.15,mat(0xd0a783),0,-.96,0,right);people.push({id,name,root:g,home:g.position.clone(),phase:rand()*10,left,right,head,activity:'idle'})}
 npc('lia','莉娅',-7,0,0x77987c);npc('oren','奥伦',-57,17,0x817767);npc('mira','米拉',7,-28,0x657ca0);npc('garran','格兰',15,8,0x7f5c4d);npc('arn','阿诺',-20,25,0xb9925d);
 for(let i=0;i<3;i++){let x=-20+i*12,z=-105-i*7;let g=new T.Group();g.position.set(x,0,z);scene.add(g);cyl(.7,.9,1.2,stone,0,.8,0,g);ball(.65,mat(0x75b5a9,.3),0,1.7,0,g);for(let j=0;j<3;j++)ball(.3,stone,Math.cos(j*2.1)*.8,1.2,Math.sin(j*2.1)*.8,g);foes.push({root:g,home:g.position.clone(),hp:100,frost:0,frozen:0,burn:0,alive:true,attack:0})}
 // hidden altar
 for(let i=0;i<6;i++)cyl(.55,.7,4,stone,-69+Math.cos(i)*4,2,-158+Math.sin(i)*4);ball(.9,new T.MeshStandardMaterial({color:0x72cfc6,emissive:0x3c8e89,emissiveIntensity:2}),-69,2,-158);interactables.push({name:'古老符文',position:new T.Vector3(-69,0,-158),action:'rune'});
}
export function updateWorld(t:number,dt:number,player:T.Vector3){for(let p of people){let target=p.home.clone();if(p.id==='lia'&&p.activity==='guide')target.set(-11,0,31);if(p.id==='arn'){let points=[[-20,25],[-10,8],[10,8],[-44,18]];let q=points[Math.floor(t/24)%points.length];target.set(q[0],0,q[1])}if(p.id==='garran')target.set(15+Math.sin(t*.14)*1.2,0,8);let v=target.sub(p.root.position);v.y=0;let moving=v.length()>.35;if(p.id==='lia'&&p.activity==='guide'&&player.distanceTo(p.root.position)>7)moving=false;if(moving){let distance=v.length();v.normalize();p.root.position.addScaledVector(v,Math.min(distance,dt*(p.id==='lia'&&p.activity==='guide'?2.7:1.4)));p.root.rotation.y=Math.atan2(v.x,v.z)}else if(player.distanceTo(p.root.position)<6)p.root.rotation.y=T.MathUtils.damp(p.root.rotation.y,Math.atan2(player.x-p.root.position.x,player.z-p.root.position.z),3,dt);let beat=Math.sin(t*(p.id==='oren'?2.4:3)+p.phase);p.root.position.y=Math.sin(t*1.7+p.phase)*.025+(moving?Math.abs(beat)*.04:0);p.left.rotation.x=moving?beat*.27:p.id==='mira'?-.5+Math.sin(t*2)*.15:0;p.right.rotation.x=moving?-beat*.27:p.id==='oren'?-1.1+beat*.4:p.id==='garran'?-1.1+beat*.65:p.id==='mira'?-1+Math.sin(t*1.5)*.3:0;p.head.rotation.y=Math.sin(t*.7+p.phase)*.12}
 for(let i=0;i<miraStones.length;i++){let m=miraStones[i],a=t*.6+i*Math.PI*2/3;m.position.set(7+Math.cos(a)*1.6,2.8+Math.sin(t*1.4+i)*.22,-28+Math.sin(a)*1.6);m.rotation.set(t*.7+i,t*.4,0)}trainingDummy.rotation.z=T.MathUtils.damp(trainingDummy.rotation.z,0,5,dt);
 for(let i=0;i<clouds.length;i++)clouds[i].position.x+=dt*(i%2?.3:.5);for(let i=0;i<smoke.length;i++){smoke[i].position.y=6+((t*.7+i*.7)%5);smoke[i].position.x=15+Math.sin(t*.3+i)*.5;smoke[i].scale.setScalar(1+((t*.7+i*.7)%5)*.2)}
 for(let f of foes){if(!f.alive)continue;f.frozen=Math.max(0,f.frozen-dt);f.burn=Math.max(0,f.burn-dt);if(f.burn>0)f.hp-=dt*5;if(f.hp<=0){f.alive=false;scene.remove(f.root);continue}let d=player.distanceTo(f.root.position);if(d<20&&f.frozen<=0){let v=player.clone().sub(f.root.position);v.y=0;v.normalize();f.root.position.addScaledVector(v,dt*(d>2.5?1.9:0));f.root.rotation.y=Math.atan2(v.x,v.z)}else if(f.frozen<=0){f.root.position.x=f.home.x+Math.sin(t*.4+f.home.x)*2;f.root.position.z=f.home.z+Math.cos(t*.4+f.home.z)*2}f.root.position.y=f.frozen>0?0:Math.sin(t*3+f.home.x)*.13;f.root.scale.setScalar(f.frozen>0?.92:1)}
}
