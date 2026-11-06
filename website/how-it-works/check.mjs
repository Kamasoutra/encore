// Fails when the "How it works" map no longer describes the code, or its links would not lead to it. Runs before every release.
import fs from 'node:fs'; import {createHash} from 'node:crypto'; import {execFileSync} from 'node:child_process';
import {cases,refOf} from './cases.mjs';
const html=fs.readFileSync(new URL('./map/encore-map.html',import.meta.url),'utf8');
const start=html.indexOf('window.FLOORPLAN = ')+19, G=JSON.parse(html.slice(start,html.indexOf('</script>',start)).trim().replace(/;$/,''));
const problems=[], tracked=execFileSync('git',['ls-files','Sources','Tests','website','scripts','Package.swift'],{encoding:'utf8'}).trim().split('\n');
const mapped=new Set(G.files.map(f=>f.p)), hash=p=>createHash('sha1').update(fs.readFileSync(p,'utf8')).digest('hex').slice(0,12);
for(const f of G.files){
  if(!fs.existsSync(f.p)) problems.push(`removed from the code: ${f.p}`);
  else if(/^(Sources|scripts)\//.test(f.p)&&hash(f.p)!==f.h) problems.push(`changed since the map was made: ${f.p}`);
  if(!f.name||!f.d) problems.push(`no description: ${f.p}`);
}
for(const p of tracked) if(p.endsWith('.swift')&&!mapped.has(p)) problems.push(`missing from the map: ${p}`);
for(const c of cases) for(const [ref] of c.steps){ const r=refOf(ref); if(r.startsWith('f:')?!mapped.has(r.slice(2)):!G.nodes.some(n=>n.id===r.slice(2))) problems.push(`case ${c.id} points to nothing: ${ref}`); }
if(html.includes('/Users/')) problems.push('the export contains a local path');
const version=execFileSync('/usr/bin/plutil',['-extract','CFBundleShortVersionString','raw','Resources/Info.plist'],{encoding:'utf8'}).trim();
const latest=fs.readFileSync('website/features.py','utf8').match(/^LATEST = "([^"]+)"/m)?.[1];
if(latest!==version) problems.push(`the site announces ${latest}, the app is ${version}`);
if(problems.length){ console.error(`How it works is out of date. Run website/how-it-works/refresh.sh:\n  ${problems.join('\n  ')}`); process.exit(1); }
console.log(`How it works: ${G.files.length} files and ${cases.length} cases match the code.`);
