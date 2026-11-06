// Builds the "How it works" pages from Floorplan's export of the map, into the shells website/build.py has just written.
// Usage: node website/how-it-works/build.mjs <website/public> <version>. Any mismatch stops the build: see README.md.
import fs from 'node:fs'; import path from 'node:path'; import {fileURLToPath} from 'node:url';
import {cases,refOf} from './cases.mjs'; import * as EN from './en.mjs';
const HERE=path.dirname(fileURLToPath(import.meta.url)), OUT=process.argv[2], VERSION=process.argv[3], MINOR=VERSION.split('.').slice(0,2).join('.');
const REPO='https://github.com/Kamasoutra/encore', REF='v'+VERSION;
const src=fs.readFileSync(HERE+'/map/encore-map.html','utf8'); const miss=[];
const esc=s=>String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/"/g,'&quot;');
const rep=(s,a,b)=>{const hit=typeof a==='string'?s.includes(a):a.test(s); if(!hit)miss.push(String(a).slice(0,70)); return typeof a==='string'?s.split(a).join(b):s.replace(a,b)};
const T={fr:{dir:'fr/',label:'Comment ça marche',priv:'Tes données',h1:'Comment ça marche',lead:'Tout le code d’encore est ouvert. Choisis une situation pour la voir étape par étape sur la carte. Clique sur une partie pour t’en approcher, double-clique pour y entrer. Chaque fichier te mène à son code sur GitHub.',ask:'Que se passe-t-il…',groups:{data:'Pour tes données',daily:'Au quotidien'},newTag:'Nouveau '+MINOR,credit:'Réalisée avec <a href="https://github.com/haydenschmitty/floorplan" target="_blank" rel="noopener">Floorplan</a> de Hayden Smith (<a href="floorplan-LICENSE.txt">licence MIT</a>), dessinée avec <a href="elkjs-LICENSE.md">elkjs</a>.',phoneLead:'Tout le code d’encore est ouvert. Choisis une situation pour voir ce qui se passe, étape par étape. Chaque fichier te mène à son code sur GitHub.',note:'La carte complète s’explore sur un écran plus grand.',btn:'Exemples',github:'Voir le code sur GitHub ↗',folder:'Voir le dossier sur GitHub ↗'},
en:{dir:'',label:'How it works',priv:'Your data',h1:'How it works',lead:'All of encore’s code is open. Pick a situation to see it step by step on the map. Click a part to get closer, double-click to step inside. Every file leads to its code on GitHub.',ask:'What happens…',groups:{data:'For your data',daily:'Every day'},newTag:'New in '+MINOR,credit:'Made with <a href="https://github.com/haydenschmitty/floorplan" target="_blank" rel="noopener">Floorplan</a> by Hayden Smith (<a href="floorplan-LICENSE.txt">MIT license</a>), drawn with <a href="elkjs-LICENSE.md">elkjs</a>.',phoneLead:'All of encore’s code is open. Pick a situation to see what happens, step by step. Every file leads to its code on GitHub.',note:'The full map is best explored on a larger screen.',btn:'Examples',github:'See the code on GitHub ↗',folder:'See the folder on GitHub ↗'}};
const FR_STR={'Used by':'Utilisé par','Depends on':'Dépend de','Inside':'Contient','Files':'Fichiers','Show details':'Voir les détails','Overview':'Vue d’ensemble','Contains':'Contient','Calls':'Appels','Uses':'Utilise','Stop':'Arrêter','Up one level':'Niveau supérieur','Show on the map':'Montrer sur la carte','Search':'Rechercher','Settings':'Réglages','Outside services':'Services extérieurs','Open':'Ouvrir','On this board':'Sur cette vue','More':'Plus','Less':'Moins','Made with':'Fait avec','Guided flows':'Exemples','Folder':'Dossier','Flow':'Exemple','Fit to screen':'Ajuster à l’écran','File':'Fichier','Exports':'Exporte','Details':'Détails','Copy path':'Copier le chemin','Copy name':'Copier le nom','Copied':'Copié','Codebase':'Code','Board':'Vue','Behind the scenes':'En coulisses','Background jobs':'Tâches de fond','Back to overview':'Retour à la vue d’ensemble','Apps people use':'Ce que tu utilises','Events':'Événements','Web requests':'Requêtes web','Reads & writes data':'Lit et écrit','Tour':'Visite','Imports':'Importe','Imported by':'Importé par','From':'De','To':'Vers','Data':'Données'};
const FR_TAG={'Back to map':'Retour à la carte','Called from':'Appelé depuis','Cancel':'Annuler','Close':'Fermer','Defined in':'Défini dans','Go to source':'Aller à la source','Go to target':'Aller à la cible','Got it':'Compris','Handled by':'Traité par','Matched by':'Reconnu par','No description yet':'Pas encore de description','No matches':'Aucun résultat','Other':'Autres','Show connections':'Voir les liens','Show on map':'Montrer sur la carte','Show technical detail':'Afficher le détail technique','Systems ':'Systèmes '};
const EN_KINDS={Ui:'Interface',Test:'Tests',Infra:'Build',External:'Outside',Library:'Library',Service:'Service',Data:'Data',Feature:'Feature',File:'File',Module:'Module',Folder:'Folder',Script:'Script',Symbol:'Symbol',Overview:'Overview',Codebase:'Code'};
const FR_KINDS={File:'Fichier',Module:'Module',Folder:'Dossier',Feature:'Fonction',Library:'Bibliothèque',Service:'Service',Data:'Données',Ui:'Interface',Test:'Tests',Infra:'Fabrication',External:'Extérieur',Script:'Script',Symbol:'Symbole',Overview:'Vue d’ensemble',Codebase:'Code'};
const siteCss=fs.readFileSync(HERE+'/../style.css','utf8').split('\n').filter(l=>/^(\.support-dialog|\.choices?\b|@media \(max-width: 480px\) \{ \.support-dialog)/.test(l)).join('\n');
if(!siteCss)miss.push('support dialog css');
const skinCss=fs.readFileSync(HERE+'/skin.css','utf8')+'\n'+siteCss;
function build(lang){
 const L=T[lang], fr=lang==='fr'; let h=src;
 const drop=n=>{const re=new RegExp('<script>/\\* ui/'+n+'[\\s\\S]*?</script>');if(!re.test(h))miss.push('drop '+n);h=h.replace(re,'')};
 ['10-glossary','50-cloud','05-theme','40-tour'].forEach(drop);
 h=h.replace(/@font-face\s*\{[^}]*\}/g,'');
 // données
 const ds=h.indexOf('window.FLOORPLAN = '), de=h.indexOf('</script>',ds);
 const G=JSON.parse(h.slice(ds+19,de).trim().replace(/;$/,''));
 const known=r=>r.startsWith('f:')?G.files.some(f=>f.p===r.slice(2)):G.nodes.some(n=>n.id===r.slice(2));
 G.flows=cases.map(c=>({id:c.id,title:c[lang][0],description:c[lang][1],steps:c.steps.map(s=>{const ref=refOf(s[0]);if(!known(ref))miss.push('case '+c.id+': '+s[0]);return {ref,note:fr?s[1]:s[2]}})}));
 // The tests lean on everything: their links add a column to the overview, which shrinks it, and tell a visitor nothing.
 const inTests=r=>/^(f:Tests\/|n:tests)/.test(r);
 G.links=G.links.filter(l=>!inTests(l.a)&&!inTests(l.b));
 G.tour=[];
 if(!fr){ G.project.summary=EN.summary;
  for(const n of G.nodes){const e=EN.nodes[n.id]; if(e){n.label=e[0];n.summary=e[1]} else miss.push('en node '+n.id)}
  for(const f of G.files){const e=EN.files[f.p]||EN.test(f.p); if(e){f.name=e[0];f.d=e[1]} else miss.push('en file '+f.p); if(f.note)f.note=EN.notes[f.p]||miss.push('en note '+f.p)}
  for(const l of G.links) if(l.labels) l.labels=l.labels.map(x=>EN.labels[x]||(/[a-z]\.[a-z]/.test(x)?x:(miss.push('en label '+x),x)));
 }
 h=h.slice(0,ds+19)+JSON.stringify(G).replace(/<\//g,'<\\/')+';'+h.slice(de);
 // visionneuse
 const m=h.match(/<script>\n\(\(\) => \{\n'use strict';\nconst G = window\.FLOORPLAN;[\s\S]*?<\/script>/); if(!m)throw 'viewer';
 let v=m[0];
 v=rep(v,/const editorUrl = [^\n]*\n/,`const REPO_URL = ${JSON.stringify(REPO+'/blob/'+REF+'/')};\nconst editorUrl = (p, line = 1) => REPO_URL + encodeURI(p) + (line > 1 ? '#L' + line : '');\nconst treeOf = (id) => { const t = {app:'Sources/Encore',core:'Sources/EncoreCore',tests:'Tests',site:'website',outils:'scripts'}[String(id).split('.')[0]]; return t ? ${JSON.stringify(REPO+'/tree/'+REF+'/')} + t : null; };\n`);
 v=rep(v,"run: () => { location.href = url; } }","run: () => { window.open(url, '_blank', 'noopener'); } }");
 v=rep(v,'<a class="btn soft" href="${url}">${iconI(\'open\')}Open in editor</a>','<a class="btn soft" target="_blank" rel="noopener" href="${url}">${iconI(\'open\')}'+L.github+'</a>');
 v=rep(v,"'Open in editor'",`'${L.github}'`);
 v=rep(v,"if (n?.packages?.length || n?.hosts?.length","if (n && treeOf(n.id)) html += `<div class=\"actions\"><a class=\"btn soft\" target=\"_blank\" rel=\"noopener\" href=\"${treeOf(n.id)}\">${iconI('open')}"+L.folder+"</a></div>`;\n    if (n?.packages?.length || n?.hosts?.length");
 v=rep(v,"$('#proj-name').after(tag);","");
 v=rep(v,"$('#flowbar').hidden = true; vp.querySelectorAll('.flowfx').forEach((x) => x.remove()); select(null); }","$('#flowbar').hidden = true; vp.querySelectorAll('.flowfx').forEach((x) => x.remove()); select(null); if (state.container !== 'root') go('root'); }");
 v=rep(v,"document.title = `${G.project.name} map`;","");
 v=rep(v,"function cardExtraH(item) {\n  const i = info(item);","const descOf = (i) => i.type === 'node' ? i.n.summary : (i.type === 'file' || i.type === 'module') ? i.f.d : i.type === 'route' ? i.r.d : i.type === 'dir' ? i.d.files.slice().sort((a, b) => b.loc - a.loc).slice(0, 4).map((f) => f.name).join(', ') + (i.d.files.length > 4 ? ', …' : '') : null;\nconst descLines = (t, i) => Math.min(8, Math.max(1, Math.ceil(textW(t, 13, 400) * 1.15 / ((SIZES[i.type] || SIZES.file)[0] - 36))));\nfunction cardExtraH(item) {\n  const i = info(item);\n  const dt = descOf(i), descExtra = dt ? Math.max(0, descLines(dt, i) - (i.type === 'node' || i.type === 'route' ? 3 : 2)) * 19 : 0;");
v=rep(v,"return (cardFoot(item) ? FOOT_H : 0) + (textW(name, 15, 600) > room ? TITLE2_H : 0);","return descExtra + (cardFoot(item) ? FOOT_H : 0) + (textW(name, 15, 600) > room ? TITLE2_H : 0);");
v=rep(v,'`<div class="desc" style="--lines:${lines}">${h(t)}</div>`','`<div class="desc" style="--lines:${descOf(i) === t ? descLines(t, i) : lines}">${h(t)}</div>`');
v=rep(v,"store.get('panelWidth', 360)","store.get('panelWidth', 400)");
 // A column of outside services taller than the rest is dealt into two staggered columns, so that the overview fits larger.
 v=rep(v,"async function layout(view) {",fs.readFileSync(HERE+'/split-column.js','utf8')+"async function layout(view) {");
 v=rep(v,"  return elk.layout({\n    id: 'g', children,","  return layoutTwoColumns({\n    id: 'g', children,");
 v=rep(v,"'elk.layered.spacing.nodeNodeBetweenLayers': '130', 'elk.spacing.nodeNode': '32',","'elk.layered.spacing.nodeNodeBetweenLayers': state.container === 'root' ? '120' : '130', 'elk.spacing.nodeNode': state.container === 'root' ? '28' : '32',");
 // What calls into the app would sit left of it and add a fourth column: for the layout alone, the overview reads every link towards the outside.
 v=rep(v,"edges: view.edges.map((e) => ({ id: e.id, sources: [e.a], targets: [e.b] })),","edges: view.edges.map((e) => ({ id: e.id, ...(state.container === 'root' && String(e.a).startsWith('n:ext.') ? { sources: [e.b], targets: [e.a] } : { sources: [e.a], targets: [e.b] }) })),");
 // Links side by side on the overview keep a little air between them.
 v=rep(v,"'elk.layered.spacing.edgeEdgeBetweenLayers': '8', 'elk.spacing.edgeEdge': '8',","'elk.layered.spacing.edgeEdgeBetweenLayers': state.container === 'root' ? '14' : '8', 'elk.spacing.edgeEdge': state.container === 'root' ? '14' : '8',");
 v=rep(v,"'elk.separateConnectedComponents': 'true'","'elk.separateConnectedComponents': state.container === 'root' ? 'false' : 'true'");
 // A link in the panel brings the map to what it names, even off screen or behind the panel.
 v=rep(v,"g.classList.add('flash'); centerOn(item); } } });","g.classList.add('flash'); } centerOn(item); } });");
 v=rep(v,"const k = Math.max(state.t.k, 0.75);","clickZoomed = true; const k = Math.max(state.t.k, 0.75);");
 v=rep(v,"function select(sel) {","let clickZoomed = false;\nfunction closeUp(item) { const c = state.layout?.children.find((x) => x.id === item); if (!c || state.flow) return; if (state.t.k >= 0.95) return bringIntoView(item); const a = freeArea(); clickZoomed = true; setT({ k: 1, x: a.x + a.w / 2 - (c.x + c.width / 2), y: a.y + a.h / 2 - (c.y + c.height / 2) }, true); }\nfunction select(sel) {");
 v=rep(v,"g.addEventListener('click', (ev) => { ev.stopPropagation(); select(c.id); });","g.addEventListener('click', (ev) => { ev.stopPropagation(); select(c.id); closeUp(c.id); });");
 v=rep(v,"svg.addEventListener('click', () => select(null));","svg.addEventListener('click', () => { select(null); if (clickZoomed) { clickZoomed = false; fit(true); } });");
 v=rep(v,"function overviewPanel() {","function overviewPanel() {\n  return window.ENCORE_PANEL;");
 v=rep(v,"  $('#context').innerHTML = `<div class=\"k\">${badge}","  document.body.classList.toggle('at-root', state.container === 'root');\n  $('#context').innerHTML = `<div class=\"k\">${badge}");
 v=rep(v,"if (sel && isPhone() && document.body.classList.contains('no-panel')) { setPanel(true);","if (sel && document.body.classList.contains('no-panel')) { setPanel(true);");
 v=rep(v,"<span>endpoints</span>","<span>endpoints</span>");
 v=v.replace(/<div><b>\$\{[^<]*<\/b><span>endpoints<\/span><\/div>/g,'');
 v=rep(v,"${badge}${h(kind)}</div><h1>","${badge}${h(window.ENCORE_KINDS[kind] || kind)}</div><h1>");
v=rep(v,"panel.innerHTML = html || '';","panel.innerHTML = html || ''; panel.querySelectorAll('.kind, .kindlabel').forEach((e) => { const t = e.textContent.trim(), c = t.charAt(0).toUpperCase() + t.slice(1); e.textContent = window.ENCORE_KINDS[c] || t; });");
 if(fr){
  for(const[a,b] of Object.entries(FR_STR)) v=v.split(`'${a}'`).join(`'${b}'`);
  for(const[a,b] of Object.entries(FR_TAG)) v=v.split(`>${a}<`).join(`>${b}<`);
  for(const[w,t] of [['file','fichier'],['line','ligne'],['connection','lien'],['call','appel'],['step','étape']]) v=v.replace(new RegExp(`plural\\(([^,()]+(?:\\([^()]*\\))?[^,()]*), '${w}'\\)`,'g'),`plural($1, '${t}')`);
  for(const[a,b] of [['· free and open source','· libre et open source'],['<span>lines</span>','<span>lignes</span>'],['<span>uses</span>','<span>utilise</span>'],['used by</span>','utilisé par</span>'],['${PLAN ? \'planned files\' : \'files\'}','fichiers'],['what users and staff open','ce que tu ouvres'],['servers, background work, shared code','le travail invisible'],['other companies your app relies on','ce sur quoi l’app s’appuie'],['>click<','>clic<'],['>right-click<','>clic droit<'],['</span> details','</span> détails'],['</span> more','</span> plus'],['</span> open','</span> ouvrir'],['</span> go there','</span> y aller'],['2×click','2×clic'],['Inside ${','Dans ${']]) v=v.split(a).join(b);
  v=v.split(' steps').join(' étapes');
  v=v.replace(/ · step \$\{([^}]+)\} of \$\{([^}]+)\}/g,' · étape ${$1} sur ${$2}');
 } else {
  v=rep(v,"${PLAN ? 'planned files' : 'files'}","files");
  v=v.split("'Guided flows'").join("'Examples'").split("'Flow'").join("'Example'");
 }
 h=h.replace(m[0],()=>v);
 h=rep(h,/root\.setAttribute\('data-theme',[^;]*\);/,"root.setAttribute('data-theme','dark');");
 h=rep(h,'<span class="bl">Flows</span>',`<span class="bl">${L.btn}</span>`); h=rep(h,'aria-label="Flows"',`aria-label="${L.btn}"`);
 if(fr) for(const[a,b] of [['Search files, routes, modules','Chercher un fichier ou un module'],['Search by name, description, path or route…','Chercher par nom, description ou chemin…'],['Zoom out (−)','Dézoomer (−)'],['Zoom in (+)','Zoomer (+)'],['Fit to screen (F)','Ajuster à l’écran (F)'],['Connection types','Types de liens'],['Toggle details (P)','Détails (P)'],['Toggle details','Détails'],['Laying out…','Mise en place…'],['Drag to resize','Tirer pour redimensionner'],['</span> navigate<','</span> naviguer<'],['</span> open<','</span> ouvrir<'],['</span> close<','</span> fermer<']]) h=h.split(a).join(b);
 else for(const[a,b] of [['Search files, routes, modules','Search for a file or module'],['Search by name, description, path or route…','Search by name, description or path…']]) h=h.split(a).join(b);
 h=h.replace('<html lang="en"',`<html lang="${lang}"`);
 const nameOf=r=>r.startsWith('f:')?(G.files.find(f=>f.p===r.slice(2))?.name||r):(G.nodes.find(n=>n.id===r.slice(2))?.label||r);
 const stepsHtml=c=>G.flows.find(f=>f.id===c.id).steps.map(s=>{const r=s.ref;const link=r.startsWith('f:')?`<a href="${REPO}/blob/${REF}/${encodeURI(r.slice(2))}" target="_blank" rel="noopener">${esc(nameOf(r))} ↗</a>`:`<b>${esc(nameOf(r))}</b>`;return `<li>${link}<span>${esc(s.note)}</span></li>`}).join('');
 const tag=c=>c.since===MINOR?`<em>${L.newTag}</em>`:'';
 const group=g=>cases.filter(c=>c.g===g);
 const panel=`<div class="hiw-panel"><h1>${L.h1}</h1><p class="hiw-lead">${L.lead}</p><p class="hiw-ask">${L.ask}</p>
${['data','daily'].map(g=>`<h2 class="tone-${g}">${L.groups[g]}</h2>${group(g).map(c=>`<a class="hiw-case tone-${g}" href="#" data-flow="${c.id}"><b>${esc(c[lang][0])} ${tag(c)}<i aria-hidden="true">→</i></b><span>${esc(c[lang][1])}</span></a>`).join('')}`).join('')}
<p class="hiw-credit">${L.credit}</p></div>`;
 const phone=`<div class="phone-page"><h1>${L.h1}</h1><p class="lead">${L.phoneLead}</p><p class="ask">${L.ask}</p>
${['data','daily'].map(g=>`<h2 class="tone-${g}">${L.groups[g]}</h2>${group(g).map(c=>`<details class="phone-case tone-${g}"><summary>${esc(c[lang][0])} ${tag(c)}</summary><p>${esc(c[lang][1])}</p><ol>${stepsHtml(c)}</ol></details>`).join('')}`).join('')}
<p class="note">${L.note}</p><p class="credit">${L.credit}</p></div>`;
 const dir=OUT+'/'+L.dir+'how-it-works', t=fs.readFileSync(dir+'/index.html','utf8');
 let top=t.match(/<header class="top">([\s\S]*?)<\/header>/)[1];
 for(const[a,b] of [['wrap bar','st-bar'],['"brand"','"st-brand"'],['pages-nav','st-nav'],['"tools"','"st-tools"'],['"langs"','"st-langs"'],['"gh"','"st-gh"'],['class="sponsor"','class="st-sponsor"'],['class="label"','class="st-label"']]) top=top.split(a).join(b);
 const shellHead=t.slice(t.indexOf('<title>'),t.indexOf('</head>')).replace(/<link rel="stylesheet"[^>]*>\n?/,'');
 const dialog=t.match(/<dialog class="support-dialog"[\s\S]*?<\/dialog>/)[0], siteJs=t.match(/<script src="[^"]*site\.js"><\/script>/)[0];
 const head=`<style id="encore-skin">${skinCss}</style>\n<script>window.ENCORE_KINDS=${JSON.stringify(fr?FR_KINDS:EN_KINDS)};window.ENCORE_PANEL=${JSON.stringify(panel).replace(/</g,'\\u003c')};</script>\n</head>`;
 h=h.replace('</head>',()=>head);
 h=h.replace(/<link rel="icon"[^>]*>\n?/,'').replace(/<title>[^<]*<\/title>/,()=>shellHead);
 h=h.replace('</body>',()=>`${dialog}\n${siteJs}\n</body>`);
 h=h.replace('<body>',()=>`<body>\n<div class="site-top">${top}</div>\n${phone}`);
 fs.writeFileSync(dir+'/index.html',h);
 for(const l of ['floorplan-LICENSE.txt','elkjs-LICENSE.md']) fs.copyFileSync(HERE+'/'+l,dir+'/'+l);
}
build('fr'); build('en');
if(miss.length){console.error('how-it-works: the build no longer matches its inputs:\n  '+miss.join('\n  '));process.exit(1)}
