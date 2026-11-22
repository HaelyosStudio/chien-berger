extends Node
## Sons fabriqués par le code (aboiement, bêlement, sifflet…) + musiques chill (musique/*.wav, créées par outils/musique.py).

const TAUX := 22050

var _aboi: AudioStreamWAV
var _bele: AudioStreamWAV
var _victoire: AudioStreamWAV
var _bonus: AudioStreamWAV
var _ding: AudioStreamWAV
var _grogne: AudioStreamWAV
var _glapit: AudioStreamWAV
var _choc: AudioStreamWAV
var _vent: AudioStreamWAV
var _sifflet: AudioStreamWAV
var _clic: AudioStreamWAV
var _defaite: AudioStreamWAV
var _porte: AudioStreamWAV
var _pret: AudioStreamWAV
var _pop: AudioStreamWAV
var _lecteurs: Array[AudioStreamPlayer] = []
var _musique: AudioStreamPlayer
var _morceaux: Array[AudioStream] = []
var _numero := -1
var musique_active := true
var _suivant := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 6:
		var l := AudioStreamPlayer.new()
		add_child(l)
		_lecteurs.append(l)

	# « Wouf » : un son grave qui descend, un peu rugueux
	_aboi = _fabriquer(0.18, func(t: float, d: float) -> float:
		var env := minf(t / 0.01, 1.0) * exp(-t * 18.0)
		var phase := TAU * (430.0 * t + (170.0 - 430.0) * t * t / (2.0 * d))
		return env * (0.75 * clampf(sin(phase) * 2.5, -1.0, 1.0) + 0.25 * randf_range(-1.0, 1.0)))

	# « Bêêê » : son chevrotant
	_bele = _fabriquer(0.45, func(t: float, d: float) -> float:
		var env := minf(t / 0.03, 1.0) * clampf((d - t) / 0.12, 0.0, 1.0)
		var phase := TAU * 320.0 * t - (30.0 / 26.0) * cos(TAU * 26.0 * t)
		var trem := 0.65 + 0.35 * sin(TAU * 26.0 * t)
		return env * trem * 0.5 * (sin(phase) + 0.5 * sin(2.0 * phase) + 0.25 * sin(3.0 * phase)) / 1.75 * 1.6)

	# Petite fanfare de victoire : do mi sol do
	_victoire = _fabriquer(0.6, func(t: float, _d: float) -> float:
		var notes := [523.25, 659.25, 783.99, 1046.5]
		var i := mini(int(t / 0.13), 3)
		var tl := t - i * 0.13
		var env := minf(tl / 0.01, 1.0) * exp(-tl * (6.0 if i == 3 else 12.0))
		var f: float = notes[i]
		return env * 0.45 * (sin(TAU * f * t) + 0.3 * sin(TAU * 2.0 * f * t)))

	# Bonus ramassé : petit glissando montant
	_bonus = _fabriquer(0.28, func(t: float, d: float) -> float:
		var env := minf(t / 0.01, 1.0) * clampf((d - t) / 0.08, 0.0, 1.0)
		var phase := TAU * (500.0 * t + 1400.0 * t * t / (2.0 * d))
		return env * 0.4 * (sin(phase) + 0.3 * sin(2.0 * phase)))

	# « Ding » cristallin (étoiles, combos : la hauteur change avec pitch_scale)
	_ding = _fabriquer(0.5, func(t: float, _d: float) -> float:
		var env := minf(t / 0.005, 1.0) * exp(-t * 7.0)
		return env * 0.4 * (sin(TAU * 880.0 * t) + 0.4 * sin(TAU * 1760.0 * t) + 0.2 * sin(TAU * 2640.0 * t)))

	# Grognement du loup : grave et rugueux
	_grogne = _fabriquer(0.7, func(t: float, d: float) -> float:
		var env := minf(t / 0.08, 1.0) * clampf((d - t) / 0.2, 0.0, 1.0)
		var f := 85.0 + 10.0 * sin(TAU * 7.0 * t)
		return env * (0.5 * clampf(sin(TAU * f * t) * 3.0, -1.0, 1.0) + 0.35 * randf_range(-1.0, 1.0)) * 0.6)

	# Glapissement du loup chassé : aigu qui descend
	_glapit = _fabriquer(0.3, func(t: float, d: float) -> float:
		var env := minf(t / 0.01, 1.0) * clampf((d - t) / 0.1, 0.0, 1.0)
		var phase := TAU * (1100.0 * t + (500.0 - 1100.0) * t * t / (2.0 * d))
		return env * 0.45 * (sin(phase) + 0.25 * randf_range(-1.0, 1.0)))

	# Coup de tête du bélier : « bonk » sourd et rebondi
	_choc = _fabriquer(0.25, func(t: float, _d: float) -> float:
		var env := minf(t / 0.003, 1.0) * exp(-t * 22.0)
		var f := 180.0 * exp(-t * 6.0) + 60.0
		return env * 0.8 * (sin(TAU * f * t) + 0.3 * randf_range(-1.0, 1.0) * exp(-t * 60.0)))

	# Souffle du vent : bruit filtré qui enfle puis retombe
	var filtre := [0.0]
	_vent = _fabriquer(1.6, func(t: float, d: float) -> float:
		var env := sin(PI * t / d)
		filtre[0] = filtre[0] * 0.96 + randf_range(-1.0, 1.0) * 0.04
		return env * filtre[0] * 6.0 * (0.7 + 0.3 * sin(TAU * 1.3 * t)))

	# Sifflet du berger : deux notes glissées (« fuiii-fuit »), un peu de souffle
	_sifflet = _fabriquer(0.75, func(t: float, _d: float) -> float:
		var f: float
		var env: float
		if t < 0.38:
			f = 1500.0 + 900.0 * minf(t / 0.25, 1.0)
			env = minf(t / 0.04, 1.0) * clampf((0.38 - t) / 0.05, 0.0, 1.0)
		else:
			var u := t - 0.45
			f = 2500.0 - 700.0 * clampf(u / 0.25, 0.0, 1.0)
			env = clampf(u / 0.03, 0.0, 1.0) * clampf((0.75 - t) / 0.08, 0.0, 1.0)
		var vib := 1.0 + 0.012 * sin(TAU * 6.0 * t)
		return env * 0.35 * (sin(TAU * f * vib * t) + 0.12 * randf_range(-1.0, 1.0)))

	# Petit « tic » doux des boutons
	_clic = _fabriquer(0.07, func(t: float, _d: float) -> float:
		return exp(-t * 70.0) * 0.45 * sin(TAU * 1250.0 * t))

	# Défaite : trois notes qui descendent, gentiment
	_defaite = _fabriquer(0.9, func(t: float, _d: float) -> float:
		var notes := [392.0, 349.23, 293.66]
		var i := mini(int(t / 0.22), 2)
		var tl := t - i * 0.22
		var f: float = notes[i]
		var env := minf(tl / 0.01, 1.0) * exp(-tl * (3.0 if i == 2 else 7.0))
		return env * 0.4 * (sin(TAU * f * t) + 0.35 * sin(TAU * 2.0 * f * t)))

	# Porte de l'enclos qui se ferme : « clonk » de bois
	_porte = _fabriquer(0.3, func(t: float, _d: float) -> float:
		var env := minf(t / 0.002, 1.0) * exp(-t * 18.0)
		return env * 0.6 * (sin(TAU * 210.0 * t) * 0.7 + sin(TAU * 523.0 * t) * 0.3 * exp(-t * 20.0) + 0.3 * randf_range(-1.0, 1.0) * exp(-t * 80.0)))

	# Chargement terminé : petit carillon (do puis sol aigus)
	_pret = _fabriquer(0.9, func(t: float, _d: float) -> float:
		var e1 := minf(t / 0.004, 1.0) * exp(-t * 5.0)
		var t2 := maxf(t - 0.12, 0.0)
		var e2 := (1.0 if t > 0.12 else 0.0) * minf(t2 / 0.004, 1.0) * exp(-t2 * 4.0)
		return 0.3 * (e1 * sin(TAU * 1046.5 * t) + e2 * sin(TAU * 1568.0 * t) + 0.2 * e2 * sin(TAU * 3136.0 * t)))

	# « Pop » joyeux quand un mouton entre dans l'enclos
	_pop = _fabriquer(0.12, func(t: float, d: float) -> float:
		var env := minf(t / 0.003, 1.0) * exp(-t * 35.0)
		var phase := TAU * (600.0 * t + 900.0 * t * t / (2.0 * d))
		return env * 0.4 * sin(phase))

	# Musique : les morceaux s'enchaînent, dans le désordre
	_musique = AudioStreamPlayer.new()
	_musique.volume_db = -9.0
	_musique.finished.connect(func() -> void:
		get_tree().create_timer(2.5, true).timeout.connect(_morceau_suivant))
	add_child(_musique)
	for nom in ["prairie", "brise", "crepuscule"]:
		var m: AudioStream = load("res://musique/%s.wav" % nom)
		if m:
			_morceaux.append(m)
	_morceaux.shuffle()


# ---------------------------------------------------------------- musique

func lancer_musique() -> void:
	if musique_active and not _musique.playing and not _morceaux.is_empty():
		_morceau_suivant()


func basculer_musique() -> bool:
	musique_active = not musique_active
	if musique_active:
		_musique.volume_db = -40.0
		_morceau_suivant()
		create_tween().tween_property(_musique, "volume_db", -9.0, 1.0)
	else:
		_musique.stop()
	return musique_active


func _morceau_suivant() -> void:
	if not musique_active or _morceaux.is_empty() or _musique.playing:
		return
	_numero = (_numero + 1) % _morceaux.size()
	_musique.stream = _morceaux[_numero]
	_musique.play()


func sifflet() -> void:
	_jouer(_sifflet, randf_range(0.97, 1.03))


func clic() -> void:
	_jouer(_clic, 1.0)


func defaite() -> void:
	_jouer(_defaite, 1.0)


func porte() -> void:
	_jouer(_porte, 1.0)


func pret() -> void:
	_jouer(_pret, 1.0)


## « Pop » qui monte avec la part du troupeau déjà rentrée (0 à 1)
func pop(part: float) -> void:
	_jouer(_pop, 0.85 + part * 0.6)


func choc() -> void:
	_jouer(_choc, randf_range(0.9, 1.1))


func vent() -> void:
	_jouer(_vent, 1.0)


## Petit bêlement aigu d'agneau
func bele_agneau() -> void:
	_jouer(_bele, randf_range(1.55, 1.75))


func bonus() -> void:
	_jouer(_bonus, 1.0)


## Ding dont la hauteur monte avec n (combo, étoiles).
func ding(n: int) -> void:
	_jouer(_ding, pow(2.0, minf(n, 12) / 12.0 * 1.0))


func grogne() -> void:
	_jouer(_grogne, randf_range(0.9, 1.05))


func glapit() -> void:
	_jouer(_glapit, randf_range(0.95, 1.1))

func aboie() -> void:
	_jouer(_aboi, randf_range(0.92, 1.08))


func bele() -> void:
	_jouer(_bele, randf_range(0.85, 1.2))


func victoire() -> void:
	_jouer(_victoire, 1.0)


func _jouer(son: AudioStream, hauteur: float) -> void:
	var l := _lecteurs[_suivant]
	_suivant = (_suivant + 1) % _lecteurs.size()
	l.stream = son
	l.pitch_scale = hauteur
	l.play()


func _fabriquer(duree: float, onde: Callable) -> AudioStreamWAV:
	var n := int(duree * TAUX)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / TAUX
		var v: float = clampf(onde.call(t, duree), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 30000.0))
	var son := AudioStreamWAV.new()
	son.format = AudioStreamWAV.FORMAT_16_BITS
	son.mix_rate = TAUX
	son.stereo = false
	son.data = data
	return son
