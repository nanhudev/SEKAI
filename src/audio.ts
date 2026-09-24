export type AudioBus = 'music' | 'ambience' | 'sfx' | 'ui' | 'voice';
export type AudioVolumes = { master: number; music: number; ambience: number; sfx: number; ui: number; voice: number };

export class AudioManager {
  private context: AudioContext | null = null;
  private master: GainNode | null = null;
  private buses = {} as Record<AudioBus, GainNode>;
  private media = new WeakSet<HTMLMediaElement>();
  private lastBird = 0;
  private lastSmith = 0;
  private river: { source: AudioBufferSourceNode; gain: GainNode; panner: PannerNode } | null = null;

  constructor(private volumes: () => AudioVolumes) {}

  start() {
    if (this.context) { void this.context.resume(); return; }
    this.context = new AudioContext();
    this.master = this.context.createGain();
    this.master.connect(this.context.destination);
    for (const bus of ['music', 'ambience', 'sfx', 'ui', 'voice'] as AudioBus[]) {
      this.buses[bus] = this.context.createGain();
      this.buses[bus].connect(this.master);
    }
    this.updateVolumes();
  }

  updateVolumes() {
    if (!this.context || !this.master) return;
    const v = this.volumes();
    this.master.gain.setTargetAtTime(v.master, this.context.currentTime, .08);
    for (const bus of Object.keys(this.buses) as AudioBus[])
      this.buses[bus].gain.setTargetAtTime(v[bus], this.context.currentTime, .08);
  }

  attachMusic(audio: HTMLAudioElement) {
    this.start();
    if (!this.context || this.media.has(audio)) return;
    this.context.createMediaElementSource(audio).connect(this.buses.music);
    this.media.add(audio);
  }

  tone(frequency = 240, duration = .12, type: OscillatorType = 'sine', level = .08, bus: AudioBus = 'sfx') {
    this.start();
    if (!this.context) return;
    const now = this.context.currentTime;
    const osc = this.context.createOscillator();
    const gain = this.context.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(frequency * (0.97 + Math.random() * .06), now);
    osc.frequency.exponentialRampToValueAtTime(Math.max(35, frequency * .45), now + duration);
    gain.gain.setValueAtTime(level * (0.92 + Math.random() * .16), now);
    gain.gain.exponentialRampToValueAtTime(.0001, now + duration);
    osc.connect(gain).connect(this.buses[bus]);
    osc.start(now);
    osc.stop(now + duration);
  }

  private noiseBuffer(seconds: number) {
    const context = this.context!;
    const buffer = context.createBuffer(1, Math.ceil(context.sampleRate * seconds), context.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
    return buffer;
  }

  spatialNoise(position: [number, number, number], duration: number, level: number, cutoff: number) {
    this.start();
    const context = this.context!;
    const source = context.createBufferSource();
    source.buffer = this.noiseBuffer(duration);
    const filter = context.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = cutoff;
    const gain = context.createGain();
    gain.gain.setValueAtTime(.0001, context.currentTime);
    gain.gain.linearRampToValueAtTime(level, context.currentTime + .06);
    gain.gain.exponentialRampToValueAtTime(.0001, context.currentTime + duration);
    const panner = context.createPanner();
    panner.panningModel = 'HRTF';
    panner.distanceModel = 'inverse';
    panner.refDistance = 4;
    panner.maxDistance = 100;
    panner.rolloffFactor = 1;
    panner.positionX.value = position[0];
    panner.positionY.value = position[1];
    panner.positionZ.value = position[2];
    source.connect(filter).connect(gain).connect(panner).connect(this.buses.ambience);
    source.start();
    source.stop(context.currentTime + duration);
  }

  updateAmbience(position: { x: number; y: number; z: number }, forward: { x: number; z: number }, region: string) {
    if (!this.context) return;
    this.updateVolumes();
    const listener = this.context.listener;
    listener.positionX.value = position.x;
    listener.positionY.value = position.y;
    listener.positionZ.value = position.z;
    listener.forwardX.value = forward.x;
    listener.forwardY.value = 0;
    listener.forwardZ.value = forward.z;
    if (!this.river) {
      const source = this.context.createBufferSource();
      source.buffer = this.noiseBuffer(4);
      source.loop = true;
      const filter = this.context.createBiquadFilter();
      filter.type = 'lowpass';
      filter.frequency.value = 650;
      const gain = this.context.createGain();
      gain.gain.value = .018;
      const panner = this.context.createPanner();
      panner.panningModel = 'HRTF';
      panner.refDistance = 7;
      panner.rolloffFactor = .8;
      panner.positionX.value = 35;
      panner.positionY.value = 0;
      panner.positionZ.value = 0;
      source.connect(filter).connect(gain).connect(panner).connect(this.buses.ambience);
      source.start();
      this.river = { source, gain, panner };
    }
    const now = this.context.currentTime;
    if (region === 'village' && now - this.lastBird > 7) {
      this.lastBird = now;
      this.tone(1250, .13, 'sine', .012, 'ambience');
      this.tone(1650, .09, 'sine', .009, 'ambience');
    }
    if (region === 'village' && now - this.lastSmith > 10 && Math.hypot(position.x + 28, position.z - 20) < 38) {
      this.lastSmith = now;
      this.spatialNoise([-28, 1.5, 20], .12, .08, 2400);
      this.tone(390, .18, 'triangle', .018, 'ambience');
    }
  }

  setPaused(paused: boolean) {
    if (!this.context) return;
    if (paused) void this.context.suspend(); else void this.context.resume();
  }
}
