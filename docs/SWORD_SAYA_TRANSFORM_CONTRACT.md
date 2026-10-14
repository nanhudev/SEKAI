# Sword / Saya Transform Contract

Authoritative geometry: `godot/scripts/weapons/sword_classes.gd`. Existing Sword_FP.tscn, fp_sword.glb and fp_saya.glb are preserved. These are metre-scale first-person assets; never add a corrective scale or a second Euler offset to make a seat appear correct.

| Frame / value | Contract |
|---|---|
| Sword | local +Y to tip, -X cutting edge, +/-Z blade flats |
| Saya | origin at mouth plane, +Y into bore, -X edge slot |
| Tip / guard setback | registry tip Y=0.765 m; tsuba mouth Y=0.0042 m |
| Blade extraction | derived tip minus guard setback: 0.7608 m |
| Bore clearance | FIT_CLEAR=0.00175 m per side; curvature comes from registry samples |
| Normal sword pose owner | TempSwordVisual driven by CombatController / SwordPoseSampler |
| Normal saya pose owner | SwordSayaRig / SayaHandDriver |
| Iaido pose owner | IaidoDirector; it stands down the ordinary saya while the ceremony scabbard is shown |
| Right glove | local sword-grip centre Y=-0.13 m; follows the rendered sword |
| Left glove | owning saya mouth frame plus local Y=0.10 m; follows the rendered saya |
| Arms | elbow / shoulder anchors in WeaponRoot space; cosmetic, no hitboxes or gameplay displacement |
| AnimationPlayer | native presentation clips sampled on the existing move clock; grip/elbow channels supplement the physical sword solver |
| Foreground rendering | all glove/arm meshes must exist before ForegroundWeaponLayer scans the subtree |

While inserted, the blade follows the derived curved bore. Rotation starts after clearance. Recovery aligns the blade axis first and the cutting edge second, then approaches the mouth and inserts. Short combat and long Demo share the same geometry solver; only their authored timing resources differ.

The latest blade-clearance probe observed 386 seated samples across eight acts. Maximum mouth-axis transverse offset was 2.7 mm under the probe's 5.1 mm envelope; the probe's tip-wall error was zero. This is numeric blade/saya evidence, not a proof that every finger/sleeve pose is intersection-free. Procedural gloves still need artist anatomy and close-up review.
