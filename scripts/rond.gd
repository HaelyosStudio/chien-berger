extends RefCounted
## Disques rapides : au lieu de draw_circle (un polygone de dizaines de sommets, impossible à regrouper),
## on dessine une seule et même petite texture ronde (2 triangles), teintée et étirée.
## Comme tous les disques partagent cette texture, la carte graphique les envoie en quelques paquets
## au lieu de milliers d'appels : indispensable sur les téléphones modestes.

const TAILLE := 128

static var _texture: Texture2D


static func texture() -> Texture2D:
	if _texture == null:
		var img := Image.create(TAILLE, TAILLE, true, Image.FORMAT_RGBA8)
		var c := TAILLE / 2.0
		for y in TAILLE:
			for x in TAILLE:
				var d := Vector2(x + 0.5 - c, y + 0.5 - c).length()
				var a := clampf(c - d, 0.0, 1.0)      # bord lissé sur un pixel
				img.set_pixel(x, y, Color(1, 1, 1, a))
		img.generate_mipmaps()
		_texture = ImageTexture.create_from_image(img)
	return _texture


## Disque plein de centre p et de rayon r, de couleur c, dessiné sur ci.
static func cercle(ci: CanvasItem, p: Vector2, r: float, c: Color) -> void:
	ci.draw_texture_rect(texture(), Rect2(p.x - r, p.y - r, r * 2.0, r * 2.0), false, c)
