"""Preconvert the authored Z-up OBJ for UE's OBJ Y-axis handedness change."""
from pathlib import Path
HERE=Path(__file__).resolve().parent
src=HERE/'Mistvale_Terrain_Art_Proxy.obj'
dst=HERE/'Mistvale_Terrain_UE.obj'
with src.open() as fi,dst.open('w',encoding='ascii') as fo:
    fo.write('# Pre-reflected Y and reversed winding for UE OBJ import\n')
    for line in fi:
        parts=line.split()
        if parts and parts[0]=='v':
            fo.write(f'v {parts[1]} {-float(parts[2]):.3f} {parts[3]}\n')
        elif parts and parts[0]=='f':fo.write('f '+' '.join(reversed(parts[1:]))+'\n')
        else:fo.write(line)
print('CORRECTED_OBJ',dst)
