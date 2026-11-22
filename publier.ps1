# Publie une nouvelle version de Chien Berger sur GitHub (mise à jour automatique des téléphones).
# Usage :  powershell -ExecutionPolicy Bypass -File publier.ps1 -Notes "Ce qui a changé"
#          (option -Version 0.4.0 pour choisir le numéro ; sinon le dernier chiffre augmente : 0.3.0 -> 0.3.1)
#          (option -SansIncrement pour republier la version actuelle telle quelle)
# Étapes : numéro de version +1, export du paquet .pck et de l'APK, manifest.json, commit + release GitHub.
param(
	[string]$Notes = "Améliorations du jeu.",
	[string]$Version = "",
	[switch]$SansIncrement
)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
[Environment]::CurrentDirectory = $PSScriptRoot   # pour les fonctions .NET (chemins relatifs)
$godot = "D:\Dev\Godot\Godot_v4.7.2-stable_win64_console.exe"
$depot = "HaelyosStudio/chien-berger"
$utf8 = New-Object Text.UTF8Encoding $false

# 1. Numéro de version (build entier qui augmente toujours + version affichée x.y.z)
$projet = [IO.File]::ReadAllText("project.godot")
$build = [int]([regex]::Match($projet, 'config/build=(\d+)').Groups[1].Value)
$version = [regex]::Match($projet, 'config/version="([^"]+)"').Groups[1].Value
if (-not $SansIncrement) {
	$build += 1
	if ($Version -ne "") {
		$version = $Version
	} else {
		$p = $version.Split(".")
		while ($p.Count -lt 3) { $p += "0" }
		$version = "$($p[0]).$($p[1]).$([int]$p[2] + 1)"
	}
	$projet = [regex]::Replace($projet, 'config/build=\d+', "config/build=$build")
	$projet = [regex]::Replace($projet, 'config/version="[^"]+"', "config/version=`"$version`"")
	[IO.File]::WriteAllText("project.godot", $projet, $utf8)
	$presets = [IO.File]::ReadAllText("export_presets.cfg")
	$presets = [regex]::Replace($presets, 'version/code=\d+', "version/code=$build")
	$presets = [regex]::Replace($presets, 'version/name="[^"]+"', "version/name=`"$version`"")
	[IO.File]::WriteAllText("export_presets.cfg", $presets, $utf8)
}
Write-Host "Version $version (build $build)"

# 2. Exports : paquet de mise à jour + APK complet (pour une première installation)
New-Item -ItemType Directory -Force build | Out-Null
& $godot --headless --path . --export-pack "Android" build/chien-berger.pck 2>&1 | Out-Null
& $godot --headless --path . --export-debug "Android" build/ChienBerger.apk 2>&1 | Out-Null
if (-not (Test-Path build/chien-berger.pck) -or -not (Test-Path build/ChienBerger.apk)) { throw "Export raté." }

# 3. Manifeste lu par les téléphones
$sha = (Get-FileHash build/chien-berger.pck -Algorithm SHA256).Hash.ToLower()
$v = & $godot --headless --version
$moteur = ([regex]::Match($v, '^(\d+\.\d+)(\.\d+)?')).Value
if ($moteur.Split(".").Count -eq 2) { $moteur += ".0" }
$manifeste = [ordered]@{
	build   = $build
	version = $version
	engine  = $moteur
	pck     = "https://github.com/$depot/releases/download/v$version/chien-berger.pck"
	sha256  = $sha
	notes   = $Notes
}
[IO.File]::WriteAllText("build/manifest.json", ($manifeste | ConvertTo-Json), $utf8)

# 4. Sauvegarde du code puis release GitHub (la dernière release = celle que lisent les téléphones)
git add -A
git commit -m "Version $version : $Notes" | Out-Null
git push origin main
gh release create "v$version" build/chien-berger.pck build/manifest.json build/ChienBerger.apk --repo $depot --title "Chien Berger $version" --notes $Notes --latest
Write-Host "Publié : Chien Berger $version (build $build)."
