extends SceneTree
## Wypalanie grafiki: art/svg/*.svg → art/atlas.png + art/atlas_meta.gd, plus kafle terenu
## (art/ground.png, art/dirt.png, art/water.png). Gra czyta tylko wyniki — SVG to źródła.
##
##   godot --headless --path . --script res://tools/bake_art.gd
##
## Atrybuty korzenia <svg> (opcjonalne):
##   data-anchor="x y"  — punkt stóp/podstawy w jednostkach SVG (domyślnie środek dołu)
##   data-world="k"     — ile pikseli świata na jednostkę SVG (domyślnie 0.2)
##   data-scale="s"     — rozdzielczość wypalenia (piksele atlasu na jednostkę SVG, domyślnie 0.75)
##   data-grime="g"     — siła brudu 0..1 (domyślnie 1)
##
## Kolor drużyny: wypełnienia w odcieniach magenty #RR00RR (RR = jasność, np. #ff00ff, #a000a0).
## Wypalanie robi z nich osobną szarą nakładkę, którą gra barwi kolorem drużyny.
##
## Brud (tak jak w próbkach): plamy i błoto od dołu sylwetki; materiał rozpoznawany po kolorze —
## niskie nasycenie = metal/kamień (ziarno, rysy), wysokie = sierść/tkanina (włos).

const SRC := "res://art/svg/"
const OUT := "res://art/"
const ATLAS_W := 2048
const PAD := 6
const TEAM_RE := "#([0-9a-fA-F]{2})00\\1(?![0-9a-fA-F])"


class Grime:
	var blotch := FastNoiseLite.new()
	var fine := FastNoiseLite.new()
	var fur := FastNoiseLite.new()
	var k := 1.0  ## skala szumu (piksele atlasu → jednostki SVG)
	var strength := 1.0
	var top := 0
	var bottom := 0

	func _init(seed_: int, scale: float, strength_: float) -> void:
		k = 1.0 / scale
		strength = strength_
		blotch.seed = seed_
		blotch.frequency = 0.045
		blotch.fractal_octaves = 3
		fine.seed = seed_ + 1
		fine.frequency = 0.5
		fur.seed = seed_ + 2
		fur.frequency = 0.3

	## Mnożnik brudu w punkcie (plamy + błoto od dołu).
	func dirt(x: int, y: int) -> float:
		var b := blotch.get_noise_2d(x * k, y * k) * 0.5 + 0.5
		var d := clampf((b - 0.45) * 1.4, 0.0, 0.45)
		var down := clampf(float(y - top) / maxf(1.0, bottom - top), 0.0, 1.0)
		d += clampf((down - 0.75) * 2.0, 0.0, 0.5) * (0.6 + 0.4 * b)
		return d * strength

	func apply(c: Color, x: int, y: int, cloth := false) -> Color:
		var d := dirt(x, y)
		var out := Color(lerpf(c.r, c.r * 0.53, d), lerpf(c.g, c.g * 0.4, d), lerpf(c.b, c.b * 0.26, d), c.a)
		var metal := not cloth and c.s < 0.28 and c.v > 0.12
		if metal:
			var f := fine.get_noise_2d(x * k, y * k) * strength
			return out.lightened(f * 0.06) if f > 0 else out.darkened(-f * 0.08)
		var fn := fur.get_noise_2d(x * k * 1.8, y * k * 0.45) * strength
		return out.lightened(fn * 0.12) if fn > 0 else out.darkened(-fn * 0.18)

	## Odprysk krawędzi: czy piksel na krawędzi sylwetki wykruszyć.
	func chip(x: int, y: int) -> bool:
		return strength > 0.3 and blotch.get_noise_2d(x * k * 4.0, y * k * 4.0) > 0.4


func _init() -> void:
	var files: Array[String] = []
	for f in DirAccess.get_files_at(SRC):
		if f.ends_with(".svg"):
			files.append(f)
	files.sort()
	var items: Array[Dictionary] = []
	for f in files:
		var item := _bake_svg(f.get_basename(), FileAccess.get_file_as_string(SRC + f))
		if not item.is_empty():
			items.append(item)
	_pack_and_save(items)
	_bake_tiles()
	print("bake_art: %d sprite'ów" % items.size())
	quit()


func _attr(svg: String, name: String, def: String) -> String:
	var re := RegEx.create_from_string(name + "=\"([^\"]*)\"")
	var m := re.search(svg.substr(0, svg.find(">")))
	return m.get_string(1) if m != null else def


func _render(svg: String, scale: float) -> Image:
	var img := Image.new()
	if img.load_svg_from_string(svg, scale) != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


func _bake_svg(name: String, svg: String) -> Dictionary:
	var scale := float(_attr(svg, "data-scale", "0.75"))
	var world := float(_attr(svg, "data-world", "0.2"))
	var grime_s := float(_attr(svg, "data-grime", "1"))
	var vb := _attr(svg, "viewBox", "0 0 128 128").split_floats(" ", false)
	var anchor_def := "%f %f" % [vb[2] / 2.0, vb[3] - 4.0]
	var anchor_v := _attr(svg, "data-anchor", anchor_def).split_floats(" ", false)
	var anchor := Vector2(anchor_v[0], anchor_v[1]) * scale

	var re := RegEx.create_from_string(TEAM_RE)
	var has_team := re.search(svg) != null
	var base: Image
	var overlay: Image = null
	if has_team:
		base = _render(re.sub(svg, "#000000", true), scale)
		var white := _render(re.sub(svg, "#ffffff", true), scale)
		var shade := _render(re.sub(svg, "#$1$1$1", true), scale)
		if base == null or white == null or shade == null:
			push_error("bake_art: %s — błąd SVG" % name)
			return {}
		overlay = Image.create_empty(base.get_width(), base.get_height(), false, Image.FORMAT_RGBA8)
		for y in base.get_height():
			for x in base.get_width():
				var c := base.get_pixel(x, y)
				var cov := clampf(white.get_pixel(x, y).r - c.r, 0.0, 1.0)
				if cov < 0.02:
					continue
				var v := clampf((shade.get_pixel(x, y).r - c.r) / cov, 0.0, 1.0)
				overlay.set_pixel(x, y, Color(v, v, v, cov * white.get_pixel(x, y).a))
	else:
		base = _render(svg, scale)
		if base == null:
			push_error("bake_art: %s — błąd SVG" % name)
			return {}

	# brud
	var g := Grime.new(hash(name), scale, grime_s)
	var w := base.get_width()
	var h := base.get_height()
	g.top = h
	for y in h:
		for x in w:
			if base.get_pixel(x, y).a > 0.5:
				g.top = mini(g.top, y)
				g.bottom = maxi(g.bottom, y)
	var dirty := base.duplicate() as Image
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	for y in h:
		for x in w:
			var c := base.get_pixel(x, y)
			if c.a < 0.02:
				continue
			dirty.set_pixel(x, y, g.apply(c, x, y))
			if overlay != null:
				var o := overlay.get_pixel(x, y)
				if o.a > 0.0:
					overlay.set_pixel(x, y, g.apply(o, x, y, true))
	# rysy na metalu
	if grime_s > 0.3:
		for i in int(w * h / 300.0 * grime_s):
			var p := Vector2(rng.randf() * w, rng.randf() * h)
			var ang := rng.randf_range(-0.6, 0.6) + (PI if rng.randf() < 0.5 else 0.0)
			for s in int(rng.randf_range(2.0, 7.0) / scale * 0.75):
				var q := p + Vector2.from_angle(ang) * s
				_scratch(base, dirty, int(q.x), int(q.y), 0.25)
				_scratch(base, dirty, int(q.x), int(q.y) + 1, -0.22)
	# odpryski krawędzi
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if base.get_pixel(x, y).a < 0.5:
				continue
			var edge := base.get_pixel(x - 1, y).a < 0.5 or base.get_pixel(x + 1, y).a < 0.5 \
				or base.get_pixel(x, y - 1).a < 0.5 or base.get_pixel(x, y + 1).a < 0.5
			if edge and g.chip(x, y):
				dirty.set_pixel(x, y, Color(0, 0, 0, 0))
				if overlay != null:
					overlay.set_pixel(x, y, Color(0, 0, 0, 0))

	# przycięcie pustych brzegów (wspólne dla obu warstw)
	var used := dirty.get_used_rect()
	if overlay != null:
		used = used.merge(overlay.get_used_rect())
	var cut := dirty.get_region(used)
	var over_cut: Image = overlay.get_region(used) if overlay != null else null
	return {"name": name, "base": cut, "overlay": over_cut, "anchor": anchor - Vector2(used.position),
		"k": world / scale}


func _scratch(src: Image, out: Image, x: int, y: int, amount: float) -> void:
	if x < 0 or y < 0 or x >= src.get_width() or y >= src.get_height():
		return
	var c := src.get_pixel(x, y)
	if c.a < 0.9 or c.s >= 0.28 or c.v < 0.12:
		return
	var o := out.get_pixel(x, y)
	out.set_pixel(x, y, o.lightened(amount) if amount > 0 else o.darkened(-amount))


## Pakowanie półkowe (od najwyższych), biały blok 16×16 w rogu na kształty bez tekstury.
func _pack_and_save(items: Array[Dictionary]) -> void:
	var rects: Array[Dictionary] = []  ## {img, item, layer}
	for it in items:
		rects.append({"img": it["base"], "item": it, "layer": "base"})
		if it["overlay"] != null:
			rects.append({"img": it["overlay"], "item": it, "layer": "overlay"})
	rects.sort_custom(func(a, b): return a["img"].get_height() > b["img"].get_height())
	var x := 16 + PAD * 2
	var y := PAD
	var shelf := 16
	for r in rects:
		var im: Image = r["img"]
		if x + im.get_width() + PAD > ATLAS_W:
			x = PAD
			y += shelf + PAD * 2
			shelf = 0
		r["pos"] = Vector2i(x, y)
		x += im.get_width() + PAD * 2
		shelf = maxi(shelf, im.get_height())
	var height := 64
	while height < y + shelf + PAD:
		height *= 2
	var atlas := Image.create_empty(ATLAS_W, height, false, Image.FORMAT_RGBA8)
	atlas.fill_rect(Rect2i(PAD, PAD, 16, 16), Color.WHITE)
	for r in rects:
		var im: Image = r["img"]
		atlas.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), r["pos"])
		r["item"][r["layer"] + "_rect"] = Rect2i(r["pos"], im.get_size())
	atlas.fix_alpha_edges()
	atlas.save_png(OUT + "atlas.png")

	var lines: Array[String] = [
		"# Wygenerowane przez tools/bake_art.gd — nie edytuj ręcznie.",
		"# nazwa: [prostokąt w atlasie, prostokąt nakładki drużyny (pusty = brak), punkt stóp w px sprite'a, px świata na px atlasu]",
		"const SIZE := Vector2(%d, %d)" % [ATLAS_W, height],
		"const WHITE := Rect2(%d, %d, 16, 16)" % [PAD, PAD],
		"const SPRITES := {",
	]
	items.sort_custom(func(a, b): return a["name"] < b["name"])
	for it in items:
		var b: Rect2i = it["base_rect"]
		var o: Rect2i = it.get("overlay_rect", Rect2i())
		var a: Vector2 = it["anchor"]
		lines.append("\t\"%s\": [Rect2(%d, %d, %d, %d), Rect2(%d, %d, %d, %d), Vector2(%.1f, %.1f), %.5f]," % [
			it["name"], b.position.x, b.position.y, b.size.x, b.size.y,
			o.position.x, o.position.y, o.size.x, o.size.y, a.x, a.y, it["k"]])
	lines.append("}")
	var f := FileAccess.open(OUT + "atlas_meta.gd", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("bake_art: atlas %d×%d" % [ATLAS_W, height])


# ---------------------------------------------------------------- kafle terenu (bezszwowe)

func _seamless(seed_: int, freq: float, octaves: int, size: int) -> Image:
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.frequency = freq
	n.fractal_octaves = octaves
	var img := n.get_seamless_image(size, size, false, false, 0.1, true)
	img.convert(Image.FORMAT_RGBA8)
	return img


func _bake_tiles() -> void:
	const S := 256
	var big := _seamless(11, 0.012, 4, S)
	var mid := _seamless(12, 0.05, 3, S)
	var fine := _seamless(13, 0.3, 1, S)
	var streak := _seamless(14, 0.02, 2, S)

	# trawa: wypalona, brudna zieleń z plamami suchej ziemi
	var ground := Image.create_empty(S, S, false, Image.FORMAT_RGBA8)
	var grass_a := Color("3b4a2a")
	var grass_b := Color("56592f")
	var soil := Color("54452f")
	for y in S:
		for x in S:
			var a := big.get_pixel(x, y).r
			var b := mid.get_pixel(x, y).r
			var f := fine.get_pixel(x, y).r - 0.5
			var c := grass_a.lerp(grass_b, clampf(a * 1.4 - 0.2, 0, 1))
			c = c.lerp(soil, clampf((b - 0.62) * 4.0, 0, 0.85))
			c = c.lightened(f * 0.14) if f > 0 else c.darkened(-f * 0.22)
			ground.set_pixel(x, y, c)
	_stamp_pebbles(ground, 21, 70, [Color("7a7466"), Color("5e5a50")], Color("26231c"))
	ground.save_png(OUT + "ground.png")

	# ścieżka: ubite błoto z koleinami i kamykami
	var dirt := Image.create_empty(S, S, false, Image.FORMAT_RGBA8)
	var mud_a := Color("5a4a34")
	var mud_b := Color("6e5b3e")
	for y in S:
		for x in S:
			var a := big.get_pixel(x, y).r
			var b := mid.get_pixel(x, y).r
			var f := fine.get_pixel(x, y).r - 0.5
			var s := streak.get_pixel(x, (y * 4) % S).r
			var c := mud_a.lerp(mud_b, clampf(a * 1.2 - 0.1, 0, 1))
			c = c.darkened(clampf((b - 0.6) * 1.5, 0, 0.3))
			c = c.darkened(clampf((s - 0.55) * 1.2, 0, 0.25))  # koleiny wzdłuż drogi
			c = c.lightened(f * 0.12) if f > 0 else c.darkened(-f * 0.2)
			dirt.set_pixel(x, y, c)
	_stamp_pebbles(dirt, 22, 120, [Color("8a8270"), Color("6a6456")], Color("2e261c"))
	dirt.save_png(OUT + "dirt.png")

	# woda: mętna, ciemna, z jaśniejszymi smugami
	var water := Image.create_empty(S, S, false, Image.FORMAT_RGBA8)
	var deep := Color("1e3438")
	var shallow := Color("2b4a4a")
	for y in S:
		for x in S:
			var a := big.get_pixel(x, y).r
			var s := streak.get_pixel((x * 3) % S, y).r
			var c := deep.lerp(shallow, clampf(a * 1.1 - 0.1, 0, 1))
			c = c.lightened(clampf((s - 0.62) * 0.6, 0, 0.08))
			water.set_pixel(x, y, c)
	water.save_png(OUT + "water.png")


## Kamyki z zawijaniem na brzegach (kafel bez szwów).
func _stamp_pebbles(img: Image, seed_: int, n: int, cols: Array, shadow: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var s := img.get_width()
	for i in n:
		var cx := rng.randi_range(0, s - 1)
		var cy := rng.randi_range(0, s - 1)
		var r := rng.randf_range(0.8, 2.6)
		var col: Color = cols[rng.randi_range(0, cols.size() - 1)]
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var d := Vector2(dx, dy * 1.3).length()
				var px := posmod(cx + dx, s)
				var py := posmod(cy + dy, s)
				if d <= r:
					img.set_pixel(px, py, col.lightened(0.15) if dy < 0 else col)
				elif d <= r + 1.0 and dy > 0:
					img.set_pixel(px, py, img.get_pixel(px, py).lerp(shadow, 0.6))
