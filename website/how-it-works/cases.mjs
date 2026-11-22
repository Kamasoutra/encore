const A='Sources/Encore/',C='Sources/EncoreCore/';
const f=p=>p; const CS=A+'ClipboardService.swift',AM=A+'AppModel.swift',BV=A+'BoardView.swift',ST=C+'Storage.swift';
// id, group, nouveauté, FR {title, answer}, EN {title, answer}, étapes [node, fr, en]
export const cases=[
{id:'copie',g:'data',fr:['Quand tu copies quelque chose','Ta copie reste sur ton Mac : pas de compte, pas de serveur, et le chiffrement de l’historique est en option.'],en:['When you copy something','Your copy stays on your Mac: no account, no server, and encrypting the history is optional.'],steps:[
 ['ext.macos','Tu copies quelque chose dans n’importe quelle app.','You copy something in any app.'],
 [CS,'encore remarque le changement.','encore notices the change.'],
 [C+'PasteboardCapture.swift','Il lit tous les formats de la copie.','It reads every format of the copy.'],
 [CS,'La copie est prête à rejoindre l’historique.','The copy is ready to join the history.'],
 [AM,'Elle rejoint l’historique.','It joins the history.'],
 [ST,'Elle est enregistrée sur ton disque, chiffrée si tu as activé l’option.','It is saved on your disk, encrypted if you turned that on.'],
 ['ext.disque','Elle reste disponible après un redémarrage.','It is still there after a restart.']]},
{id:'motdepasse',g:'data',fr:['Quand tu copies un mot de passe','Depuis un champ de mot de passe ou un gestionnaire qui le signale, encore ne le garde pas.'],en:['When you copy a password','From a password field, or a password manager that flags it, encore does not keep it.'],steps:[
 ['ext.macos','Tu copies un mot de passe.','You copy a password.'],
 [CS,'encore vérifie si la copie vient d’un champ de mot de passe.','encore checks whether the copy comes from a password field.'],
 [C+'PasteboardCapture.swift','Il reconnaît aussi les copies que les gestionnaires signalent comme confidentielles : rien n’est enregistré.','It also recognises copies that password managers flag as confidential: nothing is saved.']]},
{id:'secret',g:'data',fr:['Quand une clé d’API passe dans tes copies','Avec la détection activée, elle est masquée puis effacée après un délai. Après un collage, le presse-papiers se vide aussi.'],en:['When an API key lands in your copies','With detection on, it is masked, then deleted after a delay. Once pasted, the clipboard is cleared too.'],steps:[
 [CS,'Une copie de texte arrive. La détection est une option, désactivée par défaut.','A text copy arrives. Detection is optional and off by default.'],
 [C+'Secrets.swift','encore reconnaît ce qui ressemble à une clé, une carte bancaire ou un mot de passe.','encore recognises what looks like a key, a bank card or a password.'],
 [CS,'La carte n’affiche que le début de la valeur.','The card only shows the start of the value.'],
 [AM,'La copie est supprimée après le délai choisi, 60 secondes par défaut.','The copy is deleted after the delay you chose, 60 seconds by default.']]},
{id:'chiffre',g:'data',fr:['Quand tu actives le chiffrement','La clé va dans le trousseau de ton Mac, et tout l’historique est converti.'],en:['When you turn on encryption','The key goes into your Mac’s keychain, and the whole history is converted.'],steps:[
 [A+'SettingsView.swift','Tu actives l’option dans les réglages.','You turn it on in Settings.'],
 [AM,'encore lance la conversion.','encore starts the conversion.'],
 [A+'HistoryKey.swift','Une clé aléatoire est créée avant de chiffrer le moindre fichier.','A random key is created before any file is encrypted.'],
 ['ext.trousseau','Elle est gardée dans le trousseau de ton Mac.','It is kept in your Mac’s keychain.']]},
{id:'expire',g:'data',fr:['Quand une copie arrive à expiration','Elle est supprimée du disque selon tes règles : durée, app, taille ou type.'],en:['When a copy expires','It is deleted from your disk according to your rules: duration, app, size or type.'],steps:[
 [A+'RetentionSettingsView.swift','Tu choisis combien de temps garder tes copies.','You choose how long to keep your copies.'],
 [AM,'encore applique ces règles régulièrement.','encore applies these rules regularly.'],
 [C+'Retention.swift','La règle qui correspond à chaque copie décide de sa date de fin.','The rule matching each copy decides when it ends.'],
 [AM,'Les copies expirées sont retirées de l’historique.','Expired copies leave the history.'],
 [ST,'Leurs fichiers sont supprimés.','Their files are deleted.'],
 ['ext.disque','Plus rien ne reste sur le disque.','Nothing is left on the disk.']]},
{id:'partage',g:'data',fr:['Quand tu partages avec ton autre Mac','Désactivé par défaut. Deux Mac s’associent avec un code, puis tout est chiffré. Fichiers et secrets détectés ne partent pas.'],en:['When you share with your other Mac','Off by default. Two Macs pair with a code, then everything is encrypted. Files and detected secrets stay put.'],steps:[
 [AM,'Le partage est désactivé tant que tu ne l’as pas activé dans les réglages.','Sharing stays off until you turn it on in Settings.'],
 [C+'PeerShare.swift','Les fichiers et les secrets détectés sont écartés : ils ne quittent pas ce Mac.','Files and detected secrets are set aside: they never leave this Mac.'],
 [C+'PeerService.swift','Seul un Mac associé est servi, après comparaison d’un code sur les deux écrans.','Only a paired Mac is served, after comparing a code on both screens.'],
 [C+'PeerChannel.swift','Chaque message est chiffré avant de partir.','Every message is encrypted before it leaves.'],
 ['ext.mac','Il arrive directement sur ton autre Mac, sans serveur entre les deux.','It goes straight to your other Mac, with no server in between.']]},
{id:'assistant',g:'data',since:'0.8',fr:['Quand un assistant lit ton historique','Éteint par défaut et réservé à ton compte. Les secrets détectés sont écartés, sauf si tu l’autorises, et chaque accès est noté. Ce que l’assistant lit suit ensuite ses propres règles.'],en:['When an assistant reads your history','Off by default and limited to your account. Detected secrets are withheld unless you allow them, and every access is logged. What it reads then follows its own data rules.'],steps:[
 ['ext.ia','L’assistant envoie une demande. L’accès reste éteint tant que tu ne l’as pas activé.','The assistant sends a request. Access stays off until you turn it on.'],
 [A+'MCPCommand.swift','Une petite commande relaie la demande vers l’app et la relance si besoin.','A small command relays the request to the app and restarts it if needed.'],
 [C+'MCPSocket.swift','La demande passe par un canal local réservé à ton compte.','The request goes through a local channel limited to your account.'],
 [C+'MCP.swift','La demande est décodée et l’outil demandé est identifié.','The request is decoded and the tool it asks for is identified.'],
 [A+'AppModel+MCP.swift','encore vérifie que l’accès est activé, écarte les secrets sauf réglage contraire et note l’accès au journal.','encore checks that access is on, withholds secrets unless you allow them, and logs the access.'],
 [AM,'La réponse est tirée de l’historique.','The answer comes from the history.']]},
{id:'coller',g:'daily',fr:['Quand tu recolles une copie','Tu choisis une tuile, et encore la colle dans l’app que tu utilisais.'],en:['When you paste a copy again','You pick a card, and encore pastes it into the app you were using.'],steps:[
 [A+'WorkspaceView.swift','Le bandeau s’ouvre.','The shelf opens.'],
 [BV,'Tu choisis une tuile.','You pick a card.'],
 [AM,'encore prépare ce qui sera collé.','encore prepares what will be pasted.'],
 ['ext.macos','Le contenu est déposé dans le presse-papiers pour l’app active.','The content lands on the clipboard for the active app.']]},
{id:'maccy',g:'data',since:'0.9',fr:['Quand tu importes depuis Maccy','encore lit une copie de la base de Maccy, sans jamais modifier celle de Maccy. Chaque copie suit les mêmes règles que si tu l’avais faite dans encore.'],en:['When you import from Maccy','encore reads a copy of Maccy’s database and never changes Maccy’s own. Each copy follows the same rules as if you had made it in encore.'],steps:[
 [A+'SettingsView.swift','Tu choisis Importer depuis Maccy dans Réglages → Données.','You choose Import from Maccy in Settings → Data.'],
 [C+'MaccyStore.swift','encore copie la base de Maccy à part et lit chaque copie avec ses formats.','encore copies Maccy’s database aside and reads each copy with its formats.'],
 [A+'AppModel+Maccy.swift','Les apps exclues sont écartées, les secrets masqués, les épinglés deviennent favoris, et une copie déjà connue garde sa date la plus récente.','Excluded apps are skipped, secrets masked, pinned items become favorites, and a copy encore already has keeps its latest date.'],
 [ST,'Tout est enregistré en une fois, puis tes durées de conservation s’appliquent.','Everything is saved at once, then your retention rules apply.']]},
{id:'glisser',g:'daily',since:'0.9',fr:['Quand tu glisses plusieurs images','Chaque image arrive comme un fichier à part, dans une page web comme dans un mail. Collées dans une page web, elles arrivent l’une après l’autre, après le texte choisi avec elles. Si une page laisse quelque chose de côté, encore te le dit.'],en:['When you drag several images','Each image arrives as its own file, in a web page as in a mail. Pasted into a web page, they go in one after the other, after any text picked with them. If a page leaves something out, encore tells you.'],steps:[
 [BV,'Tu choisis les images avec ⌘-clic, puis tu glisses l’une d’elles.','You pick the images with ⌘-click, then drag one of them.'],
 [BV,'Chaque image est écrite dans un fichier temporaire, effacé au glisser suivant.','Each image is written to a temporary file, removed at the next drag.'],
 ['ext.macos','L’app où tu déposes reçoit un fichier par image.','The app you drop into gets one file per image.'],
 [A+'Toast.swift','Si une page web n’a pris que le texte, un message le dit par-dessus l’app.','If a web page took only the text, a message over the app says so.']]},
{id:'retouche',g:'data',since:'0.9',fr:['Quand tu retouches une image','Une nouvelle copie est créée, sans les métadonnées ni la localisation de l’originale. L’originale ne change pas.'],en:['When you touch up an image','A new copy is made, without the original’s metadata and location. The original does not change.'],steps:[
 [BV,'Clic droit sur une image, puis Retoucher une copie.','Right-click an image, then Touch up a copy.'],
 [C+'ImageAction.swift','L’image est redessinée à la taille et au format choisis, sans ses métadonnées.','The image is drawn again at the chosen size and format, without its metadata.'],
 [AM,'Le résultat rejoint l’historique comme une nouvelle copie, en tête.','The result joins the history as a new copy, at the top.'],
 [ST,'Elle est enregistrée comme toute autre copie, chiffrée si l’option est active.','It is saved like any other copy, encrypted if that option is on.']]},
{id:'fichiers',g:'daily',since:'0.8',fr:['Quand tu colles plusieurs fichiers','Le texte et les images arrivent avec les fichiers, jusqu’à 25 Mo. Les PDF et les archives restent des fichiers.'],en:['When you paste several files','Text and images arrive along with the files, up to 25 MB. PDFs and archives stay files.'],steps:[
 [A+'Previews.swift','Tous les fichiers de la copie sont visibles en mosaïque.','Every file in the copy shows in a mosaic.'],
 [BV,'La tuile affiche leur nombre, et un glisser les emporte tous.','The card shows how many there are, and a drag takes them all.'],
 [AM,'Le contenu des fichiers texte et image s’ajoute aux fichiers.','The contents of text and image files join the files.'],
 ['ext.macos','Chaque app prend ce qu’elle sait utiliser.','Each app takes what it can use.']]},
{id:'capture',g:'daily',fr:['Quand tu fais une capture d’écran','Si l’option est activée, elle rejoint l’historique sans toucher au presse-papiers.'],en:['When you take a screenshot','If that option is on, it joins your history without touching the clipboard.'],steps:[
 ['ext.captures','macOS enregistre la capture dans son dossier.','macOS saves the screenshot in its folder.'],
 [A+'ScreenshotImporter.swift','encore surveille ce dossier et reconnaît les captures à la marque laissée par macOS.','encore watches this folder and recognises screenshots by the mark macOS leaves on them.'],
 [AM,'La capture rejoint l’historique.','The screenshot joins the history.'],
 [ST,'Elle est enregistrée avec tes autres copies.','It is saved with your other copies.']]},
{id:'recherche',g:'daily',fr:['Quand tu cherches une ancienne copie','Tout se passe sur ton Mac, avec des filtres comme app:, type: ou date:.'],en:['When you look for an old copy','It all happens on your Mac, with filters like app:, type: or date:.'],steps:[
 [BV,'Tu tapes quelques mots dans la recherche.','You type a few words in the search field.'],
 [AM,'encore demande les copies qui correspondent.','encore asks for the matching copies.'],
 [C+'Search.swift','Chaque copie est comparée à ta recherche, sans tenir compte des accents.','Each copy is compared with your search, ignoring accents.']]},
{id:'snippet',g:'daily',fr:['Quand tu utilises un snippet','encore demande les valeurs manquantes, remplit la date et le presse-papiers, puis colle le résultat.'],en:['When you use a snippet','encore asks for the missing values, fills in the date and the clipboard, then pastes the result.'],steps:[
 [BV,'Tu choisis un snippet contenant des variables comme {{nom}}.','You pick a snippet with variables like {{name}}.'],
 [AM,'encore te demande les valeurs à remplir.','encore asks you for the values to fill in.'],
 [C+'Snippets.swift','Les variables sont remplacées, y compris {{date}} et {{clipboard}}.','The variables are replaced, including {{date}} and {{clipboard}}.'],
 [AM,'Le texte final est prêt.','The final text is ready.'],
 ['ext.macos','Il est déposé dans le presse-papiers pour être collé.','It lands on the clipboard to be pasted.']]},
{id:'maj',g:'daily',fr:['Quand une mise à jour sort','Sparkle vérifie sur GitHub si une nouvelle version existe, puis te la propose ou l’installe.'],en:['When an update comes out','Sparkle checks GitHub for a new version, then offers or installs it.'],steps:[
 [A+'Updates.swift','encore demande à Sparkle de vérifier régulièrement.','encore asks Sparkle to check regularly.'],
 ['ext.github','Le flux des versions est hébergé avec les versions publiées sur GitHub.','The release feed is hosted with the published versions on GitHub.']]},
];
export const refOf=n=>n.includes('/')?'f:'+n:'n:'+n;
