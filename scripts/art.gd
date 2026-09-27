class_name Art
extends RefCounted
## Grafika z atlasu wypalonego przez `tools/bake_art.gd` (źródła: art/svg/*.svg) i kafle terenu.
## Styl (D30): sprite'y SVG z wypalonym brudem, ruch i efekty dokłada kod (kołysanie, odrzut,
## obrót głowic, poświaty) — wszystko idzie przez `Painter`, więc świat to dalej jedno wywołanie
## rysowania.
##
## Sprite ma warstwę bazową i (opcjonalnie) szarą nakładkę drużyny — rysowaną drugim czworokątem
## w kolorze drużyny. Rozmiar w świecie wynika z SVG (`data-world`), punkt zaczepienia to stopy
## (`data-anchor`) — tam trafia `feet`.

const META := preload("res://art/atlas_meta.gd")

static var atlas: Texture2D
static var ground: Texture2D
static var dirt: Texture2D
static var water: Texture2D
static var _uv := {}  ## nazwa → [uv bazy, uv nakładki (size 0 = brak)]


## Ładuje tekstury raz (mipmapy liczone tu — pliki *.import nie są w repo).
static func load_all() -> void:
	if atlas != null:
		return
	atlas = _mipmapped("res://art/atlas.png")
	ground = _mipmapped("res://art/ground.png")
	dirt = _mipmapped("res://art/dirt.png")
	water = _mipmapped("res://art/water.png")
	for name in META.SPRITES:
		var m: Array = META.SPRITES[name]
		var r: Rect2 = m[0]
		var o: Rect2 = m[1]
		_uv[name] = [Rect2(r.position / META.SIZE, r.size / META.SIZE), Rect2(o.position / META.SIZE, o.size / META.SIZE)]


static func _mipmapped(path: String) -> Texture2D:
	var tex: Texture2D = load(path)
	var img := tex.get_image() if tex != null else null
	if img == null:  # headless (atrapa renderu) — wystarczy tekstura bez mipmap
		return tex
	img.decompress()
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func has(name: String) -> bool:
	return META.SPRITES.has(name)


## Wysokość sprite'a nad stopami w pikselach świata (do pasków HP, ikon nad głową).
static func height(name: String, scale := 1.0) -> float:
	var m: Array = META.SPRITES[name]
	return (m[2] as Vector2).y * float(m[3]) * scale


## Rysuje sprite `name` stopami w `feet`. `flip` = lustro w poziomie (sprite'y patrzą w prawo),
## `rot` = obrót wokół stóp, `squash` = rozciągnięcie (x, y) do chodu i uderzeń, `tint` mnoży
## kolor (wartości > 1 rozjaśniają — błysk trafienia), `team` = kolor nakładki drużyny.
static func draw(pen: Painter, name: String, feet: Vector2, scale := 1.0, flip := false,
		tint := Color.WHITE, team := Color.WHITE, rot := 0.0, squash := Vector2.ONE) -> void:
	var m: Array = META.SPRITES[name]
	var size: Vector2 = (m[0] as Rect2).size
	var a: Vector2 = m[2]
	var k: float = float(m[3]) * scale
	var xf := Transform2D(rot, Vector2(k * squash.x * (-1.0 if flip else 1.0), k * squash.y), 0.0, feet)
	var tl := xf * (-a)
	var tr := xf * (Vector2(size.x, 0) - a)
	var br := xf * (size - a)
	var bl := xf * (Vector2(0, size.y) - a)
	var uv: Array = _uv[name]
	pen.quad_uv(tl, tr, br, bl, uv[0], tint)
	var ov: Rect2 = uv[1]
	if ov.size.x > 0.0:
		pen.quad_uv(tl, tr, br, bl, ov, team * tint)
