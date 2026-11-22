extends RigidBody2D
## Le chien berger : un corps physique plus lourd que les moutons (il peut les bousculer).
## Il suit la direction du joystick tactile (ou les flèches du clavier) et peut aboyer.

const RAYON := 16.0
const FORCE := 6800.0
const VITESSE_MAX := 440.0
const RECHARGE_ABOI := 1.2       # secondes entre deux aboiements
const PORTEE_ABOI := 260.0
const PUISSANCE_ABOI := 420.0
const DUREE_ONDE := 0.5

var direction := Vector2.ZERO    # donnée par le joystick (longueur 0 à 1)
var recharge := 0.0
var _regard := Vector2.UP
var _pas := 0.0
var _onde := 0.0


func _ready() -> void:
	gravity_scale = 0.0
	mass = 3.0
	linear_damp = 5.0
	lock_rotation = true
	can_sleep = false
	var matiere := PhysicsMaterial.new()
	matiere.bounce = 0.1
	matiere.friction = 0.2
	physics_material_override = matiere
	var forme := CollisionShape2D.new()
	var cercle := CircleShape2D.new()
	cercle.radius = RAYON
	forme.shape = cercle
	add_child(forme)


func _physics_process(delta: float) -> void:
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if dir == Vector2.ZERO:
		dir = direction.limit_length(1.0)
	apply_central_force(dir * FORCE)

	recharge = maxf(0.0, recharge - delta)
	_onde = maxf(0.0, _onde - delta)
	var v := linear_velocity
	if v.length() > 20.0:
		var r := _regard.lerp(v.normalized(), 0.25)
		if r.length() > 0.01:
			_regard = r.normalized()
	elif dir.length() > 0.1:
		_regard = _regard.lerp(dir.normalized(), 0.2).normalized()
	_pas += v.length() * delta
	queue_redraw()


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	state.linear_velocity = state.linear_velocity.limit_length(VITESSE_MAX)


## 0 juste après un aboiement, 1 quand il est de nouveau prêt.
func charge_aboi() -> float:
	return 1.0 - recharge / RECHARGE_ABOI


## Fait fuir les moutons proches. Renvoie false si le chien n'est pas encore prêt.
func aboyer(troupeau: Array) -> bool:
	if recharge > 0.0:
		return false
	recharge = RECHARGE_ABOI
	_onde = DUREE_ONDE
	for m in troupeau:
		if not is_instance_valid(m):
			continue
		var l: float = m.global_position.distance_to(global_position)
		if l < PORTEE_ABOI:
			m.effrayer(global_position, PUISSANCE_ABOI * (1.0 - l / PORTEE_ABOI) + 80.0)
	return true


func _draw() -> void:
	# Onde de l'aboiement
	if _onde > 0.0:
		var k := 1.0 - _onde / DUREE_ONDE
		var e := 1.0 - pow(1.0 - k, 3.0)
		draw_circle(Vector2.ZERO, PORTEE_ABOI * e, Color(1, 0.9, 0.6, 0.12 * (1.0 - k)))
		draw_arc(Vector2.ZERO, PORTEE_ABOI * e, 0.0, TAU, 72, Color(1, 1, 1, 0.85 * (1.0 - k)), 7.0 * (1.0 - k) + 1.0)
		draw_arc(Vector2.ZERO, PORTEE_ABOI * e * 0.7, 0.0, TAU, 56, Color(1, 1, 1, 0.5 * (1.0 - k)), 4.0)

	var vit := linear_velocity.length()
	var saut := absf(sin(_pas * 0.06)) * minf(vit / 400.0, 1.0) * 5.0
	draw_circle(Vector2(3, 6), RAYON + 3.0 - saut * 0.3, Color(0, 0, 0, 0.24))     # ombre

	# Le reste est dessiné tourné dans le sens de la course (+x = devant), étiré à pleine vitesse
	var etire := minf(vit / VITESSE_MAX, 1.0) * 0.15
	draw_set_transform(Vector2(0, -saut), _regard.angle(), Vector2(1.0 + etire, 1.0 - etire * 0.5))
	var noir := Color("1f1b19")
	var blanc := Color("f3efe8")
	var p := sin(_pas * 0.1) * 5.0
	# pattes
	for patte in [Vector2(8 + p, 9), Vector2(8 - p, -9), Vector2(-10 - p, 9), Vector2(-10 + p, -9)]:
		draw_circle(patte, 4.0, noir)
		draw_circle(patte + Vector2(2, 0), 2.2, blanc)
	# queue qui remue (plus vite quand il court)
	var remue := sin(Time.get_ticks_msec() * (0.02 + vit * 0.00005)) * 0.6
	var bout := Vector2(-17, 0) + Vector2.from_angle(PI + remue) * 15.0
	draw_line(Vector2(-15, 0), bout, noir, 6.0)
	draw_circle(bout, 3.5, blanc)
	# corps et collier blanc (façon border collie)
	draw_circle(Vector2(-7, 0), 11.0, noir)
	draw_circle(Vector2(4, 0), 11.0, noir)
	draw_circle(Vector2(9, 0), 8.0, blanc)
	draw_circle(Vector2(-4, -4), 4.0, Color(1, 1, 1, 0.08))
	# langue qui pend quand il court
	if vit > 200.0:
		draw_circle(Vector2(23, 5 + sin(_pas * 0.2)), 3.0, Color("e8657a"))
	# tête, oreilles qui battent, museau
	var o := sin(_pas * 0.12) * 2.0 if vit > 50.0 else 0.0
	draw_colored_polygon(PackedVector2Array([Vector2(10, -5), Vector2(12 - o, -14), Vector2(17, -5)]), noir)
	draw_colored_polygon(PackedVector2Array([Vector2(10, 5), Vector2(12 + o, 14), Vector2(17, 5)]), noir)
	draw_circle(Vector2(15, 0), 9.0, noir)
	draw_circle(Vector2(21, 0), 5.5, blanc)
	draw_circle(Vector2(25.5, 0), 2.4, noir)
	draw_circle(Vector2(17, -4), 1.7, Color.WHITE)
	draw_circle(Vector2(17, 4), 1.7, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
