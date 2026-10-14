"""Conform to UE-exported terrain triangles, including import simplification."""
exec(compile((__import__('pathlib').Path(__file__).parent/'measure_exported_ground.py').read_text(), 'measure_exported_ground.py', 'exec'))
count=0
for row in json.loads((HERE/'ground_surface_manifest.json').read_text()):
    if row['name'].startswith('SM_River_'):continue
    path=Path(row['file']);lines=[]
    for line in path.read_text().splitlines():
        if line.startswith('v '):
            x,y,z=map(float,line.split()[1:])
            hit,_,_,_=tree.ray_cast(Vector((x/100,y/100,100)),Vector((0,0,-1)),200)
            if hit is None:raise RuntimeError('Surface outside terrain')
            z=(hit.z+(.12 if 'Plaza' in row['name'] else .09))*100
            line=f'v {x:.4f} {y:.4f} {z:.4f}'
            count+=1
        lines.append(line)
    path.write_text('\n'.join(lines)+'\n')
print('CONFORMED_VERTICES',count)
