extends Node
## Autoload « MiseAJour », chargé AVANT le jeu.
## 1. Au démarrage (_init) : si une mise à jour a déjà été téléchargée (user://maj/), elle remplace
##    le contenu du jeu avant que la scène principale ne soit chargée.
## 2. Ensuite (_ready) : lit le manifeste publié sur GitHub (dernière « release ») ; si une version plus
##    récente existe, télécharge son paquet .pck, vérifie son empreinte SHA-256 et le garde pour le
##    prochain lancement.
## Limites : une mise à jour ne peut changer ni ce script, ni la liste des autoloads, ni les réglages
## Android (icône, nom, permissions) : dans ces cas-là, il faut réinstaller l'APK.

signal prete(version: String)    # une mise à jour est téléchargée, elle s'appliquera au prochain lancement

const DOSSIER := "user://maj/"
const INFO := DOSSIER + "version.json"

var build := 0                   # numéro de version réellement utilisé (APK ou mise à jour appliquée)
var version := ""
var maj_prete := ""              # version téléchargée, en attente du prochain lancement


func _init() -> void:
	build = int(ProjectSettings.get_setting("application/config/build", 0))
	version = str(ProjectSettings.get_setting("application/config/version", "?"))
	if "--maj-test" in OS.get_cmdline_user_args():
		build = 0                # test : on fait comme si le jeu était très ancien
	if OS.has_feature("editor") and not _force():
		return                   # en développement, on joue toujours le code du projet
	var info := _lire_info()
	if info.is_empty():
		return
	var pck := DOSSIER + str(info.get("fichier", ""))
	_nettoyer(str(info.get("fichier", "")))
	if int(info.get("build", 0)) <= build or str(info.get("engine", "")) != _moteur() or not FileAccess.file_exists(pck):
		return                   # l'APK installé est aussi récent (ou la mise à jour ne convient pas)
	if ProjectSettings.load_resource_pack(pck, true):
		build = int(info.build)
		version = str(info.get("version", version))
		print("SheperdRun : mise à jour %s appliquée (build %d)." % [version, build])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if (OS.has_feature("editor") and not _force()) or "--demo" in OS.get_cmdline_user_args():
		return
	var url := str(ProjectSettings.get_setting("application/config/maj_manifeste", ""))
	if url != "":
		_verifier(url)


func _force() -> bool:
	return "--force-maj" in OS.get_cmdline_user_args() or "--maj-test" in OS.get_cmdline_user_args()


func _moteur() -> String:
	var v := Engine.get_version_info()
	return "%d.%d.%d" % [v.major, v.minor, v.patch]


func _lire_info() -> Dictionary:
	if not FileAccess.file_exists(INFO):
		return {}
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(INFO))
	return info if typeof(info) == TYPE_DICTIONARY else {}


## Supprime les anciens paquets (on garde seulement celui en service).
func _nettoyer(garder: String) -> void:
	var d := DirAccess.open(DOSSIER)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".pck") and f != garder:
			d.remove(f)


func _verifier(url: String) -> void:
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	http.request_completed.connect(func(resultat: int, code: int, _entetes: PackedStringArray, corps: PackedByteArray) -> void:
		http.queue_free()
		if resultat != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var m: Variant = JSON.parse_string(corps.get_string_from_utf8())
		if typeof(m) != TYPE_DICTIONARY:
			return
		if int(m.get("build", 0)) <= build or str(m.get("engine", "")) != _moteur():
			return
		var deja := _lire_info()
		if int(deja.get("build", 0)) == int(m.build) and FileAccess.file_exists(DOSSIER + str(deja.get("fichier", ""))):
			maj_prete = str(m.get("version", "?"))       # déjà téléchargée, s'appliquera au prochain lancement
			prete.emit(maj_prete)
			return
		_telecharger(m))
	if http.request(url) != OK:
		http.queue_free()


func _telecharger(m: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(DOSSIER)
	var fichier := "jeu_%d.pck" % int(m.build)
	var tmp := DOSSIER + fichier + ".part"
	var http := HTTPRequest.new()
	http.timeout = 300.0
	http.download_file = tmp
	add_child(http)
	http.request_completed.connect(func(resultat: int, code: int, _entetes: PackedStringArray, _corps: PackedByteArray) -> void:
		http.queue_free()
		if resultat != HTTPRequest.RESULT_SUCCESS or code != 200 \
				or FileAccess.get_sha256(tmp) != str(m.get("sha256", "")).to_lower():
			DirAccess.remove_absolute(tmp)              # téléchargement raté ou fichier abîmé : on réessaiera
			return
		DirAccess.rename_absolute(tmp, DOSSIER + fichier)
		var f := FileAccess.open(INFO, FileAccess.WRITE)
		f.store_string(JSON.stringify({"build": int(m.build), "version": str(m.get("version", "?")),
			"engine": str(m.engine), "fichier": fichier}))
		f.close()
		maj_prete = str(m.get("version", "?"))
		prete.emit(maj_prete))
	if http.request(str(m.get("pck", ""))) != OK:
		http.queue_free()
