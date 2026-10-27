#!/usr/bin/env python3
"""Builds the encore website into website/public: one page per language, plus /download.

python3 website/build.py            then  python3 -m http.server -d website/public 8000
The copy follows encore-launch/brand/BRAND.md: slams in capitals without final period, tutoiement in French.
"""
import html, shutil
from pathlib import Path
from string import Template

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "public"
SITE = "https://kamasoutra.github.io/encore/"
REPO = "https://github.com/Kamasoutra/encore"
ZIP = REPO + "/releases/latest/download/Encore-macOS.zip"
BREW = "brew install --cask kamasoutra/tap/encore"

STRINGS = {
    "en": {
        "title": "encore, the clipboard your Mac should have shipped with",
        "description": "Free and open-source clipboard manager for macOS. Everything you copy, back in a keystroke. Local only, no account, no subscription.",
        "hook": ["You copied a link", "Then a quote", "The link?", "Gone", "Not anymore"],
        "lead": "encore keeps everything you copy on your Mac and gives it back in a keystroke. Free, open source, and nothing leaves your machine.",
        "download": "Download for Mac",
        "requirements": "For macOS 12 and later, on Apple Silicon and Intel.",
        "brew": "Or with Homebrew",
        "copy": "Copy", "copied": "Copied",
        "sound_on": "Turn sound on", "sound_off": "Mute",
        "video": "The encore launch video",
        "steps": [
            ("⇧⌘V", "Everything you copy", "Press ⇧⌘V in any app. Your recent copies slide up as cards you recognize at a glance: an image is an image, a color is a color. Return pastes it right where you were.", "shelf", "The encore shelf with text, image, PDF, link, color and code cards"),
            ("space", "Space to peek", "Not sure it’s the right one? Space opens a large preview above the card, for images, PDFs, rich text and code.", "preview", "A large preview of an image card"),
            ("↑", "Your whole history", "Press ↑ and the shelf grows into a full library: search, filters by type, app and date, and even the text inside your screenshots, recognized on your Mac. Hold ↓ to come back.", "library", "The encore library with filters, cards and a preview panel"),
        ],
        "types": ["Text", "Images", "Files", "Links", "Colors", "Code"],
        "macs": ["On all your Macs", "No cloud"],
        "macs_text": "Pair two Macs with a 6-digit code and browse each other’s recent history. The link is end-to-end encrypted and stays on your local network. No server, no account.",
        "details": [
            ("Retention you control", "Rules by size and type let heavy files go quickly and keep your snippets. Every card shows how long it stays."),
            ("Native screenshots", "Screenshots you take with macOS land in your history, ready to paste."),
            ("Favorites and collections", "Keep addresses, templates and snippets forever, and drag cards into collections."),
            ("Private by default", "No account, no telemetry. Password managers are excluded, and content that apps mark as confidential is skipped."),
            ("Native, down to the details", "SwiftUI and AppKit, light and dark, 30 languages including right-to-left."),
            ("Updates itself", "Signed updates install straight from GitHub releases."),
        ],
        "promise": ["Free", "Open source", "No subscription"],
        "promise_text": "MIT licensed. The code is on GitHub, and every release is built in public by GitHub Actions.",
        "last": "The clipboard your Mac should have shipped with",
        "star": "★ Star it on GitHub",
        "note": "encore is not notarized yet. The first time, open it from System Settings → Privacy & Security → Open Anyway.",
        "releases": "Releases",
        "license": "MIT license",
    },
    "fr": {
        "title": "encore, le presse-papiers que ton Mac aurait dû avoir dès le départ",
        "description": "Gestionnaire de presse-papiers gratuit et open source pour macOS. Tout ce que tu copies, de retour en une touche. 100 % local, sans compte, sans abonnement.",
        "hook": ["Tu copies un lien", "Puis une citation", "Le lien ?", "Perdu", "Plus jamais"],
        "lead": "encore garde tout ce que tu copies sur ton Mac et te le rend en une touche. Gratuit, open source, et rien ne quitte ta machine.",
        "download": "Télécharger pour Mac",
        "requirements": "Pour macOS 12 et plus récent, sur Apple Silicon et Intel.",
        "brew": "Ou avec Homebrew",
        "copy": "Copier", "copied": "Copié",
        "sound_on": "Activer le son", "sound_off": "Couper le son",
        "video": "La vidéo de lancement d’encore",
        "steps": [
            ("⇧⌘V", "Tout ce que tu copies", "Appuie sur ⇧⌘V dans n’importe quelle app. Tes dernières copies apparaissent sous forme de cartes qu’on reconnaît d’un coup d’œil : une image est une image, une couleur est une couleur. Entrée, et c’est collé là où tu étais.", "shelf", "Le bandeau d’encore avec des cartes texte, image, PDF, lien, couleur et code"),
            ("espace", "Espace : aperçu", "Pas sûr que ce soit la bonne ? Espace ouvre un grand aperçu au-dessus de la carte : images, PDF, texte mis en forme, code.", "preview", "Le grand aperçu d’une carte image"),
            ("↑", "Tout ton historique", "Appuie sur ↑ et le bandeau devient une bibliothèque complète : recherche, filtres par type, app et date, et même le texte de tes captures d’écran, reconnu sur ton Mac. Maintiens ↓ pour revenir.", "library", "La bibliothèque d’encore avec ses filtres, ses cartes et le panneau d’aperçu"),
        ],
        "types": ["Texte", "Images", "Fichiers", "Liens", "Couleurs", "Code"],
        "macs": ["Sur tous tes Mac", "Sans cloud"],
        "macs_text": "Associe deux Mac avec un code à 6 chiffres et parcours l’historique récent de l’autre. La liaison est chiffrée de bout en bout et reste sur ton réseau local. Pas de serveur, pas de compte.",
        "details": [
            ("Une rétention à ta main", "Des règles par taille et par type : les gros fichiers partent vite, tes extraits restent. Chaque carte affiche combien de temps elle reste."),
            ("Les captures d’écran natives", "Les captures prises avec macOS arrivent dans ton historique, prêtes à coller."),
            ("Favoris et collections", "Garde adresses, modèles et extraits pour toujours, et range tes cartes dans des collections."),
            ("Privé par défaut", "Pas de compte, pas de télémétrie. Les gestionnaires de mots de passe sont exclus, et les contenus marqués confidentiels sont ignorés."),
            ("Natif jusque dans les détails", "SwiftUI et AppKit, clair et sombre, 30 langues, y compris de droite à gauche."),
            ("Se met à jour tout seul", "Les mises à jour, signées, s’installent directement depuis GitHub."),
        ],
        "promise": ["Gratuit", "Open source", "Sans abonnement"],
        "promise_text": "Licence MIT. Le code est sur GitHub, et chaque version est compilée publiquement par GitHub Actions.",
        "last": "Le presse-papiers que ton Mac aurait dû avoir dès le départ",
        "star": "★ Une étoile sur GitHub",
        "note": "encore n’est pas notarisé pour l’instant. La première fois, ouvre-le depuis Réglages Système → Confidentialité et sécurité → Ouvrir quand même.",
        "releases": "Versions",
        "license": "Licence MIT",
    },
}

PAGE = Template("""<!doctype html>
<html lang="$lang">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<meta name="description" content="$description">
<link rel="canonical" href="$url">
$alternates
<meta property="og:title" content="$title">
<meta property="og:description" content="$description">
<meta property="og:image" content="${site}media/$lang/poster.jpg">
<meta property="og:url" content="$url">
<meta name="twitter:card" content="summary_large_image">
<meta name="theme-color" content="#0D0919">
<link rel="icon" href="${base}media/icon.png">
<link rel="stylesheet" href="${base}style.css">
$detect
</head>
<body>
<header class="wrap bar">
  <a class="brand" href="${base}$home"><img src="${base}media/icon.png" alt="" width="34" height="34">encore</a>
  <nav>
    <span class="langs">$langs</span>
    <a class="hide-small" href="$repo">GitHub</a>
  </nav>
</header>
<main>
<section class="wrap hero">
  <h1 class="slam hook">$hook</h1>
  <p class="lead">$lead</p>
  <div class="get">
    <a class="button" href="$zip">$arrow$download</a>
    <p class="fine">$requirements</p>
    <p class="fine">$brew_label</p>
    <div class="brew"><code>$brew</code><button type="button" data-copy="$brew" data-done="$copied">$copy</button></div>
  </div>
  <div class="film">
    <video src="${base}media/$lang/encore.mp4" poster="${base}media/$lang/poster.jpg" autoplay muted loop playsinline preload="metadata" aria-label="$video"></video>
    <button class="sound" type="button" data-on="$sound_on" data-off="$sound_off">$sound_on</button>
  </div>
</section>
<section class="wrap steps">
$steps
</section>
<section class="wrap" aria-label="$types_label"><p class="slam types">$types</p></section>
<section class="wrap macs">
  <h2 class="slam">$macs</h2>
  <p>$macs_text</p>
</section>
<section class="wrap details">
$details
</section>
<section class="wrap">
  <p class="slam promise">$promise</p>
  <p class="fine">$promise_text</p>
</section>
<section class="wrap last">
  <img src="${base}media/icon.png" alt="" width="132" height="132" loading="lazy">
  <h2>$last</h2>
  <div class="get">
    <a class="button" href="$zip">$arrow$download</a>
    <a class="star" href="$repo">$star</a>
  </div>
  <p class="fine note">$note</p>
</section>
</main>
<footer class="wrap">
  <span>encore · $license</span>
  <nav><a href="$repo">GitHub</a><a href="$repo/releases">$releases</a></nav>
</footer>
<script src="${base}site.js"></script>
</body>
</html>
""")

ARROW = '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 3v11M5 9.5l5 5 5-5M4 17h12"/></svg>'

# Sends French-speaking visitors to /fr/ on their first visit, unless they picked a language.
DETECT = """<script>try{if(!localStorage.getItem("lang")&&/^fr\\b/i.test(navigator.language||""))location.replace("fr/")}catch(e){}</script>"""

DOWNLOAD = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Downloading encore</title>
<meta http-equiv="refresh" content="0; url={ZIP}">
<meta name="robots" content="noindex">
<link rel="stylesheet" href="../style.css">
<script>location.replace("{ZIP}")</script>
</head>
<body>
<main class="wrap hero">
  <h1 class="slam hook" style="font-size:clamp(40px,7vw,90px)"><span>Downloading encore</span></h1>
  <p class="lead">If nothing happens, <a href="{ZIP}">download the ZIP</a>. Le téléchargement ne démarre pas ? <a href="{ZIP}">Télécharge le ZIP</a>.</p>
</main>
</body>
</html>
"""


CURRENT = ' aria-current="page"'


def e(s):
    return html.escape(s, quote=True)


def build(lang, s):
    base = "" if lang == "en" else "../"
    url = SITE if lang == "en" else SITE + "fr/"
    hook = "".join(
        f'<span style="--i:{i}" class="{["", "", "quiet", "gone", "after"][i]}">{e(t)}</span>'
        for i, t in enumerate(s["hook"]))
    langs = "".join(
        f'<a href="{base}{"" if code == "en" else "fr/"}" hreflang="{code}" lang="{code}" data-lang="{code}"'
        f'{CURRENT if code == lang else ""}>{code.upper()}</a>'
        for code in ("en", "fr"))
    steps = []
    for key, title, text, shot, alt in s["steps"]:
        wide = shot == "library"
        image = f'<img src="{base}media/{lang}/{shot}.png" alt="{e(alt)}" loading="lazy">'
        if shot == "shelf":
            image = f'<div class="shelf">{image}</div>'
        steps.append(
            f'<article class="step{" wide" if wide else ""}">'
            f'<div class="copy"><kbd class="key">{e(key)}</kbd><h2 class="slam">{e(title)}</h2><p>{e(text)}</p></div>'
            f'<figure>{image}</figure></article>')
    return PAGE.substitute(
        lang=lang, base=base, url=url, site=SITE, repo=REPO, zip=ZIP, brew=e(BREW), arrow=ARROW,
        home="" if lang == "en" else "fr/",
        title=e(s["title"]), description=e(s["description"]),
        alternates="\n".join(f'<link rel="alternate" hreflang="{c}" href="{SITE}{"" if c == "en" else "fr/"}">' for c in ("en", "fr")),
        detect=DETECT if lang == "en" else "",
        langs=langs, hook=hook, lead=e(s["lead"]), download=e(s["download"]), requirements=e(s["requirements"]),
        brew_label=e(s["brew"]), copy=e(s["copy"]), copied=e(s["copied"]),
        sound_on=e(s["sound_on"]), sound_off=e(s["sound_off"]), video=e(s["video"]),
        steps="\n".join(steps),
        types_label=e(", ".join(s["types"])), types="".join(f"<span>{e(t)}</span>" for t in s["types"]),
        macs="".join(f"<span>{e(t)}</span>" for t in s["macs"]), macs_text=e(s["macs_text"]),
        details="\n".join(f"<div><h3>{e(t)}</h3><p>{e(d)}</p></div>" for t, d in s["details"]),
        promise="".join(f"<span>{e(t)}</span>" for t in s["promise"]), promise_text=e(s["promise_text"]),
        last=e(s["last"]), star=e(s["star"]), note=e(s["note"]), releases=e(s["releases"]), license=e(s["license"]),
    )


def main():
    shutil.rmtree(OUT, ignore_errors=True)
    (OUT / "fr").mkdir(parents=True)
    (OUT / "download").mkdir()
    for name in ("style.css", "site.js"):
        shutil.copy(ROOT / name, OUT / name)
    shutil.copytree(ROOT / "media", OUT / "media")
    (OUT / "index.html").write_text(build("en", STRINGS["en"]))
    (OUT / "fr" / "index.html").write_text(build("fr", STRINGS["fr"]))
    (OUT / "download" / "index.html").write_text(DOWNLOAD)
    (OUT / ".nojekyll").write_text("")
    print(OUT)


if __name__ == "__main__":
    main()
