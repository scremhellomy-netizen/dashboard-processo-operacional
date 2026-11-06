// Fotografia persistente: algoritmos extraidos do index.html do dashboard.
// Uso: node scripts/gerar_historico_alertas.js --base data [--historico data/historico_alertas.json]
//      node scripts/gerar_historico_alertas.js --base pasta_de_backup --historico data/historico_alertas.json
const fs=require('fs'),path=require('path'),zlib=require('zlib');
const args=process.argv.slice(2),arg=(k,d)=>{let i=args.indexOf(k);return i<0?d:args[i+1]};
const root=path.resolve(__dirname,'..'),base=path.resolve(root,arg('--base','data'));
const output=path.resolve(root,arg('--historico','data/historico_alertas.json'));
const state={rawData:{rec:[],emb:[],arm:[],exp:[]},data:{rec:[],emb:[],arm:[],exp:[]},indexes:{},rawIndexes:{},issues:{},filterMonth:''};
function norm(v){return v==null?'':String(v).normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim().toUpperCase().replace(/\s+/g,'')}
function isBlank(v){return v==null||String(v).trim()===''}
function dateObj(v){if(!v)return null;let s=String(v).trim();let m=s.match(/^(\d{4})-(\d\d)-(\d\d)[ T](\d\d):(\d\d)(?::(\d\d))?/);if(m)return new Date(+m[1],+m[2]-1,+m[3],+m[4],+m[5],+(m[6]||0));m=s.match(/^(\d\d)\/(\d\d)\/(\d{4})/);if(m)return new Date(+m[3],+m[2]-1,+m[1]);return null}
function dayKey(v){let d=dateObj(v);return d?`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`:''}
function monthKey(v){let d=dateObj(v);return d?`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}`:''}
function processDateValue(kind,r){return kind==='rec'?field(r,['Início']):kind==='emb'?field(r,['inicio']):kind==='arm'?field(r,['ENTRADA']):field(r,['DATA_ALT'])}
function toObjects(obj,kind){let cols=obj.columns||[];let rows=obj.data||[];if(kind==='rec'){let hidx=rows.findIndex(r=>r.some(v=>String(v??'').trim()==='Nº Série'));if(hidx<0)throw new Error('Não foi localizado o cabeçalho real da base de Recebimento.');cols=rows[hidx];rows=rows.slice(hidx+1)}return {cols,rows:rows.map(r=>Object.fromEntries(cols.map((c,i)=>[String(c??`COL_${i}`),r[i]])))} }
function field(o, names){for(const n of names){if(Object.prototype.hasOwnProperty.call(o,n))return o[n]}return ''}
function prepare(kind,obj){let {cols,rows}=toObjects(obj,kind);if(kind==='rec')cols=rows.length?Object.keys(rows[0]):cols;let mapped=rows.filter(r=>Object.values(r).some(v=>!isBlank(v)));return {cols,mapped}}
function serialInfo(v){let raw=v==null?'':String(v);let numeric=typeof v==='number';let scientific=/e[+-]?\d+/i.test(raw);let n=norm(v);return {raw,n,numeric,scientific,valid:!!n&&!scientific}}
function buildIndex(kind){let m=new Map();let bad=0,numeric=0;for(const r of state.data[kind]){let v=kind==='rec'?field(r,['Nº Série']):kind==='emb'?field(r,['Série']):field(r,['Nº_DE_SÉRIE']);let si=serialInfo(v);if(!si.valid){bad++;if(si.numeric||si.scientific)numeric++;continue}if(!m.has(si.n))m.set(si.n,[]);m.get(si.n).push(r)}state.indexes[kind]=m;return {bad,numeric}}
function buildRawIndex(kind){let m=new Map();let bad=0,numeric=0;for(const r of state.rawData[kind]){let v=kind==='rec'?field(r,['Nº Série']):kind==='emb'?field(r,['Série']):field(r,['Nº_DE_SÉRIE']);let si=serialInfo(v);if(!si.valid){bad++;if(si.numeric||si.scientific)numeric++;continue}if(!m.has(si.n))m.set(si.n,[]);m.get(si.n).push(r)}state.rawIndexes[kind]=m;return {bad,numeric}}
function levenshtein(a,b){if(a===b)return 0;if(Math.abs(a.length-b.length)>1)return 2;let prev=Array.from({length:b.length+1},(_,i)=>i);for(let i=1;i<=a.length;i++){let cur=[i];for(let j=1;j<=b.length;j++)cur[j]=Math.min(cur[j-1]+1,prev[j]+1,prev[j-1]+(a[i-1]===b[j-1]?0:1));prev=cur}return prev[b.length]}
function similarity(a,b){return 1-levenshtein(a,b)/Math.max(a.length,b.length)}
function nearDuplicates(m){let seen=new Map(), pairs=[];for(const [s,rows] of m){if(s.length<4||s.length>50)continue;for(let i=0;i<s.length;i++){let sig=s.slice(0,i)+'_'+s.slice(i+1);if(seen.has(sig)){for(const other of seen.get(sig)){if(other!==s){let sim=similarity(s,other);if(sim>=.98)pairs.push([other,s,sim])}}}if(!seen.has(sig))seen.set(sig,[s]);else if(seen.get(sig).length<4)seen.get(sig).push(s)}}return pairs.slice(0,500)}
function crossIssues(){let arm=state.rawIndexes.arm,exp=state.rawIndexes.exp,rec=state.rawIndexes.rec;let inMonth=(kind,r)=>!state.filterMonth||monthKey(processDateValue(kind,r))===state.filterMonth;let receivedMissing=[],shippedInStock=[];for(const [s,rows] of rec){if(inMonth('rec',rows[0])&&!arm.has(s)&&!exp.has(s))receivedMissing.push({s,rec:rows[0]})}for(const [s,rows] of exp){let first=rows.find(r=>norm(field(r,['STATUS']))==='ATIVO');if(first&&inMonth('exp',first)&&arm.has(s))shippedInStock.push({s,exp:first,arm:arm.get(s)[0]})}let dup=[...arm.entries()].filter(([,rows])=>rows.length>1).map(([s,rows])=>({s,rows})).filter(x=>inMonth('arm',x.rows[0]));let near=nearDuplicates(arm).filter(x=>{let rows=arm.get(x[0])||arm.get(x[1])||[];return rows.some(r=>inMonth('arm',r))});let stMissing=[];for(const [serial,rows] of arm){let stRows=rows.filter(r=>norm(field(r,['DEPÓSITO']))==='ST');if(stRows.length&&!state.rawIndexes.emb.has(serial)&&stRows.some(r=>inMonth('arm',r)))stMissing.push({s:serial,arm:stRows[0]})}state.issues={receivedMissing,shippedInStock,dup,near,stMissing};}
function evolutionInvalid(kind){let result=[];for(const r of state.rawData[kind]){let v=kind==='rec'?field(r,['Nº Série']):kind==='emb'?field(r,['Série']):field(r,['Nº_DE_SÉRIE']);let si=serialInfo(v);if(!si.valid)result.push('registro-'+result.length)}return result}
function evolutionCurrent(){let a=state.issues, result={};
 const alertMap={receivedMissing:a.receivedMissing.map(x=>x.s),stMissing:a.stMissing.map(x=>x.s),shippedInStock:a.shippedInStock.map(x=>x.s),dup:a.dup.map(x=>x.s),near:a.near.map(x=>[x[0],x[1]].sort().join(' ↔ '))};
 for(const [k,ids] of Object.entries(alertMap))result[k]={count:ids.length,ids:[...new Set(ids)]};
 for(const kind of ['rec','emb','arm','exp']){let invalid=evolutionInvalid(kind);result[kind+'Invalid']={count:invalid.length};}
 const emb=state.rawData.emb,arm=state.rawData.arm,exp=state.rawData.exp;
 result.recTotal={count:state.rawData.rec.length};result.embTotal={count:emb.length};result.armTotal={count:arm.length};
 result.expActive={count:exp.filter(r=>norm(field(r,['STATUS']))==='ATIVO').length};
 result.expCancelled={count:exp.filter(r=>norm(field(r,['STATUS']))!=='ATIVO').length};
 result.embRepack={count:emb.filter(r=>!isBlank(field(r,['Motivo_se_Reembalagem']))).length};
 result.armOver90={count:arm.filter(r=>{let d=dateObj(field(r,['ENTRADA']));return d&&(Date.now()-d.getTime())>90*86400000}).length};
 return result;
}
function evolutionEntryDates(){
 const map={};for(const r of state.rawData.arm){const s=serialInfo(field(r,['Nº_DE_SÉRIE']));if(!s.valid)continue;const dt=dateObj(field(r,['ENTRADA']));if(!dt)continue;const date=[dt.getFullYear(),String(dt.getMonth()+1).padStart(2,'0'),String(dt.getDate()).padStart(2,'0')].join('-');if(!map[s.n]||date<map[s.n])map[s.n]=date}
 return map;
}
function evolutionStorageDetails(){
 const result={};
 for(const r of state.rawData.arm){
  const s=serialInfo(field(r,['Nº_DE_SÉRIE']));if(!s.valid)continue;
  const dt=dateObj(field(r,['ENTRADA']));const date=dt?[dt.getFullYear(),String(dt.getMonth()+1).padStart(2,'0'),String(dt.getDate()).padStart(2,'0')].join('-'):null;
  const detail={user:String(field(r,['USUÁRIO_REGISTRO'])||'').trim(),deposit:String(field(r,['DEPÓSITO'])||'').trim(),address:String(field(r,['ENDEREÇO'])||'').trim(),entry:date};
  if(!result[s.n]||(date&&(!result[s.n].entry||date>result[s.n].entry)))result[s.n]=detail;
 }
 return result;
}
function evolutionCompactSnapshot(s){
 const ids=new Set();
 for(const m of Object.values(s.metrics||{}))if(Array.isArray(m.ids))for(const id of m.ids){
  if(typeof id!=='string')continue;
  ids.add(id);
  // Alertas de pares usam a forma 'serie ↔ serie'.
  if(id.includes(' ↔ '))for(const part of id.split(' ↔ '))ids.add(part);
 }
 const keep=obj=>{const out={};if(obj&&typeof obj==='object')for(const id of ids)if(Object.prototype.hasOwnProperty.call(obj,id))out[id]=obj[id];return out};
 return {...s,entryDates:keep(s.entryDates),storageDetails:keep(s.storageDetails)};
}
function snapshot(){
 const manifest=JSON.parse(fs.readFileSync(path.join(base,'manifest.json'),'utf8').replace(/^\uFEFF/,''));
 if(!manifest.atualizado_em)throw Error('Manifesto sem atualizado_em');
 const dt=new Date(manifest.atualizado_em);
 if(!Number.isFinite(dt.getTime()))throw Error('Data invalida no manifesto');
 const date=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Sao_Paulo',year:'numeric',month:'2-digit',day:'2-digit'}).format(dt);
 for(const [k,f] of Object.entries({rec:'recebimento',emb:'embalagem',arm:'armazenagem',exp:'expedicao'})){
  const raw=zlib.gunzipSync(fs.readFileSync(path.join(base,f+'.json.gz')));
  const obj=JSON.parse(raw.toString('utf8').replace(/^\uFEFF/,''));
  const prepared=prepare(k,obj);
  if(!prepared.mapped.length)throw Error('Base vazia: '+k);
  state.rawData[k]=prepared.mapped;state.data[k]=prepared.mapped;
  buildRawIndex(k);buildIndex(k);
 }
 crossIssues();
 const s={date,updated:manifest.atualizado_em,metrics:evolutionCurrent(),entryDates:evolutionEntryDates(),storageDetails:evolutionStorageDetails()};
 return evolutionCompactSnapshot(s);
}
try{
 const s=snapshot();let history=[];
 if(fs.existsSync(output)){
  const existing=JSON.parse(fs.readFileSync(output,'utf8').replace(/^\uFEFF/,''));
  history=Array.isArray(existing)?existing:existing.snapshots;
  if(!Array.isArray(history))throw Error('Historico publicado invalido');
 }
 const i=history.findIndex(x=>x.date===s.date);
 if(i>=0)history[i]=s;else history.push(s);
 history.sort((a,b)=>a.date.localeCompare(b.date));
 const data=JSON.stringify({schema:1,snapshots:history});
 fs.mkdirSync(path.dirname(output),{recursive:true});
 const tmp=output+'.tmp';fs.writeFileSync(tmp,data);fs.renameSync(tmp,output);
 console.log('Fotografia '+s.date+' gerada: '+s.metrics.receivedMissing.count+' recebimentos sem destino; '+history.length+' data(s).');
}catch(e){console.error('ERRO ao gerar fotografia:',e.stack||e.message);process.exit(1)}
