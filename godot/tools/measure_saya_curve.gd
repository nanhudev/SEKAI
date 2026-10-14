extends SceneTree
## MEASURE · THE SAYA'S BORE CURVE, AND THE ANGLE BETWEEN ITS MOUTH AND ITS TIP
##
## ===========================================================================
## WHY THIS EXISTS
## ===========================================================================
## `docs/weapons/` and `sword_classes.gd` both say the same thing about every
## number in the registry: it is MEASURED off the asset, never typed in from a
## document. The registry has `blade_tip_y`, `tsuba_mouth_y`, `habaki_half_*`,
## `bore_len`, `body_len`, `taper` — and NOTHING about curvature.
##
## That gap is now load-bearing. The presentation pass forbids DRAW and SHEATHE
## from being "pure straight-line translation", on the stated grounds that the
## saya has a real curve. The rule is easy to write down and impossible to
## satisfy without knowing HOW MUCH curve: extracting a blade along the mouth's
## own axis is exactly right for a straight bore and exactly wrong for a bent
## one, and the difference shows up as the blade wearing through the wall a
## little way down.
##
## So this measures the bore's centreline the only way it can be measured: slice
## the shell along its length and take the centroid of each slice. The result is
## a polyline — (y, x_centre, z_centre) per band — plus `sori`, the maximum
## lateral departure of that centreline from the mouth's axis, and the total
## angle swept between the mouth plane's normal and the centreline at the kojiri.
##
## `sori` is the number DRAW/SHEATHE need. It says how far off a straight pull
## the blade has to travel over a given depth, which is what turns "no pure
## straight-line translation" from an instruction into an arithmetic.
##
## ===========================================================================
## WHAT IT PRINTS, AND WHAT IT REFUSES TO PRINT
## ===========================================================================
## It prints numbers and a verdict, never a picture. The two summaries at the end
## are the ones a caller should read:
##
##   sori            max |centreline - mouth_axis| along the bore, in metres
##   axis_skew_deg   angle between the mouth axis and the line mouth -> kojiri
##
## If the shell is too thin to slice meaningfully (a band with no vertices) the
## band is skipped and COUNTED, so a curve derived from three bands cannot be
## mistaken for one derived from forty.
##
## Run:
##   "/g/Godot/Godot_v4.4.1-stable_win64_console.exe" --headless \
##     --path F:/SEKAI/godot --script res://tools/measure_saya_curve.gd

const SAYA_PATH := "res://models/weapons/fp_saya.glb"
const SWORD_PATH := "res://models/weapons/fp_sword.glb"
const BANDS := 40
## The bore runs mouth (y=0) to kojiri (+Y). Bands are taken over the real
## extent rather than a remembered length, so a re-authored GLB reports its own.
const MIN_BAND_VERTS := 4


func _initialize() -> void:
	print("=== SAYA BORE CURVE ===")
	_report(SAYA_PATH, "saya")
	print("")
	print("=== SWORD BLADE CURVE (the mirror measurement) ===")
	_report(SWORD_PATH, "sword")
	quit(0)


func _report(path: String, label: String) -> void:
	if not ResourceLoader.exists(path):
		print("  MISSING  %s" % path)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		print("  NOT A SCENE  %s" % path)
		return
	var root := packed.instantiate()
	var pts := _gather_vertices(root)
	root.free()
	if pts.is_empty():
		print("  NO VERTICES  %s" % path)
		return

	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var span := hi - lo
	print("  %s  verts=%d  aabb size = (%.4f, %.4f, %.4f)" % [
		label, pts.size(), span.x, span.y, span.z])
	print("  aabb min = (%.4f, %.4f, %.4f)   max = (%.4f, %.4f, %.4f)" % [
		lo.x, lo.y, lo.z, hi.x, hi.y, hi.z])

	# Y is the bore axis in both frames (mouth -> tip for the sword, mouth ->
	# kojiri for the saya), which is the convention sword_classes.gd documents.
	var y0 := lo.y
	var y1 := hi.y
	var band_h := (y1 - y0) / float(BANDS)
	if band_h <= 0.0:
		print("  DEGENERATE along Y")
		return

	# --- the bands ---------------------------------------------------------
	var centres: Array[Vector3] = []
	var empty := 0
	var widths: Array[float] = []
	for b in BANDS:
		var a := y0 + band_h * float(b)
		var z := a + band_h
		var sum := Vector3.ZERO
		var n := 0
		var wmin := INF
		var wmax := -INF
		for p in pts:
			if p.y >= a and p.y < z:
				sum += p
				n += 1
				wmin = minf(wmin, p.x)
				wmax = maxf(wmax, p.x)
		if n < MIN_BAND_VERTS:
			empty += 1
			continue
		centres.append(sum / float(n))
		widths.append(wmax - wmin)

	if centres.size() < 3:
		print("  TOO FEW BANDS (%d of %d usable)" % [centres.size(), BANDS])
		return

	print("  bands usable=%d / %d   (skipped %d)" % [centres.size(), BANDS, empty])
	print("  centreline, mouth -> far end:")
	print("      %-8s %-10s %-10s %-10s" % ["y", "x_centre", "z_centre", "x_width"])
	var step := maxi(1, centres.size() / 12)
	var i := 0
	while i < centres.size():
		var c: Vector3 = centres[i]
		print("      %-8.4f %-10.5f %-10.5f %-10.4f" % [c.y, c.x, c.z, widths[i]])
		i += step

	# --- the two summaries -------------------------------------------------
	#
	# The MOUTH AXIS is the direction the bore points at its opening: from the
	# first two centres, so it is the tangent at the mouth and not a chord that
	# already has the curve baked into it.
	var mouth_axis := (centres[1] - centres[0])
	if mouth_axis.length() < 1e-6:
		mouth_axis = Vector3.UP
	mouth_axis = mouth_axis.normalized()

	var origin: Vector3 = centres[0]
	var max_dev := 0.0
	var max_dev_y := 0.0
	for c in centres:
		var v := c - origin
		var along := v.dot(mouth_axis)
		var perp := (v - mouth_axis * along).length()
		if perp > max_dev:
			max_dev = perp
			max_dev_y = along

	# Axis skew: the mouth's own tangent against the chord to the far end. This
	# is the angle a straight pull would be wrong by over the bore's length.
	var far: Vector3 = centres[centres.size() - 1]
	var chord := far - origin
	var skew := 0.0
	if chord.length() > 1e-6:
		skew = rad_to_deg(mouth_axis.angle_to(chord.normalized()))

	print("")
	print("  SUMMARY %s" % label)
	print("      sori (max lateral departure from mouth axis) = %.5f m  at +%.4f m along" % [
		max_dev, max_dev_y])
	print("      axis_skew_deg (mouth tangent vs mouth->far chord) = %.3f deg" % skew)
	print("      bore length measured = %.4f m" % chord.length())
	# Straight is not a failure — it is a fact, and it changes what the draw has
	# to do. Only the caller can decide which of the two it got.
	if max_dev <= 0.002:
		print("      VERDICT: effectively STRAIGHT (sori under 2 mm) — a straight")
		print("               pull is geometrically correct and the curvature rule")
		print("               has to be satisfied by the POSE, not by the path.")
	elif max_dev <= 0.012:
		print("      VERDICT: gently curved — a straight pull clips by up to %.1f mm." % [
			max_dev * 1000.0])
	else:
		print("      VERDICT: CURVED — a straight pull clips by up to %.1f mm; the" % [
			max_dev * 1000.0])
		print("               extraction path MUST follow the centreline above.")


## Every vertex of every MeshInstance3D under `node`, in the ROOT's space.
##
## The node transforms are applied because a GLB's parts are usually siblings
## with their own offsets, and a curve measured in each part's own local space
## would be measured in as many frames as there are parts.
func _gather_vertices(node: Node) -> Array[Vector3]:
	var out: Array[Vector3] = []
	_collect(node, Transform3D.IDENTITY, out)
	return out


func _collect(node: Node, xform: Transform3D, out: Array[Vector3]) -> void:
	var here := xform
	if node is Node3D:
		here = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh != null:
			var arrays := mesh.surface_get_arrays(0)
			if arrays.size() > Mesh.ARRAY_VERTEX:
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for v in verts:
					out.append(here * v)
	for child in node.get_children():
		_collect(child, here, out)
