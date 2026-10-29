#!/usr/bin/env python3
"""Builds the encore website into website/public: one page per language, plus /download.

python3 website/build.py            then  python3 -m http.server -d website/public 8000
The copy follows encore-launch/brand/BRAND.md: slams in capitals without final period, tutoiement in French.
"""
import html, shutil
from pathlib import Path
from string import Template

from features import FEATURES, RELEASES, changelog_main, features_main

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "public"
SITE = "https://kamasoutra.github.io/encore/"
REPO = "https://github.com/Kamasoutra/encore"
ZIP = REPO + "/releases/latest/download/Encore-macOS.zip"
BREW = "brew install --cask kamasoutra/tap/encore"
SPONSORS = "https://github.com/sponsors/Kamasoutra"

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
        "new_tag": "New in 0.6", "new": "A compact window, wherever you want it",
        "snippets": ["Snippets", "On every Mac"],
        "snippets_text": "Press ⌘S on any card: a name, a language (encore guesses it among 85) and tags. Placeholders like {{name}} ask for a value before pasting. Your snippets and favorites stay in step between your paired Macs.",
        "snippets_video": "Snippets in encore 0.5",
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
            ("Favorites and collections", "Keep addresses and templates forever, and drag cards into collections."),
            ("Private by default", "No account, no telemetry. Password managers are excluded, and content that apps mark as confidential is skipped."),
            ("Native, down to the details", "SwiftUI and AppKit, light and dark, 30 languages including right-to-left."),
            ("Updates itself", "Signed updates install straight from GitHub releases."),
        ],
        "promise": ["Free", "Open source", "No subscription"],
        "promise_text": "MIT licensed. The code is on GitHub, and every release is built in public by GitHub Actions.",
        "last": "The clipboard your Mac should have shipped with",
        "star": "★ Star it on GitHub",
        "back_title": "Like encore?",
        "back_text": "A star on GitHub helps other people find it, and your support helps it last.",
        "support": "Support encore",
        "note": "encore is not notarized yet. The first time, open it from System Settings → Privacy & Security → Open Anyway.",
        "releases": "Releases",
        "sponsor": "Sponsor",
        "privacy_nav": "Your data",
        "features_nav": "Features",
        "changelog_nav": "What's new",
        "trust": ["Stays on your Mac", "No account", "No telemetry", "Passwords left out"],
        "trust_ask": "Want to know more? Worried about your data, and whether it will last?",
        "trust_link": "We explain everything",
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
        "new_tag": "Nouveautés · 0.6", "new": "Une fenêtre compacte, où tu veux",
        "snippets": ["Snippets", "Sur tous tes Mac"],
        "snippets_text": "⌘S sur n’importe quelle carte : un nom, un langage (encore le devine parmi 85) et des tags. Les placeholders comme {{nom}} te demandent une valeur avant de coller. Tes snippets et tes favoris restent synchronisés entre tes Mac appairés.",
        "snippets_video": "Les snippets dans encore 0.5",
        "steps": [
            ("⇧⌘V", "Tout ce que tu copies", "Appuie sur ⇧⌘V dans n’importe quelle app. Tes dernières copies apparaissent sous forme de cartes qu’on reconnaît d’un coup d’œil : une image est une image, une couleur est une couleur. Entrée, et c’est collé là où tu étais.", "shelf", "Le bandeau d’encore avec des cartes texte, image, PDF, lien, couleur et code"),
            ("espace", "Espace : aperçu", "Pas sûr que ce soit la bonne ? Espace ouvre un grand aperçu au-dessus de la carte : images, PDF, texte mis en forme, code.", "preview", "Le grand aperçu d’une carte image"),
            ("↑", "Tout ton historique", "Appuie sur ↑ et le bandeau devient une bibliothèque complète : recherche, filtres par type, app et date, et même le texte de tes captures d’écran, reconnu sur ton Mac. Maintiens ↓ pour revenir.", "library", "La bibliothèque d’encore avec ses filtres, ses cartes et le panneau d’aperçu"),
        ],
        "types": ["Texte", "Images", "Fichiers", "Liens", "Couleurs", "Code"],
        "macs": ["Sur tous tes Mac", "Sans cloud"],
        "macs_text": "Associe deux Mac avec un code à 6 chiffres et parcours l’historique récent de l’autre. La liaison est chiffrée de bout en bout et reste sur ton réseau local. Pas de serveur, pas de compte.",
        "details": [
            ("Une rétention à ta main", "Des règles par taille et par type : les gros fichiers partent vite, tes snippets restent. Chaque carte affiche combien de temps elle reste."),
            ("Les captures d’écran natives", "Les captures prises avec macOS arrivent dans ton historique, prêtes à coller."),
            ("Favoris et collections", "Garde adresses et modèles pour toujours, et range tes cartes dans des collections."),
            ("Privé par défaut", "Pas de compte, pas de télémétrie. Les gestionnaires de mots de passe sont exclus, et les contenus marqués confidentiels sont ignorés."),
            ("Natif jusque dans les détails", "SwiftUI et AppKit, clair et sombre, 30 langues, y compris de droite à gauche."),
            ("Se met à jour tout seul", "Les mises à jour, signées, s’installent directement depuis GitHub."),
        ],
        "promise": ["Gratuit", "Open source", "Sans abonnement"],
        "promise_text": "Licence MIT. Le code est sur GitHub, et chaque version est compilée publiquement par GitHub Actions.",
        "last": "Le presse-papiers que ton Mac aurait dû avoir dès le départ",
        "star": "★ Soutiens-le sur GitHub",
        "back_title": "encore te plaît ?",
        "back_text": "Une étoile sur GitHub aide d’autres personnes à le trouver, et un don via GitHub Sponsors l’aide à durer.",
        "support": "Faire un don",
        "note": "encore n’est pas notarisé pour l’instant. La première fois, ouvre-le depuis Réglages Système → Confidentialité et sécurité → Ouvrir quand même.",
        "releases": "Versions",
        "sponsor": "Soutenir",
        "privacy_nav": "Tes données",
        "features_nav": "Fonctionnalités",
        "changelog_nav": "Nouveautés",
        "trust": ["Reste sur ton Mac", "Sans compte", "Sans télémétrie", "Mots de passe ignorés"],
        "trust_ask": "Tu veux en savoir plus ? Tu te préoccupes de tes données et de leur pérennité ?",
        "trust_link": "On t’explique tout",
        "license": "Licence MIT",
    },
}

SRC = REPO + "/blob/main/Sources/EncoreCore/"

# The data page, in trusted HTML and plain words. Every claim must match the code:
# check it again whenever storage, capture, sync or updates change.
PRIVACY = {
    "en": {
        "page_title": "Your data · encore",
        "description": "Where encore keeps what you copy, what it never keeps, why there is no server, what is not perfect yet, and why the project is built to last.",
        "title": "Your data stays yours",
        "lead": "encore sees everything you copy: messages, addresses, sometimes sensitive things. So here is, simply and without jargon, what it does with them, what it never does, and what is not perfect yet.",
        "facts": ["On your Mac", "No account", "No server", "No tracking", "Open source"],
        "map_title": "Where does your data go?",
        "map_lead": "Nowhere but your own Macs.",
        "map": {
            "mac": ("Your Mac", "Your history, favorites and snippets. One folder, that only you can open."),
            "other": ("Your other Mac", "Only if you pair it yourself.", "Local network · encrypted"),
            "github": ("GitHub", "Only to check for a new version.", "Signed updates"),
            "server": ("An encore server", "It does not exist. No account, no cloud, no statistics: there is nowhere to send your data."),
        },
        "blocks": [
            ("Everything stays on your Mac", [
                "What you copy is kept in a single folder on your Mac: <code>~/Library/Application Support/Encore/</code>. Only your macOS account can open it.",
                "No account to create, no usage statistics, no ads. encore does not even load the links you copy: it shows them as they are.",
                "Text inside your images is recognized by macOS itself, on your Mac. Nothing is sent anywhere to be analyzed.",
            ], None, ""),
            ("What encore never keeps", [
                "Password managers mark what they copy as confidential, and encore skips it. It also leaves out the password apps installed on your Mac: 1Password, Bitwarden, Dashlane, KeePassXC, Keychain Access and Passwords.",
                "Exclude any other app, like your bank or your work chat, in Settings → Privacy. And pause capture in one click from the menu bar.",
                "<small>Not every app marks its sensitive copies. When in doubt, exclude it.</small>",
            ], "privacy", "encore’s Privacy settings: confidential content ignored, text recognition on this Mac, password apps excluded"),
            ("You stay in control", [
                "By default a copy is kept 30 days, then deleted. You choose how long, and rules by size or type clean up sooner. Favorites and snippets stay as long as you keep them.",
                "Export your whole history, import it on another Mac, export your snippets to a readable file, open the folder, or clear the history, all from Settings → Data.",
                "To uninstall completely, delete the app, that folder and its settings file, <code>~/Library/Preferences/local.kama.Encore.plist</code>.",
            ], "data", "encore’s Data settings: retention, export and import, open the folder, clear the history"),
            ("Between your Macs, without a cloud", [
                "Sharing is off until you turn it on. To link two Macs, you pair them once: both screens show the same 6-digit code, and you confirm it matches. Nobody else can join.",
                "Then your Macs talk to each other directly on your local network, without going through the internet or any server. Everything is end-to-end encrypted.",
                "Copies from excluded apps, files and confidential content are never shared.",
                "<small>For the curious: Curve25519 key exchange, ChaCha20-Poly1305 encryption.</small>",
            ], "peers", "encore’s Other Macs settings: sharing and sync off by default, pairing with a 6-digit code"),
        ],
        "honest_title": "What is not perfect yet",
        "honest_lead": "I would rather tell you myself.",
        "honest": [
            "<strong>Your history is not encrypted on disk.</strong> It is protected by your macOS account, and by FileVault when it is on: check System Settings → Privacy & Security → FileVault. Software running under your account could read it, as with most clipboard managers. Encrypting it is on the list.",
            "<strong>encore is not notarized by Apple yet.</strong> To notarize an app, Apple asks for a developer membership at $99 a year. encore is a free personal project that earns me nothing, so until then the first launch needs “Open Anyway” in System Settings, once. If a small community gets behind it, that is the first thing its support will pay for: <a href='" + SPONSORS + "'>support encore on GitHub Sponsors</a>.",
            "<strong>There is just me behind encore.</strong> I build it in the evenings, alongside my day job and my family life. There is no team and no guaranteed support: I fix things as fast as those evenings allow, starting with anything that touches security or your data. That is also why everything is open: anyone can report a problem, propose a fix on GitHub, or contribute.",
        ],
        "project_title": "A project built to last",
        "project": [
            "encore is a personal project, built in the open. It is free: no subscription, no paid tier, no ads.",
            "All the code is public, under the MIT license. If I ever stop, encore keeps working on your Mac, and anyone can pick the code up.",
            "Your data is not locked in: it is stored in standard JSON files that any program can read, and you can export all of it.",
            "The code is written with the help of AI tools, openly: I decide, review and test every change, and I use encore every day. Automated tests run on every change, and every release is built in public by GitHub Actions.",
        ],
        "cta": ("A bug, a question, a doubt about security?", "I read every issue on GitHub. And if you want to help encore last, you can support it.", "Open an issue", "Support encore"),
        "check_title": "Check it yourself",
        "check_text": "Don’t take my word for it. These files hold what this page describes:",
        "check": [
            ("Storage.swift", "the folder and its permissions"),
            ("PasteboardCapture.swift", "the copies that are skipped"),
            ("PeerCrypto.swift", "the pairing code and the encryption between Macs"),
        ],
    },
    "fr": {
        "page_title": "Tes données · encore",
        "description": "Où encore garde ce que tu copies, ce qu’il ne garde jamais, pourquoi il n’y a aucun serveur, ce qui n’est pas encore parfait, et pourquoi le projet est fait pour durer.",
        "title": "Tes données restent chez toi",
        "lead": "encore voit tout ce que tu copies : des messages, des adresses, parfois des choses sensibles. Alors voici, simplement et sans jargon, ce qu’il en fait, ce qu’il n’en fait jamais, et ce qui n’est pas encore parfait.",
        "facts": ["Sur ton Mac", "Sans compte", "Sans serveur", "Sans pistage", "Open source"],
        "map_title": "Où vont tes données ?",
        "map_lead": "Nulle part ailleurs que sur tes propres Mac.",
        "map": {
            "mac": ("Ton Mac", "Ton historique, tes favoris et tes snippets. Un seul dossier, que toi seul peux ouvrir."),
            "other": ("Ton autre Mac", "Seulement si tu l’appaires toi-même.", "Réseau local · chiffré"),
            "github": ("GitHub", "Uniquement pour vérifier s’il y a une nouvelle version.", "Mises à jour signées"),
            "server": ("Un serveur encore", "Il n’existe pas. Pas de compte, pas de cloud, pas de statistiques : il n’y a nulle part où envoyer tes données."),
        },
        "blocks": [
            ("Tout reste sur ton Mac", [
                "Ce que tu copies est rangé dans un seul dossier de ton Mac : <code>~/Library/Application Support/Encore/</code>. Seule ta session macOS peut l’ouvrir.",
                "Pas de compte à créer, pas de statistiques d’utilisation, pas de publicité. encore ne charge même pas les liens que tu copies : il les affiche tels quels.",
                "Le texte de tes images est reconnu par macOS lui-même, sur ton Mac. Rien n’est envoyé ailleurs pour être analysé.",
            ], None, ""),
            ("Ce qu’encore ne garde jamais", [
                "Les gestionnaires de mots de passe signalent leurs copies comme confidentielles, et encore les ignore. Il écarte aussi d’office les apps de mots de passe installées sur ton Mac : 1Password, Bitwarden, Dashlane, KeePassXC, Trousseaux d’accès et Mots de passe.",
                "Exclus n’importe quelle autre app, ta banque ou ta messagerie pro par exemple, dans Réglages → Confidentialité. Et mets la capture en pause en un clic depuis la barre des menus.",
                "<small>Toutes les apps ne signalent pas leurs copies sensibles. Dans le doute, exclus-les.</small>",
            ], "privacy", "Les réglages Confidentialité d’encore : contenus confidentiels ignorés, reconnaissance du texte sur ce Mac, apps de mots de passe exclues"),
            ("Tu gardes la main", [
                "Par défaut, une copie est gardée 30 jours, puis effacée. Tu choisis la durée, et des règles par taille ou par type font le ménage plus tôt. Favoris et snippets restent tant que tu les gardes.",
                "Exporte tout ton historique, réimporte-le sur un autre Mac, exporte tes snippets dans un fichier lisible, ouvre le dossier ou vide l’historique, depuis Réglages → Données.",
                "Pour désinstaller complètement, supprime l’app, ce dossier et son fichier de réglages, <code>~/Library/Preferences/local.kama.Encore.plist</code>.",
            ], "data", "Les réglages Données d’encore : conservation, export et import, ouverture du dossier, effacement de l’historique"),
            ("Entre tes Mac, sans cloud", [
                "Le partage est désactivé tant que tu ne l’actives pas. Pour relier deux Mac, tu les appaires une seule fois : les deux écrans affichent le même code à 6 chiffres, et tu confirmes qu’ils correspondent. Personne d’autre ne peut s’inviter.",
                "Ensuite, tes Mac se parlent directement sur ton réseau local, sans passer par internet ni par un serveur. Tout est chiffré de bout en bout.",
                "Les copies des apps exclues, les fichiers et les contenus confidentiels ne sont jamais partagés.",
                "<small>Pour les curieux : échange de clés Curve25519, chiffrement ChaCha20-Poly1305.</small>",
            ], "peers", "Les réglages Autres Mac d’encore : partage et synchronisation désactivés par défaut, appairage avec un code à 6 chiffres"),
        ],
        "honest_title": "Ce qui n’est pas encore parfait",
        "honest_lead": "Je préfère te le dire moi-même.",
        "honest": [
            "<strong>Ton historique n’est pas chiffré sur le disque.</strong> Il est protégé par ta session macOS, et par FileVault s’il est activé : vérifie dans Réglages Système → Confidentialité et sécurité → FileVault. Un logiciel qui tourne sous ta session pourrait le lire, comme avec la plupart des gestionnaires de presse-papiers. Le chiffrer est sur la liste.",
            "<strong>encore n’est pas encore notarisé par Apple.</strong> Pour notariser une app, Apple demande un abonnement développeur à 99 $ par an. encore est un projet personnel et gratuit qui ne me rapporte rien : en attendant, il faut passer une fois par « Ouvrir quand même » dans les Réglages Système. Si une petite communauté se forme autour du projet, c’est la première chose que son soutien financera : <a href='" + SPONSORS + "'>soutenir encore sur GitHub Sponsors</a>.",
            "<strong>Derrière encore, il n’y a que moi.</strong> Je le développe le soir, à côté de mon travail et de ma vie de famille. Il n’y a ni équipe ni support garanti : je corrige aussi vite que ces soirées le permettent, en commençant par tout ce qui touche à la sécurité ou à tes données. C’est aussi pour ça que tout est ouvert : n’importe qui peut signaler un problème, proposer une correction sur GitHub ou contribuer.",
        ],
        "project_title": "Un projet fait pour durer",
        "project": [
            "encore est un projet personnel, construit en public. Il est gratuit : pas d’abonnement, pas de version payante, pas de publicité.",
            "Tout le code est public, sous licence MIT. Si je m’arrête un jour, encore continue de fonctionner sur ton Mac, et n’importe qui peut reprendre le code.",
            "Tes données ne sont pas prisonnières : elles sont rangées dans des fichiers JSON standard, lisibles par n’importe quel programme, et tu peux tout exporter.",
            "Le code est écrit avec l’aide d’outils d’IA, et c’est assumé : je décide, relis et teste chaque changement, et j’utilise encore tous les jours. Des tests automatiques tournent à chaque modification, et chaque version est compilée publiquement par GitHub Actions.",
        ],
        "cta": ("Un bug, une question, un doute sur la sécurité ?", "Je lis chaque issue sur GitHub. Et si tu veux aider encore à durer, tu peux le soutenir.", "Ouvrir une issue", "Soutenir encore"),
        "check_title": "Vérifie par toi-même",
        "check_text": "Ne me crois pas sur parole. Ces fichiers contiennent ce que décrit cette page :",
        "check": [
            ("Storage.swift", "le dossier et ses permissions"),
            ("PasteboardCapture.swift", "les copies ignorées"),
            ("PeerCrypto.swift", "le code d’appairage et le chiffrement entre Mac"),
        ],
    },
}

LAYOUT = Template("""<!doctype html>
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
<header class="top">
 <div class="wrap bar">
  <a class="brand" href="${base}$home"><img src="${base}media/icon.png" alt="" width="34" height="34">encore</a>
  <nav class="pages-nav">
    <a href="${base}${home}features/"$features_current>$features_nav</a>
    <a href="${base}${home}changelog/"$changelog_current>$changelog_nav</a>
    <a href="${base}${home}privacy/"$privacy_current>$privacy_nav</a>
  </nav>
  <div class="tools">
    <span class="langs">$langs</span>
    <a class="gh" href="$repo">GitHub</a>
    <a class="sponsor" href="$sponsors" aria-label="$sponsor"><span aria-hidden="true">♥</span><span class="label">$sponsor</span></a>
  </div>
 </div>
</header>
<main>
$main</main>
<footer class="wrap">
  <span>encore · $license</span>
  <nav><a href="${base}${home}features/">$features_nav</a><a href="${base}${home}changelog/">$changelog_nav</a><a href="$repo">GitHub</a><a href="$repo/releases">$releases</a><a class="sponsor" href="$sponsors"><span aria-hidden="true">♥</span>$sponsor</a></nav>
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

HOME = Template("""<section class="wrap hero">
  <a class="new" href="${base}${home}features/#compact"><b>$new_tag</b>$new<span aria-hidden="true">→</span></a>
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
<section class="wrap trust">
  <p class="slam">$trust</p>
  <p class="ask">$trust_ask</p>
  <a class="button" href="${base}${home}privacy/">$trust_link<span aria-hidden="true">→</span></a>
</section>
<section class="wrap snippets" id="snippets">
  <div><h2 class="slam">$snippets</h2><p>$snippets_text</p></div>
  <div class="film">
    <video src="${base}media/$lang/snippets.mp4" poster="${base}media/$lang/snippets.jpg" autoplay muted loop playsinline preload="metadata" aria-label="$snippets_video"></video>
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
  </div>
  <p class="fine note">$note</p>
  <div class="cta">
    <div><h3>$back_title</h3><p>$back_text</p></div>
    <a class="button ghost" href="$repo">$star</a>
    <a class="button" href="$sponsors"><span aria-hidden="true">♥</span>$support</a>
  </div>
</section>
""")


def e(s):
    return html.escape(s, quote=True)


def layout(lang, s, page, title, description, main):
    """Wraps a page body in the head, top bar and footer shared by every page; `page` is its path below the language root."""
    root = "" if lang == "en" else "fr/"
    base = "../" * (root + page).count("/")
    langs = "".join(
        f'<a href="{base}{"" if code == "en" else "fr/"}{page}" hreflang="{code}" lang="{code}" data-lang="{code}"'
        f'{CURRENT if code == lang else ""}>{code.upper()}</a>'
        for code in ("en", "fr"))
    return LAYOUT.substitute(
        lang=lang, base=base, url=SITE + root + page, site=SITE, repo=REPO, home=root,
        title=e(title), description=e(description),
        alternates="\n".join(f'<link rel="alternate" hreflang="{c}" href="{SITE}{"" if c == "en" else "fr/"}{page}">' for c in ("en", "fr")),
        detect=DETECT if lang == "en" and not page else "",
        langs=langs, privacy_nav=e(s["privacy_nav"]), privacy_current=CURRENT if page == "privacy/" else "",
        features_nav=e(s["features_nav"]), features_current=CURRENT if page == "features/" else "",
        changelog_nav=e(s["changelog_nav"]), changelog_current=CURRENT if page == "changelog/" else "",
        releases=e(s["releases"]), license=e(s["license"]),
        sponsor=e(s["sponsor"]), sponsors=SPONSORS, main=main,
    )


def build(lang, s):
    base = "" if lang == "en" else "../"
    hook = "".join(
        f'<span style="--i:{i}" class="{["", "", "quiet", "gone", "after"][i]}">{e(t)}</span>'
        for i, t in enumerate(s["hook"]))
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
    main = HOME.substitute(
        lang=lang, base=base, home="" if lang == "en" else "fr/", repo=REPO, zip=ZIP, brew=e(BREW), arrow=ARROW,
        hook=hook, lead=e(s["lead"]), download=e(s["download"]), requirements=e(s["requirements"]),
        brew_label=e(s["brew"]), copy=e(s["copy"]), copied=e(s["copied"]),
        sound_on=e(s["sound_on"]), sound_off=e(s["sound_off"]), video=e(s["video"]),
        steps="\n".join(steps), new=e(s["new"]), new_tag=e(s["new_tag"]),
        trust="".join(f"<span>{e(t)}</span>" for t in s["trust"]), trust_ask=e(s["trust_ask"]), trust_link=e(s["trust_link"]),
        snippets="".join(f"<span>{e(t)}</span>" for t in s["snippets"]), snippets_text=e(s["snippets_text"]), snippets_video=e(s["snippets_video"]),
        types_label=e(", ".join(s["types"])), types="".join(f"<span>{e(t)}</span>" for t in s["types"]),
        macs="".join(f"<span>{e(t)}</span>" for t in s["macs"]), macs_text=e(s["macs_text"]),
        details="\n".join(f"<div><h3>{e(t)}</h3><p>{e(d)}</p></div>" for t, d in s["details"]),
        promise="".join(f"<span>{e(t)}</span>" for t in s["promise"]), promise_text=e(s["promise_text"]),
        last=e(s["last"]), star=e(s["star"]), note=e(s["note"]),
        back_title=e(s["back_title"]), back_text=e(s["back_text"]), support=e(s["support"]), sponsors=SPONSORS,
    )
    return layout(lang, s, "", s["title"], s["description"], main)


def build_privacy(lang, s):
    """The data page. Its copy is trusted HTML, so it can hold paths and links."""
    p = PRIVACY[lang]
    base = "../" if lang == "en" else "../../"
    para = lambda x: f"<p>{x}</p>" if isinstance(x, str) else "<ul>" + "".join(f"<li>{i}</li>" for i in x) + "</ul>"
    m = p["map"]
    diagram = (
        f'<div class="map">'
        f'<div class="node other"><h3>{m["other"][0]}</h3><p>{m["other"][1]}</p></div>'
        f'<div class="link"><span>{m["other"][2]}</span></div>'
        f'<div class="node mac"><img src="{base}media/icon.png" alt="" width="64" height="64"><h3>{m["mac"][0]}</h3><p>{m["mac"][1]}</p></div>'
        f'<div class="link in"><span>{m["github"][2]}</span></div>'
        f'<div class="node github"><h3>{m["github"][0]}</h3><p>{m["github"][1]}</p></div>'
        f'<div class="node server"><h3><s>{m["server"][0]}</s></h3><p>{m["server"][1]}</p></div>'
        f'</div>')
    blocks = []
    for i, (title, body, shot, alt) in enumerate(p["blocks"]):
        figure = f'<figure><img src="{base}media/{lang}/settings-{shot}.png" alt="{e(alt)}" width="780" height="708" loading="lazy"></figure>' if shot else ""
        blocks.append(f'<section class="block{" flip" if i % 2 == 0 else ""}{"" if shot else " solo"}"><div><h2 class="slam">{title}</h2>{"".join(para(x) for x in body)}</div>{figure}</section>')
    check = "".join(f'<li><a href="{SRC}{f}"><code>{f}</code></a> {t}</li>' for f, t in p["check"])
    main = f"""<div class="wrap data">
<section class="intro">
  <h1 class="slam">{e(p["title"])}</h1>
  <p class="lead">{p["lead"]}</p>
  <p class="facts">{"".join(f"<span>{e(t)}</span>" for t in p["facts"])}</p>
</section>
<section class="where">
  <h2 class="slam">{p["map_title"]}</h2>
  <p class="sub">{p["map_lead"]}</p>
  {diagram}
</section>
{chr(10).join(blocks)}
<section class="honest">
  <h2 class="slam">{p["honest_title"]}</h2>
  <p class="sub">{p["honest_lead"]}</p>
  <ul>{"".join(f"<li>{x}</li>" for x in p["honest"])}</ul>
</section>
<section class="project">
  <h2 class="slam">{p["project_title"]}</h2>
  {"".join(para(x) for x in p["project"])}
  <div class="cta">
    <div><h3>{p["cta"][0]}</h3><p>{p["cta"][1]}</p></div>
    <a class="button ghost" href="{REPO}/issues">{p["cta"][2]}</a>
    <a class="button" href="{SPONSORS}"><span aria-hidden="true">♥</span>{p["cta"][3]}</a>
  </div>
</section>
<section class="check">
  <h2 class="slam">{p["check_title"]}</h2>
  <p>{p["check_text"]}</p>
  <ul>{check}</ul>
</section>
</div>
"""
    return layout(lang, s, "privacy/", p["page_title"], p["description"], main)


def build_features(lang, s):
    f = FEATURES[lang]
    base = "../" if lang == "en" else "../../"
    return layout(lang, s, "features/", f["page_title"], f["description"], features_main(lang, base, "" if lang == "en" else "fr/"))


def build_changelog(lang, s):
    r = RELEASES[lang]
    base = "../" if lang == "en" else "../../"
    return layout(lang, s, "changelog/", r["page_title"], r["description"], changelog_main(lang, base, REPO))


def main():
    shutil.rmtree(OUT, ignore_errors=True)
    (OUT / "fr").mkdir(parents=True)
    (OUT / "download").mkdir()
    for name in ("style.css", "site.js"):
        shutil.copy(ROOT / name, OUT / name)
    shutil.copytree(ROOT / "media", OUT / "media")
    (OUT / "index.html").write_text(build("en", STRINGS["en"]))
    (OUT / "fr" / "index.html").write_text(build("fr", STRINGS["fr"]))
    for lang, folder in (("en", OUT), ("fr", OUT / "fr")):
        for page, builder in (("privacy", build_privacy), ("features", build_features), ("changelog", build_changelog)):
            (folder / page).mkdir()
            (folder / page / "index.html").write_text(builder(lang, STRINGS[lang]))
    (OUT / "download" / "index.html").write_text(DOWNLOAD)
    (OUT / ".nojekyll").write_text("")
    print(OUT)


if __name__ == "__main__":
    main()
