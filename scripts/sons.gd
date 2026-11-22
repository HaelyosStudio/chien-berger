extends Node
## Petits sons fabriqués par le code (aucun fichier audio) : aboiement, bêlement, victoire.

const TAUX := 22050

var _aboi: AudioStreamWAV
var _bele: AudioStreamWAV
var _victoire: AudioStreamWAV
var _lecteurs: Array[AudioStreamPlayer] = []
var _suivant := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 4:
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
