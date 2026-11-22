# Fabrique les musiques « chill » de SheperdRun (style lo-fi doux) : python outils/musique.py
# Tout est synthétisé ici (aucun échantillon externe) puis écrit en WAV dans musique/.
# Chaque morceau : piano électrique feutré, kalimba, basse ronde, batterie très douce,
# nappe, léger craquement de vinyle et réverbération.
import os
import wave
import numpy as np

SR = 22050
DOSSIER = os.path.join(os.path.dirname(__file__), "..", "musique")


def freq(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def temps(d):
    return np.arange(int(d * SR)) / SR


def fondu(x, attaque=0.005, relache=0.08):
    n = len(x)
    a = min(n, int(attaque * SR))
    r = min(n, int(relache * SR))
    env = np.ones(n)
    if a > 0:
        env[:a] = np.linspace(0, 1, a)
    if r > 0:
        env[n - r:] *= np.linspace(1, 0, r)
    return x * env


# ---------------------------------------------------------------- instruments

def epiano(m, d, v):
    t = temps(d)
    f = freq(m)
    x = np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 1.004 * t)
    x += 0.22 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 3)
    x += 0.06 * np.sin(2 * np.pi * 7 * f * t) * np.exp(-t * 25)      # petit « tine »
    x *= np.exp(-t * 1.3) * (1 + 0.07 * np.sin(2 * np.pi * 4.2 * t))
    return fondu(x * v * 0.16, 0.004, 0.25)


def kalimba(m, d, v):
    t = temps(d)
    f = freq(m)
    x = np.sin(2 * np.pi * f * t) * np.exp(-t * 3.2)
    x += 0.25 * np.sin(2 * np.pi * 5.4 * f * t) * np.exp(-t * 22)
    x += 0.1 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 6)
    return fondu(x * v * 0.26, 0.002, 0.1)


def basse(m, d, v):
    t = temps(d)
    f = freq(m)
    x = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * 2 * f * t) + 0.08 * np.sin(2 * np.pi * 3 * f * t)
    x *= 0.75 + 0.25 * np.exp(-t * 4)
    return fondu(x * v * 0.22, 0.015, 0.12)


def nappe(m, d, v):
    t = temps(d)
    f = freq(m)
    x = sum(np.sin(2 * np.pi * f * k * t) / k ** 1.6 for k in (1, 2, 3)) + 0.6 * np.sin(2 * np.pi * f * 0.997 * t)
    return fondu(x * v * 0.035, min(1.2, d / 3), min(1.2, d / 3))


def grosse_caisse(v):
    t = temps(0.35)
    f = 45 + 70 * np.exp(-t * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t * 11) * v * 0.55


def caisse_claire(v, rng):
    t = temps(0.25)
    bruit = passe_bas(rng.uniform(-1, 1, len(t)), 9)
    return (bruit * np.exp(-t * 20) * 0.5 + 0.25 * np.sin(2 * np.pi * 190 * t) * np.exp(-t * 35)) * v * 0.35


def charleston(v, rng):
    t = temps(0.06)
    b = rng.uniform(-1, 1, len(t))
    b = np.diff(b, prepend=0)                 # bruit aigu
    return b * np.exp(-t * 70) * v * 0.09


# ---------------------------------------------------------------- effets

def passe_bas(x, taille):
    noyau = np.hanning(taille * 2 + 1)
    return np.convolve(x, noyau / noyau.sum(), mode="same")


def reverbe(x, duree=1.8, mix=0.25, rng=None):
    t = temps(duree)
    ir = rng.uniform(-1, 1, len(t)) * np.exp(-t * 3.2)
    ir = passe_bas(ir, 6)
    ir[0] = 0
    n = len(x) + len(ir)
    taille = 1 << (n - 1).bit_length()
    y = np.fft.irfft(np.fft.rfft(x, taille) * np.fft.rfft(ir, taille), taille)[:len(x)]
    y *= np.std(x) / max(np.std(y), 1e-9)
    return x * (1 - mix) + y * mix


def echo(x, retard, repetitions=3, gain=0.35):
    y = x.copy()
    d = int(retard * SR)
    for k in range(1, repetitions + 1):
        y[d * k:] += x[:len(x) - d * k] * gain ** k
    return y


# ---------------------------------------------------------------- composition

def morceau(nom, tempo, accords, basses, gamme, graine, swing=0.12):
    rng = np.random.default_rng(graine)
    noire = 60.0 / tempo
    mesure = 4 * noire
    nb = 16                                    # 16 mesures : intro 4, cœur 8, fin 4
    total = nb * mesure + 3.0
    pistes = {k: np.zeros(int(total * SR) + SR) for k in ("piano", "melo", "basse", "batt", "nappe")}

    def poser(piste, debut, son):
        i = int(max(0.0, debut) * SR)
        p = pistes[piste]
        fin = min(len(p), i + len(son))
        p[i:fin] += son[:fin - i]

    def humain():
        return rng.normal(0, 0.006)

    # motif de mélodie de 2 mesures, repris avec variations
    rythmes = [[0, 1, 1.5, 3], [0.5, 1.5, 2, 3.5], [0, 2, 2.5, 3], [1, 1.5, 2.5], [0, 0.5, 1.5, 3, 3.5]]
    motif = []
    deg = int(rng.integers(3, 6))
    for b in range(2):
        for pos in rythmes[int(rng.integers(len(rythmes)))]:
            deg = int(np.clip(deg + rng.choice([-2, -1, -1, 0, 1, 1, 2]), 0, len(gamme) - 1))
            motif.append((b, pos, deg))

    for k in range(nb):
        t0 = k * mesure
        acc = accords[k % len(accords)]
        racine = basses[k % len(basses)]
        coeur = 4 <= k < 14
        derniere = k == nb - 1

        # nappe tenue sur toute la mesure
        for m in acc[:3]:
            poser("nappe", t0, nappe(m, mesure + 0.6, 1.0))
        # piano électrique : accord égrené sur le 1er temps, rappel léger sur le « et » du 3
        for i, m in enumerate(acc):
            poser("piano", t0 + i * 0.018 + humain(), epiano(m, mesure * 0.9, 0.9))
        if not derniere and rng.random() < 0.7:
            for i, m in enumerate(acc[1:]):
                poser("piano", t0 + 2.5 * noire + i * 0.015 + humain(), epiano(m, mesure * 0.45, 0.45))

        if k >= 2 and not derniere:
            poser("basse", t0 + humain(), basse(racine + 12, noire * 1.8, 1.0))
            poser("basse", t0 + 2.5 * noire + humain(), basse(racine + 12 + (7 if rng.random() < 0.5 else 12), noire * 1.2, 0.7))

        if coeur:
            for temps_ in range(4):
                for demi in range(2):
                    pos = t0 + (temps_ + demi * (0.5 + swing)) * noire + humain()
                    poser("batt", pos, charleston(0.6 if demi else 1.0, rng))
            poser("batt", t0, grosse_caisse(1.0))
            poser("batt", t0 + 2.5 * noire + humain(), grosse_caisse(0.7))
            poser("batt", t0 + noire + humain(), caisse_claire(1.0, rng))
            poser("batt", t0 + 3 * noire + humain(), caisse_claire(1.0, rng))

        # mélodie : motif repris dès la mesure 3, un peu varié la 2e fois
        if 2 <= k < nb - 1:
            for (b, pos, d) in motif:
                if b != k % 2:
                    continue
                if k >= 10 and rng.random() < 0.3:
                    d = int(np.clip(d + rng.choice([-1, 1, 2]), 0, len(gamme) - 1))
                if rng.random() < 0.12:
                    continue          # une note qui respire
                p = pos + (swing if (pos * 2) % 2 == 1 else 0)
                poser("melo", t0 + p * noire + humain(), kalimba(gamme[d], noire * 1.5, 0.8 + rng.random() * 0.3))

    # fin : dernière note tenue
    poser("piano", (nb - 1) * mesure, epiano(accords[0][0] - 12, 3.0, 0.7))

    melo = echo(pistes["melo"], noire * 0.75, 3, 0.3)
    mix = pistes["piano"] + melo + pistes["basse"] + pistes["nappe"] + pistes["batt"] * 0.9
    mix = reverbe(mix, 1.8, 0.22, rng)
    mix = passe_bas(mix, 2)                                  # un peu feutré, façon cassette
    mix += passe_bas(rng.normal(0, 0.004, len(mix)), 3)      # souffle
    craque = np.zeros(len(mix))
    idx = rng.integers(0, len(mix), int(total * 6))
    craque[idx] = rng.uniform(-0.05, 0.05, len(idx))
    mix += passe_bas(craque, 1)
    mix = np.tanh(mix * 1.4) / 1.4                            # légère saturation chaude
    mix = mix[: int(total * SR)]
    mix *= 0.82 / np.max(np.abs(mix))
    mix[-int(1.5 * SR):] *= np.linspace(1, 0, int(1.5 * SR))
    ecrire(nom, mix)


def ecrire(nom, x):
    os.makedirs(DOSSIER, exist_ok=True)
    chemin = os.path.join(DOSSIER, nom + ".wav")
    with wave.open(chemin, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32000).astype("<i2").tobytes())
    print(chemin, "%.1f s" % (len(x) / SR))


# Prairie : Fa majeur, tranquille
morceau("prairie", 76,
        [[53, 57, 60, 64], [52, 55, 59, 62], [50, 53, 57, 60], [48, 52, 55, 59]],
        [41, 40, 38, 36], [65, 67, 69, 72, 74, 77, 79, 81], 11)
# Brise : Do majeur, un peu plus allant
morceau("brise", 82,
        [[48, 52, 55, 59], [45, 52, 55, 60], [53, 57, 60, 64], [50, 55, 59, 62]],
        [36, 33, 41, 43], [72, 74, 76, 79, 81, 84, 86, 88], 23)
# Crépuscule : La mineur, lent et doux
morceau("crepuscule", 68,
        [[57, 60, 64, 67], [50, 53, 57, 62], [55, 59, 62, 67], [52, 55, 60, 64]],
        [45, 38, 43, 36], [69, 72, 74, 76, 79, 81, 84, 86], 37)
