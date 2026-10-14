import * as T from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import wallPlainUrl from '../assets/models/mistvale/wall_plain.glb?url';
import wallWindowUrl from '../assets/models/mistvale/wall_window.glb?url';
import wallDoorUrl from '../assets/models/mistvale/wall_door.glb?url';
import beamUrl from '../assets/models/mistvale/beam.glb?url';
import roofUrl from '../assets/models/mistvale/roof_slope.glb?url';
import doorUrl from '../assets/models/mistvale/door.glb?url';
import windowUrl from '../assets/models/mistvale/window.glb?url';
import foundationUrl from '../assets/models/mistvale/foundation.glb?url';
import fenceUrl from '../assets/models/mistvale/fence.glb?url';
import stairUrl from '../assets/models/mistvale/stair.glb?url';
import chimneyUrl from '../assets/models/mistvale/chimney.glb?url';
import signUrl from '../assets/models/mistvale/sign.glb?url';

const sources = {
  wallPlain: wallPlainUrl, wallWindow: wallWindowUrl, wallDoor: wallDoorUrl,
  beam: beamUrl, roof: roofUrl, door: doorUrl, window: windowUrl,
  foundation: foundationUrl, fence: fenceUrl, stair: stairUrl,
  chimney: chimneyUrl, sign: signUrl,
};

export async function addMistvaleTown(scene: T.Scene) {
  const loader = new GLTFLoader();
  const entries = await Promise.all(Object.entries(sources).map(async ([name, url]) => [name, (await loader.loadAsync(url)).scene] as const));
  const models = Object.fromEntries(entries) as Record<keyof typeof sources, T.Group>;
  for(const [hx,hz,scale,label] of [[18,35,1,'East cottage'],[-17,-10,1.8,'Guild tavern'],[15,4,1.45,'Blacksmith']] as [number,number,number,string][]){
  const house = new T.Group();house.name='Mistvale '+label;house.position.set(hx,0,hz);house.scale.setScalar(scale);scene.add(house);

  const add = (key: keyof typeof sources, x: number, y: number, z: number, rotation = 0, scaleX = 1) => {
    const part = models[key].clone(true);
    part.position.set(x, y, z);
    part.rotation.y = rotation;
    part.scale.x = scaleX;
    part.traverse(object => {
      if (object instanceof T.Mesh) { object.castShadow = key === 'roof'; object.receiveShadow = true; }
    });
    house.add(part);
    return part;
  };

  for (const x of [-1.5, 1.5]) for (const z of [-1.5, 1.5]) add('foundation', x, 0, z);
  add('wallDoor', -1.5, .35, 2.2);
  add('wallWindow', 1.5, .35, 2.2);
  add('wallPlain', -1.5, .35, -2.2, Math.PI);
  add('wallWindow', 1.5, .35, -2.2, Math.PI);
  add('wallPlain', -3, .35, 0, -Math.PI / 2, 1.46);
  add('wallPlain', 3, .35, 0, Math.PI / 2, 1.46);
  add('door', -1.5, .35, 2.31);
  add('window', 1.5, .35, 2.32);
  for (const x of [-1.5, 1.5]) {
    add('roof', x, 3.38, 1.1);
    add('roof', x, 3.38, -1.1, Math.PI);
  }
  add('beam', 0, 4.8, 0);
  add('chimney', 1.75, 4.1, -.7);
  add('stair', -1.5, 0, 2.85);
  add('fence', -3.8, 0, 5.4);
  add('fence', 3.8, 0, 5.4);
  add('sign', -5.3, 0, 4.4);
  }
}
