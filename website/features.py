"""The features and changelog pages. Their copy is trusted HTML, so it can hold <kbd> and links.

Features are ordered by how much they matter to someone discovering encore, not by release.
Each one says the version it arrived in: check it against `git tag --contains` when adding one.
"""

from html import escape

LATEST = "0.6.0"

# (key, version, media, title, text): media is an image or video in media/<lang>/, or None for the cards at the end.
FEATURES = {
    "en": {
        "page_title": "Features · encore",
        "description": "Everything encore does: the shelf, the library, snippets, the compact window, your other Macs, and the details.",
        "title": "Everything encore does",
        "lead": "A clipboard manager is a small thing you use a hundred times a day. Here is all of it, the big ideas first, each with the version that brought it.",
        "since": "Since {}",
        "new": "New",
        "more_title": "And the details",
        "changelog": "See every version",
        "items": [
            ("shelf", "0.2", "shelf.png", "Your clipboard, one shortcut away",
             "Press <kbd>⇧⌘V</kbd> wherever you type: your latest copies line up in a shelf at the bottom of the screen. Each card shows what it holds, the text, the image, the page of a PDF, the color, the code, and the app it came from. Pick one with the arrows, press <kbd>↩</kbd>, and it is pasted right where you were. <kbd>⌘1</kbd> to <kbd>⌘9</kbd> paste the first nine without moving."),
            ("library", "0.3", "library.png", "A library when you need to dig",
             "Press <kbd>↑</kbd> and the shelf grows into a full library: every copy grouped by day, filters by type, app and date, and a large preview with when it was first and last copied. Start typing to search, even the text inside your images, recognized on your Mac. Hold <kbd>↓</kbd> to come back."),
            ("snippets", "0.5", "snippets.mp4", "Snippets, ready when you are",
             "Press <kbd>⌘S</kbd> on any card to make it a snippet: a name, a language among 85, guessed for you with the icons you know from VS Code, and tags. Snippets have their own board and never expire. Write <code>{{name}}</code> and encore asks for the value before pasting; <code>{{clipboard}}</code>, <code>{{date}}</code> and <code>{{cursor}}</code> fill in by themselves."),
            ("compact", "0.6.0", "compact.png", "A compact window, wherever you want it",
             "Prefer something smaller than the shelf? The compact window lists your latest copies in a narrow panel. Drag it anywhere: it is drawn to the corners, the middle of each edge and the center, and opens at the same spot next time, even on another screen. Choose how many copies it shows, from 3 to 10, scroll with the arrows, and press <kbd>↑</kbd> on the first one to open the library."),
            ("macs", "0.4", "settings-peers.png", "Your other Macs, without a cloud",
             "Pair two Macs on the same network with a 6-digit code, and each one appears as a tab: browse the other Mac's recent copies and paste them as if they were yours. Since 0.5, favorites and snippets can stay in step between your Macs. The connection is end-to-end encrypted, keys stay on each Mac, and there is no server or account."),
            ("privacy", "0.2", "settings-privacy.png", "Private by design",
             "Everything stays on your Mac: no account, no telemetry, no link loaded behind your back. Password managers are left out, and content that apps mark as confidential is never recorded. <a href='{privacy}'>Read how your data is handled, in plain words</a>."),
            ("preview", "0.4", "preview.png", "See before you paste",
             "Press <kbd>Space</kbd> on a card for a large floating preview that follows your selection: long texts scroll, images and PDFs show in full, rich text keeps its layout."),
            ("shortcut", "0.6.0", "settings-general.png", "Your shortcut, your rules",
             "<kbd>⇧⌘V</kbd> taken by another app, or just not your habit? Click the shortcut in Settings and type your own. encore refuses the combinations that would break your apps, like <kbd>⌘V</kbd> alone, and <kbd>⌃⌥⌘V</kbd> always works as a fallback."),
            ("retention", "0.2", "settings-retention.png", "Keep what matters, drop the heavy stuff",
             "Retention rules by size and type clean up on their own: a 3 GB file for an hour, small texts forever. The first matching rule wins, every card tells you how long it stays, and you see what a change would remove before applying it. Favorites, snippets and collections are kept."),
            ("sounds", "0.2", "settings-sounds.png", "Quiet sounds, or yours",
             "A soft sound on copy and paste, so you know it worked without looking. Pick one of nine sets, preview each in one click, or use your own files and, since 0.6, the sounds that come with macOS."),
            ("data", "0.2", "settings-data.png", "Your data, yours to take",
             "Your history is stored in readable JSON files in one folder. Export all of it, import it on another Mac, export your snippets on their own, or clear the history while keeping favorites and collections."),
            ("keyboard", "0.2", "settings-shortcuts.png", "All from the keyboard",
             "Everything has a key: search, preview, favorite, rename, delete and undo, switch boards with <kbd>⌘←</kbd> <kbd>⌘→</kbd>, paste as plain text with <kbd>⇧↩</kbd>. Search understands <code>app:safari</code>, <code>type:image</code>, <code>tag:</code>, <code>lang:</code> and dates."),
            ("favorites", "0.2", None, "Favorites and collections",
             "Keep addresses, templates and answers forever, and drag cards into your own collections."),
            ("queue", "0.2", None, "A paste queue",
             "Line up several items, then paste them in order, one <kbd>⌘V</kbd> at a time."),
            ("paste-copy", "0.5", None, "Paste or copy",
             "A switch chooses what <kbd>↩</kbd> does: paste into the app, or put the card back on top, ready for <kbd>⌘V</kbd>."),
            ("rename", "0.5", None, "Rename in place",
             "<kbd>⌘R</kbd>, or a click on a card's header, gives it a name right on the card."),
            ("transforms", "0.2", None, "Clean before you paste",
             "Remove tracking from links, format JSON, and encode or decode Base64, without touching the original."),
            ("screenshots", "0.2", None, "Screenshots join in",
             "Turn it on, and new screenshots saved by macOS land in your history, ready to paste."),
            ("languages", "0.4", None, "30 languages",
             "With local formats, plurals and right-to-left layouts."),
            ("updates", "0.4", None, "Signed updates",
             "encore checks GitHub every hour and installs only updates signed with the project's key."),
            ("universal", "0.4.3", None, "Every recent Mac",
             "One app for Apple Silicon and Intel, from macOS 12 Monterey."),
        ],
    },
    "fr": {
        "page_title": "Fonctionnalités · encore",
        "description": "Tout ce que fait encore : le bandeau, la bibliothèque, les snippets, la fenêtre compacte, tes autres Mac, et les détails.",
        "title": "Tout ce que fait encore",
        "lead": "Un gestionnaire de presse-papiers, c’est un petit outil qu’on utilise cent fois par jour. Le voici en entier, les grandes idées d’abord, chacune avec la version qui l’a apportée.",
        "since": "Depuis la {}",
        "new": "Nouveau",
        "more_title": "Et les détails",
        "changelog": "Voir toutes les versions",
        "items": [
            ("shelf", "0.2", "shelf.png", "Ton presse-papiers, à un raccourci",
             "Appuie sur <kbd>⇧⌘V</kbd> où que tu écrives : tes dernières copies s’alignent dans un bandeau en bas de l’écran. Chaque carte montre ce qu’elle contient, le texte, l’image, la page d’un PDF, la couleur, le code, et l’app d’où elle vient. Choisis avec les flèches, appuie sur <kbd>↩</kbd>, et c’est collé là où tu étais. <kbd>⌘1</kbd> à <kbd>⌘9</kbd> collent les neuf premières sans bouger."),
            ("library", "0.3", "library.png", "Une bibliothèque pour fouiller",
             "Appuie sur <kbd>↑</kbd> et le bandeau devient une bibliothèque complète : toutes tes copies rangées par jour, des filtres par type, app et date, et un grand aperçu avec la date de première et de dernière copie. Tape pour chercher, jusque dans le texte de tes images, reconnu sur ton Mac. Maintiens <kbd>↓</kbd> pour revenir."),
            ("snippets", "0.5", "snippets.mp4", "Des snippets, prêts quand tu l’es",
             "Appuie sur <kbd>⌘S</kbd> sur n’importe quelle carte pour en faire un snippet : un nom, un langage parmi 85, deviné pour toi avec les icônes de VS Code, et des tags. Les snippets ont leur propre tableau et n’expirent jamais. Écris <code>{{nom}}</code> et encore te demande la valeur avant de coller ; <code>{{clipboard}}</code>, <code>{{date}}</code> et <code>{{cursor}}</code> se remplissent tout seuls."),
            ("compact", "0.6.0", "compact.png", "Une fenêtre compacte, où tu veux",
             "Tu préfères plus discret que le bandeau ? La fenêtre compacte liste tes dernières copies dans un panneau étroit. Déplace-la où tu veux : elle est attirée par les coins, le milieu de chaque bord et le centre, et se rouvre au même endroit, même sur un autre écran. Choisis combien de copies elle affiche, de 3 à 10, fais défiler avec les flèches, et appuie sur <kbd>↑</kbd> sur la première pour ouvrir la bibliothèque."),
            ("macs", "0.4", "settings-peers.png", "Tes autres Mac, sans cloud",
             "Appaire deux Mac du même réseau avec un code à 6 chiffres, et chacun apparaît dans un onglet : parcours les dernières copies de l’autre Mac et colle-les comme si c’étaient les tiennes. Depuis la 0.5, favoris et snippets peuvent rester synchronisés entre tes Mac. La connexion est chiffrée de bout en bout, les clés restent sur chaque Mac, et il n’y a ni serveur ni compte."),
            ("privacy", "0.2", "settings-privacy.png", "Privé par conception",
             "Tout reste sur ton Mac : pas de compte, pas de télémétrie, aucun lien chargé dans ton dos. Les gestionnaires de mots de passe sont écartés, et ce que les apps marquent comme confidentiel n’est jamais enregistré. <a href='{privacy}'>Lis comment tes données sont traitées, sans jargon</a>."),
            ("preview", "0.4", "preview.png", "Voir avant de coller",
             "Appuie sur <kbd>Espace</kbd> sur une carte pour un grand aperçu flottant qui suit ta sélection : les longs textes défilent, images et PDF s’affichent en entier, le texte enrichi garde sa mise en page."),
            ("shortcut", "0.6.0", "settings-general.png", "Ton raccourci, tes règles",
             "<kbd>⇧⌘V</kbd> déjà pris par une autre app, ou pas dans tes habitudes ? Clique sur le raccourci dans les Réglages et tape le tien. encore refuse les combinaisons qui casseraient tes apps, comme <kbd>⌘V</kbd> seul, et <kbd>⌃⌥⌘V</kbd> marche toujours en secours."),
            ("retention", "0.2", "settings-retention.png", "Garder l’utile, jeter le lourd",
             "Des règles de rétention par taille et par type font le ménage toutes seules : un fichier de 3 Go pendant une heure, les petits textes pour toujours. La première règle qui correspond l’emporte, chaque carte indique combien de temps elle reste, et tu vois ce qu’un changement supprimerait avant de l’appliquer. Favoris, snippets et collections sont gardés."),
            ("sounds", "0.2", "settings-sounds.png", "Des sons discrets, ou les tiens",
             "Un son léger à la copie et au collage, pour savoir que c’est fait sans regarder. Choisis parmi neuf jeux, écoute chacun en un clic, ou utilise tes propres fichiers et, depuis la 0.6, les sons fournis avec macOS."),
            ("data", "0.2", "settings-data.png", "Tes données, à emporter",
             "Ton historique est rangé dans des fichiers JSON lisibles, dans un seul dossier. Exporte tout, importe-le sur un autre Mac, exporte tes snippets à part, ou vide l’historique en gardant favoris et collections."),
            ("keyboard", "0.2", "settings-shortcuts.png", "Tout au clavier",
             "Chaque action a sa touche : chercher, prévisualiser, mettre en favori, renommer, supprimer et annuler, changer de panneau avec <kbd>⌘←</kbd> <kbd>⌘→</kbd>, coller en texte brut avec <kbd>⇧↩</kbd>. La recherche comprend <code>app:safari</code>, <code>type:image</code>, <code>tag:</code>, <code>lang:</code> et les dates."),
            ("favorites", "0.2", None, "Favoris et collections",
             "Garde pour toujours adresses, modèles et réponses, et glisse tes cartes dans tes propres collections."),
            ("queue", "0.2", None, "Une file de collage",
             "Prépare plusieurs éléments, puis colle-les dans l’ordre, un <kbd>⌘V</kbd> à la fois."),
            ("paste-copy", "0.5", None, "Coller ou copier",
             "Un interrupteur choisit ce que fait <kbd>↩</kbd> : coller dans l’app, ou remettre la carte en tête, prête pour <kbd>⌘V</kbd>."),
            ("rename", "0.5", None, "Renommer sur place",
             "<kbd>⌘R</kbd>, ou un clic sur l’en-tête d’une carte, lui donne un nom directement sur la carte."),
            ("transforms", "0.2", None, "Nettoyer avant de coller",
             "Retire le pistage des liens, formate du JSON, encode ou décode du Base64, sans toucher à l’original."),
            ("screenshots", "0.2", None, "Les captures d’écran s’invitent",
             "Active l’option, et les nouvelles captures enregistrées par macOS rejoignent ton historique, prêtes à coller."),
            ("languages", "0.4", None, "30 langues",
             "Avec les formats locaux, les pluriels et les mises en page de droite à gauche."),
            ("updates", "0.4", None, "Des mises à jour signées",
             "encore vérifie GitHub toutes les heures et n’installe que les mises à jour signées avec la clé du projet."),
            ("universal", "0.4.3", None, "Tous les Mac récents",
             "Une seule app pour Apple Silicon et Intel, dès macOS 12 Monterey."),
        ],
    },
}

# Newest first: (version, date, media or None, tagline, changes).
RELEASES = {
    "en": {
        "page_title": "What's new · encore",
        "description": "Every version of encore, what it added and fixed, with pictures.",
        "title": "What's new",
        "lead": "Every version of encore, newest first. Installed copies update themselves.",
        "versions": "Versions",
        "notes": "Release on GitHub",
        "items": [
            ("0.6.0", "2026-10-29", "compact.png", "A compact window, your own shortcut, and updates that arrive on their own.", [
                "<b>Compact window.</b> A small panel of your latest copies, instead of the shelf: move it anywhere, it is drawn to the corners, edges and center, and opens there next time. Choose 3 to 10 copies, scroll with the arrows, press <kbd>↑</kbd> on the first one for the library.",
                "<b>Your own shortcut.</b> Click it in Settings and type any combination, except those that would break your apps, like <kbd>⌘V</kbd> alone.",
                "<b>System sounds.</b> The custom sound set can use the sounds that come with macOS.",
                "<b>Updates that arrive.</b> encore checks every hour and, by default, installs updates as soon as none of its windows is open, then relaunches.",
                "A switch in the footer moves between the shelf and the compact window. <kbd>⌘←</kbd> <kbd>⌘→</kbd> is listed in the shelf and in Settings.",
                "The first letter typed into the search is no longer lost, and the volume slider is no longer cut off in Settings.",
                "A link to support encore on GitHub Sponsors, in Settings and in About.",
            ]),
            ("0.5.0", "2026-10-28", "snippets.jpg", "Snippets, and favorites that follow you from Mac to Mac.", [
                "<b>Snippets.</b> <kbd>⌘S</kbd> on any card gives it a name, a language among 85 and tags. Snippets get their own board and never expire.",
                "<b>Placeholders.</b> <code>{{name}}</code> asks for a value before pasting; <code>{{clipboard}}</code>, <code>{{date}}</code> and <code>{{cursor}}</code> fill in by themselves. Export and import snippets as JSON.",
                "<b>Rename in place.</b> <kbd>⌘R</kbd>, or a click on a card's header.",
                "<b>Paste or copy.</b> A switch chooses what <kbd>↩</kbd> and double-click do.",
                "<b>Sync with your paired Macs.</b> Favorites and snippets, each with its own setting, merged then kept in step: the latest change wins, and removals follow.",
            ]),
            ("0.4.3", "2026-10-26", None, "Intel Macs, macOS 12, and a smoother app on older Macs.", [
                "One universal app for Apple Silicon and Intel, from macOS 12 Monterey.",
                "Paired Macs no longer ask for your login password after each update.",
                "A larger Space preview that scrolls through long content; rich text shown as laid out.",
                "Arrows, the shelf and the library stay smooth on older Macs.",
                "Fixed a freeze on rich-text emails with tables.",
            ]),
            ("0.4.2", "2026-10-26", None, "Polish for light mode.", [
                "Library day titles no longer show as a grey band on light backgrounds.",
                "The storage usage is centered under its bar.",
            ]),
            ("0.4.1", "2026-10-26", None, "Safer deletion and a steadier library.", [
                "Deleting a card takes <kbd>⌘⌫</kbd>: a lone <kbd>⌫</kbd> no longer removes anything by accident.",
                "A right click on card text opens encore's menu, with its shortcuts.",
                "The keyboard cursor always stays in view in the library.",
                "The bottom bar lists the shortcuts to search, favorite and delete.",
            ]),
            ("0.4.0", "2026-10-25", "preview.png", "The shelf grows into the library, and your other Macs join in.", [
                "<b>A redesigned shelf</b> that grows into the full library: <kbd>↑</kbd> to explore, hold <kbd>↓</kbd> to come back.",
                "<b>Space preview</b>, floating above the selected card.",
                "<b>Your other Macs.</b> Browse and paste their recent history, paired with a code and end-to-end encrypted.",
                "<b>Automatic updates</b> from GitHub releases, with a stable signature that keeps Accessibility allowed.",
                "<b>30 languages</b>, with plurals, local formats and right-to-left layouts.",
                "Six new sound sets with instant previews, and the time left before each card expires.",
            ]),
            ("0.3.0", "2026-10-25", "library.png", "A full library, in French and English.", [
                "A library view with search, filters and preview.",
                "French and English, selectable in Settings.",
                "Exclusions that follow the apps you install.",
                "Retention presets from 500 MB to 3 GB.",
            ]),
            ("0.2.1", "2026-10-25", None, "Real thumbnails for files copied from Finder.", [
                "Finder file references resolve, so image and PDF history gets real thumbnails, names and sizes.",
            ]),
            ("0.2.0", "2026-10-25", "shelf.png", "The first public version.", [
                "The shelf: your history at <kbd>⇧⌘V</kbd>, pasted where you type.",
                "Image and PDF thumbnails, rich text cards, search including the text in images.",
                "Retention rules by size and type, with a preview before applying them.",
                "Favorites, collections, the paste queue, and transforms for links, JSON and Base64.",
                "Sounds on copy and paste, display choice, and opt-in screenshot import.",
            ]),
        ],
    },
    "fr": {
        "page_title": "Nouveautés · encore",
        "description": "Toutes les versions d’encore, ce qu’elles ont ajouté et corrigé, images à l’appui.",
        "title": "Nouveautés",
        "lead": "Toutes les versions d’encore, de la plus récente à la plus ancienne. Les copies installées se mettent à jour toutes seules.",
        "versions": "Versions",
        "notes": "Version sur GitHub",
        "items": [
            ("0.6.0", "2026-10-29", "compact.png", "Une fenêtre compacte, ton propre raccourci, et des mises à jour qui arrivent seules.", [
                "<b>Fenêtre compacte.</b> Un petit panneau de tes dernières copies, à la place du bandeau : déplace-le où tu veux, il est attiré par les coins, les bords et le centre, et se rouvre au même endroit. Choisis de 3 à 10 copies, fais défiler avec les flèches, appuie sur <kbd>↑</kbd> sur la première pour la bibliothèque.",
                "<b>Ton propre raccourci.</b> Clique dessus dans les Réglages et tape la combinaison de ton choix, sauf celles qui casseraient tes apps, comme <kbd>⌘V</kbd> seul.",
                "<b>Sons système.</b> Le jeu de sons personnalisé peut utiliser les sons fournis avec macOS.",
                "<b>Des mises à jour qui arrivent.</b> encore vérifie toutes les heures et, par défaut, installe la mise à jour dès qu’aucune de ses fenêtres n’est ouverte, puis se relance.",
                "Un interrupteur dans le pied passe du bandeau à la fenêtre compacte. <kbd>⌘←</kbd> <kbd>⌘→</kbd> apparaît dans le bandeau et dans les Réglages.",
                "La première lettre tapée dans la recherche n’est plus perdue, et le curseur de volume n’est plus coupé dans les Réglages.",
                "Un lien pour soutenir encore sur GitHub Sponsors, dans les Réglages et dans À propos.",
            ]),
            ("0.5.0", "2026-10-28", "snippets.jpg", "Les snippets, et des favoris qui te suivent de Mac en Mac.", [
                "<b>Snippets.</b> <kbd>⌘S</kbd> sur une carte lui donne un nom, un langage parmi 85 et des tags. Les snippets ont leur propre tableau et n’expirent jamais.",
                "<b>Variables.</b> <code>{{nom}}</code> demande une valeur avant de coller ; <code>{{clipboard}}</code>, <code>{{date}}</code> et <code>{{cursor}}</code> se remplissent seuls. Export et import des snippets en JSON.",
                "<b>Renommer sur place.</b> <kbd>⌘R</kbd>, ou un clic sur l’en-tête d’une carte.",
                "<b>Coller ou copier.</b> Un interrupteur choisit ce que font <kbd>↩</kbd> et le double-clic.",
                "<b>Synchro avec tes Mac appairés.</b> Favoris et snippets, chacun avec son réglage, fusionnés puis tenus à jour : la modification la plus récente l’emporte, et les suppressions suivent.",
            ]),
            ("0.4.3", "2026-10-26", None, "Les Mac Intel, macOS 12, et plus de fluidité sur les Mac anciens.", [
                "Une seule app universelle pour Apple Silicon et Intel, dès macOS 12 Monterey.",
                "Les Mac appairés ne demandent plus ton mot de passe de session après chaque mise à jour.",
                "Un aperçu Espace plus grand qui fait défiler les longs contenus ; le texte enrichi garde sa mise en page.",
                "Les flèches, le bandeau et la bibliothèque restent fluides sur les Mac anciens.",
                "Correction d’un blocage sur les e-mails en texte enrichi avec des tableaux.",
            ]),
            ("0.4.2", "2026-10-26", None, "Des finitions pour le mode clair.", [
                "Les titres de jour de la bibliothèque n’apparaissent plus comme une bande grise sur fond clair.",
                "L’espace utilisé est centré sous sa barre.",
            ]),
            ("0.4.1", "2026-10-26", None, "Une suppression plus sûre et une bibliothèque plus stable.", [
                "Supprimer une carte demande <kbd>⌘⌫</kbd> : un <kbd>⌫</kbd> seul ne supprime plus rien par accident.",
                "Un clic droit sur le texte d’une carte ouvre le menu d’encore, avec ses raccourcis.",
                "Le curseur clavier reste toujours visible dans la bibliothèque.",
                "La barre du bas liste les raccourcis pour chercher, mettre en favori et supprimer.",
            ]),
            ("0.4.0", "2026-10-25", "preview.png", "Le bandeau devient bibliothèque, et tes autres Mac s’invitent.", [
                "<b>Un bandeau repensé</b> qui devient la bibliothèque complète : <kbd>↑</kbd> pour explorer, maintiens <kbd>↓</kbd> pour revenir.",
                "<b>L’aperçu Espace</b>, flottant au-dessus de la carte choisie.",
                "<b>Tes autres Mac.</b> Parcours et colle leur historique récent, appairés avec un code et chiffrés de bout en bout.",
                "<b>Mises à jour automatiques</b> depuis les versions GitHub, avec une signature stable qui garde l’autorisation Accessibilité.",
                "<b>30 langues</b>, avec les pluriels, les formats locaux et les mises en page de droite à gauche.",
                "Six nouveaux jeux de sons à écouter en un clic, et le temps restant avant l’expiration de chaque carte.",
            ]),
            ("0.3.0", "2026-10-25", "library.png", "Une bibliothèque complète, en français et en anglais.", [
                "Une vue bibliothèque avec recherche, filtres et aperçu.",
                "Français et anglais, au choix dans les Réglages.",
                "Des exclusions qui suivent les apps que tu installes.",
                "Des préréglages de rétention de 500 Mo à 3 Go.",
            ]),
            ("0.2.1", "2026-10-25", None, "De vraies miniatures pour les fichiers copiés depuis le Finder.", [
                "Les références de fichiers du Finder sont résolues : l’historique d’images et de PDF a de vraies miniatures, noms et tailles.",
            ]),
            ("0.2.0", "2026-10-25", "shelf.png", "La première version publique.", [
                "Le bandeau : ton historique à <kbd>⇧⌘V</kbd>, collé là où tu écris.",
                "Miniatures d’images et de PDF, cartes en texte enrichi, recherche jusque dans le texte des images.",
                "Règles de rétention par taille et par type, avec un aperçu avant de les appliquer.",
                "Favoris, collections, file de collage, et transformations pour les liens, le JSON et le Base64.",
                "Sons à la copie et au collage, choix de l’écran, et import des captures d’écran en option.",
            ]),
        ],
    },
}


# Screens much wider than tall, shown across the page under their text.
WIDE = {"shelf.png", "library.png"}


def short(version):
    """0.4.0 reads as 0.4 in a badge; 0.4.3 stays as it is."""
    return version[:-2] if version.endswith(".0") else version


def media(base, lang, name, alt):
    src = f"{base}media/{lang}/{name}"
    if name.endswith(".mp4"):
        poster = src.replace(".mp4", ".jpg")
        return f'<video src="{src}" poster="{poster}" autoplay muted loop playsinline preload="metadata" aria-label="{escape(alt)}"></video>'
    return f'<img src="{src}" alt="{escape(alt)}" loading="lazy">'


def features_main(lang, base, home):
    f = FEATURES[lang]
    privacy = f"{base}{home}privacy/"
    blocks, cards = [], []
    for key, version, shot, title, text in f["items"]:
        text = text.replace("{privacy}", privacy)
        badge = f'<span class="since{" fresh" if version == LATEST else ""}">{escape(f["new"]) + " · " if version == LATEST else ""}{escape(f["since"].format(short(version)))}</span>'
        if shot:
            blocks.append(
                f'<section class="feature{" flip" if len(blocks) % 2 else ""}{" tall" if shot == "compact.png" else ""}{" wide" if shot in WIDE else ""}" id="{key}">'
                f'<div>{badge}<h2 class="slam">{escape(title)}</h2><p>{text}</p></div>'
                f'<figure>{media(base, lang, shot, title)}</figure></section>')
        else:
            cards.append(f'<li id="{key}">{badge}<h3>{escape(title)}</h3><p>{text}</p></li>')
    return f"""<div class="wrap pages">
<section class="intro">
  <h1 class="slam">{escape(f["title"])}</h1>
  <p class="lead">{escape(f["lead"])}</p>
</section>
{chr(10).join(blocks)}
<section class="more">
  <h2 class="slam">{escape(f["more_title"])}</h2>
  <ul>{"".join(cards)}</ul>
  <p class="next"><a class="button ghost" href="{base}{home}changelog/">{escape(f["changelog"])}<span aria-hidden="true">→</span></a></p>
</section>
</div>
"""


def changelog_main(lang, base, repo):
    r = RELEASES[lang]
    nav = "".join(f'<li><a href="#v{v}">{v}{" ·" if i == 0 else ""}{"<i>" + escape(FEATURES[lang]["new"]) + "</i>" if i == 0 else ""}</a></li>' for i, (v, *_rest) in enumerate(r["items"]))
    entries = []
    for version, date, shot, tagline, changes in r["items"]:
        figure = f"<figure>{media(base, lang, shot, tagline)}</figure>" if shot else ""
        entries.append(
            f'<article class="release" id="v{version}">'
            f'<header><h2>{version}</h2><time datetime="{date}">{date}</time></header>'
            f'<p class="tagline">{escape(tagline)}</p>{figure}'
            f'<ul>{"".join(f"<li>{c}</li>" for c in changes)}</ul>'
            f'<a class="gh" href="{repo}/releases/tag/v{version}">{escape(r["notes"])} →</a></article>')
    return f"""<div class="wrap pages">
<section class="intro">
  <h1 class="slam">{escape(r["title"])}</h1>
  <p class="lead">{escape(r["lead"])}</p>
</section>
<div class="changes">
  <nav aria-label="{escape(r["versions"])}"><ul>{nav}</ul></nav>
  <div>{"".join(entries)}</div>
</div>
</div>
"""
