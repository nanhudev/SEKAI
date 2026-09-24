import * as T from 'three';

// Spatial massing for MVP 0.4. These in-engine forms mark the intended landmarks
// and circulation; finish geometry will be replaced by Chat2Blender modules.
export function buildTownBlockout(scene:T.Scene){
 const stone=new T.MeshStandardMaterial({color:0x9c9d8d,roughness:1,flatShading:true});
 const timber=new T.MeshStandardMaterial({color:0x5c4538,roughness:1,flatShading:true});
 const plaster=new T.MeshStandardMaterial({color:0xc8b898,roughness:1,flatShading:true});
 const dark=new T.MeshStandardMaterial({color:0x455f5b,roughness:1,flatShading:true});
 const leaf=new T.MeshStandardMaterial({color:0x668660,roughness:1,flatShading:true});
 const gold=new T.MeshStandardMaterial({color:0xc7aa75,roughness:.5,metalness:.2});
 const add=(g:T.BufferGeometry,m:T.Material,x:number,y:number,z:number)=>{let o=new T.Mesh(g,m);o.position.set(x,y,z);o.castShadow=true;o.receiveShadow=true;scene.add(o);return o};
 const box=(w:number,h:number,d:number,m:T.Material,x:number,y:number,z:number)=>add(new T.BoxGeometry(w,h,d),m,x,y,z);
 const cyl=(r1:number,r2:number,h:number,m:T.Material,x:number,y:number,z:number,n=8)=>add(new T.CylinderGeometry(r1,r2,h,n),m,x,y,z);
 // Square: visible from the south road, with a meeting tree and stone edge.
 let square=cyl(12,12,.07,stone,-4,.045,-2,12);square.scale.z=.8;
 cyl(2.5,2.7,.55,stone,-8,.25,-5,10);
 cyl(.95,1.2,8,timber,-8,4.3,-5,8);
 for(const [x,y,z,s] of [[-8,10,-5,4.8],[-11,8.5,-5,3.5],[-5,9,-5,3.8],[-8,12,-4,2.9]] as [number,number,number,number][])add(new T.IcosahedronGeometry(s,1),leaf,x,y,z);
 // Guild is visually identifiable even before the full tavern kit arrives.
 box(13,.55,1.3,timber,-17,4.4,-5.4);
 box(8,.15,.25,gold,-17,6.8,-5.2);
 box(1.3,3,.35,timber,-22,5.3,-5.2);box(1.3,3,.35,timber,-12,5.3,-5.2);
 let guildRoof=add(new T.ConeGeometry(10,4,4),dark,-17,8,-10);guildRoof.rotation.y=Math.PI/4;
 // Bell tower across the bridge anchors the east skyline and explains the alarm.
 box(7,12,7,plaster,60,6,18);for(let y of [2,9]){box(7.6,.55,7.6,stone,60,y,18)}
 for(let x of [56.6,63.4])for(let z of [14.6,21.4])box(.45,12,.45,timber,x,6,z);
 for(let y of [9.5,11])box(2.1,.22,.3,timber,60,y,21.7);
 cyl(.75,.75,1.1,gold,60,10.2,18,12);
 let cap=add(new T.ConeGeometry(5.8,5,4),dark,60,14.5,18);cap.rotation.y=Math.PI/4;
 // North gate, two flanking wall masses, and a clear passage to the forest.
 for(const x of [-7,7]){box(3.6,8,4,stone,x,4,-65);box(4.2,.4,4.4,timber,x,8.1,-65)}
 box(11,1,4,timber,0,8.4,-65);
 for(const x of [-24,24])box(27,3.5,2,stone,x,1.75,-65);
 // Framed market and small garden pockets, kept off the main walking axis.
 for(const [x,z] of [[-25,23],[-32,25],[15,24],[23,24]] as [number,number][]) {box(4,.25,2,timber,x,1.1,z);for(const dx of [-1.7,1.7])box(.17,2,.17,timber,x+dx,1,z);let roof=box(4.7,.12,2.7,dark,x,2.2,z);roof.rotation.z=x<0?.08:-.08}
 for(const [x,z] of [[-24,39],[20,42],[-27,-35],[18,-39]] as [number,number][]) {box(7,.12,4,stone,x,.04,z);for(let i=0;i<5;i++)add(new T.IcosahedronGeometry(.35,0),leaf,x-2.5+i*1.2,.38,z)}
}
