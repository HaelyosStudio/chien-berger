extends Node2D
const Rond := preload("res://scripts/rond.gd")
## Petits effets visuels dessinés par le code : poussière, brins d'herbe, cœurs,
## étincelles, confettis et textes qui s'envolent. Un seul nœud pour tout (léger sur téléphone).

const MAX := 220

var _parts: Array = []
var _police: Font


func _ready() -> void:
	_police = ThemeDB.fallback_font


func _ajouter(p: Dictionary) -> void:
	if _parts.size() >= MAX:
		_parts.pop_front()
	p.age = 0.0
	if not p.has("rot"):
		p.rot = 0.0
	if not p.has("vrot"):
		p.vrot = 0.0
	_parts.append(p)


func poussiere(pos: Vector2, dir := Vector2.ZERO, taille := 8.0) -> void:
	_ajouter({"type": 0, "p": pos + Vector2(randf_range(-5, 5), randf_range(-3, 5)),
		"v": dir * randf_range(10, 40) + Vector2(randf_range(-15, 15), randf_range(-20, 0)),
		"vie": randf_range(0.4, 0.7), "taille": taille * randf_range(0.7, 1.3), "frein": 3.0,
		"c": Color(0.86, 0.8, 0.62, 0.55)})


func herbe(pos: Vector2, nb := 12) -> void:
	for i in nb:
		var a := randf() * TAU
		_ajouter({"type": 1, "p": pos, "v": Vector2.from_angle(a) * randf_range(120, 330),
			"vie": randf_range(0.4, 0.8), "taille": randf_range(5, 9), "frein": 4.0,
			"rot": a, "vrot": randf_range(-12, 12),
			"c": [Color("5f9e43"), Color("7cbf55"), Color("9ad06c")][i % 3]})


func coeur(pos: Vector2) -> void:
	_ajouter({"type": 2, "p": pos + Vector2(randf_range(-6, 6), -10), "v": Vector2(randf_range(-20, 20), -70),
		"vie": 0.9, "taille": randf_range(6, 9), "frein": 1.0, "c": Color("ff5d7a")})


func etincelles(pos: Vector2, nb := 8, couleur := Color("fff3a0")) -> void:
	for i in nb:
		var a := TAU * i / nb + randf_range(-0.2, 0.2)
		_ajouter({"type": 3, "p": pos, "v": Vector2.from_angle(a) * randf_range(90, 180),
			"vie": randf_range(0.35, 0.55), "taille": randf_range(3, 5), "frein": 5.0, "c": couleur})


func confettis(pos: Vector2, nb := 60) -> void:
	var couleurs := [Color("ff5d7a"), Color("ffd23f"), Color("3ec1d3"), Color("7ed957"), Color("b388ff"), Color("ff9f43")]
	for i in nb:
		var a := randf_range(-PI, 0.0)
		_ajouter({"type": 4, "p": pos + Vector2(randf_range(-40, 40), 0), "v": Vector2.from_angle(a) * randf_range(200, 520),
			"vie": randf_range(1.2, 2.0), "taille": randf_range(6, 11), "frein": 1.6, "grav": 260.0,
			"rot": randf() * TAU, "vrot": randf_range(-10, 10), "c": couleurs[i % couleurs.size()]})


func texte(pos: Vector2, t: String, couleur: Color, taille := 30, vie := 0.9) -> void:
	_ajouter({"type": 5, "p": pos, "v": Vector2(0, -60), "vie": vie, "taille": float(taille), "frein": 2.0,
		"txt": t, "c": couleur})


func _process(delta: float) -> void:
	if _parts.is_empty():
		return
	var i := _parts.size() - 1
	while i >= 0:
		var p: Dictionary = _parts[i]
		p.age += delta
		if p.age >= p.vie:
			_parts.remove_at(i)
		else:
			var v: Vector2 = p.v
			p.p += v * delta
			v *= maxf(0.0, 1.0 - p.frein * delta)
			if p.has("grav"):
				v.y += p.grav * delta
			p.v = v
			p.rot += p.vrot * delta
		i -= 1
	queue_redraw()


func _draw() -> void:
	for p in _parts:
		var k: float = p.age / p.vie        # 0 → 1 au cours de la vie
		var c: Color = p.c
		match p.type:
			0:  # poussière : grossit et s'efface
				c.a *= 1.0 - k
				Rond.cercle(self, p.p, p.taille * (0.6 + k * 0.9), c)
			1:  # brin d'herbe qui tourne
				c.a = 1.0 - k * k
				var d: Vector2 = Vector2.from_angle(p.rot) * p.taille
				draw_line(p.p - d, p.p + d, c, 2.5)
			2:  # cœur
				c.a = 1.0 - k * k
				var s: float = p.taille * (0.6 + minf(k * 4.0, 1.0) * 0.4)
				Rond.cercle(self, p.p + Vector2(-s * 0.5, 0), s * 0.6, c)
				Rond.cercle(self, p.p + Vector2(s * 0.5, 0), s * 0.6, c)
				draw_colored_polygon(PackedVector2Array([p.p + Vector2(-s * 1.05, s * 0.2), p.p + Vector2(s * 1.05, s * 0.2), p.p + Vector2(0, s * 1.3)]), c)
			3:  # étincelle en forme d'étoile
				c.a = 1.0 - k
				var s: float = p.taille * (1.0 - k * 0.5)
				draw_line(p.p - Vector2(s * 1.6, 0), p.p + Vector2(s * 1.6, 0), c, 2.0)
				draw_line(p.p - Vector2(0, s * 1.6), p.p + Vector2(0, s * 1.6), c, 2.0)
				Rond.cercle(self, p.p, s * 0.6, c)
			4:  # confetti qui tourne
				c.a = 1.0 if k < 0.7 else (1.0 - k) / 0.3
				var l: float = p.taille
				var w: float = l * 0.5 * absf(cos(p.rot * 1.7))
				draw_set_transform(p.p, p.rot, Vector2.ONE)
				draw_rect(Rect2(-l / 2.0, -w / 2.0, l, maxf(w, 1.0)), c)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			5:  # texte qui grossit, monte et s'efface
				var taille := int(p.taille * (0.6 + minf(k * 6.0, 1.0) * 0.4 + (0.15 if k < 0.2 else 0.0)))
				var largeur := _police.get_string_size(p.txt, HORIZONTAL_ALIGNMENT_LEFT, -1, taille).x
				var pos: Vector2 = p.p - Vector2(largeur / 2.0, 0)
				var a := 1.0 if k < 0.6 else (1.0 - k) / 0.4
				draw_string_outline(_police, pos, p.txt, HORIZONTAL_ALIGNMENT_LEFT, -1, taille, 7, Color(0.1, 0.07, 0.03, a))
				c.a = a
				draw_string(_police, pos, p.txt, HORIZONTAL_ALIGNMENT_LEFT, -1, taille, c)
