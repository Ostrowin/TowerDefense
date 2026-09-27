extends SceneTree
## Arkusz podglądu sprite'ów z atlasu (z nakładką w kolorach obu drużyn):
##
##   godot --headless --path . --script res://tools/art_sheet.gd -- <plik.png> [prefiks...] [--scale 2]
##
## Bez prefiksów — wszystkie sprite'y. Każdy sprite dwa razy: drużyna gracza (niebieska) i wroga.

const META := preload("res://art/atlas_meta.gd")
const TEAMS: Array[Color] = [Color(0.35, 0.62, 1.0), Color(1.0, 0.36, 0.3)]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var scale := 2.0
	var prefixes: Array[String] = []
	var i := 1
	while i < args.size():
		if args[i] == "--scale":
			scale = float(args[i + 1])
			i += 2
			continue
		prefixes.append(args[i])
		i += 1
	var atlas := Image.load_from_file(ProjectSettings.globalize_path("res://art/atlas.png"))
	atlas.convert(Image.FORMAT_RGBA8)
	var names: Array = []
	for n in META.SPRITES:
		if prefixes.is_empty() or prefixes.any(func(p: String) -> bool: return (n as String).begins_with(p)):
			names.append(n)
	names.sort()
	var cells: Array[Image] = []
	for n in names:
		for team in 2:
			cells.append(_compose(atlas, META.SPRITES[n], TEAMS[team], scale))
	var cols := 8
	var cw := 0
	var ch := 0
	for c in cells:
		cw = maxi(cw, c.get_width())
		ch = maxi(ch, c.get_height())
	cw += 12
	ch += 12
	var rows := ceili(cells.size() / float(cols))
	var sheet := Image.create_empty(cw * cols, ch * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.36, 0.38, 0.3))
	for k in cells.size():
		var c := cells[k]
		var at := Vector2i((k % cols) * cw + (cw - c.get_width()) / 2, (k / cols) * ch + ch - 6 - c.get_height())
		sheet.blend_rect(c, Rect2i(Vector2i.ZERO, c.get_size()), at)
	sheet.save_png(out)
	print("art_sheet: %d sprite'ów → %s" % [names.size(), out])
	quit()


func _compose(atlas: Image, m: Array, team: Color, scale: float) -> Image:
	var r: Rect2 = m[0]
	var o: Rect2 = m[1]
	var img := atlas.get_region(Rect2i(r))
	if o.size.x > 0:
		var ov := atlas.get_region(Rect2i(o))
		for y in ov.get_height():
			for x in ov.get_width():
				var c := ov.get_pixel(x, y)
				if c.a > 0.0:
					ov.set_pixel(x, y, Color(c.r * team.r, c.g * team.g, c.b * team.b, c.a))
		img.blend_rect(ov, Rect2i(Vector2i.ZERO, ov.get_size()), Vector2i.ZERO)
	img.resize(int(img.get_width() * scale), int(img.get_height() * scale), Image.INTERPOLATE_LANCZOS)
	return img
