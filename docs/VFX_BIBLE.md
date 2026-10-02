# SEKAI VFX Bible · MVP 0.4

The visual language is precise shapes, fast timing, muted world colors, and short high-contrast impact frames. No rainbow palette or sustained full-screen bloom. UE5 Niagara is the intended reference-production path; the web runtime uses cheaper meshes, sprites, material shifts, and camera impulses.

| Effect | Purpose | Shape and color | Timing | Niagara reference | Web strategy | Status |
| --- | --- | --- | --- | --- | --- | --- |
| Sword aura | Define Sword King power | Hair-thin ivory edge, cool air compression | 0.12 s | Ribbon plus refractive wedge | Thin mesh plane and narrow light | Rough opening stand-in |
| Sword slash | Impossible speed | Single straight ivory cut | 0.18 s, then silence | Beam ribbon with shuttered exposure | Plane trail and sound delay | Rough opening stand-in |
| Magic circle | Archmage scale | Three concentric cyan-white rune rings | 0.3 s open, 1.5 s hold | Niagara rotating mesh rings | Ring meshes and light | One ring stand-in |
| Fire ground burst | Immediate counterattack | Small point ignition into vertical amber column | 0.2 s anticipation, 0.5 s burst | Mesh emitter and ember field | Cone column and spark sprites | Pending |
| Magic shield | Deflect sword | Flat glass-cyan disk with visible fracture | 0.1 s open, 0.25 s break | Dynamic material crack mask | Ring/disc mesh, shard sprites | Ring stand-in |
| Large spell charge | Build ultimate scale | Wide pale circles, pulled cloud edges | 3 s build | Layered rune planes and cloud particles | Large translucent rings and rotating cloud cards | Pending |
| Shockwave | World reaction | Clear air ring, displaced dust and water | 0.35 s travel | Expanding torus and ground dust | Expanding ring mesh, camera impulse | Flash only |
| Mountain slash dust | Persistent consequence | Dark fracture with pale drifting dust | 0.5 s delay, 5 s dust | Plane fracture and dust emitters | Persistent scar geometry and low-count sprites | Scar blockout |
| Frost shatter | First combat signature | Sharp icy shards, stone fragments | 0.08 s hit stop, 0.5 s burst | Mesh shards with radial impulse | Instanced shards, material swap, bass hit | Pending polish |

The scene should be readable with effects disabled. Effects clarify force and timing; they do not carry the entire narrative event alone.
