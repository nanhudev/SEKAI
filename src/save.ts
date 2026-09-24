export type Settings = {
  master: number; music: number; ambience: number; sfx: number; ui: number; voice: number;
  sensitivity: number; quality: string; shadow: string; scale: number; fov: number;
  subtitles: boolean; shake: boolean; headBob: number; motion: number; compass: boolean;
};

export type SaveSlot = 'auto' | 'slot1' | 'slot2' | 'slot3';
export type PersistentWorldSave = {
  saveVersion: 2;
  player: {
    position: [number, number, number]; rotation: [number, number];
    health: number; mana: number; stamina: number;
    currentWeapon: 'none' | 'sword' | 'staff'; currentMagic: number;
    ownedWeapons: string[]; knownAbilities: string[]; learnedMagic: string[];
    unlockedSkills: string[]; temporaryStatus: Record<string, number>;
  };
  world: {
    currentDay: number; worldTime: number; weatherSeed: number;
    currentRegion: string; discoveredLocations: string[];
    foes: { hp: number; alive: boolean; frost: number; frozen: number; burn: number }[];
    props: { fireScale: number; frostScale: number; windX: number };
  };
  events: { flags: string[]; completedEvents: string[]; activeEvents: string[]; objective: string };
  npcs: { currentStates: Record<string, string>; relationship: Record<string, number>; importantFlags: string[] };
  inventory: string[];
  journal: string[];
  settings: Settings;
  playtime: number;
  lastSaveTimestamp: string;
};

const prefix = 'sekai.save.v2.';
const legacyKey = 'sekai.save.v1';
const slots: SaveSlot[] = ['auto', 'slot1', 'slot2', 'slot3'];

export function readSave(slot: SaveSlot): PersistentWorldSave | null {
  try {
    const value = JSON.parse(localStorage.getItem(prefix + slot) || 'null');
    return value?.saveVersion === 2 && Array.isArray(value.player?.position) ? value as PersistentWorldSave : null;
  } catch { return null; }
}

export function writeSave(slot: SaveSlot, value: PersistentWorldSave) {
  localStorage.setItem(prefix + slot, JSON.stringify({ ...value, lastSaveTimestamp: new Date().toISOString() }));
}

export function listSaves() {
  return slots.map(slot => ({ slot, save: readSave(slot) }));
}

export function hasSave() {
  return listSaves().some(item => item.save) || localStorage.getItem(legacyKey) !== null;
}

export function latestSave(): { slot: SaveSlot; save: PersistentWorldSave } | null {
  const existing = listSaves().filter((item): item is { slot: SaveSlot; save: PersistentWorldSave } => item.save !== null);
  existing.sort((a, b) => b.save.lastSaveTimestamp.localeCompare(a.save.lastSaveTimestamp));
  return existing[0] || null;
}

export function readLegacy(settings: Settings): PersistentWorldSave | null {
  try {
    const old = JSON.parse(localStorage.getItem(legacyKey) || 'null');
    if (old?.version !== 1 || !Array.isArray(old.position)) return null;
    return {
      saveVersion: 2,
      player: { position: old.position, rotation: [0, 0], health: 100, mana: 100, stamina: 100,
        currentWeapon: old.staff ? 'staff' : old.sword ? 'sword' : 'none', currentMagic: old.spell || 0,
        ownedWeapons: [old.sword && 'sword', old.staff && 'staff'].filter(Boolean) as string[],
        knownAbilities: old.flags || [], learnedMagic: old.staff ? ['fire', 'frost', 'wind'] : [],
        unlockedSkills: (old.flags || []).filter((x: string) => x === 'sword_trained'), temporaryStatus: {} },
      world: { currentDay: 1, worldTime: old.time || 8, weatherSeed: 42,
        currentRegion: old.position[2] < -70 ? 'forest' : 'village', discoveredLocations: ['village'], foes: [],
        props: { fireScale: 1, frostScale: 1, windX: 0 } },
      events: { flags: old.flags || [], completedEvents: old.flags || [], activeEvents: [], objective: '' },
      npcs: { currentStates: {}, relationship: {}, importantFlags: [] }, inventory: [], journal: [],
      settings: { ...settings, ...old.settings }, playtime: 0, lastSaveTimestamp: new Date().toISOString(),
    };
  } catch { return null; }
}
