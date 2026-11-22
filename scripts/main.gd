extends Node2D
## SheperdRun : guide tout le troupeau dans l'enclos avant la fin du temps.
## Tout est construit par le code (aucune image) pour rester léger sur téléphone.
## Commandes : joystick flottant (pose le doigt n'importe où et glisse) ; bouton OUAF = aboyer.
## Sur ordinateur : clic-glisser (souris = doigt) ou flèches du clavier + Espace.

const Mouton := preload("res://scripts/mouton.gd")
const Chien := preload("res://scripts/chien.gd")
const Sons := preload("res://scripts/sons.gd")
const Effets := preload("res://scripts/effets.gd")
const Loup := preload("res://scripts/loup.gd")

const Carte := preload("res://scripts/carte.gd")

const TAILLE := Vector2(720, 1280)
const CHAMP := Rect2(24, 120, 672, 1136)     # prairie entourée de barrières
const EPAISSEUR := 12.0
const FICHIER := "user://chien_berger.cfg"
const Chargement := preload("res://scripts/chargement.gd")

var _carte: Dictionary = {}        # le niveau généré (voir carte.gd)
var _enclos := Rect2()

var niveau := 1
var _niveau_joue := 1               # niveau affiché pendant la partie
var chien: Chien
var moutons: Array = []
var en_jeu := false

var _monde: Node2D                 # tout ce qui est recréé à chaque niveau
var _effets_sol: Effets            # poussière, herbe (sous les moutons)
var _effets_air: Effets            # cœurs, textes, confettis (au-dessus de tout)
var _camera: Camera2D
var _secousse := 0.0
var _grille: Dictionary = {}       # cases de 95 px -> moutons (voisinage rapide)
var _infos: Dictionary = {}        # partagé avec les moutons : centre du troupeau, porte, part rentrée
var _temps_total := 90.0
var _temps_restant := 0.0
var _temps_ecoule := 0.0
var _tenue := 0.0                  # temps passé avec tous les moutons dedans
var _dans_avant := 0
var _dernier_bele := 0.0
var _gagne := false
var _doigt := -1
var _graine := 0
var _demo := false
var _mesures := Vector3.ZERO
var _sons: Node

# Éléments de jeu : combos, mouton d'or, os (turbo), loup, étoiles
var _combo := 0
var _dernier_entre := 99.0
var _dernier_ding := 0.0
var _os: Os = null
var _prochain_os := 12.0
var _loup: Loup = null
var _loup_prevu := false
var _belier: Node2D = null
var _vent := Vector2.ZERO          # direction du prochain / du coup de vent
var _vent_t := -1.0               # >0 : temps restant du coup de vent en cours
var _prochain_vent := 0.0
var _rafale: Rafale = null
var _astuce_belier := false
var _prochain_loup := 20.0
var _loups_restants := 0
var _rng_jeu := RandomNumberGenerator.new()
var _etoiles: Etoiles

# Interface
var _lbl_niveau: Label
var _lbl_moutons: Label
var _lbl_temps: Label
var _barre: ColorRect
var _joystick: Joystick
var _bouton_aboi: BoutonRond
var _bouton_pause: BoutonRond
var _bouton_musique: BoutonRond
var _ecran: Control
var _ecran_titre: Label
var _ecran_texte: Label
var _ecran_b1: Button
var _ecran_b2: Button
var _action1 := ""
var _action2 := ""


# ---------------------------------------------------------------- démarrage

func _ready() -> void:
	randomize()
	_demo = "--demo" in OS.get_cmdline_user_args()
	_sons = Sons.new()
	add_child(_sons)
	_camera = Camera2D.new()
	_camera.position = TAILLE / 2.0
	add_child(_camera)
	_camera.make_current()
	_creer_bordures()
	_creer_interface()
	niveau = _charger()
	_construire_niveau()
	if _demo:
		_demarrer()
		return
	var maj := get_node_or_null("/root/MiseAJour")
	# écran plein des mises à jour (relance automatique) ; placé à la racine pour survivre à la relance
	var ecran_maj: CanvasLayer = preload("res://scripts/ecran_maj.gd").new()
	ecran_maj.peut_afficher = func() -> bool: return not en_jeu
	get_tree().root.add_child.call_deferred(ecran_maj)
	_sons.musique_active = _lire_reglage("musique", true)
	_sons.lancer_musique()
	_montrer_ecran("SheperdRun",
		"Pose ton doigt n'importe où et glisse : un joystick apparaît sous ton doigt pour diriger le chien.\n\nLe troupeau le fuit : pousse-le dans l'enclos.\n\nOUAF ! fait détaler les moutons.\n\nRamasse les os (turbo), chasse le loup et rentre le mouton d'or (+15 s) !\n\nVersion %s" % (maj.version if maj else "?"),
		"Jouer - niveau %d" % niveau, "jouer",
		"Recommencer au niveau 1" if niveau > 1 else "", "niveau1")


# ---------------------------------------------------------------- construction du terrain

func _mur(rect: Rect2, parent: Node) -> void:
	var corps := StaticBody2D.new()
	corps.position = rect.get_center()
	var forme := CollisionShape2D.new()
	var boite := RectangleShape2D.new()
	boite.size = rect.size
	forme.shape = boite
	corps.add_child(forme)
	parent.add_child(corps)


func _creer_bordures() -> void:
	var e := 60.0
	var c := CHAMP
	_mur(Rect2(c.position.x - e, c.position.y - e, c.size.x + 2 * e, e), self)   # haut
	_mur(Rect2(c.position.x - e, c.end.y, c.size.x + 2 * e, e), self)            # bas
	_mur(Rect2(c.position.x - e, c.position.y, e, c.size.y), self)               # gauche
	_mur(Rect2(c.end.x, c.position.y, e, c.size.y), self)                        # droite


## Mur droit entre deux points, quelle que soit son orientation.
func _mur_segment(a: Vector2, b: Vector2, epaisseur: float, parent: Node) -> void:
	var corps := StaticBody2D.new()
	corps.position = (a + b) / 2.0
	corps.rotation = (b - a).angle()
	var forme := CollisionShape2D.new()
	var boite := RectangleShape2D.new()
	boite.size = Vector2(a.distance_to(b) + epaisseur, epaisseur)
	forme.shape = boite
	corps.add_child(forme)
	parent.add_child(corps)


func _mur_rond(p: Vector2, r: float, parent: Node) -> void:
	var corps := StaticBody2D.new()
	corps.position = p
	var forme := CollisionShape2D.new()
	var cercle := CircleShape2D.new()
	cercle.radius = r
	forme.shape = cercle
	corps.add_child(forme)
	parent.add_child(corps)


## Intérieur de l'enclos où un mouton compte comme rentré : marge seulement du côté de la porte
## (au fond, les moutons serrés contre la clôture comptent aussi).
func _zone_comptee() -> Rect2:
	var cote := SIDE_BOTTOM
	match _carte.cote:
		"gauche":
			cote = SIDE_RIGHT
		"droite":
			cote = SIDE_LEFT
	return _enclos.grow_side(cote, -15.0)


func _en_foret(p: Vector2, marge := 0.0) -> bool:
	for f in _carte.get("forets", []):
		if Geometry2D.is_point_in_polygon(p, f):
			return true
		if marge > 0.0:
			for i in f.size():
				var q := Geometry2D.get_closest_point_to_segment(p, f[i], f[(i + 1) % f.size()])
				if p.distance_to(q) < marge:
					return true
	return false


## Vrai si le point touche un obstacle du décor (pour ne pas y dessiner de fleurs).
func _sur_obstacle(p: Vector2, marge: float) -> bool:
	if _enclos.grow(marge).has_point(p) or _en_foret(p, marge):
		return true
	for o in _carte.obstacles:
		var d: float = p.distance_to(o.c) - o.r if o.t == 0 else p.distance_to(Geometry2D.get_closest_point_to_segment(p, o.a, o.b)) - o.e
		if d < marge:
			return true
	return false


func _construire_niveau() -> void:
	if _monde:
		remove_child(_monde)
		_monde.queue_free()
	_carte = Carte.new().generer(niveau)
	var c := _carte
	_enclos = c.enclos
	_niveau_joue = niveau
	_temps_total = c.temps
	_graine = c.graine
	_monde = Node2D.new()
	add_child(_monde)

	# Murs : enclos, clôtures en biais, rivière, haies, étangs
	for m in c.murs:
		_mur_segment(m[0], m[1], EPAISSEUR, _monde)
	for m in c.biais:
		_mur_segment(m[0], m[1], 20.0, _monde)
	for o in c.obstacles:
		if o.has("eau") or o.has("garde"):
			_mur_segment(o.a, o.b, o.e * 2.0, _monde)
	for h in c.haies:
		_mur_segment(h[0], h[1], 30.0, _monde)
	for etang in c.etangs:
		for b in etang:
			_mur_rond(Vector2(b.x, b.y), b.z, _monde)

	_effets_sol = Effets.new()
	_monde.add_child(_effets_sol)
	var rng := RandomNumberGenerator.new()
	rng.seed = c.graine

	for r in c.rochers:
		var roc := Rocher.new()
		roc.rayon = r.r
		roc.buisson = r.buisson
		roc.position = r.p
		_monde.add_child(roc)
	for f in c.foin:
		var botte := Foin.new()
		botte.position = f.p
		botte.rotation = f.rot
		_monde.add_child(botte)

	# Le troupeau, à l'endroit choisi par le générateur
	moutons = []
	_grille.clear()
	_infos.clear()
	var index_dore: int = rng.randi() % c.positions.size() if niveau >= 2 else -1
	# Rôles : un bélier (dès le niveau 3) et des agneaux collés à leur maman (dès le niveau 2)
	var libres: Array[int] = []
	for i in c.positions.size():
		if i != index_dore:
			libres.append(i)
	for i in range(libres.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp := libres[i]
		libres[i] = libres[j]
		libres[j] = tmp
	var index_belier: int = libres.pop_back() if niveau >= 3 else -1
	var mamans := {}          # index de l'agneau -> index de sa maman
	var nb_agneaux := 0 if niveau < 2 else mini(1 + (niveau - 2) / 2, 4)
	for k in nb_agneaux:
		if libres.size() < 2:
			break
		var a: int = libres.pop_back()
		mamans[a] = libres.pop_back()
	for p in c.positions:
		var i := moutons.size()
		var m := Mouton.new()
		m.dore = i == index_dore
		m.belier = i == index_belier
		m.agneau = mamans.has(i)
		m.position = p
		if m.agneau:          # né à côté de sa maman
			m.position = c.positions[mamans[i]] + Vector2.from_angle(rng.randf() * TAU) * 22.0
		if m.belier:
			m.charge.connect(_belier_charge.bind(m))
		if m.agneau:
			m.appelle.connect(_agneau_appelle.bind(m))
		if "--victoire" in OS.get_cmdline_user_args():     # test : troupeau déjà dans l'enclos
			m.position = Vector2(rng.randf_range(_enclos.position.x + 30, _enclos.end.x - 30), rng.randf_range(_enclos.position.y + 30, _enclos.end.y - 30))
		m.enclos = _zone_comptee()
		m.fond = c.dedans
		m.grille = _grille
		m.infos = _infos
		m.noir = rng.randf() < 0.07 and not (m.belier or m.agneau)
		_monde.add_child(m)
		moutons.append(m)
	for a in mamans:
		moutons[a].mere = moutons[mamans[a]]
		moutons[mamans[a]].petit = moutons[a]
	_belier = moutons[index_belier] if index_belier >= 0 else null

	chien = Chien.new()
	chien.position = c.chien
	_monde.add_child(chien)
	for m in moutons:
		m.chien = chien

	_monde.add_child(Nuages.new())
	_effets_air = Effets.new()
	_monde.add_child(_effets_air)

	_temps_restant = _temps_total
	_temps_ecoule = 0.0
	_tenue = 0.0
	_dans_avant = 0
	_gagne = false
	_relacher_joystick()
	_joystick.aide = niveau <= 2
	_rng_jeu.seed = c.graine + 99
	_combo = 0
	_dernier_entre = 99.0
	_os = null
	_prochain_os = 12.0
	_loup = null
	_loup_prevu = niveau >= 4 and _rng_jeu.randf() < 0.7
	_prochain_loup = _rng_jeu.randf_range(15.0, 28.0)
	_loups_restants = 1 if niveau < 8 else 2
	_infos.loup_actif = false
	_vent_t = -1.0
	_prochain_vent = _rng_jeu.randf_range(14.0, 22.0) if niveau >= 6 else INF
	_rafale = Rafale.new()
	_monde.add_child(_rafale)
	queue_redraw()
	_barre.anchor_right = 0.0
	_maj_hud(0)

# ---------------------------------------------------------------- partie

func _demarrer() -> void:
	_cacher_ecran()
	get_tree().paused = false
	en_jeu = true
	if _temps_ecoule == 0.0:
		_sons.sifflet()
		_effets_air.texte(CHAMP.get_center() + Vector2(0, -60), _carte.nom, Color("fff3c4"), 46, 2.6)
		var astuces := {
			2: ["Nouveau : les agneaux !", "Rentre-les avec leur maman (+5 s)"],
			3: ["Nouveau : le bélier !", "Le troupeau le suit. De face, il fonce !"],
			6: ["Nouveau : le vent !", "Les rafales poussent les moutons"],
		}
		if astuces.has(niveau):
			_effets_air.texte(CHAMP.get_center() + Vector2(0, 10), astuces[niveau][0], Color("ffd23f"), 34, 3.6)
			_effets_air.texte(CHAMP.get_center() + Vector2(0, 52), astuces[niveau][1], Color("ffffff"), 26, 3.6)


## Grille de voisinage, remplie avant que les moutons ne calculent leurs forces
## (le parent est traité avant ses enfants).
func _physics_process(_delta: float) -> void:
	_grille.clear()
	var centre := Vector2.ZERO
	var dehors := 0
	for m in moutons:
		if not m.dans_enclos:
			centre += m.global_position
			dehors += 1
		var k := Vector2i(int(floor(m.global_position.x / Mouton.CASE)), int(floor(m.global_position.y / Mouton.CASE)))
		if _grille.has(k):
			_grille[k].append(m)
		else:
			_grille[k] = [m]
	if dehors > 0:
		_infos.dehors = centre / dehors
	if not _carte.is_empty():
		_infos.porte = _carte.porte_centre + _carte.dedans * 30.0
	_infos.part_dedans = 1.0 - float(dehors) / maxi(1, moutons.size())
	# le bélier est le chef : dehors, on le suit ; rentré, tout le monde veut le rejoindre
	_infos.erase("belier")
	if is_instance_valid(_belier):
		if _belier.dans_enclos:
			_infos.part_dedans = minf(1.0, _infos.part_dedans + 0.35)
		else:
			_infos.belier = _belier.global_position


func _process(delta: float) -> void:
	_bouton_aboi.charge = chien.charge_aboi() if chien else 1.0
	_bouton_aboi.appuye = maxf(0.0, _bouton_aboi.appuye - delta)
	_bouton_aboi.queue_redraw()

	# Secousse de la caméra
	_secousse = maxf(0.0, _secousse - delta * 2.5)
	_camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _secousse * _secousse * 14.0

	if chien == null:
		return
	# Poussière soulevée par les sabots et les pattes
	for m in moutons:
		var v: Vector2 = m.linear_velocity
		if v.length() > 180.0 and randf() < delta * 3.0:
			_effets_sol.poussiere(m.global_position + Vector2(0, 8), -v.normalized(), 6.0)
	if chien.linear_velocity.length() > 260.0 and randf() < delta * 16.0:
		_effets_sol.poussiere(chien.global_position + Vector2(0, 8), -chien.linear_velocity.normalized(), 8.0)

	if not en_jeu:
		return
	if _demo:
		_pilote_auto()
		var maintenant := Time.get_ticks_usec()
		if _mesures.y > 0.0:
			_mesures.x += (maintenant - _mesures.y) / 1000000.0
		_mesures.y = maintenant
		_mesures.z += 1
		if int(_mesures.z) % 1200 == 0:
			print("PERF %.2f ms par image" % [_mesures.x / _mesures.z * 1000.0])

	_temps_restant -= delta
	_temps_ecoule += delta
	_dernier_bele += delta
	_dernier_entre += delta
	_dernier_ding += delta
	_gerer_os(delta)
	_gerer_loup(delta)
	_gerer_vent(delta)
	var dedans := 0
	for m in moutons:
		if m.dans_enclos:
			dedans += 1
			if not m.compte:
				m.compte = true
				_mouton_rentre(m)
				_sons.pop(float(dedans) / moutons.size())
				_effets_air.coeur(m.global_position)
				_effets_air.etincelles(m.global_position, 6)
				if _dernier_bele > 0.12:
					_sons.bele()
					_dernier_bele = 0.0
		elif m.compte and not _enclos.grow(4.0).has_point(m.global_position):
			m.compte = false
	if dedans != _dans_avant:
		if dedans > _dans_avant:
			_rebond(_lbl_moutons)
		create_tween().tween_property(_barre, "anchor_right", float(dedans) / moutons.size(), 0.25)
	_dans_avant = dedans

	if dedans == moutons.size():
		_tenue += delta
		if _tenue > 0.5:
			_gagner()
	else:
		_tenue = 0.0
	if en_jeu and _temps_restant <= 0.0:
		_temps_restant = 0.0
		_perdre(moutons.size() - dedans)
	_maj_hud(dedans)


func _gagner() -> void:
	en_jeu = false
	if is_instance_valid(_loup):
		_loup.chasser()
	_gagne = true
	_relacher_joystick()
	queue_redraw()                   # la porte se ferme
	_sons.victoire()
	_sons.porte()
	Input.vibrate_handheld(150)
	_secousse = 0.5
	for m in moutons:
		m.fete = true
	var c := _enclos.get_center()
	var pa: Vector2 = _carte.porte[0]
	var pb: Vector2 = _carte.porte[1]
	for k in 3:
		_effets_air.confettis(pa.lerp(pb, 0.2 + 0.3 * k) + _carte.dedans * 25.0, 45)
	_effets_air.texte(c + Vector2(0, -10), "BRAVO !", Color("ffd23f"), 64, 1.8)
	var temps := _temps_ecoule
	var reste := _temps_restant / _temps_total
	var nb := moutons.size()
	var nom: String = _carte.nom
	niveau += 1
	_sauver()
	if _demo:
		print("DEMO: niveau gagné en %.1f s (%d moutons)" % [temps, nb])
		await get_tree().create_timer(1.2).timeout
		get_tree().quit()
		return
	await get_tree().create_timer(2.0).timeout
	var nb_etoiles := 1 + (1 if reste >= 0.3 else 0) + (1 if reste >= 0.55 else 0)
	var bilan: String = ["Ouf, juste à temps !", "Beau travail !", "Chien d'or : quel berger !"][nb_etoiles - 1]
	_montrer_ecran("Bravo !",
		"%s : les %d moutons sont à l'abri en %s.\n\n%s" % [nom, nb, _format_temps(temps), bilan],
		"Niveau %d : nouvelle prairie" % niveau, "suivant", "Rejouer ce niveau", "precedent")
	_etoiles.montrer(nb_etoiles)


func _perdre(dehors: int) -> void:
	en_jeu = false
	_relacher_joystick()
	_sons.defaite()
	Input.vibrate_handheld(250)
	if _demo:
		print("DEMO: temps écoulé, %d moutons dehors sur %d" % [dehors, moutons.size()])
		for m in moutons:
			if not m.dans_enclos:
				print("   dehors en ", m.global_position.round())
		get_tree().quit()
		return
	_montrer_ecran("Temps écoulé !",
		"Il reste %d mouton%s dehors.\n\nAstuce : passe derrière le troupeau et avance doucement. Un chien qui fonce disperse les moutons." % [dehors, "s" if dehors > 1 else ""],
		"Réessayer", "rejouer")


func _pause() -> void:
	if not en_jeu or get_tree().paused:
		return
	_relacher_joystick()
	_montrer_ecran("Pause", "Niveau %d : %s\n%d moutons" % [_niveau_joue, _carte.nom, moutons.size()], "Reprendre", "reprendre", "Recommencer le niveau", "rejouer")


func _aboyer() -> void:
	if not en_jeu:
		return
	if chien.aboyer(moutons):
		if is_instance_valid(_loup) and _loup.global_position.distance_to(chien.global_position) < chien.PORTEE_ABOI:
			_loup.chasser()
		_sons.aboie()
		Input.vibrate_handheld(50)
		_bouton_aboi.appuye = 0.15
		_secousse = 0.55
		_effets_sol.herbe(chien.global_position, 16)
		_effets_air.texte(chien.global_position + Vector2(0, -34), "OUAF !", Color("ffb347"), 34)


func _clic(action: String) -> void:
	_sons.clic()
	match action:
		"jouer":
			_demarrer()
		"reprendre":
			_cacher_ecran()
			get_tree().paused = false
		"rejouer":
			_construire_niveau()
			_demarrer()
		"suivant":
			_construire_niveau()
			_chargement()
		"precedent":
			niveau = maxi(1, niveau - 1)
			_construire_niveau()
			_chargement()
		"niveau1":
			niveau = 1
			_sauver()
			_construire_niveau()
			_chargement()


## Petit écran de chargement (verset biblique) ; un toucher lance le niveau.
func _chargement() -> void:
	_ecran.hide()
	var e := Chargement.new(niveau, _sons)
	e.fini.connect(_demarrer)
	add_child(e)


# ---------------------------------------------------------------- éléments de jeu

## Un mouton vient de rentrer : combo si les entrées s'enchaînent, bonus du mouton d'or.
func _mouton_rentre(m: Node2D) -> void:
	_combo = _combo + 1 if _dernier_entre < 1.6 else 1
	_dernier_entre = 0.0
	var p: Vector2 = m.global_position
	if _combo >= 2:
		var couleurs := [Color("ffffff"), Color("fff3a0"), Color("ffd23f"), Color("ff9f43"), Color("ff5d7a"), Color("b388ff")]
		var c: Color = couleurs[mini(_combo / 3, couleurs.size() - 1)]
		_effets_air.texte(p + Vector2(0, -30), "x%d" % _combo, c, 24 + mini(_combo, 12) * 2, 0.8)
		if _dernier_ding > 0.07:
			_sons.ding(mini(_combo, 12))
			_dernier_ding = 0.0
		if _combo % 10 == 0:
			_effets_air.confettis(p, 25)
			_secousse = 0.3
	# agneau et maman enfin réunis dans l'enclos
	var a = m if m.agneau else m.petit
	if a != null and is_instance_valid(a) and not a.reuni and a.compte and a.mere.compte:
		a.reuni = true
		_temps_restant += 5.0
		for k in 3:
			_effets_air.coeur(a.global_position + Vector2(randf_range(-14, 14), randf_range(-10, 4)))
		_effets_air.texte(a.global_position + Vector2(0, -48), "Réunis ! +5 s", Color("ff8fb1"), 32, 1.4)
		_sons.bele_agneau()
	if m.dore:
		# le mouton d'or rapporte du temps
		_temps_restant += 15.0
		_effets_air.etincelles(p, 18, Color("ffd23f"))
		_effets_air.texte(p + Vector2(0, -60), "Mouton d'or ! +15 s", Color("ffd23f"), 34, 1.6)
		_sons.bonus()
		Input.vibrate_handheld(60)


## Une case libre de la carte, au hasard, qui respecte une condition.
func _case_au_hasard(condition: Callable) -> Variant:
	var dist: PackedInt32Array = _carte.grille_dist
	var cols: int = _carte.grille_cols
	for essai in 200:
		var k := _rng_jeu.randi() % dist.size()
		if dist[k] < 0:
			continue
		var p: Vector2 = CHAMP.position + Vector2((k % cols) + 0.5, (k / cols) + 0.5) * _carte.grille_case
		if condition.call(p):
			return p
	return null


## Os : apparaît de temps en temps ; ramassé, il donne au chien 6 secondes de turbo.
func _gerer_os(delta: float) -> void:
	# scintillement du mouton d'or (pour qu'on le repère)
	for m in moutons:
		if m.dore and not m.dans_enclos and randf() < delta * 3.0:
			_effets_air.etincelles(m.global_position + Vector2(randf_range(-8, 8), randf_range(-8, 8)), 2, Color("fff3a0"))
	if not is_instance_valid(_os):
		_prochain_os -= delta
		if _prochain_os <= 0.0:
			var p: Variant = _case_au_hasard(func(q: Vector2) -> bool:
				return q.distance_to(chien.global_position) > 220.0 and not _enclos.grow(40).has_point(q))
			if p != null:
				_os = Os.new()
				_os.position = p
				_monde.add_child(_os)
			_prochain_os = _rng_jeu.randf_range(18.0, 28.0)
	elif chien.global_position.distance_to(_os.position) < 36.0:
		chien.turbo = 6.0
		chien.recharge = 0.0
		_effets_air.etincelles(_os.position, 14, Color("ffd23f"))
		_effets_air.texte(_os.position + Vector2(0, -30), "TURBO !", Color("ffd23f"), 38, 1.2)
		_sons.bonus()
		Input.vibrate_handheld(40)
		_os.queue_free()
		_os = null


## Loup : sort d'un bord du pré, disperse le troupeau ; le chien le chasse.
func _gerer_loup(delta: float) -> void:
	if is_instance_valid(_loup):
		_loup.cible = _infos.get("dehors", _loup.global_position)
		if not _loup.en_fuite and chien.global_position.distance_to(_loup.global_position) < 58.0:
			_loup.chasser()
		_infos.loup = _loup.global_position
		_infos.loup_actif = _loup.actif()
		return
	_infos.loup_actif = false
	if not _loup_prevu or _loups_restants <= 0:
		return
	_prochain_loup -= delta
	if _prochain_loup > 0.0:
		return
	var bord := CHAMP.grow(-75.0)
	var p: Variant = _case_au_hasard(func(q: Vector2) -> bool:
		return not bord.has_point(q) and q.distance_to(chien.global_position) > 380.0 and not _enclos.grow(120).has_point(q))
	if p == null:
		_prochain_loup = 5.0
		return
	_loups_restants -= 1
	_loup = Loup.new()
	_loup.position = p
	# il s'enfuira par le bord le plus proche
	var s: Vector2 = p
	var dx := minf(p.x - CHAMP.position.x, CHAMP.end.x - p.x)
	var dy := minf(p.y - CHAMP.position.y, CHAMP.end.y - p.y)
	if dx < dy:
		s.x = CHAMP.position.x - 60.0 if p.x - CHAMP.position.x < CHAMP.end.x - p.x else CHAMP.end.x + 60.0
	else:
		s.y = CHAMP.position.y - 60.0 if p.y - CHAMP.position.y < CHAMP.end.y - p.y else CHAMP.end.y + 60.0
	_loup.sortie = s
	_loup.chasse.connect(_loup_chasse)
	_monde.add_child(_loup)
	_monde.move_child(_loup, chien.get_index())      # sous le chien, au-dessus des moutons
	_effets_air.texte(p + Vector2(0, -40), "Un loup !", Color("ff6b5b"), 40, 1.8)
	_sons.grogne()
	_secousse = 0.35
	Input.vibrate_handheld(120)


func _loup_chasse() -> void:
	_sons.glapit()
	_effets_air.texte(_loup.global_position + Vector2(0, -36), "Ouste !", Color("ffffff"), 38, 1.2)
	_effets_sol.herbe(_loup.global_position, 10)
	_prochain_loup = _rng_jeu.randf_range(20.0, 35.0)


## Le bélier vient de foncer sur le chien (approché de face)
func _belier_charge(dir: Vector2, b: Node2D) -> void:
	_sons.choc()
	_secousse = 0.7
	Input.vibrate_handheld(90)
	var p := b.global_position + dir * 22.0
	_effets_air.etincelles(p, 10, Color("ffffff"))
	_effets_sol.herbe(p, 8)
	_effets_air.texte(p + Vector2(0, -30), "BOING !", Color("ffb347"), 36, 0.9)
	if not _astuce_belier:
		_astuce_belier = true
		_effets_air.texte(b.global_position + Vector2(0, -70), "Prends-le par derrière !", Color("fff3c4"), 28, 2.2)


## Un agneau a perdu sa maman : il bêle (petit son aigu)
func _agneau_appelle(a: Node2D) -> void:
	if not en_jeu:
		return
	_sons.bele_agneau()
	_effets_air.texte(a.global_position + Vector2(0, -26), "Bêê ?", Color("ff8fb1"), 22, 0.9)


## Coups de vent (dès le niveau 6) : annoncés 1,5 s avant, ils poussent le troupeau 3 secondes.
func _gerer_vent(delta: float) -> void:
	if _vent_t > 0.0:
		_vent_t -= delta
		var k := sin(PI * clampf(1.0 - _vent_t / 3.0, 0.0, 1.0))      # monte puis retombe
		_infos.vent = _vent * 230.0 * k
		_rafale.force = k
		if _vent_t <= 0.0:
			_infos.erase("vent")
			_rafale.force = 0.0
			_prochain_vent = _rng_jeu.randf_range(18.0, 30.0)
		return
	_prochain_vent -= delta
	if _prochain_vent <= 1.5 and _rafale.annonce == Vector2.ZERO:
		# souffle de travers par rapport au chemin vers l'enclos (sinon il aiderait)
		var vers_porte: Vector2 = (_carte.porte_centre - _infos.get("dehors", CHAMP.get_center())).normalized()
		_vent = vers_porte.orthogonal() * (1.0 if _rng_jeu.randf() < 0.5 else -1.0)
		_rafale.annonce = _vent
		_effets_air.texte(CHAMP.get_center() + Vector2(0, -200), "Coup de vent !", Color("d8f3ff"), 40, 1.6)
	if _prochain_vent <= 0.0:
		_rafale.annonce = Vector2.ZERO
		_rafale.dir = _vent
		_vent_t = 3.0
		_sons.vent()


func _rebond(lbl: Control) -> void:
	lbl.pivot_offset = lbl.size / 2.0
	var t := create_tween()
	t.tween_property(lbl, "scale", Vector2(1.25, 1.25), 0.06)
	t.tween_property(lbl, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Mode démonstration (lancé avec « -- --demo ») : le chien se place derrière le mouton
## le plus éloigné de la porte et le pousse. Sert à vérifier que les niveaux sont faisables.
func _pilote_auto() -> void:
	var dehors: Array = []
	var centre := Vector2.ZERO
	for m in moutons:
		if not m.dans_enclos:
			dehors.append(m)
			centre += m.global_position
	if dehors.is_empty():
		chien.direction = Vector2.ZERO
		return
	centre /= dehors.size()
	var etendue0 := 0.0
	for m in dehors:
		etendue0 = maxf(etendue0, m.global_position.distance_to(centre))
	# Troupeau éparpillé : on va d'abord chercher le retardataire (le plus loin de l'entrée)
	if etendue0 > 170.0:
		var pire := -1
		for m in dehors:
			var d := _distance_chemin(m.global_position)
			if d > pire:
				pire = d
				centre = m.global_position
	var porte := _point_suivant(centre)
	# On pousse le troupeau vers la porte, par l'arrière ; si le chien est du mauvais côté,
	# il contourne le troupeau par le flanc.
	var etendue := 0.0
	for m in dehors:
		etendue = maxf(etendue, m.global_position.distance_to(centre))
	etendue = minf(etendue, 220.0)
	var dir := (centre - porte).normalized()
	var cible := centre + dir * minf(etendue + 25.0, 130.0)
	var vers_chien := chien.global_position - centre
	if vers_chien.dot(dir) < 0.0:
		var flanc := dir.orthogonal() * signf(vers_chien.dot(dir.orthogonal()) + 0.01)
		cible = centre + flanc * (etendue + 90.0)
	cible = cible.clamp(CHAMP.position + Vector2(20, 20), CHAMP.end - Vector2(20, 20))
	# si ce point tombe dans l'eau ou un obstacle, on le rapproche du troupeau jusqu'à une case libre
	for essai in 40:
		if _case_libre(cible):
			break
		cible = cible.move_toward(centre, 8.0)
	var etape := _etape_vers(cible)
	chien.direction = ((etape - chien.global_position) / 70.0).limit_length(1.0)
	# montre le joystick comme si un joueur le tenait (captures d'écran)
	_joystick.actif = true
	_joystick.centre = Vector2(190, get_viewport().get_visible_rect().size.y - 260)
	_joystick.bouton = _joystick.bouton.lerp(chien.direction * _joystick.rayon, 0.2)
	_joystick.queue_redraw()


## Pilote automatique : prochain point pour que le chien aille vers « cible » en contournant
## rivière, étangs et haies (recherche de chemin sur la grille de la carte, refaite 3 fois par seconde).
var _nav_dist := PackedInt32Array()
var _nav_temps := 0.0

func _etape_vers(cible: Vector2) -> Vector2:
	var libre: PackedInt32Array = _carte.grille_dist        # -1 = case bloquée
	var cols: int = _carte.grille_cols
	var taille: float = _carte.grille_case
	var lignes := libre.size() / cols
	var case_de := func(p: Vector2) -> int:
		var i := clampi(int((p.x - CHAMP.position.x) / taille), 0, cols - 1)
		var j := clampi(int((p.y - CHAMP.position.y) / taille), 0, lignes - 1)
		return j * cols + i
	_nav_temps -= get_process_delta_time()
	if _nav_temps <= 0.0 or _nav_dist.size() != libre.size():
		_nav_temps = 0.33
		var depart: int = case_de.call(cible)
		if libre[depart] < 0:
			var meilleur := -1
			var md := INF
			for k in libre.size():
				if libre[k] >= 0:
					var d := (CHAMP.position + Vector2((k % cols) + 0.5, (k / cols) + 0.5) * taille).distance_squared_to(cible)
					if d < md:
						md = d
						meilleur = k
			depart = meilleur
		_nav_dist.resize(libre.size())
		_nav_dist.fill(-1)
		_nav_dist[depart] = 0
		var file: Array[int] = [depart]
		var tete := 0
		while tete < file.size():
			var k := file[tete]
			tete += 1
			for v in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni: int = k % cols + v.x
				var nj: int = k / cols + v.y
				if ni < 0 or nj < 0 or ni >= cols or nj >= lignes:
					continue
				var nk := nj * cols + ni
				if libre[nk] >= 0 and _nav_dist[nk] < 0:
					_nav_dist[nk] = _nav_dist[k] + 1
					file.append(nk)
	var k: int = case_de.call(chien.global_position)
	if _nav_dist[k] < 0:
		# le chien frôle un obstacle : on part de la case libre la plus proche
		var ci := k % cols
		var cj := k / cols
		var trouve := -1
		for r in range(1, 5):
			for dj in range(-r, r + 1):
				for di in range(-r, r + 1):
					var ni := ci + di
					var nj := cj + dj
					if ni >= 0 and nj >= 0 and ni < cols and nj < lignes and _nav_dist[nj * cols + ni] >= 0:
						if trouve < 0 or _nav_dist[nj * cols + ni] < _nav_dist[trouve]:
							trouve = nj * cols + ni
			if trouve >= 0:
				break
		if trouve < 0:
			return cible
		return CHAMP.position + Vector2((trouve % cols) + 0.5, (trouve / cols) + 0.5) * taille
	for pas in 4:
		var suivant := k
		for v in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var ni: int = k % cols + v.x
			var nj: int = k / cols + v.y
			if ni < 0 or nj < 0 or ni >= cols or nj >= lignes:
				continue
			var nk := nj * cols + ni
			if _nav_dist[nk] >= 0 and _nav_dist[nk] < _nav_dist[suivant]:
				suivant = nk
		k = suivant
	if _nav_dist[k] <= 1:
		return cible
	return CHAMP.position + Vector2((k % cols) + 0.5, (k / cols) + 0.5) * taille


func _case_libre(p: Vector2) -> bool:
	var cols: int = _carte.grille_cols
	var dist: PackedInt32Array = _carte.grille_dist
	var i := int((p.x - CHAMP.position.x) / _carte.grille_case)
	var j := int((p.y - CHAMP.position.y) / _carte.grille_case)
	if i < 0 or j < 0 or i >= cols or j * cols + i >= dist.size():
		return false
	return dist[j * cols + i] >= 0


## Distance (en cases) jusqu'à l'entrée, en suivant les passages.
func _distance_chemin(p: Vector2) -> int:
	var cols: int = _carte.grille_cols
	var dist: PackedInt32Array = _carte.grille_dist
	var i := int((p.x - CHAMP.position.x) / _carte.grille_case)
	var j := int((p.y - CHAMP.position.y) / _carte.grille_case)
	var k := j * cols + i
	if i < 0 or j < 0 or i >= cols or k >= dist.size():
		return 0
	return maxi(dist[k], 0)


## Prochain point du chemin vers l'entrée (suit la grille des distances de la carte :
## contourne la rivière par un pont, les haies, les étangs...).
func _point_suivant(p: Vector2) -> Vector2:
	var fin: Vector2 = _carte.porte_centre + _carte.dedans * 50.0
	var dist: PackedInt32Array = _carte.grille_dist
	var cols: int = _carte.grille_cols
	var taille: float = _carte.grille_case
	var lignes := dist.size() / cols
	var i := int((p.x - CHAMP.position.x) / taille)
	var j := int((p.y - CHAMP.position.y) / taille)
	if i < 0 or j < 0 or i >= cols or j >= lignes:
		return fin
	var k := j * cols + i
	if dist[k] < 0:
		# case bloquée : on cherche la plus proche case libre autour
		var meilleur := -1
		for r in range(1, 6):
			for dj in range(-r, r + 1):
				for di in range(-r, r + 1):
					var ni := i + di
					var nj := j + dj
					if ni >= 0 and nj >= 0 and ni < cols and nj < lignes and dist[nj * cols + ni] >= 0:
						meilleur = nj * cols + ni
			if meilleur >= 0:
				break
		if meilleur < 0:
			return fin
		k = meilleur
	for pas in 26:
		if dist[k] <= 0:
			return fin
		var ci := k % cols
		var cj := k / cols
		var suivant := k
		for v in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var ni: int = ci + v.x
			var nj: int = cj + v.y
			if ni >= 0 and nj >= 0 and ni < cols and nj < lignes:
				var nk := nj * cols + ni
				if dist[nk] >= 0 and dist[nk] < dist[suivant]:
					suivant = nk
		if suivant == k:
			break
		k = suivant
	return CHAMP.position + Vector2((k % cols) + 0.5, (k / cols) + 0.5) * taille


# ---------------------------------------------------------------- commandes

func _sur(bouton: Control, p: Vector2) -> bool:
	if not bouton.visible:
		return false
	var r := bouton.get_global_rect()
	return p.distance_to(r.get_center()) < r.size.x * 0.55


## Les boutons du jeu sont gérés ici, au toucher : on peut diriger le chien
## avec un doigt et aboyer avec un autre en même temps.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		if _sur(_bouton_aboi, event.position):
			_aboyer()
			get_viewport().set_input_as_handled()
		elif _sur(_bouton_pause, event.position):
			_sons.clic()
			_pause()
			get_viewport().set_input_as_handled()
		elif _sur(_bouton_musique, event.position):
			_sons.clic()
			_bouton_musique.barre = not _sons.basculer_musique()
			_bouton_musique.queue_redraw()
			_ecrire_reglage("musique", _sons.musique_active)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_aboyer()
		elif event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
			_pause()


## Joystick flottant : il apparaît là où le doigt se pose et suit le doigt s'il va trop loin.
func _unhandled_input(event: InputEvent) -> void:
	if not en_jeu or chien == null:
		return
	if event is InputEventScreenTouch:
		if event.pressed and _doigt == -1:
			_doigt = event.index
			_joystick.actif = true
			_joystick.aide = false
			_joystick.centre = event.position
			_joystick.bouton = Vector2.ZERO
			chien.direction = Vector2.ZERO
			_joystick.queue_redraw()
		elif not event.pressed and event.index == _doigt:
			_relacher_joystick()
	elif event is InputEventScreenDrag and event.index == _doigt:
		var o: Vector2 = event.position - _joystick.centre
		var r := _joystick.rayon
		if o.length() > r:
			_joystick.centre += o - o.normalized() * r      # la base suit le doigt
			o = o.normalized() * r
		_joystick.bouton = o
		var force := o.length() / r
		# zone morte puis courbe douce : un petit geste = un petit pas, pleine vitesse seulement au bord
		chien.direction = Vector2.ZERO if force < 0.15 else o.normalized() * pow((force - 0.15) / 0.85, 1.7)
		_joystick.queue_redraw()


func _relacher_joystick() -> void:
	_doigt = -1
	if chien:
		chien.direction = Vector2.ZERO
	if _joystick:
		_joystick.actif = false
		_joystick.queue_redraw()


func _notification(what: int) -> void:
	# Bouton « retour » d'Android ou appli mise en arrière-plan : on met en pause
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if en_jeu:
			_pause()


# ---------------------------------------------------------------- dessin du décor

func _draw() -> void:
	draw_rect(Rect2(-2000, -2000, 4720, 5280), Color("4a8237"))
	# arbres hors de la prairie (bords visibles sur les écrans allongés)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in 40:
		var p := Vector2(rng.randf_range(-300, 1020), rng.randf_range(-400, 1700))
		if CHAMP.grow(40).has_point(p):
			continue
		draw_circle(p + Vector2(6, 10), 40, Color(0, 0, 0, 0.18))
		draw_circle(p, 40, Color("2f6a2a"))
		draw_circle(p + Vector2(-10, -12), 26, Color("3f8236"))

	draw_rect(CHAMP, Color("7cbf55"))
	rng.seed = _graine
	# grandes taches d'herbe plus sombres ou plus claires
	for i in 16:
		var p := Vector2(rng.randf_range(CHAMP.position.x, CHAMP.end.x), rng.randf_range(CHAMP.position.y, CHAMP.end.y))
		var c := Color(0.0, 0.12, 0.0, 0.07) if i % 2 == 0 else Color(1.0, 1.0, 0.6, 0.07)
		var r := rng.randf_range(50, 110)
		draw_circle(p, r, c)
		draw_circle(p + Vector2(r * 0.5, r * 0.2), r * 0.7, c)
	for i in int(CHAMP.size.y / 80.0) + 1:
		var y := CHAMP.position.y + i * 80.0
		draw_rect(Rect2(CHAMP.position.x, y, CHAMP.size.x, minf(40.0, CHAMP.end.y - y)), Color(1, 1, 1, 0.04))

	if _carte.is_empty():
		return
	var e := _enclos
	var dedans: Vector2 = _carte.dedans

	# Chemin de terre battue : le trajet du troupeau jusqu'à l'entrée
	var chemin: PackedVector2Array = _carte.chemin
	for pas in 2:
		var couleur := Color("a3a35f") if pas == 0 else Color("b9b277")
		var largeur := 32.0 if pas == 0 else 24.0
		var reste := 0.0
		for i in chemin.size() - 1:
			var a := chemin[i]
			var b := chemin[i + 1]
			var l := a.distance_to(b)
			var t := reste
			while t < l:
				var p := a.lerp(b, t / l)
				draw_circle(p, largeur + sin(p.x * 0.05 + p.y * 0.03) * 3.0, couleur)
				t += 9.0
			reste = t - l

	# Herbes et fleurs (pas sur les obstacles)
	var couleurs := [Color("ffffff"), Color("ffe066"), Color("f7a1c4"), Color("b8d8ff")]
	for i in 170:
		var p := Vector2(rng.randf_range(CHAMP.position.x + 10, CHAMP.end.x - 10), rng.randf_range(CHAMP.position.y + 10, CHAMP.end.y - 10))
		if _sur_obstacle(p, 8.0):
			continue
		if i % 3 != 0:
			var herbe := Color("5f9e43") if i % 2 == 0 else Color("6aab4b")
			draw_line(p, p + Vector2(-3, -7), herbe, 2.0)
			draw_line(p, p + Vector2(0, -9), herbe, 2.0)
			draw_line(p, p + Vector2(3, -7), herbe, 2.0)
		else:
			for k in 5:
				draw_circle(p + Vector2.from_angle(TAU * k / 5.0) * 3.0, 2.4, couleurs[i % couleurs.size()])
			draw_circle(p, 1.8, Color("f4c542"))

	# Rivière, puis ses ponts
	if not _carte.riviere.is_empty():
		var pts: PackedVector2Array = _carte.riviere.points
		for p in pts:
			draw_circle(p, 31.0, Color("6f8f4a"))           # berge
		for p in pts:
			draw_circle(p, 25.0, Color("3f8fc9"))           # eau
		for p in pts:
			draw_circle(p + Vector2(0, -4), 13.0, Color("5aa9dd"))
		var t_eau := float(_graine % 100)
		for i in range(0, pts.size(), 2):
			var p := pts[i] + Vector2(sin(i * 1.7 + t_eau) * 8.0, sin(i * 2.3) * 8.0)
			draw_line(p, p + Vector2(12, 0), Color(1, 1, 1, 0.45), 2.0)
		for px in _carte.riviere.ponts:
			var py := _hauteur_riviere(px)
			var pont := Rect2(px - 70, py - 40, 140, 80)
			draw_rect(Rect2(pont.position + Vector2(4, 7), pont.size), Color(0, 0, 0, 0.25))
			draw_rect(pont, Color("9a6a3a"))
			for k in 8:
				var y := pont.position.y + 5 + k * 10
				draw_line(Vector2(pont.position.x, y), Vector2(pont.end.x, y), Color("7a4f28"), 2.0)
			draw_rect(Rect2(pont.position + Vector2(0, 2), Vector2(pont.size.x, 3)), Color(1, 1, 1, 0.1))
			_barriere(Vector2(pont.position.x, pont.position.y - 4), Vector2(pont.position.x, pont.end.y + 4))
			_barriere(Vector2(pont.end.x, pont.position.y - 4), Vector2(pont.end.x, pont.end.y + 4))

	# Étangs avec leurs roseaux
	for etang in _carte.etangs:
		for b in etang:
			draw_circle(Vector2(b.x, b.y), b.z + 7.0, Color("6f8f4a"))
		for b in etang:
			draw_circle(Vector2(b.x, b.y), b.z, Color("3f8fc9"))
		for b in etang:
			draw_circle(Vector2(b.x - b.z * 0.2, b.y - b.z * 0.25), b.z * 0.55, Color("5aa9dd"))
		for b in etang:
			for k in 4:
				var a := rng.randf() * TAU
				var p: Vector2 = Vector2(b.x, b.y) + Vector2.from_angle(a) * (b.z + 4.0)
				if not _dans_eau(p, etang):
					draw_line(p, p + Vector2(-2, -14), Color("4f7a2a"), 2.5)
					draw_line(p + Vector2(3, 0), p + Vector2(5, -11), Color("5f8f34"), 2.5)
					draw_circle(p + Vector2(-2, -14), 2.5, Color("7a5230"))
			if rng.randf() < 0.5:
				var p: Vector2 = Vector2(b.x + rng.randf_range(-b.z, b.z) * 0.4, b.y + rng.randf_range(-b.z, b.z) * 0.4)
				draw_circle(p, 7.0, Color("4f9a3a"))           # nénuphar
				draw_circle(p + Vector2(2, -1), 2.5, Color("f7a1c4"))

	# Sol de paille dans l'enclos, avec une ombre le long du fond
	draw_rect(e, Color("dcbc6e"))
	var fond := Rect2()
	match _carte.cote:
		"haut":
			fond = Rect2(e.position, Vector2(e.size.x, 18))
		"gauche":
			fond = Rect2(e.position, Vector2(18, e.size.y))
		_:
			fond = Rect2(Vector2(e.end.x - 18, e.position.y), Vector2(18, e.size.y))
	draw_rect(fond, Color(0, 0, 0, 0.08))
	for i in int(e.get_area() / 1500.0):
		var p := Vector2(rng.randf_range(e.position.x + 8, e.end.x - 8), rng.randf_range(e.position.y + 8, e.end.y - 8))
		draw_line(p, p + Vector2.from_angle(rng.randf() * TAU) * 11.0, Color("c29a4a") if i % 2 else Color("ecd28a"), 2.0)
	# abreuvoir contre le fond, dans un coin
	var ab: Rect2
	match _carte.cote:
		"haut":
			ab = Rect2(e.end.x - 70, e.position.y + 14, 52, 24)
		"gauche":
			ab = Rect2(e.position.x + 14, e.position.y + 18, 24, 52)
		_:
			ab = Rect2(e.end.x - 38, e.position.y + 18, 24, 52)
	draw_rect(ab.grow(3), Color("6b4a2a"))
	draw_rect(ab, Color("5fb7e8"))
	draw_rect(Rect2(ab.position + Vector2(4, 3), Vector2(minf(20, ab.size.x - 8), 4)), Color(1, 1, 1, 0.5))

	# Bosquets
	for f in _carte.forets:
		draw_colored_polygon(f, Color("3d7a2f"))
	var rf := RandomNumberGenerator.new()
	rf.seed = _graine + 7
	for i in 220:
		var p := Vector2(rf.randf_range(CHAMP.position.x, CHAMP.end.x), rf.randf_range(CHAMP.position.y, CHAMP.end.y))
		if not _en_foret(p):
			continue
		var r := rf.randf_range(16, 30)
		draw_circle(p + Vector2(4, 8), r, Color(0, 0, 0, 0.2))
		draw_circle(p, r, Color("2c6526"))
		draw_circle(p + Vector2(-r * 0.25, -r * 0.3), r * 0.6, Color("3f8a36"))
		draw_circle(p + Vector2(-r * 0.35, -r * 0.4), r * 0.25, Color("5aa84a"))

	# Haies : une rangée de buissons
	for h in _carte.haies:
		var a: Vector2 = h[0]
		var b: Vector2 = h[1]
		var l := a.distance_to(b)
		var nb := int(l / 15.0)
		for k in nb + 1:
			var p := a.lerp(b, float(k) / nb)
			draw_circle(p + Vector2(4, 8), 18.0, Color(0, 0, 0, 0.18))
		for k in nb + 1:
			var p := a.lerp(b, float(k) / nb) + Vector2(0, sin(k * 2.1) * 2.0)
			draw_circle(p, 17.0 + sin(k * 1.3) * 2.0, Color("2f6e2a"))
		for k in nb + 1:
			var p := a.lerp(b, float(k) / nb)
			draw_circle(p + Vector2(-4, -5), 8.0, Color("4c9640"))
			if k % 4 == 1:
				draw_circle(p + Vector2(5, 2), 2.5, Color("f2f2f2"))     # petites fleurs blanches

	# Flèches au sol devant l'entrée
	if not _gagne:
		var pc: Vector2 = _carte.porte_centre
		var cote := dedans.orthogonal()
		for k in 2:
			var base := pc - dedans * (40.0 + k * 30.0)
			draw_colored_polygon(PackedVector2Array([base + dedans * 14.0, base - dedans * 10.0 + cote * 24.0, base - dedans * 10.0 - cote * 24.0]), Color(1, 1, 1, 0.35 - k * 0.14))

	# Barrières de la prairie, de l'enclos et des bosquets
	var c := CHAMP
	_barriere(c.position, Vector2(c.end.x, c.position.y))
	_barriere(Vector2(c.position.x, c.end.y), c.end)
	_barriere(c.position, Vector2(c.position.x, c.end.y))
	_barriere(Vector2(c.end.x, c.position.y), c.end)
	for m in _carte.murs:
		_barriere(m[0], m[1])
	for m in _carte.biais:
		_barriere(m[0], m[1])
	if _gagne:
		_barriere(_carte.porte[0], _carte.porte[1], Color("c0392b"))


func _hauteur_riviere(x: float) -> float:
	var pts: PackedVector2Array = _carte.riviere.points
	for i in pts.size() - 1:
		if x >= pts[i].x and x <= pts[i + 1].x:
			return lerpf(pts[i].y, pts[i + 1].y, (x - pts[i].x) / (pts[i + 1].x - pts[i].x))
	return pts[0].y


func _dans_eau(p: Vector2, etang: Array) -> bool:
	for b in etang:
		if p.distance_to(Vector2(b.x, b.y)) < b.z:
			return true
	return false

func _barriere(a: Vector2, b: Vector2, bois := Color("a87440")) -> void:
	var sombre := Color("5e3b1a")
	var l := a.distance_to(b)
	if l < 1.0:
		return
	var n := (b - a) / l
	draw_line(a + Vector2(3, 6), b + Vector2(3, 6), Color(0, 0, 0, 0.22), 11.0)
	draw_line(a, b, sombre, 10.0)
	draw_line(a, b, bois, 5.0)
	draw_line(a - Vector2(0, 1.5), b - Vector2(0, 1.5), bois.lightened(0.25), 1.5)
	var nb := maxi(1, int(l / 48.0))
	for i in nb + 1:
		var p := a + n * (l * i / nb)
		draw_circle(p + Vector2(2, 4), 7.5, Color(0, 0, 0, 0.2))
		draw_circle(p, 7.5, sombre)
		draw_circle(p, 5.0, bois.lightened(0.15))
		draw_circle(p + Vector2(-1.5, -1.5), 2.0, bois.lightened(0.4))


# ---------------------------------------------------------------- interface

func _creer_interface() -> void:
	var calque := CanvasLayer.new()
	calque.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(calque)
	var racine := Control.new()
	racine.set_anchors_preset(Control.PRESET_FULL_RECT)
	racine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	calque.add_child(racine)

	# Vignette : bords de l'écran légèrement assombris
	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv * vec2(1.0, 0.7));
	COLOR = vec4(0.03, 0.07, 0.02, smoothstep(0.32, 0.72, d) * 0.55);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	vignette.material = mat
	racine.add_child(vignette)

	_joystick = Joystick.new()
	racine.add_child(_joystick)

	var haut := _marge_haut()
	var bande := ColorRect.new()
	bande.color = Color(0.08, 0.16, 0.06, 0.55)
	bande.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bande.offset_bottom = haut + 104
	bande.mouse_filter = Control.MOUSE_FILTER_IGNORE
	racine.add_child(bande)

	var ligne := HBoxContainer.new()
	ligne.set_anchors_preset(Control.PRESET_TOP_WIDE)
	ligne.offset_left = 24
	ligne.offset_right = -120
	ligne.offset_top = haut + 12
	ligne.offset_bottom = haut + 78
	ligne.mouse_filter = Control.MOUSE_FILTER_IGNORE
	racine.add_child(ligne)
	_lbl_niveau = _etiquette(30)
	_lbl_moutons = _etiquette(34)
	_lbl_temps = _etiquette(30)
	_lbl_moutons.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_temps.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for lbl in [_lbl_niveau, _lbl_moutons, _lbl_temps]:
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ligne.add_child(lbl)

	# Barre de progression du troupeau rentré
	var fond := ColorRect.new()
	fond.color = Color(0, 0, 0, 0.35)
	fond.set_anchors_preset(Control.PRESET_TOP_WIDE)
	fond.offset_left = 24
	fond.offset_right = -24
	fond.offset_top = haut + 84
	fond.offset_bottom = haut + 94
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	racine.add_child(fond)
	_barre = ColorRect.new()
	_barre.color = Color("9be36d")
	_barre.anchor_left = 0.0
	_barre.anchor_top = 0.0
	_barre.anchor_bottom = 1.0
	_barre.anchor_right = 0.0
	_barre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fond.add_child(_barre)

	_bouton_pause = BoutonRond.new()
	_bouton_pause.texte = "II"
	_bouton_pause.couleur = Color("3d6b2b")
	_bouton_pause.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_bouton_pause.offset_left = -96
	_bouton_pause.offset_right = -24
	_bouton_pause.offset_top = haut + 6
	_bouton_pause.offset_bottom = haut + 78
	racine.add_child(_bouton_pause)
	_bouton_musique = BoutonRond.new()
	_bouton_musique.note = true
	_bouton_musique.couleur = Color("3d6b2b")
	_bouton_musique.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_bouton_musique.offset_left = -84
	_bouton_musique.offset_right = -36
	_bouton_musique.offset_top = haut + 92
	_bouton_musique.offset_bottom = haut + 140
	racine.add_child(_bouton_musique)

	_bouton_aboi = BoutonRond.new()
	_bouton_aboi.texte = "OUAF !"
	_bouton_aboi.couleur = Color("e67e22")
	_bouton_aboi.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_bouton_aboi.offset_left = -200
	_bouton_aboi.offset_right = -36
	_bouton_aboi.offset_top = -210
	_bouton_aboi.offset_bottom = -46
	racine.add_child(_bouton_aboi)

	# Écran superposé : accueil, victoire, défaite, pause
	_ecran = ColorRect.new()
	(_ecran as ColorRect).color = Color(0, 0, 0, 0.55)
	_ecran.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ecran.mouse_filter = Control.MOUSE_FILTER_STOP
	racine.add_child(_ecran)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ecran.add_child(centre)
	var panneau := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fbf6e9")
	style.set_corner_radius_all(32)
	style.set_content_margin_all(36)
	style.border_color = Color("5e3b1a")
	style.set_border_width_all(6)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 8)
	panneau.add_theme_stylebox_override("panel", style)
	centre.add_child(panneau)
	var boite := VBoxContainer.new()
	boite.add_theme_constant_override("separation", 22)
	panneau.add_child(boite)
	_ecran_titre = Label.new()
	_ecran_titre.add_theme_font_size_override("font_size", 58)
	_ecran_titre.add_theme_color_override("font_color", Color("3d6b2b"))
	_ecran_titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boite.add_child(_ecran_titre)
	_ecran_texte = Label.new()
	_ecran_texte.add_theme_font_size_override("font_size", 28)
	_ecran_texte.add_theme_color_override("font_color", Color("3b2f24"))
	_ecran_texte.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ecran_texte.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ecran_texte.custom_minimum_size = Vector2(540, 0)
	boite.add_child(_ecran_texte)
	_etoiles = Etoiles.new()
	_etoiles.son = func(i: int) -> void: _sons.ding(4 + i * 4)
	boite.add_child(_etoiles)
	_ecran_b1 = _bouton(Color("4f9a35"))
	_ecran_b2 = _bouton(Color("8a7a66"))
	boite.add_child(_ecran_b1)
	boite.add_child(_ecran_b2)
	_ecran_b1.pressed.connect(func() -> void: _clic(_action1))
	_ecran_b2.pressed.connect(func() -> void: _clic(_action2))
	_ecran.hide()


## Une mise à jour vient d'être téléchargée : bandeau discret (elle s'appliquera au prochain lancement).
func _maj_prete(v: String) -> void:
	var calque := CanvasLayer.new()
	calque.layer = 50
	calque.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(calque)
	var fond := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.2, 0.08, 0.92)
	style.set_corner_radius_all(24)
	style.set_content_margin_all(18)
	fond.add_theme_stylebox_override("panel", style)
	fond.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	fond.offset_left = -330
	fond.offset_right = 330
	fond.offset_top = -330
	fond.offset_bottom = -240
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	calque.add_child(fond)
	var l := _etiquette(26)
	l.text = "Nouvelle version %s téléchargée !\nFerme et relance le jeu pour l'avoir." % v
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fond.add_child(l)
	get_tree().create_timer(10.0, true).timeout.connect(calque.queue_free)


func _etiquette(taille: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", taille)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.18, 0.06))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bouton(couleur: Color) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 96)
	b.add_theme_font_size_override("font_size", 34)
	for etat in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = couleur.darkened(0.2) if etat == "pressed" else couleur
		s.set_corner_radius_all(48)
		s.set_content_margin_all(16)
		if etat != "pressed":
			s.shadow_color = couleur.darkened(0.45)
			s.shadow_offset = Vector2(0, 6)
		if etat == "focus":
			s.draw_center = false
			s.shadow_size = 0
			s.shadow_color = Color.TRANSPARENT
		b.add_theme_stylebox_override(etat, s)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	return b


## Hauteur réservée en haut de l'écran (encoche / caméra des téléphones).
func _marge_haut() -> float:
	var ecran := DisplayServer.screen_get_size()
	if ecran.y <= 0 or not OS.has_feature("mobile"):
		return 0.0
	var sur := DisplayServer.get_display_safe_area()
	var hauteur_vue := get_viewport().get_visible_rect().size.y
	return clampf(float(sur.position.y) / ecran.y * hauteur_vue, 0.0, 120.0)


func _montrer_ecran(titre: String, texte: String, b1: String, a1: String, b2 := "", a2 := "") -> void:
	_ecran_titre.text = titre
	_ecran_texte.text = texte
	_ecran_b1.text = b1
	_action1 = a1
	_ecran_b2.text = b2
	_action2 = a2
	_ecran_b2.visible = b2 != ""
	_etoiles.visible = false
	_ecran.show()
	_bouton_aboi.hide()
	_bouton_pause.hide()
	_bouton_musique.hide()
	_joystick.hide()
	get_tree().paused = true
	# petite apparition en douceur
	_ecran.modulate.a = 0.0
	# le fondu est rattaché à l'écran lui-même, qui continue de vivre pendant la pause
	_ecran.create_tween().tween_property(_ecran, "modulate:a", 1.0, 0.25)


func _cacher_ecran() -> void:
	_ecran.hide()
	_bouton_aboi.show()
	_bouton_pause.show()
	_bouton_musique.show()
	_bouton_musique.barre = not _sons.musique_active
	_joystick.show()


func _maj_hud(dedans: int) -> void:
	_lbl_niveau.text = "Niveau %d" % _niveau_joue
	_lbl_moutons.text = "%d / %d" % [dedans, moutons.size()]
	_lbl_temps.text = _format_temps(maxf(_temps_restant, 0.0))
	_lbl_temps.add_theme_color_override("font_color", Color("ff6b5b") if _temps_restant < 15.0 else Color.WHITE)


func _format_temps(t: float) -> String:
	var s := int(ceil(t))
	return "%d:%02d" % [s / 60, s % 60]


# ---------------------------------------------------------------- sauvegarde

func _charger() -> int:
	var c := ConfigFile.new()
	if c.load(FICHIER) == OK:
		return maxi(1, int(c.get_value("jeu", "niveau", 1)))
	return 1


func _sauver() -> void:
	var c := ConfigFile.new()
	c.load(FICHIER)
	c.set_value("jeu", "niveau", niveau)
	c.save(FICHIER)


func _lire_reglage(cle: String, defaut: Variant) -> Variant:
	var c := ConfigFile.new()
	c.load(FICHIER)
	return c.get_value("reglages", cle, defaut)


func _ecrire_reglage(cle: String, valeur: Variant) -> void:
	var c := ConfigFile.new()
	c.load(FICHIER)
	c.set_value("reglages", cle, valeur)
	c.save(FICHIER)


# ---------------------------------------------------------------- petits objets du décor

## Rocher ou buisson : obstacle fixe.
class Rocher extends StaticBody2D:
	var rayon := 30.0
	var buisson := false

	func _ready() -> void:
		var forme := CollisionShape2D.new()
		var cercle := CircleShape2D.new()
		cercle.radius = rayon
		forme.shape = cercle
		add_child(forme)

	func _draw() -> void:
		draw_circle(Vector2(5, 9), rayon, Color(0, 0, 0, 0.22))
		if buisson:
			var vert := Color("3f7d2c")
			for i in 6:
				draw_circle(Vector2.from_angle(TAU * i / 6.0) * rayon * 0.45, rayon * 0.6, vert)
			draw_circle(Vector2(-rayon * 0.2, -rayon * 0.25), rayon * 0.5, Color("57a03d"))
			draw_circle(Vector2(-rayon * 0.35, -rayon * 0.4), rayon * 0.22, Color("74bb55"))
			for i in 5:
				draw_circle(Vector2.from_angle(1.0 + i * 1.3) * rayon * 0.55, 3.0, Color("d94a4a"))
		else:
			draw_circle(Vector2.ZERO, rayon, Color("77797e"))
			draw_circle(Vector2(-rayon * 0.12, -rayon * 0.15), rayon * 0.85, Color("8d8f94"))
			draw_circle(Vector2(-rayon * 0.28, -rayon * 0.32), rayon * 0.5, Color("a9abb0"))
			draw_circle(Vector2(rayon * 0.35, rayon * 0.35), rayon * 0.2, Color("6d6f74"))
			draw_circle(Vector2(rayon * 0.2, -rayon * 0.5), rayon * 0.16, Color("6e9e4a"))   # mousse


## Botte de foin : un objet physique lourd que le chien et les moutons peuvent pousser.
class Foin extends RigidBody2D:
	const COTE := 46.0

	func _ready() -> void:
		gravity_scale = 0.0
		mass = 4.0
		linear_damp = 5.0
		angular_damp = 5.0
		var forme := CollisionShape2D.new()
		var boite := RectangleShape2D.new()
		boite.size = Vector2(COTE, COTE)
		forme.shape = boite
		add_child(forme)

	func _draw() -> void:
		var r := Rect2(-COTE / 2.0, -COTE / 2.0, COTE, COTE)
		draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
		draw_circle(Vector2(5, 8), COTE * 0.62, Color(0, 0, 0, 0.2))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(r, Color("e2bf5a"))
		for i in 5:
			var y := r.position.y + 6 + i * 9
			draw_line(Vector2(r.position.x + 4, y), Vector2(r.end.x - 4, y + 2), Color("c49a35"), 2.0)
		draw_line(Vector2(-8, r.position.y), Vector2(-8, r.end.y), Color("8a5a2b"), 3.0)
		draw_line(Vector2(8, r.position.y), Vector2(8, r.end.y), Color("8a5a2b"), 3.0)
		draw_rect(r, Color("a88a3a"), false, 2.0)

	func _physics_process(_d: float) -> void:
		if linear_velocity.length() > 1.0 or absf(angular_velocity) > 0.01:
			queue_redraw()


## Ombres de nuages qui glissent lentement sur la prairie.
class Nuages extends Node2D:
	func _ready() -> void:
		for i in 4:
			var n := Nuage.new()
			n.position = Vector2(randf_range(-250, 900), randf_range(150, 1250))
			add_child(n)

	func _process(delta: float) -> void:
		for n in get_children():
			n.position.x += n.vitesse * delta
			if n.position.x > 1000:
				n.position = Vector2(-300, randf_range(150, 1250))


## Un nuage : dessiné une fois, puis seulement déplacé.
class Nuage extends Node2D:
	var vitesse := randf_range(10, 22)

	func _draw() -> void:
		var w := randf_range(120, 220)
		for i in randi_range(5, 8):
			draw_circle(Vector2(randf_range(-w / 2, w / 2), randf_range(-35, 35)), randf_range(40, 75), Color(0.02, 0.1, 0.02, 0.06))


## Joystick tactile flottant (dessin seulement ; le toucher est géré par main.gd).
class Joystick extends Control:
	var actif := false
	var aide := false
	var centre := Vector2.ZERO
	var bouton := Vector2.ZERO
	var rayon := 125.0
	var _t := 0.0

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		if aide and not actif:
			queue_redraw()

	func _draw() -> void:
		if actif:
			_dessiner(centre, bouton, 1.0)
		elif aide:
			# démonstration animée tant que le joueur n'a pas touché l'écran
			var c := Vector2(size.x / 2.0, size.y - 330)
			var b := Vector2(sin(_t * 2.2) * rayon * 0.7, cos(_t * 1.6) * rayon * 0.35)
			_dessiner(c, b, 0.55 + 0.2 * sin(_t * 4.0))
			var police := ThemeDB.fallback_font
			var txt := "Pose ton doigt et glisse"
			var w := police.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
			var p := Vector2(c.x - w / 2.0, c.y + rayon + 50)
			draw_string_outline(police, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 8, Color(0.1, 0.18, 0.06, 0.8))
			draw_string(police, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)

	func _dessiner(c: Vector2, b: Vector2, a: float) -> void:
		draw_circle(c, rayon, Color(0, 0, 0, 0.18 * a))
		draw_arc(c, rayon, 0.0, TAU, 64, Color(1, 1, 1, 0.55 * a), 5.0)
		# petites flèches sur le pourtour
		for i in 4:
			var d := Vector2.from_angle(TAU * i / 4.0)
			var p := c + d * (rayon - 18)
			draw_colored_polygon(PackedVector2Array([p + d * 8, p - d * 4 + d.orthogonal() * 8, p - d * 4 - d.orthogonal() * 8]), Color(1, 1, 1, 0.4 * a))
		if b.length() > 4:
			draw_line(c, c + b, Color(1, 1, 1, 0.25 * a), 14.0)
		draw_circle(c + b + Vector2(0, 5), 44, Color(0, 0, 0, 0.25 * a))
		draw_circle(c + b, 44, Color(1, 1, 1, 0.8 * a))
		draw_circle(c + b, 34, Color(0.95, 0.95, 0.9, 0.9 * a))
		draw_circle(c + b + Vector2(-10, -12), 10, Color(1, 1, 1, a))


## Os à ramasser (turbo) : flotte doucement et brille ; disparaît au bout de 15 secondes.
class Os extends Node2D:
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t > 15.0:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var a := 1.0 if _t < 13.0 else (0.5 + 0.5 * sin(_t * 20.0))
		var h := sin(_t * 3.0) * 3.0
		draw_circle(Vector2(2, 9), 13.0, Color(0, 0, 0, 0.18 * a))
		draw_circle(Vector2(0, h), 24.0 + sin(_t * 5.0) * 3.0, Color(1, 0.9, 0.4, 0.22 * a))
		draw_set_transform(Vector2(0, h), 0.5, Vector2.ONE)
		var os := Color(0.98, 0.95, 0.86, a)
		var ombre := Color(0.8, 0.75, 0.62, a)
		draw_rect(Rect2(-11, -4, 22, 8), ombre)
		draw_rect(Rect2(-11, -4, 22, 6), os)
		for x in [-12.0, 12.0]:
			for y in [-4.0, 4.0]:
				draw_circle(Vector2(x, y), 5.0, ombre)
				draw_circle(Vector2(x, y - 1), 4.5, os)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Étoiles de fin de niveau : apparaissent une à une avec un « ding ».
class Etoiles extends Control:
	var son: Callable
	var _echelles := [0.0, 0.0, 0.0]
	var _n := 0

	func _ready() -> void:
		custom_minimum_size = Vector2(320, 96)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func montrer(n: int) -> void:
		_n = n
		_echelles = [0.0, 0.0, 0.0]
		visible = true
		queue_redraw()
		var t := create_tween()
		t.tween_interval(0.35)
		for i in n:
			t.tween_method(func(v: float) -> void:
				_echelles[i] = v
				queue_redraw(), 0.0, 1.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t.tween_callback(func() -> void:
				if son.is_valid():
					son.call(i))

	func _etoile(c: Vector2, r: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for k in 10:
			var a := -PI / 2.0 + k * PI / 5.0
			pts.append(c + Vector2.from_angle(a) * (r if k % 2 == 0 else r * 0.45))
		return pts

	func _draw() -> void:
		for i in 3:
			var c := Vector2(size.x / 2.0 + (i - 1) * 100.0, size.y / 2.0 + (0.0 if i == 1 else 8.0))
			var r := 40.0 if i == 1 else 34.0
			draw_colored_polygon(_etoile(c + Vector2(0, 4), r), Color(0, 0, 0, 0.15))
			draw_colored_polygon(_etoile(c, r), Color("d8cfbd"))
			if i < _n and _echelles[i] > 0.01:
				var s: float = _echelles[i]
				draw_colored_polygon(_etoile(c, r * s), Color("ffc93c"))
				draw_colored_polygon(_etoile(c + Vector2(-r * 0.12, -r * 0.15) * s, r * 0.45 * s), Color("ffe68a"))


## Bouton rond dessiné (le toucher est géré par main.gd pour permettre le multi-doigts).
class BoutonRond extends Control:
	var texte := ""
	var couleur := Color.ORANGE
	var charge := 1.0          # 0..1 : remplissage du cercle de recharge
	var note := false          # dessine une note de musique au lieu du texte
	var barre := false         # note barrée (musique coupée)
	var appuye := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		var pret := charge >= 0.999
		var enfonce := appuye > 0.0
		draw_circle(c + Vector2(0, 8), r, couleur.darkened(0.55))
		var col := couleur if pret else couleur.darkened(0.45)
		var cc := c + (Vector2(0, 5) if enfonce else Vector2.ZERO)
		draw_circle(cc, r, col)
		draw_circle(cc, r * 0.8, col.lightened(0.12))
		draw_circle(cc + Vector2(-r * 0.3, -r * 0.35), r * 0.25, Color(1, 1, 1, 0.18))
		if not pret:
			draw_arc(cc, r - 5.0, -PI / 2.0, -PI / 2.0 + TAU * charge, 48, Color(1, 1, 1, 0.9), 7.0)
		if note:
			var blanc := Color(1, 1, 1, 0.5 if barre else 1.0)
			draw_circle(cc + Vector2(-r * 0.18, r * 0.28), r * 0.2, blanc)
			draw_line(cc + Vector2(0, r * 0.28), cc + Vector2(0, -r * 0.42), blanc, 3.0)
			draw_line(cc + Vector2(0, -r * 0.42), cc + Vector2(r * 0.3, -r * 0.2), blanc, 3.0)
			if barre:
				draw_line(cc + Vector2(-r * 0.5, -r * 0.5), cc + Vector2(r * 0.5, r * 0.5), Color("ff6b5b"), 4.0)
			return
		var police := ThemeDB.fallback_font
		var taille := int(r * (0.36 if texte.length() > 2 else 0.6))
		var largeur := police.get_string_size(texte, HORIZONTAL_ALIGNMENT_LEFT, -1, taille).x
		var pos := Vector2(cc.x - largeur / 2.0, cc.y + taille * 0.35)
		draw_string_outline(police, pos, texte, HORIZONTAL_ALIGNMENT_LEFT, -1, taille, 6, Color(0, 0, 0, 0.35))
		draw_string(police, pos, texte, HORIZONTAL_ALIGNMENT_LEFT, -1, taille, Color.WHITE)


## Traînées de vent : de fines lignes blanches qui traversent le pré (annonce puis rafale).
class Rafale extends Node2D:
	var dir := Vector2.RIGHT
	var annonce := Vector2.ZERO     # quelques feuilles annoncent la rafale
	var force := 0.0
	var _traits: Array = []

	func _ready() -> void:
		z_index = 5
		for i in 26:
			_traits.append(Vector3(randf_range(0, 720), randf_range(100, 1280), randf()))

	func _process(delta: float) -> void:
		var d := dir if annonce == Vector2.ZERO else annonce
		var vit := 900.0 * force + (160.0 if annonce != Vector2.ZERO else 0.0)
		if vit <= 0.0:
			if visible:
				visible = false
			return
		visible = true
		for i in _traits.size():
			var t: Vector3 = _traits[i]
			var p := Vector2(t.x, t.y) + d * vit * delta * (0.7 + t.z * 0.6)
			p.x = fposmod(p.x, 760.0) - 20.0
			p.y = fposmod(p.y - 100.0, 1200.0) + 100.0
			_traits[i] = Vector3(p.x, p.y, t.z)
		queue_redraw()

	func _draw() -> void:
		var d := dir if annonce == Vector2.ZERO else annonce
		for t in _traits:
			var p := Vector2(t.x, t.y)
			if annonce != Vector2.ZERO:
				if t.z < 0.3:      # feuilles qui tourbillonnent
					draw_circle(p, 4.0, Color(0.45, 0.7, 0.3, 0.9))
			else:
				draw_line(p, p - d * (40.0 + 60.0 * t.z) * force, Color(1, 1, 1, 0.45 * force), 2.0 + t.z * 2.0)
