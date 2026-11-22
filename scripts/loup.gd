extends RigidBody2D
## Le loup (à partir du niveau 4) : il sort d'un bord du pré, fonce vers le troupeau et le disperse.
## Il ne mange personne : le chien le chasse en aboyant près de lui ou en lui fonçant dessus.
## Chassé, il s'enfuit, disparaît, puis peut revenir plus tard.

signal chasse                    # le chien vient de le faire fuir

const RAYON := 17.0
const FORCE_APPROCHE := 2600.0
const FORCE_FUITE := 5200.0

var cible := Vector2.ZERO        # centre du troupeau (mis à jour par main.gd)
var sortie := Vector2.ZERO       # point du bord par où il s'enfuit
var en_fuite := false
var _regard := Vector2.DOWN
var _pas := 0.0
var _vie_fuite := 0.0


func _ready() -> void:
	gravity_scale = 0.0
	mass = 2.5
	linear_damp = 4.0
	lock_rotation = true
	can_sleep = false
	var forme := CollisionShape2D.new()
	var cercle := CircleShape2D.new()
	cercle.radius = RAYON
	forme.shape = cercle
	add_child(forme)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.6)


## Est-il dangereux en ce moment ? (lu par les moutons via main.gd)
func actif() -> bool:
	return not en_fuite and modulate.a > 0.5


func chasser() -> void:
	if en_fuite:
		return
	en_fuite = true
	_vie_fuite = 3.0
	chasse.emit()


func _physics_process(delta: float) -> void:
	var dir := Vector2.ZERO
	if en_fuite:
		dir = (sortie - global_position).normalized()
		apply_central_force(dir * FORCE_FUITE)
		_vie_fuite -= delta
		modulate.a = clampf(_vie_fuite / 1.2, 0.0, 1.0)
		if _vie_fuite <= 0.0:
			queue_free()
	else:
		var d := cible - global_position
		dir = d.normalized()
		# rôde : avance vers le troupeau en zigzaguant un peu
		dir = dir.rotated(sin(Time.get_ticks_msec() * 0.002) * 0.5)
		apply_central_force(dir * FORCE_APPROCHE)
	var v := linear_velocity
	if v.length() > 20.0:
		_regard = _regard.lerp(v.normalized(), 0.2).normalized()
	_pas += v.length() * delta
	queue_redraw()


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	state.linear_velocity = state.linear_velocity.limit_length(420.0 if en_fuite else 210.0)


func _draw() -> void:
	draw_circle(Vector2(3, 6), RAYON + 3.0, Color(0, 0, 0, 0.25))
	draw_set_transform(Vector2.ZERO, _regard.angle(), Vector2.ONE)
	var gris := Color("6e6a66")
	var fonce := Color("4a4643")
	var clair := Color("b9b2a8")
	var p := sin(_pas * 0.1) * 5.0
	for patte in [Vector2(9 + p, 10), Vector2(9 - p, -10), Vector2(-11 - p, 10), Vector2(-11 + p, -10)]:
		draw_circle(patte, 4.5, fonce)
	# queue touffue, basse
	var q := Vector2(-20, 0) + Vector2.from_angle(PI + sin(_pas * 0.08) * 0.3) * 14.0
	draw_line(Vector2(-16, 0), q, gris, 9.0)
	draw_circle(q, 5.0, fonce)
	# corps
	draw_circle(Vector2(-8, 0), 12.0, gris)
	draw_circle(Vector2(4, 0), 12.0, gris)
	draw_circle(Vector2(-4, 0), 7.0, fonce)            # dos plus sombre
	draw_circle(Vector2(8, 0), 7.0, clair)              # poitrail clair
	# tête, oreilles pointues, museau long
	draw_colored_polygon(PackedVector2Array([Vector2(11, -5), Vector2(13, -16), Vector2(19, -6)]), fonce)
	draw_colored_polygon(PackedVector2Array([Vector2(11, 5), Vector2(13, 16), Vector2(19, 6)]), fonce)
	draw_circle(Vector2(16, 0), 9.5, gris)
	draw_colored_polygon(PackedVector2Array([Vector2(20, -5), Vector2(31, 0), Vector2(20, 5)]), clair)
	draw_circle(Vector2(30, 0), 2.6, Color("1a1817"))
	# yeux jaunes (plissés quand il fuit)
	var oeil := Color("ffd23f")
	if en_fuite:
		draw_line(Vector2(17, -6), Vector2(20, -3), oeil, 2.0)
		draw_line(Vector2(17, 6), Vector2(20, 3), oeil, 2.0)
	else:
		draw_circle(Vector2(19, -4), 2.2, oeil)
		draw_circle(Vector2(19, 4), 2.2, oeil)
		draw_circle(Vector2(19.8, -4), 1.0, Color.BLACK)
		draw_circle(Vector2(19.8, 4), 1.0, Color.BLACK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
