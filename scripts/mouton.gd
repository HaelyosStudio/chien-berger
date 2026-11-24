extends RigidBody2D
const Rond := preload("res://scripts/rond.gd")
## Un mouton : corps physique qui fuit le chien, reste collé au troupeau et broute au hasard.
## Il est poussé par des forces (jamais déplacé directement) : collisions, poids et inertie réels.
## La peur se transmet de voisin en voisin : le troupeau réagit comme une seule masse.
##
## Dessin économe : chaque morceau (ombre, pattes, laine, tête) est dessiné UNE fois,
## puis seulement déplacé / étiré / tourné à chaque image (indispensable avec 50+ moutons sur téléphone).

const RAYON := 13.0
const PEUR_DISTANCE := 210.0     # distance à partir de laquelle le chien fait peur
const FORCE_PEUR := 900.0
const FORCE_TROUPEAU := 160.0    # envie de rejoindre les autres
const FORCE_SUIVRE := 1.4        # envie d'aller dans le même sens que les autres
const FORCE_ECART := 500.0       # garder un peu de place autour de soi
const FORCE_ERRANCE := 90.0      # promenade quand tout est calme
const CASE := 95.0               # taille des cases de la grille de voisinage (= portée de vue)
const VOISINS_MAX := 16
const VITESSE_MAX := 265.0
const FORCE_GREGAIRE := 55.0     # attirance vers l'ensemble du troupeau (instinct grégaire)
const FORCE_SUIVRE_ENCLOS := 120.0  # envie de rejoindre ceux déjà rentrés

var chien: RigidBody2D
var grille: Dictionary = {}      # Vector2i -> moutons de la case (remplie par main.gd)
var infos: Dictionary = {}       # centre du troupeau dehors, porte, part déjà rentrée (main.gd)
var enclos := Rect2()            # intérieur de l'enclos (pour savoir s'il est rentré)
var dans_enclos := false
var compte := false              # déjà compté comme rentré (géré par main.gd)
var fete := false                # saute de joie (victoire)
var peur := 0.0                  # 0 = calme, 1 = terrifié (lu par les voisins)
var noir := false                # mouton noir
var dore := false               # mouton d'or : rare, plus peureux et plus rapide
var fond := Vector2.UP           # direction de l'entrée vers le fond de l'enclos
var belier := false              # le chef : têtu, fonce sur le chien de face, le troupeau le suit
var agneau := false              # petit : suit sa maman partout, appelle s'il la perd
var mere = null                  # maman de l'agneau (un autre mouton)
var petit = null                 # agneau de cette maman
var reuni := false               # agneau rentré avec sa maman (bonus déjà donné)
var perdu := false               # agneau trop loin de sa maman

signal charge(dir: Vector2)      # le bélier vient de foncer sur le chien
signal appelle                   # l'agneau perdu bêle

var _face := false               # le bélier fait face au chien
var _recharge_charge := 0.0
var _appel := 1.0
var _immobile := false

var _errance := Vector2.ZERO
var _prochaine_errance := 0.0
var _panique := 0.0              # monte d'un coup après un aboiement, puis redescend
var _regard := Vector2.DOWN
var _pas := 0.0
var _r := RAYON
var _choc := 0.0                 # écrasement après un choc
var _v_prec := Vector2.ZERO
var _phase := 0.0
var _tour := 0
var _nb_voisins := 0
var _centre_voisins := Vector2.ZERO
var _vitesse_voisins := Vector2.ZERO
var _ecartement := Vector2.ZERO
var _peur_voisine := 0.0

# Morceaux du dessin
var _ombre: Partie
var _pattes: Node2D
var _patte: Array[Partie] = []
var _corps: Partie
var _tete: Partie
var _alerte: Partie
var _yeux_effrayes := false


func _ready() -> void:
	gravity_scale = 0.0
	mass = 1.0
	linear_damp = 2.6             # frottement de l'herbe (assez faible : les moutons glissent sur leur élan)
	lock_rotation = true
	can_sleep = false
	var matiere := PhysicsMaterial.new()
	matiere.bounce = 0.2
	matiere.friction = 0.4
	physics_material_override = matiere
	var forme := CollisionShape2D.new()
	var cercle := CircleShape2D.new()
	var taille := 1.35 if belier else (0.62 if agneau else 1.0)
	mass = 3.0 if belier else (0.5 if agneau else 1.0)
	cercle.radius = RAYON * taille
	forme.shape = cercle
	add_child(forme)
	_regard = Vector2.from_angle(randf() * TAU)
	_r = RAYON * taille * (1.0 if belier or agneau else randf_range(0.88, 1.12))
	_prochaine_errance = randf() * 2.0
	_phase = randf() * TAU
	_tour = randi() % 2
	_creer_dessin()
	_process(0.0)          # pose de départ correcte, même si le jeu est en pause


# ---------------------------------------------------------------- comportement

func _physics_process(delta: float) -> void:
	# Économie de calcul : chaque mouton ne réfléchit qu'une image sur deux (la moitié du troupeau
	# à chaque image). Entre deux, sa force reste appliquée (constant_force).
	if (Engine.get_physics_frames() + _tour) % 2 != 0:
		return
	delta *= 2.0
	var pos := global_position
	var force := Vector2.ZERO
	_panique = maxf(0.0, _panique - delta * 0.7)

	# 1. Peur du chien : on s'éloigne, d'autant plus vite qu'il est près (et qu'il court)
	var peur_directe := _panique
	_recharge_charge = maxf(0.0, _recharge_charge - delta)
	if chien:
		var ecart := pos - chien.global_position
		var dist := ecart.length()
		var portee := PEUR_DISTANCE * (1.3 if dore else (1.15 if agneau else 1.0))
		# le bélier ne recule pas devant un chien qui arrive de face : il le regarde… et fonce
		_face = belier and not dans_enclos and dist < 170.0 and _regard.dot(-ecart / maxf(dist, 0.1)) > 0.3
		if _face:
			if dist < 64.0 and _recharge_charge <= 0.0:
				_recharge_charge = 2.2
				var vers := -ecart / maxf(dist, 0.1)
				apply_central_impulse(vers * 520.0)
				chien.apply_central_impulse(vers * 1150.0)
				chien.set("etourdi", 0.7)
				charge.emit(vers)
		elif dist < portee and dist > 0.1:
			var p := 1.0 - dist / portee
			if chien.linear_velocity.length() > 160.0:
				p *= 1.35
			peur_directe = maxf(peur_directe, minf(p, 1.0))
			force += ecart / dist * FORCE_PEUR * p

	# 1 bis. Peur du loup : bien plus forte que celle du chien
	if infos.get("loup_actif", false):
		var ecart_l: Vector2 = pos - infos.loup
		var dl := ecart_l.length()
		if dl < 260.0 and dl > 0.1:
			var pl := 1.0 - dl / 260.0
			peur_directe = maxf(peur_directe, minf(pl * 1.4, 1.0))
			force += ecart_l / dl * FORCE_PEUR * 1.3 * pl

	# 2. Troupeau : se rapprocher, suivre les autres, sans se coller ; la peur est contagieuse.
	_chercher_voisins(pos)
	peur = maxf(peur_directe, _peur_voisine * 0.85)
	if _nb_voisins > 0:
		var envie := 0.35 + peur * 1.3      # un mouton qui a peur se serre contre les autres
		force += ((_centre_voisins - pos) / 80.0).limit_length(1.0) * FORCE_TROUPEAU * envie
		force += (_vitesse_voisins - linear_velocity) * FORCE_SUIVRE * (0.15 + peur * 1.2)
	force += _ecartement * FORCE_ECART

	# 2 bis. Instinct grégaire : tout le troupeau s'attire (les égarés reviennent vers la masse),
	#        et près de l'entrée, on suit ceux qui sont déjà dans l'enclos.
	if not dans_enclos and infos.has("dehors"):
		var vers_troupeau: Vector2 = infos.dehors - pos
		var dt := vers_troupeau.length()
		if dt > 50.0:
			force += vers_troupeau / dt * FORCE_GREGAIRE * minf((dt - 50.0) / 150.0, 1.0)
		# près de l'enclos, ils reconnaissent l'entrée (et suivent ceux déjà rentrés)
		var part: float = infos.get("part_dedans", 0.0)
		if infos.has("porte"):
			var vers_porte: Vector2 = infos.porte - pos
			var dp := vers_porte.length()
			if dp < 260.0:
				force += vers_porte / maxf(dp, 1.0) * FORCE_SUIVRE_ENCLOS * (0.35 + part) * (1.0 - dp / 260.0)
	# 2 ter. Le bélier est le chef : les moutons proches le suivent
	if not belier and not dans_enclos and infos.has("belier"):
		var vers_chef: Vector2 = infos.belier - pos
		var dc := vers_chef.length()
		if dc > 55.0 and dc < 320.0:
			force += vers_chef / dc * 65.0 * (1.0 - dc / 320.0)

	# 2 quater. L'agneau colle à sa maman ; trop loin, il s'arrête et l'appelle
	if agneau and is_instance_valid(mere):
		var vers_mere: Vector2 = mere.global_position - pos
		var dm := vers_mere.length()
		perdu = dm > 150.0 and not (dans_enclos and mere.dans_enclos)
		if dm > 26.0:
			force += vers_mere / dm * (300.0 if not perdu else 120.0) * minf((dm - 26.0) / 60.0, 1.0)
		if perdu:
			_appel -= delta
			if _appel <= 0.0:
				_appel = randf_range(2.0, 3.0)
				appelle.emit()

	# 2 quinquies. Coup de vent (les petits s'envolent presque, le bélier résiste)
	var vent: Vector2 = infos.get("vent", Vector2.ZERO)
	if vent != Vector2.ZERO:
		force += vent * (0.35 if belier else (1.5 if agneau else 1.0)) * (0.25 if dans_enclos else 1.0)

	# 3. Errance tranquille (ou pause pour brouter)
	_prochaine_errance -= delta
	if _prochaine_errance <= 0.0:
		_prochaine_errance = randf_range(1.0, 3.5)
		_errance = Vector2.ZERO if randf() < 0.45 else Vector2.from_angle(randf() * TAU)
	var calme := 1.0 - peur
	force += _errance * FORCE_ERRANCE * calme * (0.25 if dans_enclos else 1.0)

	# 4. Une fois dans l'enclos, il s'y sent bien et va vers le fond
	dans_enclos = enclos.has_point(pos)
	if dans_enclos:
		force += fond * 70.0 * calme + (enclos.get_center() - pos).limit_length(1.0) * 30.0

	constant_force = force * mass


func _chercher_voisins(pos: Vector2) -> void:
	var centre := Vector2.ZERO
	var vitesse := Vector2.ZERO
	var voisins := 0
	var ecartement := Vector2.ZERO
	var peur_voisine := 0.0
	var cx := int(floor(pos.x / CASE))
	var cy := int(floor(pos.y / CASE))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var liste: Variant = grille.get(Vector2i(cx + dx, cy + dy))
			if liste == null:
				continue
			for autre in liste:
				if autre == self:
					continue
				var d: Vector2 = pos - autre.global_position
				var l := d.length()
				if l >= CASE:
					continue
				peur_voisine = maxf(peur_voisine, autre.peur * (1.0 - l / CASE))
				if l < RAYON * 3.0 and l > 0.1:
					ecartement += d / l * (1.0 - l / (RAYON * 3.0))
				if voisins < VOISINS_MAX:
					centre += autre.global_position
					vitesse += autre.linear_velocity
					voisins += 1
	_nb_voisins = voisins
	_ecartement = ecartement
	_peur_voisine = peur_voisine
	if voisins > 0:
		_centre_voisins = centre / voisins
		_vitesse_voisins = vitesse / voisins


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	state.linear_velocity = state.linear_velocity.limit_length(VITESSE_MAX * (1.15 if dore else 1.0))
	# un brusque changement de vitesse = un choc : le mouton s'écrase un instant
	if (state.linear_velocity - _v_prec).length() > 110.0:
		_choc = 1.0
	_v_prec = state.linear_velocity


## Appelé quand le chien aboie : le mouton est projeté loin de la source.
func effrayer(source: Vector2, puissance: float) -> void:
	var d := global_position - source
	if d.length() < 0.1:
		d = Vector2.UP
	apply_central_impulse(d.normalized() * puissance)
	_panique = 1.0


# ---------------------------------------------------------------- animation (sans redessiner)

func _process(delta: float) -> void:
	_choc = maxf(0.0, _choc - delta * 5.0)
	var v := linear_velocity
	var vit := v.length()
	# immobile et calme : la pose ne change pas, inutile de tout recalculer
	if vit < 4.0 and not fete and _choc <= 0.0 and _panique <= 0.55 and not perdu and not _face:
		if _immobile:
			return
		_immobile = true
	else:
		_immobile = false
	if _face and chien:
		var vers_chien := (chien.global_position - global_position).normalized()
		_regard = _regard.slerp(vers_chien, minf(delta * 1.3, 1.0)).normalized()
	elif vit > 15.0:
		var r := _regard.lerp(v / vit, minf(delta * 9.0, 1.0))
		if r.length() > 0.01:
			_regard = r.normalized()
	_pas += vit * delta

	# Saut : en courant, ou de joie à la victoire
	var saut := 0.0
	if fete:
		saut = absf(sin(Time.get_ticks_msec() / 1000.0 * 9.0 + _phase)) * 9.0
	elif vit > 60.0:
		saut = absf(sin(_pas * 0.07)) * minf(vit / 260.0, 1.0) * 6.0
	var haut := Vector2(0, -saut)

	_ombre.scale = Vector2.ONE * (1.0 - saut * 0.025)

	# Pattes qui trottent
	var marche := vit > 30.0 or fete
	_pattes.visible = marche
	if marche:
		_pattes.position = haut * 0.5
		_pattes.rotation = _regard.angle()
		var p := sin(_pas * 0.18) * _r * 0.3
		_patte[0].position = Vector2(_r * 0.45 + p, _r * 0.5)
		_patte[1].position = Vector2(_r * 0.45 - p, -_r * 0.5)
		_patte[2].position = Vector2(-_r * 0.45 - p, _r * 0.5)
		_patte[3].position = Vector2(-_r * 0.45 + p, -_r * 0.5)

	# Corps : étiré dans le sens de la course, écrasé après un choc (la lumière reste en haut à gauche)
	var etire := clampf(vit / VITESSE_MAX, 0.0, 1.0) * 0.2
	var sx := 1.0 + etire - _choc * 0.22
	var sy := 1.0 - etire * 0.55 + _choc * 0.18
	var a := _regard.angle()
	var gonfle := 1.0 + saut * 0.02
	var m := Transform2D(a, Vector2.ZERO) * Transform2D(0.0, Vector2(sx, sy) * gonfle, 0.0, Vector2.ZERO) * Transform2D(-a, Vector2.ZERO)
	m.origin = haut
	_corps.transform = m

	# Tête (tournée dans le sens du regard), yeux écarquillés quand il a peur
	_tete.position = haut + m.basis_xform(_regard * _r * 0.95)
	_tete.rotation = a
	var effraye := peur > 0.45
	if effraye != _yeux_effrayes:
		_yeux_effrayes = effraye
		_tete.queue_redraw()

	_alerte.visible = _panique > 0.55 or perdu
	if _alerte.visible:
		_alerte.position = Vector2(0, -_r - 8 - saut)


func _creer_dessin() -> void:
	_ombre = _partie(self, _dessiner_ombre)
	_ombre.position = Vector2(2, 5)
	_pattes = Node2D.new()
	add_child(_pattes)
	for i in 4:
		_patte.append(_partie(_pattes, _dessiner_patte))
	_corps = _partie(self, _dessiner_corps)
	_tete = _partie(self, _dessiner_tete)
	_alerte = _partie(self, _dessiner_alerte)
	_alerte.visible = false
	_pattes.visible = false


func _partie(parent: Node, dessin: Callable) -> Partie:
	var p := Partie.new()
	p.dessin = dessin
	parent.add_child(p)
	return p


func _dessiner_ombre(n: Node2D) -> void:
	Rond.cercle(n, Vector2.ZERO, _r * 1.05, Color(0, 0, 0, 0.22))


func _dessiner_patte(n: Node2D) -> void:
	Rond.cercle(n, Vector2.ZERO, _r * 0.18, Color(0.16, 0.14, 0.13))


func _dessiner_corps(n: Node2D) -> void:
	var r := _r
	var laine := Color(0.33, 0.3, 0.29) if noir else Color(0.97, 0.96, 0.92)
	if dore:
		laine = Color(1.0, 0.8, 0.28)
	elif belier:
		laine = Color(0.9, 0.84, 0.72)
	var laine_ombre := laine.darkened(0.2)
	var laine_lumiere := laine.lightened(0.5) if (noir or dore) else Color.WHITE
	var bouclettes: Array[Vector2] = []
	for i in 9:
		bouclettes.append(Vector2.from_angle(TAU * i / 9.0 + randf_range(-0.2, 0.2)) * randf_range(0.48, 0.62))
	Rond.cercle(n, Vector2(0.5, 1.5), r * 1.02, laine_ombre)
	for o in bouclettes:
		Rond.cercle(n, o * r + Vector2(0.5, 1.0), r * 0.47, laine_ombre)
	for o in bouclettes:
		Rond.cercle(n, o * r, r * 0.44, laine)
	Rond.cercle(n, Vector2.ZERO, r * 0.7, laine)
	Rond.cercle(n, Vector2(-r * 0.25, -r * 0.3), r * 0.38, laine_lumiere)


func _dessiner_tete(n: Node2D) -> void:
	# repère local : +x = devant
	var r := _r
	var fonce := Color(0.16, 0.14, 0.13)
	Rond.cercle(n, Vector2(-2.0, r * 0.5), r * 0.22, fonce)
	Rond.cercle(n, Vector2(-2.0, -r * 0.5), r * 0.22, fonce)
	Rond.cercle(n, Vector2.ZERO, r * 0.42, fonce)
	if belier:      # grosses cornes enroulées
		var corne := Color("a07850")
		for s in [-1.0, 1.0]:
			n.draw_arc(Vector2(-3.0, r * 0.42 * s), r * 0.3, 0.0, TAU * 0.8, 14, corne.darkened(0.3), 5.0)
			n.draw_arc(Vector2(-3.0, r * 0.42 * s), r * 0.3, 0.0, TAU * 0.8, 14, corne, 3.0)
	var oeil := 3.0 if _yeux_effrayes else 1.6
	for s in [-1.0, 1.0]:
		var p := Vector2(1.5, 3.0 * s)
		Rond.cercle(n, p, oeil, Color.WHITE)
		Rond.cercle(n, p + Vector2(0.7, 0), 0.9, fonce)


func _dessiner_alerte(n: Node2D) -> void:
	var police := ThemeDB.fallback_font
	var pos := Vector2(-3, 0)
	var signe := "?" if agneau else "!"
	n.draw_string_outline(police, pos, signe, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 5, Color(0.1, 0.05, 0))
	n.draw_string(police, pos, signe, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("ff8fb1") if agneau else Color("ffcf3a"))


## Un morceau de dessin : dessiné une seule fois (ou sur demande), puis simplement déplacé.
class Partie extends Node2D:
	var dessin: Callable

	func _draw() -> void:
		dessin.call(self)
