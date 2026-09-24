import openingUrl from '../assets/audio/music/first-awakening.mp3?url';
import villageUrl from '../assets/audio/music/mistvale-morning.mp3?url';
import forestUrl from '../assets/audio/music/forest-edge.mp3?url';
import combatUrl from '../assets/audio/music/first-encounter.mp3?url';
import { AudioManager } from './audio';

type Mode = 'opening' | 'village' | 'forest' | 'combat';
const urls: Record<Mode, string> = { opening: openingUrl, village: villageUrl, forest: forestUrl, combat: combatUrl };

export class MusicDirector {
  private tracks: Record<Mode, HTMLAudioElement>;
  private mode: Mode = 'opening';
  private started = false;
  private paused = false;

  constructor(private volumes: () => { master: number; music: number; sfx: number }, private audioManager: AudioManager) {
    this.tracks = Object.fromEntries((Object.entries(urls) as [Mode, string][]).map(([mode, url]) => {
      const audio = new Audio(url);
      audio.loop = true;
      audio.preload = mode === 'opening' || mode === 'village' ? 'auto' : 'metadata';
      audio.volume = 0;
      return [mode, audio];
    })) as Record<Mode, HTMLAudioElement>;
  }

  start() {
    this.started = true;
    this.paused = false;
    Object.values(this.tracks).forEach(track => this.audioManager.attachMusic(track));
    void this.tracks[this.mode].play().catch(() => {});
  }

  beginOpening() {
    this.setMode('opening');
  }

  setPaused(paused: boolean) {
    this.paused = paused;
    if (paused) {
      Object.values(this.tracks).forEach(track => track.pause());
    } else if (this.started) {
      void this.tracks[this.mode].play().catch(() => {});
    }
  }

  private setMode(mode: Mode) {
    if (mode === this.mode) return;
    this.mode = mode;
    if (this.started && !this.paused) void this.tracks[mode].play().catch(() => {});
  }

  update(zone: 'village' | 'forest' | 'combat', _position: { x: number; z: number }) {
    if (!this.started || this.paused) return;
    this.setMode(this.mode === 'opening' ? 'opening' : zone);
    const settings = this.volumes();
    const target = settings.master > 0 && settings.music > 0 ? 0.68 : 0;
    for (const [mode, track] of Object.entries(this.tracks) as [Mode, HTMLAudioElement][]) {
      const wanted = mode === this.mode ? target : 0;
      track.volume += (wanted - track.volume) * 0.045;
      if (mode !== this.mode && track.volume < 0.002 && !track.paused) {
        track.pause();
        track.currentTime = 0;
      }
    }
  }

  releaseOpening() {
    if (this.mode === 'opening') this.setMode('village');
  }
}
