extends CanvasLayer
## Écran de chargement entre deux niveaux : un verset biblique tiré au hasard (Louis Segond 1910),
## une barre qui se remplit avec un mouton qui trotte dessus, puis « Touche l'écran pour continuer ».
## Toucher l'écran (une fois la barre pleine) lance le niveau.

signal fini

const DUREE := 2.4             # secondes de remplissage de la barre

const VERSETS := [
	["L'Éternel est mon berger : je ne manquerai de rien.", "Psaume 23.1"],
	["Il me fait reposer dans de verts pâturages, il me dirige près des eaux paisibles.", "Psaume 23.2"],
	["Quand je marche dans la vallée de l'ombre de la mort, je ne crains aucun mal, car tu es avec moi.", "Psaume 23.4"],
	["Je suis le bon berger. Le bon berger donne sa vie pour ses brebis.", "Jean 10.11"],
	["Mes brebis entendent ma voix ; je les connais, et elles me suivent.", "Jean 10.27"],
	["Réjouissez-vous avec moi, car j'ai trouvé ma brebis qui était perdue.", "Luc 15.6"],
	["Comme un berger, il paîtra son troupeau, il prendra les agneaux dans ses bras.", "Ésaïe 40.11"],
	["Je chercherai celle qui était perdue, je ramènerai celle qui était égarée.", "Ézéchiel 34.16"],
	["Nous sommes son peuple, et le troupeau de son pâturage.", "Psaume 100.3"],
	["Venez à moi, vous tous qui êtes fatigués et chargés, et je vous donnerai du repos.", "Matthieu 11.28"],
	["Je puis tout par celui qui me fortifie.", "Philippiens 4.13"],
	["Fortifie-toi et prends courage ! Ne t'effraie point, car l'Éternel, ton Dieu, est avec toi.", "Josué 1.9"],
	["Ceux qui se confient en l'Éternel renouvellent leur force. Ils courent, et ne se lassent point.", "Ésaïe 40.31"],
	["Déchargez-vous sur lui de tous vos soucis, car lui-même prend soin de vous.", "1 Pierre 5.7"],
	["Confie-toi en l'Éternel de tout ton cœur, et ne t'appuie pas sur ta sagesse.", "Proverbes 3.5"],
	["C'est ici la journée que l'Éternel a faite : qu'elle soit pour nous un sujet d'allégresse et de joie !", "Psaume 118.24"],
	["Ses compassions se renouvellent chaque matin. Oh ! que ta fidélité est grande !", "Lamentations 3.22-23"],
	["L'Éternel gardera ton départ et ton arrivée, dès maintenant et à jamais.", "Psaume 121.8"],
	["Je vous laisse la paix, je vous donne ma paix.", "Jean 14.27"],
	["Nous sommes le peuple de son pâturage, le troupeau que sa main conduit.", "Psaume 95.7"],
]

var _fond: Control
var _boite: VBoxContainer
var _barre: Barre
var _invite: Label
var _niveau: Label
var _t := 0.0
var _pret := false
var _parti := false
var _sons: Node
static var _dernier := -1      # évite de tirer deux fois de suite le même verset


func _init(niveau: int, sons: Node) -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sons = sons
	_fond = Fond.new()
	_fond.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fond.mouse_filter = Control.MOUSE_FILTER_STOP
	_fond.gui_input.connect(_toucher)
	add_child(_fond)

	_boite = VBoxContainer.new()
	_boite.set_anchors_preset(Control.PRESET_FULL_RECT)
	_boite.offset_left = 60
	_boite.offset_right = -60
	_boite.alignment = BoxContainer.ALIGNMENT_CENTER
	_boite.add_theme_constant_override("separation", 26)
	_boite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fond.add_child(_boite)

	var i := randi() % VERSETS.size()
	if i == _dernier:
		i = (i + 1) % VERSETS.size()
	_dernier = i
	_niveau = _label("Niveau %d" % niveau, 30, Color("ffd23f"))
	_boite.add_child(_niveau)
	var guillemets := _label("« %s »" % VERSETS[i][0], 34, Color("fffaf0"))
	guillemets.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_boite.add_child(guillemets)
	_boite.add_child(_label(VERSETS[i][1], 26, Color("cfe8c4")))
	var vide := Control.new()
	vide.custom_minimum_size = Vector2(0, 60)
	_boite.add_child(vide)
	_barre = Barre.new()
	_barre.custom_minimum_size = Vector2(0, 70)
	_boite.add_child(_barre)
	_invite = _label("Chargement…", 28, Color("ffffff"))
	_boite.add_child(_invite)

	_fond.modulate.a = 0.0
	_fond.create_tween().tween_property(_fond, "modulate:a", 1.0, 0.3)


func _label(texte: String, taille: int, couleur: Color) -> Label:
	var l := Label.new()
	l.text = texte
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", taille)
	l.add_theme_color_override("font_color", couleur)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(delta: float) -> void:
	_t += delta
	_barre.part = clampf(_t / DUREE, 0.0, 1.0)
	_barre.queue_redraw()
	_fond.queue_redraw()
	if not _pret and _t >= DUREE:
		_pret = true
		_invite.text = "Touche l'écran pour continuer"
		if _sons:
			_sons.pret()
	if _pret:
		_invite.modulate.a = 0.55 + 0.45 * sin(_t * 4.0)


func _toucher(event: InputEvent) -> void:
	var appui: bool = (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed)
	if not appui or not _pret or _parti:
		return
	_parti = true
	if _sons:
		_sons.clic()
	var t := _fond.create_tween()
	t.tween_property(_fond, "modulate:a", 0.0, 0.3)
	t.tween_callback(func() -> void:
		fini.emit()
		queue_free())


## Fond : dégradé du soir, collines et étoiles qui scintillent doucement.
class Fond extends Control:
	var _etoiles: Array = []

	func _ready() -> void:
		for i in 40:
			_etoiles.append(Vector3(randf(), randf() * 0.45, randf() * TAU))

	func _draw() -> void:
		var s := size
		var haut := Color("1d2b4a")
		var bas := Color("3f6b4a")
		for k in 64:
			var y0 := s.y * k / 64.0
			draw_rect(Rect2(0, y0, s.x, s.y / 64.0 + 1.0), haut.lerp(bas, k / 63.0))
		var t := Time.get_ticks_msec() / 1000.0
		for e in _etoiles:
			var a := 0.35 + 0.35 * sin(t * 1.5 + e.z)
			draw_circle(Vector2(e.x * s.x, e.y * s.y), 1.6 + e.z * 0.15, Color(1, 1, 0.9, a))
		# deux collines
		var c1 := PackedVector2Array([Vector2(0, s.y)])
		var c2 := PackedVector2Array([Vector2(0, s.y)])
		for i in 33:
			var x := s.x * i / 32.0
			c1.append(Vector2(x, s.y * 0.8 + sin(i * 0.35) * 30.0))
			c2.append(Vector2(x, s.y * 0.87 + sin(i * 0.27 + 2.0) * 22.0))
		c1.append(Vector2(s.x, s.y))
		c2.append(Vector2(s.x, s.y))
		draw_colored_polygon(c1, Color("2f5a3c"))
		draw_colored_polygon(c2, Color("264a31"))


## Barre de chargement avec un petit mouton qui trotte sur le bord avant.
class Barre extends Control:
	var part := 0.0

	func _draw() -> void:
		var h := 22.0
		var y := size.y - h - 4.0
		var r := Rect2(0, y, size.x, h)
		draw_rect(r, Color(0, 0, 0, 0.3))
		draw_rect(Rect2(r.position, Vector2(size.x * part, h)), Color("ffd23f"))
		draw_rect(r, Color(1, 1, 1, 0.5), false, 2.0)
		# mouton
		var t := Time.get_ticks_msec() / 1000.0
		var saut := absf(sin(t * 10.0)) * 8.0 if part < 1.0 else absf(sin(t * 5.0)) * 4.0
		var p := Vector2(clampf(size.x * part, 18.0, size.x - 18.0), y - 14.0 - saut)
		for dx in [-8.0, 8.0]:
			draw_line(p + Vector2(dx, 6), p + Vector2(dx, 14 + saut * 0.5), Color("2a2420"), 4.0)
		for o in [Vector2(-8, -3), Vector2(0, -7), Vector2(8, -3), Vector2(-5, 4), Vector2(5, 4)]:
			draw_circle(p + o, 9.0, Color("f7f4ea"))
		draw_circle(p + Vector2(15, -2), 6.5, Color("2a2420"))
		draw_circle(p + Vector2(17, -4), 1.6, Color.WHITE)
