class_name Painter
extends RefCounted
## Rysowanie wielu kształtów jednym wywołaniem: koła, prostokąty, linie, łuki i wielokąty trafiają
## do jednej listy trójkątów (kolejność zachowana), napisy są rysowane na końcu, na wierzchu.
##
## Po co: w Godocie każde draw_circle / draw_arc / draw_colored_polygon / draw_polyline to osobne
## wywołanie rysowania. Na PC to nie boli, ale telefonowe GPU (Mali-G57) przy ~600 wywołaniach
## na klatkę spadało do 35–45 FPS. Metody mają te same argumenty co CanvasItem.draw_*, więc
## `draw_circle(...)` → `pen.circle(...)`. Wierzchołki kół liczy C++ (Transform2D * gotowy
## kształt), GDScript tylko skleja tablice.
##
##   pen.clear() → pen.circle(...) / pen.rect(...) / … → pen.draw_on(canvas_item)  (w jego _draw)

static var _circles := {}  ## liczba segmentów → trójkąty koła o promieniu 1
static var _rings := {}  ## "segmenty:grubość" → trójkąty pierścienia o promieniu zewn. 1

var points := PackedVector2Array()
var colors := PackedColorArray()
var _texts: Array[Array] = []


func clear() -> void:
	points.clear()
	colors.clear()
	_texts.clear()


func is_empty() -> bool:
	return points.is_empty() and _texts.is_empty()


## Dodaje wszystko jako jedno wywołanie rysowania (+ napisy). Wołać w _draw danego węzła.
func draw_on(item: CanvasItem) -> void:
	if not points.is_empty():
		RenderingServer.canvas_item_add_triangle_array(item.get_canvas_item(), PackedInt32Array(), points, colors)
	for t in _texts:
		if t[6] > 0:
			item.draw_string_outline(t[0], t[1], t[2], t[3], t[4], t[5], t[6], t[7])
		else:
			item.draw_string(t[0], t[1], t[2], t[3], t[4], t[5], t[7])


func circle(center: Vector2, radius: float, color: Color) -> void:
	if radius <= 0.0:
		return
	var n := clampi(int(sqrt(radius) * 4.5), 8, 64)
	if not _circles.has(n):
		var tris := PackedVector2Array()
		for i in n:
			tris.append_array([Vector2.ZERO, Vector2.from_angle(TAU * i / n), Vector2.from_angle(TAU * (i + 1) / n)])
		_circles[n] = tris
	_add(Transform2D(0.0, Vector2(radius, radius), 0.0, center) * (_circles[n] as PackedVector2Array), color)


## Jak CanvasItem.draw_rect: obrys (filled = false) leży na krawędzi prostokąta, pół grubości w każdą stronę.
func rect(r: Rect2, color: Color, filled := true, width := 1.0) -> void:
	if filled:
		_quad(r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), color)
		return
	var h := maxf(width, 1.0) / 2.0
	var a := r.position
	var b := r.end
	rect(Rect2(a.x - h, a.y - h, r.size.x + 2 * h, 2 * h), color)  # góra
	rect(Rect2(a.x - h, b.y - h, r.size.x + 2 * h, 2 * h), color)  # dół
	rect(Rect2(a.x - h, a.y + h, 2 * h, r.size.y - 2 * h), color)  # lewo
	rect(Rect2(b.x - h, a.y + h, 2 * h, r.size.y - 2 * h), color)  # prawo


func line(from: Vector2, to: Vector2, color: Color, width := 1.0) -> void:
	var d := to - from
	if d.length_squared() < 0.0001:
		return
	var n := d.orthogonal().normalized() * (maxf(width, 1.0) / 2.0)
	_quad(from + n, to + n, to - n, from - n, color)


func polyline(pts: PackedVector2Array, color: Color, width := 1.0) -> void:
	for i in pts.size() - 1:
		line(pts[i], pts[i + 1], color, width)


## Pary punktów: [a0, b0, a1, b1, …].
func multiline(pts: PackedVector2Array, color: Color, width := 1.0) -> void:
	for i in range(0, pts.size() - 1, 2):
		line(pts[i], pts[i + 1], color, width)


func dashed_line(from: Vector2, to: Vector2, color: Color, width := 1.0, dash := 2.0) -> void:
	var length := from.distance_to(to)
	var dir := (to - from) / maxf(length, 0.001)
	var s := 0.0
	while s < length:
		line(from + dir * s, from + dir * minf(s + dash, length), color, width)
		s += dash * 2.0


## Wielokąt wypukły (wachlarz trójkątów) — wszystkie w grze takie są.
func polygon(pts: PackedVector2Array, color: Color) -> void:
	var out := PackedVector2Array()
	for i in range(1, pts.size() - 1):
		out.append_array([pts[0], pts[i], pts[i + 1]])
	_add(out, color)


## Jak CanvasItem.draw_arc (`point_count` punktów, łuk o grubości `width`).
func arc(center: Vector2, radius: float, start: float, end: float, point_count: int, color: Color, width := 1.0) -> void:
	var w := maxf(width, 1.0)
	var outer := radius + w / 2.0
	var segments := maxi(point_count - 1, 3)
	if absf(end - start) >= TAU - 0.001:
		# pełny okrąg: gotowy pierścień przeskalowany w C++ (grubość zaokrąglona do 5% promienia)
		var k := clampf(snappedf(1.0 - w / outer, 0.05), 0.0, 0.95)
		var key := "%d:%.2f" % [segments, k]
		if not _rings.has(key):
			_rings[key] = _ring_tris(segments, k, 0.0, TAU)
		_add(Transform2D(0.0, Vector2(outer, outer), 0.0, center) * (_rings[key] as PackedVector2Array), color)
		return
	_add(Transform2D(0.0, Vector2(outer, outer), 0.0, center) * _ring_tris(segments, 1.0 - w / outer, start, end), color)


func text(font: Font, pos: Vector2, s: String, align: HorizontalAlignment, width: float, size: int, color: Color) -> void:
	_texts.append([font, pos, s, align, width, size, 0, color])


func text_outline(font: Font, pos: Vector2, s: String, align: HorizontalAlignment, width: float, size: int, outline: int, color: Color) -> void:
	_texts.append([font, pos, s, align, width, size, outline, color])


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	points.append_array([a, b, c, a, c, d])
	for i in 6:
		colors.append(color)


func _add(tris: PackedVector2Array, color: Color) -> void:
	points.append_array(tris)
	var cols := PackedColorArray()
	cols.resize(tris.size())
	cols.fill(color)
	colors.append_array(cols)


## Trójkąty pierścienia o promieniu zewnętrznym 1 i wewnętrznym `inner`.
static func _ring_tris(segments: int, inner: float, start: float, end: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var step := (end - start) / segments
	for i in segments:
		var a := Vector2.from_angle(start + step * i)
		var b := Vector2.from_angle(start + step * (i + 1))
		out.append_array([a, b, b * inner, a, b * inner, a * inner])
	return out
