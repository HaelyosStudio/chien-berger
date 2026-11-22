extends CanvasLayer
## Écran des mises à jour (plein écran, par-dessus le jeu).
## - Une nouvelle version existe : l'écran s'affiche (jamais en pleine partie : il attend la fin du niveau),
##   montre les nouveautés et la progression du téléchargement, puis le jeu se RELANCE TOUT SEUL.
## - Juste après la relance : écran « Quoi de neuf » avec les nouveautés de la version.
## Fonctionne avec l'autoload MiseAJour déjà installé (maj.gd ne peut pas lui-même être mis à jour) :
## c'est lui qui télécharge ; ici on lit le manifeste (notes), on suit le téléchargement et on relance.

const DOSSIER := "user://maj/"
const NOUVEAUTES := DOSSIER + "nouveautes.json"

var peut_afficher: Callable          # fourni par main.gd : vrai quand on n'est pas en pleine partie
var _maj: Node
var _manifeste: Dictionary = {}
var _etat := ""                      # "" | "attente" | "telechargement" | "relance"
var _fond: ColorRect
var _titre: Label
var _version: Label
var _notes: Label
var _statut: Label
var _barre: ColorRect
var _barre_fond: ColorRect
var _bouton: Button
var _mouton: Control
var _progression := 0.0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_maj = get_node_or_null("/root/MiseAJour")
	_construire()
	visible = false
	if _maj == null:
		return
	_maj.prete.connect(func(_v: String) -> void: _progression = 1.0)
	# Juste mis à jour ? → « Quoi de neuf »
	if FileAccess.file_exists(NOUVEAUTES):
		var n: Variant = JSON.parse_string(FileAccess.get_file_as_string(NOUVEAUTES))
		DirAccess.remove_absolute(NOUVEAUTES)
		if typeof(n) == TYPE_DICTIONARY and int(n.get("build", -1)) == int(_maj.build):
			_quoi_de_neuf(n)
			return
	if (OS.has_feature("editor") and not "--maj-test" in OS.get_cmdline_user_args()) or "--demo" in OS.get_cmdline_user_args():
		return
	_lire_manifeste()


# ---------------------------------------------------------------- recherche et suivi

func _lire_manifeste() -> void:
	var url := str(ProjectSettings.get_setting("application/config/maj_manifeste", ""))
	if url == "":
		return
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	http.request_completed.connect(func(resultat: int, code: int, _e: PackedStringArray, corps: PackedByteArray) -> void:
		http.queue_free()
		if resultat != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var m: Variant = JSON.parse_string(corps.get_string_from_utf8())
		if typeof(m) == TYPE_DICTIONARY and int(m.get("build", 0)) > int(_maj.build):
			_manifeste = m
			_etat = "attente")
	if http.request(url) != OK:
		http.queue_free()


func _process(delta: float) -> void:
	if _etat == "":
		return
	if _etat == "attente":
		if peut_afficher.is_valid() and peut_afficher.call():
			_afficher_maj()
		return
	if _etat == "telechargement":
		var p := _avancement()
		_progression = maxf(_progression, p)
		_barre.anchor_right = lerpf(_barre.anchor_right, _progression, minf(delta * 8.0, 1.0))
		if _maj.maj_prete != "":
			_etat = "relance"
			_barre.anchor_right = 1.0
			_statut.text = "Installation… le jeu redémarre"
			get_tree().create_timer(1.3).timeout.connect(_relancer)
		else:
			_statut.text = "Téléchargement… %d %%" % int(_progression * 100.0)


## Avancement du téléchargement fait par l'autoload (0 → 1).
func _avancement() -> float:
	for enfant in _maj.get_children():
		if enfant is HTTPRequest and enfant.download_file != "":
			var total: int = enfant.get_body_size()
			if total > 0:
				return clampf(float(enfant.get_downloaded_bytes()) / total, 0.0, 0.99)
	return 1.0 if _maj.maj_prete != "" else 0.05


# ---------------------------------------------------------------- relance automatique

## Applique la mise à jour téléchargée et relance le jeu (sans quitter l'appli).
func _relancer() -> void:
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(DOSSIER + "version.json"))
	if typeof(info) != TYPE_DICTIONARY:
		_statut.text = "Mise à jour prête : ferme et relance le jeu."
		return
	var pck: String = DOSSIER + str(info.get("fichier", ""))
	# on note les nouveautés pour l'écran « Quoi de neuf » après la relance
	var f := FileAccess.open(NOUVEAUTES, FileAccess.WRITE)
	f.store_string(JSON.stringify({"build": int(info.build), "version": str(info.get("version", "?")),
		"notes": str(_manifeste.get("notes", ""))}))
	f.close()
	if not ProjectSettings.load_resource_pack(pck, true):
		_statut.text = "Mise à jour prête : ferme et relance le jeu."
		return
	_maj.build = int(info.build)
	_maj.version = str(info.get("version", "?"))
	_maj.maj_prete = ""
	# l'ancienne partie disparaît, puis on recharge tout le jeu depuis la nouvelle version
	var arbre := get_tree()
	arbre.paused = false
	if arbre.current_scene:
		arbre.current_scene.queue_free()
	await arbre.process_frame
	await arbre.process_frame
	# Godot garde les scripts en mémoire : on force la relecture de chacun depuis la mise à jour
	# (sauf le gestionnaire de mises à jour et cet écran, qui tournent en ce moment).
	for nom in _scripts():
		if nom != "maj.gd" and nom != "ecran_maj.gd":
			ResourceLoader.load("res://scripts/" + nom, "", ResourceLoader.CACHE_MODE_IGNORE)
	var scene := ResourceLoader.load("res://main.tscn", "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var nouvelle := scene.instantiate()
	arbre.root.add_child(nouvelle)
	arbre.current_scene = nouvelle
	queue_free()


## Noms des scripts du jeu (dans le jeu exporté, ils apparaissent en .gdc / .remap).
func _scripts() -> PackedStringArray:
	var noms: PackedStringArray = []
	for f in DirAccess.get_files_at("res://scripts/"):
		var n := f.trim_suffix(".remap").trim_suffix(".gdc")
		if n.ends_with(".gd") and not n in noms:
			noms.append(n)
	return noms


# ---------------------------------------------------------------- affichage

func _afficher_maj() -> void:
	_etat = "telechargement"
	_titre.text = "Nouvelle version !"
	_version.text = str(_manifeste.get("version", "?"))
	_notes.text = _liste(str(_manifeste.get("notes", "")))
	_statut.text = "Téléchargement…"
	_barre_fond.visible = true
	_bouton.visible = false
	_apparaitre()


func _quoi_de_neuf(n: Dictionary) -> void:
	_titre.text = "Quoi de neuf ?"
	_version.text = "Version " + str(n.get("version", "?"))
	_notes.text = _liste(str(n.get("notes", "")))
	_statut.text = ""
	_barre_fond.visible = false
	_bouton.visible = true
	_bouton.text = "C'est parti !"
	_bouton.pressed.connect(func() -> void:
		var t := create_tween()
		t.tween_property(_fond, "modulate:a", 0.0, 0.25)
		t.tween_callback(queue_free))
	_apparaitre()


## Notes « a ; b ; c » → liste à puces.
func _liste(notes: String) -> String:
	var lignes: PackedStringArray = []
	for morceau in notes.split(";", false):
		var m := morceau.strip_edges()
		if m != "":
			lignes.append("•  " + m[0].to_upper() + m.substr(1))
	return "\n".join(lignes)


func _apparaitre() -> void:
	visible = true
	_fond.modulate.a = 0.0
	create_tween().tween_property(_fond, "modulate:a", 1.0, 0.3)


func _construire() -> void:
	_fond = ColorRect.new()
	_fond.color = Color(0.13, 0.27, 0.11, 0.97)
	_fond.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fond.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_fond)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fond.add_child(centre)
	var boite := VBoxContainer.new()
	boite.custom_minimum_size = Vector2(580, 0)
	boite.add_theme_constant_override("separation", 20)
	centre.add_child(boite)

	_mouton = MoutonCadeau.new()
	boite.add_child(_mouton)
	_titre = _texte(56, Color("fff3c4"))
	boite.add_child(_titre)
	_version = _texte(84, Color("ffd23f"))
	boite.add_child(_version)
	_notes = _texte(30, Color.WHITE)
	_notes.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	boite.add_child(_notes)

	_barre_fond = ColorRect.new()
	_barre_fond.color = Color(0, 0, 0, 0.35)
	_barre_fond.custom_minimum_size = Vector2(0, 26)
	boite.add_child(_barre_fond)
	_barre = ColorRect.new()
	_barre.color = Color("9be36d")
	_barre.anchor_bottom = 1.0
	_barre.anchor_right = 0.0
	_barre_fond.add_child(_barre)
	_statut = _texte(28, Color(1, 1, 1, 0.8))
	boite.add_child(_statut)

	_bouton = Button.new()
	_bouton.custom_minimum_size = Vector2(0, 100)
	_bouton.add_theme_font_size_override("font_size", 38)
	for etat in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color("e67e22").darkened(0.2 if etat == "pressed" else 0.0)
		s.set_corner_radius_all(50)
		if etat == "focus":
			s.draw_center = false
		b_style(s)
		_bouton.add_theme_stylebox_override(etat, s)
	_bouton.add_theme_color_override("font_color", Color.WHITE)
	_bouton.add_theme_color_override("font_hover_color", Color.WHITE)
	boite.add_child(_bouton)


func b_style(s: StyleBoxFlat) -> void:
	s.shadow_color = Color(0, 0, 0, 0.3)
	s.shadow_offset = Vector2(0, 6)


func _texte(taille: int, couleur: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", taille)
	l.add_theme_color_override("font_color", couleur)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.12, 0.04))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Un mouton qui sautille, avec un nœud de cadeau sur la tête.
class MoutonCadeau extends Control:
	var _t := 0.0

	func _ready() -> void:
		custom_minimum_size = Vector2(0, 170)
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var saut := absf(sin(_t * 4.0)) * 24.0
		var c := Vector2(size.x / 2.0, size.y - 60.0 - saut)
		draw_circle(Vector2(size.x / 2.0, size.y - 14.0), 42.0 - saut * 0.4, Color(0, 0, 0, 0.25))
		for i in 9:
			draw_circle(c + Vector2.from_angle(TAU * i / 9.0) * 30.0, 26.0, Color(0.97, 0.96, 0.92))
		draw_circle(c, 34.0, Color(0.97, 0.96, 0.92))
		draw_circle(c + Vector2(-12, -12), 16.0, Color.WHITE)
		var tete := c + Vector2(44, 6)
		draw_circle(tete + Vector2(-6, -16), 9.0, Color(0.16, 0.14, 0.13))
		draw_circle(tete, 20.0, Color(0.16, 0.14, 0.13))
		draw_circle(tete + Vector2(5, -5), 5.0, Color.WHITE)
		draw_circle(tete + Vector2(6, -5), 2.2, Color.BLACK)
		# nœud rouge
		var n := c + Vector2(-4, -40)
		draw_colored_polygon(PackedVector2Array([n, n + Vector2(-22, -14), n + Vector2(-22, 12)]), Color("e74c3c"))
		draw_colored_polygon(PackedVector2Array([n, n + Vector2(22, -14), n + Vector2(22, 12)]), Color("e74c3c"))
		draw_circle(n, 7.0, Color("c0392b"))
