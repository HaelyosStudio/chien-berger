extends RefCounted
## Générateur de niveaux (« cartes »), procédural.
## Tout est tiré au hasard à partir du numéro du niveau : un même niveau donne toujours
## la même prairie (« Rejouer » = même carte), le niveau suivant en donne une nouvelle.
## Chaque carte est vérifiée : il doit exister un passage assez large pour le troupeau
## entre son point de départ et l'entrée de l'enclos (recherche de chemin sur une grille).
## Le résultat est un simple dictionnaire de données ; main.gd construit et dessine le niveau.

const CHAMP := Rect2(24, 120, 672, 1136)
const CASE := 16.0                 # taille des cases de la grille de vérification
const PASSAGE := 28.0              # demi-largeur minimale d'un passage pour le troupeau
const BOUTON := Vector2(616, 1176) # coin du bouton OUAF : on n'y fait pas partir le troupeau

const LIEUX := ["Pré", "Prairie", "Vallon", "Colline", "Clairière", "Pâturage", "Plateau", "Combe"]
const NOMS := ["des Saules", "du Moulin", "aux Coquelicots", "du Vieux Chêne", "des Brumes", "de la Source",
	"du Berger", "des Trois Pierres", "aux Grillons", "des Alouettes", "du Loup", "aux Mûres",
	"des Genêts", "du Clocher", "de la Lune", "aux Papillons"]

var _cols := 0
var _lignes := 0
var _bloque := PackedByteArray()
var _dist := PackedInt32Array()


func generer(n: int) -> Dictionary:
	for essai in 40:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("chien-berger-%d-%d" % [n, essai])
		var c := _essayer(n, rng, essai >= 25)    # après 25 échecs : carte sans pièges
		if not c.is_empty():
			return c
	var secours := RandomNumberGenerator.new()
	secours.seed = n
	return _essayer(n, secours, true)


# ---------------------------------------------------------------- une tentative

func _essayer(n: int, rng: RandomNumberGenerator, simple: bool) -> Dictionary:
	var L := CHAMP.position.x
	var R := CHAMP.end.x
	var T := CHAMP.position.y
	var B := CHAMP.end.y
	var c := {}
	c.niveau = n
	c.graine = rng.randi()
	c.moutons = mini(12 + (n - 1) * 6, 70)
	c.obstacles = []        # {t: 0 cercle (c, r) | 1 segment (a, b, e = demi-épaisseur)}
	c.murs = []             # clôtures fines [a, b] (enclos)
	c.biais = []            # clôtures en biais des bosquets [a, b]
	c.forets = []           # bosquets (polygones interdits)
	c.etangs = []           # listes de Vector3(x, y, rayon)
	c.haies = []            # [a, b]
	c.rochers = []          # {p, r, buisson}
	c.foin = []             # {p, rot}
	c.riviere = {}

	# 1. L'enclos : côté, taille (selon le troupeau), position le long du bord
	var cote := "haut"
	if n >= 3 and not simple:
		var t := rng.randf()
		cote = "haut" if t < 0.5 else ("gauche" if t < 0.75 else "droite")
	c.cote = cote
	var aire: float = 9000.0 + c.moutons * 1350.0
	var enclos: Rect2
	var dedans: Vector2                     # direction : de la porte vers le fond de l'enclos
	if cote == "haut":
		var w := rng.randf_range(320.0, 440.0)
		var d := clampf(aire / w, 200.0, 340.0)
		w = clampf(aire / d, 300.0, CHAMP.size.x - 150.0)
		var x0 := _le_long(rng, L, R, w)
		enclos = Rect2(x0, T, w, d)
		dedans = Vector2.UP
	else:
		var d := rng.randf_range(210.0, 280.0)
		var w := clampf(aire / d, 280.0, 520.0)
		d = clampf(aire / w, 210.0, 320.0)
		var y0 := _le_long(rng, T, B - 280.0, w)
		enclos = Rect2(L, y0, d, w) if cote == "gauche" else Rect2(R - d, y0, d, w)
		dedans = Vector2.LEFT if cote == "gauche" else Vector2.RIGHT
	c.enclos = enclos
	c.dedans = dedans

	# Côtés de l'enclos : celui contre la clôture n'existe pas, celui face au pré porte l'entrée
	var coins := [enclos.position, Vector2(enclos.end.x, enclos.position.y), enclos.end, Vector2(enclos.position.x, enclos.end.y)]
	var largeur_porte := 190.0 if simple else clampf(215.0 - n * 7.0, 120.0, 215.0)
	for i in 4:
		var a: Vector2 = coins[i]
		var b: Vector2 = coins[(i + 1) % 4]
		if _sur_bord(a, b):
			continue
		var milieu := (a + b) / 2.0
		if (milieu - enclos.get_center()).normalized().dot(-dedans) > 0.9:
			var lg := a.distance_to(b)
			var u := (b - a) / lg
			var porte := minf(largeur_porte, lg - 80.0)
			var centre := rng.randf_range(porte / 2.0 + 35.0, lg - porte / 2.0 - 35.0)
			# enclos collé dans un coin : la porte touche la clôture du pré (sinon le bout de clôture
			# restant formerait un recoin où les moutons se coincent)
			if _sur_un_bord(a):
				centre = porte / 2.0
			elif _sur_un_bord(b):
				centre = lg - porte / 2.0
			var pa := a + u * (centre - porte / 2.0)
			var pb := a + u * (centre + porte / 2.0)
			if a.distance_to(pa) > 1.0:
				c.murs.append([a, pa])
			if pb.distance_to(b) > 1.0:
				c.murs.append([pb, b])
			c.porte = [pa, pb]
			c.porte_centre = (pa + pb) / 2.0
		else:
			c.murs.append([a, b])
	c.devant = c.porte_centre - dedans * 70.0        # juste devant l'entrée, dans le pré
	for m in c.murs:
		c.obstacles.append({"t": 1, "a": m[0], "b": m[1], "e": 6.0})

	# 2. Bosquets en biais entre l'enclos et les coins proches (aucun recoin où se coincer)
	for f in _bosquets(enclos, cote):
		c.forets.append(f.poly)
		c.biais.append(f.biais)
		c.obstacles.append({"t": 1, "a": f.biais[0], "b": f.biais[1], "e": 10.0})
	var bas_bosquets := enclos.end.y
	for f in c.forets:
		for p in f:
			bas_bosquets = maxf(bas_bosquets, p.y)

	# 3. Rivière avec ses ponts (enclos en haut seulement, à partir du niveau 4)
	if cote == "haut" and n >= 5 and not simple and rng.randf() < 0.55:
		var yr := maxf(enclos.end.y + 170.0, bas_bosquets + 80.0) + rng.randf_range(0.0, 120.0)
		if yr < B - 480.0:
			c.riviere = _riviere(rng, yr, n)
			var pts: PackedVector2Array = c.riviere.points
			for i in pts.size() - 1:
				var milieu := (pts[i] + pts[i + 1]) / 2.0
				var sur_pont := false
				for px in c.riviere.ponts:
					if absf(milieu.x - px) < 80.0:
						sur_pont = true
				if not sur_pont:
					c.obstacles.append({"t": 1, "a": pts[i], "b": pts[i + 1], "e": 24.0, "eau": true})
			# garde-corps des ponts (de vrais murs)
			for px in c.riviere.ponts:
				var py := _y_riviere(pts, px)
				for s in [-72.0, 72.0]:
					c.obstacles.append({"t": 1, "a": Vector2(px + s, py - 44.0), "b": Vector2(px + s, py + 44.0), "e": 5.0, "garde": true})

	# 4. Étangs
	var nb_etangs := 0 if (simple or n < 2) else rng.randi_range(1, mini(1 + n / 4, 3))
	for i in nb_etangs:
		var p: Variant = _place(rng, c, 75.0)
		if p == null:
			continue
		var blobs: Array = []
		for k in rng.randi_range(2, 4):
			var b: Vector3 = Vector3(p.x + rng.randf_range(-45, 45), p.y + rng.randf_range(-30, 30), rng.randf_range(28, 50))
			blobs.append(b)
			c.obstacles.append({"t": 0, "c": Vector2(b.x, b.y), "r": b.z})
		c.etangs.append(blobs)

	# 5. Haie qui part d'un bord et barre une partie du pré (à partir du niveau 3)
	if n >= 3 and not simple and rng.randf() < 0.5:
		for essai in 20:
			var y := rng.randf_range(bas_bosquets + 140.0, B - 300.0)
			var long := CHAMP.size.x * rng.randf_range(0.38, 0.58)
			var depuis_gauche := rng.randf() < 0.5
			var a := Vector2(L if depuis_gauche else R, y)
			var b := a + Vector2(long if depuis_gauche else -long, 0)
			if _segment_libre(c, a + (b - a).normalized() * 30.0, b, 75.0):
				c.haies.append([a, b])
				c.obstacles.append({"t": 1, "a": a, "b": b, "e": 15.0})
				break

	# 6. Rochers, buissons et bottes de foin
	var nb_rochers := 0 if simple else mini(2 + n / 2, 9)
	for i in nb_rochers:
		var r := rng.randf_range(22.0, 40.0)
		var p: Variant = _place(rng, c, r)
		if p == null:
			continue
		c.rochers.append({"p": p, "r": r, "buisson": rng.randf() < 0.4})
		c.obstacles.append({"t": 0, "c": p, "r": r})
	for i in mini(1 + n / 3, 4):
		var p: Variant = _place(rng, c, 34.0)
		if p != null:
			c.foin.append({"p": p, "rot": rng.randf() * TAU})

	# 7. Vérification : passage assez large jusqu'à l'entrée ?
	_remplir_grille(c, PASSAGE)
	var depart := _case(c.devant)
	if depart < 0 or _bloque[depart] == 1:
		return {}
	_chemins(depart)
	var dmax := 0
	for d in _dist:
		dmax = maxi(dmax, d)
	if dmax < 25:
		return {}

	# 8. Départ du troupeau : loin de l'entrée (en suivant les passages)
	var candidats: Array[int] = []
	for i in _dist.size():
		var q := _centre_case(i)
		var loin_des_bords := q.x > CHAMP.position.x + 110.0 and q.x < CHAMP.end.x - 110.0 and q.y > CHAMP.position.y + 110.0 and q.y < CHAMP.end.y - 110.0
		if _dist[i] >= int(dmax * 0.6) and q.distance_to(BOUTON) > 230.0 and loin_des_bords:
			candidats.append(i)
	if candidats.is_empty():
		return {}
	var centre := _centre_case(candidats[rng.randi_range(0, candidats.size() - 1)])

	# 9. Les moutons, en paquet autour de ce point (uniquement dans les cases atteignables)
	var cases: Array = []
	for i in _dist.size():
		if _dist[i] >= 0:
			var p := _centre_case(i)
			cases.append([p.distance_squared_to(centre), p])
	cases.sort_custom(func(x, y): return x[0] < y[0])
	var positions: Array[Vector2] = []
	for e in cases:
		var p: Vector2 = e[1] + Vector2(rng.randf_range(-5, 5), rng.randf_range(-5, 5))
		var ok := true
		for q in positions:
			if p.distance_squared_to(q) < 27.0 * 27.0:
				ok = false
				break
		for f in c.foin:
			if p.distance_to(f.p) < 45.0:
				ok = false
		if ok:
			positions.append(p)
			if positions.size() >= c.moutons:
				break
	if positions.size() < c.moutons:
		return {}
	c.positions = positions
	var etendue := 0.0
	var vrai_centre := Vector2.ZERO
	for p in positions:
		vrai_centre += p
	vrai_centre /= positions.size()
	for p in positions:
		etendue = maxf(etendue, p.distance_to(vrai_centre))

	# 10. Le chien : derrière le troupeau (côté opposé à l'entrée), sur une case libre
	var vise: Vector2 = vrai_centre + (vrai_centre - c.devant).normalized() * (etendue + 80.0)
	var meilleur := -1
	var meilleur_d := INF
	for i in _dist.size():
		if _dist[i] < 0:
			continue
		var d := _centre_case(i).distance_squared_to(vise)
		var trop_pres := false
		for p in positions:
			if _centre_case(i).distance_squared_to(p) < 40.0 * 40.0:
				trop_pres = true
				break
		if d < meilleur_d and not trop_pres:
			meilleur_d = d
			meilleur = i
	if meilleur < 0:
		return {}
	c.chien = _centre_case(meilleur)

	# 11. Chemin de terre (le trajet le plus court jusqu'à l'entrée) et temps accordé
	c.chemin = _tracer_chemin(_case(centre), c)      # centre = une case libre (le vrai centre peut tomber dans un étang)
	var longueur := 0.0
	for i in c.chemin.size() - 1:
		longueur += c.chemin[i].distance_to(c.chemin[i + 1])
	var base: float = 50.0 + c.moutons * 1.8 + longueur * 0.08 + (20.0 if not c.riviere.is_empty() else 0.0) + c.etangs.size() * 8.0
	c.temps = snappedf(base * clampf(1.15 - n * 0.025, 0.85, 1.15), 5.0)

	# Données utiles au pilote automatique : la grille des distances jusqu'à l'entrée
	c.grille_dist = _dist.duplicate()
	c.grille_cols = _cols
	c.grille_case = CASE

	c.nom = _nom(rng, c)
	return c


## Position le long d'un bord : soit collée au coin, soit à plus de 70 px (jamais de couloir étroit).
func _le_long(rng: RandomNumberGenerator, debut: float, fin: float, taille: float) -> float:
	var p := rng.randf_range(debut, fin - taille)
	if p - debut < 70.0:
		p = debut
	elif fin - (p + taille) < 70.0:
		p = fin - taille
	return p


func _sur_un_bord(p: Vector2) -> bool:
	return is_equal_approx(p.x, CHAMP.position.x) or is_equal_approx(p.x, CHAMP.end.x) or is_equal_approx(p.y, CHAMP.position.y) or is_equal_approx(p.y, CHAMP.end.y)


func _sur_bord(a: Vector2, b: Vector2) -> bool:
	var L := CHAMP.position.x
	var R := CHAMP.end.x
	var T := CHAMP.position.y
	var B := CHAMP.end.y
	return (is_equal_approx(a.x, L) and is_equal_approx(b.x, L)) or (is_equal_approx(a.x, R) and is_equal_approx(b.x, R)) \
		or (is_equal_approx(a.y, T) and is_equal_approx(b.y, T)) or (is_equal_approx(a.y, B) and is_equal_approx(b.y, B))


## Bosquets bordés d'une clôture à 45° entre l'enclos et les coins proches du même bord.
func _bosquets(e: Rect2, cote: String) -> Array:
	var L := CHAMP.position.x
	var R := CHAMP.end.x
	var T := CHAMP.position.y
	var B := CHAMP.end.y
	var res: Array = []
	var ajouter := func(poly: PackedVector2Array, a: Vector2, b: Vector2) -> void:
		res.append({"poly": poly, "biais": [a, b]})
	if cote == "haut":
		var g := e.position.x - L
		if g > 1.0 and g <= 300.0:
			ajouter.call(PackedVector2Array([Vector2(L, T), Vector2(e.position.x, T), Vector2(e.position.x, e.end.y), Vector2(L, e.end.y + g)]), Vector2(e.position.x, e.end.y), Vector2(L, e.end.y + g))
		elif g > 300.0:
			# coin lointain : petit triangle dans l'angle entre l'enclos et la clôture du haut
			ajouter.call(PackedVector2Array([Vector2(e.position.x, T), Vector2(e.position.x, T + e.size.y), Vector2(e.position.x - e.size.y, T)]), Vector2(e.position.x, T + e.size.y), Vector2(e.position.x - e.size.y, T))
		var dr := R - e.end.x
		if dr > 1.0 and dr <= 300.0:
			ajouter.call(PackedVector2Array([Vector2(R, T), Vector2(e.end.x, T), e.end, Vector2(R, e.end.y + dr)]), e.end, Vector2(R, e.end.y + dr))
		elif dr > 300.0:
			ajouter.call(PackedVector2Array([Vector2(e.end.x, T), e.end, Vector2(e.end.x + e.size.y, T)]), e.end, Vector2(e.end.x + e.size.y, T))
	else:
		var bord := L if cote == "gauche" else R
		var s := 1.0 if cote == "gauche" else -1.0          # vers l'intérieur du pré
		var x_int := bord + s * e.size.x
		var h := e.position.y - T
		var p := e.size.x                                   # profondeur de l'enclos
		if h > 1.0 and h <= 300.0:
			ajouter.call(PackedVector2Array([Vector2(bord, T), Vector2(bord, e.position.y), Vector2(x_int, e.position.y), Vector2(x_int + s * h, T)]), Vector2(x_int, e.position.y), Vector2(x_int + s * h, T))
		elif h > 300.0:
			ajouter.call(PackedVector2Array([Vector2(bord, e.position.y), Vector2(x_int, e.position.y), Vector2(bord, e.position.y - p)]), Vector2(x_int, e.position.y), Vector2(bord, e.position.y - p))
		var bas := B - e.end.y
		if bas > 1.0 and bas <= 300.0:
			ajouter.call(PackedVector2Array([Vector2(bord, B), Vector2(bord, e.end.y), Vector2(x_int, e.end.y), Vector2(x_int + s * bas, B)]), Vector2(x_int, e.end.y), Vector2(x_int + s * bas, B))
		elif bas > 300.0:
			ajouter.call(PackedVector2Array([Vector2(bord, e.end.y), Vector2(x_int, e.end.y), Vector2(bord, e.end.y + p)]), Vector2(x_int, e.end.y), Vector2(bord, e.end.y + p))
	return res


func _riviere(rng: RandomNumberGenerator, yr: float, n: int) -> Dictionary:
	var pts := PackedVector2Array()
	var phase := rng.randf() * TAU
	var amp := rng.randf_range(12.0, 30.0)
	var x := CHAMP.position.x - 10.0
	while x <= CHAMP.end.x + 10.0:
		pts.append(Vector2(x, yr + sin(x * 0.011 + phase) * amp))
		x += 24.0
	var ponts: Array = []
	var nb := 1 if n < 7 else 2
	for essai in 30:
		if ponts.size() >= nb:
			break
		var px := rng.randf_range(CHAMP.position.x + 100.0, CHAMP.end.x - 100.0)
		var ok := true
		for q in ponts:
			if absf(px - q) < 220.0:
				ok = false
		if ok:
			ponts.append(px)
	ponts.sort()
	return {"points": pts, "ponts": ponts}


func _y_riviere(pts: PackedVector2Array, x: float) -> float:
	for i in pts.size() - 1:
		if x >= pts[i].x and x <= pts[i + 1].x:
			return lerpf(pts[i].y, pts[i + 1].y, (x - pts[i].x) / (pts[i + 1].x - pts[i].x))
	return pts[0].y


func _distance_obstacle(p: Vector2, o: Dictionary) -> float:
	if o.t == 0:
		return p.distance_to(o.c) - o.r
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, o.a, o.b)) - o.e


func _dans_foret(c: Dictionary, p: Vector2, marge: float) -> bool:
	for f in c.forets:
		if Geometry2D.is_point_in_polygon(p, f):
			return true
		for i in f.size():
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, f[i], f[(i + 1) % f.size()])) < marge:
				return true
	return false


## Un point libre pour un obstacle de rayon donné, en laissant de la place pour passer.
func _place(rng: RandomNumberGenerator, c: Dictionary, rayon: float) -> Variant:
	for essai in 50:
		var p := Vector2(rng.randf_range(CHAMP.position.x + rayon + 40.0, CHAMP.end.x - rayon - 40.0),
			rng.randf_range(CHAMP.position.y + rayon + 40.0, CHAMP.end.y - rayon - 40.0))
		if c.enclos.grow(rayon + 60.0).has_point(p) or p.distance_to(c.devant) < 150.0 + rayon:
			continue
		if _dans_foret(c, p, rayon + 50.0):
			continue
		var ok := true
		for o in c.obstacles:
			if _distance_obstacle(p, o) < rayon + 60.0:
				ok = false
				break
		for f in c.foin:
			if p.distance_to(f.p) < rayon + 70.0:
				ok = false
		if ok:
			return p
	return null


func _segment_libre(c: Dictionary, a: Vector2, b: Vector2, marge: float) -> bool:
	for k in 11:
		var p := a.lerp(b, k / 10.0)
		if c.enclos.grow(marge).has_point(p) or _dans_foret(c, p, marge) or p.distance_to(c.devant) < 150.0:
			return false
		for o in c.obstacles:
			if _distance_obstacle(p, o) < marge:
				return false
	return true


# ---------------------------------------------------------------- grille et chemins

func _case(p: Vector2) -> int:
	var i := int((p.x - CHAMP.position.x) / CASE)
	var j := int((p.y - CHAMP.position.y) / CASE)
	if i < 0 or j < 0 or i >= _cols or j >= _lignes:
		return -1
	return j * _cols + i


func _centre_case(k: int) -> Vector2:
	return CHAMP.position + Vector2((k % _cols) + 0.5, (k / _cols) + 0.5) * CASE


func _remplir_grille(c: Dictionary, marge: float) -> void:
	_cols = int(CHAMP.size.x / CASE)
	_lignes = int(CHAMP.size.y / CASE)
	_bloque = PackedByteArray()
	_bloque.resize(_cols * _lignes)
	_bloque.fill(0)
	var dedans_enclos: Rect2 = c.enclos.grow(marge)
	for k in _bloque.size():
		var p := _centre_case(k)
		if p.x < CHAMP.position.x + marge or p.x > CHAMP.end.x - marge or p.y < CHAMP.position.y + marge or p.y > CHAMP.end.y - marge:
			_bloque[k] = 1
		elif dedans_enclos.has_point(p):
			_bloque[k] = 1
	# obstacles : on ne regarde que les cases autour de chacun
	for o in c.obstacles:
		var boite: Rect2
		if o.t == 0:
			boite = Rect2(o.c, Vector2.ZERO).grow(o.r + marge)
		else:
			boite = Rect2(o.a, Vector2.ZERO).expand(o.b).grow(o.e + marge)
		_marquer(boite, func(p: Vector2) -> bool: return _distance_obstacle(p, o) < marge)
	for f in c.forets:
		var boite := Rect2(f[0], Vector2.ZERO)
		for p in f:
			boite = boite.expand(p)
		var poly: PackedVector2Array = f
		_marquer(boite.grow(marge), func(p: Vector2) -> bool:
			if Geometry2D.is_point_in_polygon(p, poly):
				return true
			for i in poly.size():
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])) < marge:
					return true
			return false)


func _marquer(boite: Rect2, test: Callable) -> void:
	var i0 := maxi(0, int((boite.position.x - CHAMP.position.x) / CASE))
	var i1 := mini(_cols - 1, int((boite.end.x - CHAMP.position.x) / CASE))
	var j0 := maxi(0, int((boite.position.y - CHAMP.position.y) / CASE))
	var j1 := mini(_lignes - 1, int((boite.end.y - CHAMP.position.y) / CASE))
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var k := j * _cols + i
			if _bloque[k] == 0 and test.call(_centre_case(k)):
				_bloque[k] = 1


## Distance (en cases) de chaque case libre jusqu'à l'entrée ; -1 = inaccessible.
func _chemins(depart: int) -> void:
	_dist = PackedInt32Array()
	_dist.resize(_bloque.size())
	_dist.fill(-1)
	_dist[depart] = 0
	var file: Array[int] = [depart]
	var tete := 0
	while tete < file.size():
		var k := file[tete]
		tete += 1
		var i := k % _cols
		var j := k / _cols
		for v in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ni: int = i + v.x
			var nj: int = j + v.y
			if ni < 0 or nj < 0 or ni >= _cols or nj >= _lignes:
				continue
			var nk := nj * _cols + ni
			if _bloque[nk] == 0 and _dist[nk] < 0:
				_dist[nk] = _dist[k] + 1
				file.append(nk)


## Descend les distances depuis le troupeau jusqu'à l'entrée, puis lisse le tracé.
func _tracer_chemin(k: int, c: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if k < 0 or _dist[k] < 0:
		return pts
	var garde := 0
	while _dist[k] > 0 and garde < 2000:
		garde += 1
		if garde % 3 == 1:
			pts.append(_centre_case(k))
		var i := k % _cols
		var j := k / _cols
		var suivant := k
		for v in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var ni: int = i + v.x
			var nj: int = j + v.y
			if ni < 0 or nj < 0 or ni >= _cols or nj >= _lignes:
				continue
			var nk := nj * _cols + ni
			if _dist[nk] >= 0 and _dist[nk] < _dist[suivant]:
				suivant = nk
		if suivant == k:
			break
		k = suivant
	pts.append(c.devant)
	pts.append(c.porte_centre)
	# lissage (coins arrondis)
	for passe in 2:
		var lisse := PackedVector2Array([pts[0]])
		for i in pts.size() - 1:
			lisse.append(pts[i].lerp(pts[i + 1], 0.25))
			lisse.append(pts[i].lerp(pts[i + 1], 0.75))
		lisse.append(pts[pts.size() - 1])
		pts = lisse
	return pts


func _nom(rng: RandomNumberGenerator, c: Dictionary) -> String:
	if not c.riviere.is_empty() and rng.randf() < 0.6:
		return "%s %s" % [LIEUX[rng.randi() % LIEUX.size()], ["du Ruisseau", "de la Rivière", "du Gué", "des Ponts"][rng.randi() % 4]]
	if not c.etangs.is_empty() and rng.randf() < 0.4:
		return "%s %s" % [LIEUX[rng.randi() % LIEUX.size()], ["de l'Étang", "des Grenouilles", "aux Roseaux"][rng.randi() % 3]]
	return "%s %s" % [LIEUX[rng.randi() % LIEUX.size()], NOMS[rng.randi() % NOMS.size()]]
