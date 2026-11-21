/* ===== Motor de geração de questões (determinístico por semente) ===== */
(function (root) {
'use strict';
function mulberry32(a){return function(){a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296;};}
function RNG(seed){const f=mulberry32(seed>>>0);return{f,
  int:(a,b)=>a+Math.floor(f()*(b-a+1)),
  pick:a=>a[Math.floor(f()*a.length)],
  shuffle:a=>{a=a.slice();for(let i=a.length-1;i>0;i--){const j=Math.floor(f()*(i+1));const t=a[i];a[i]=a[j];a[j]=t;}return a;},
  chance:p=>f()<p};}

/* ---------- vocabulário ---------- */
const SH={circle:{sym:0},triangle:{sym:120,sides:3},square:{sym:90,sides:4},pentagon:{sym:72,sides:5},hexagon:{sym:60,sides:6},star:{sym:72},cross:{sym:90},arrow:{sym:360},half:{sym:360},flag:{sym:360}};
const SHAPE_PT={circle:'círculo',triangle:'triângulo',square:'quadrado',pentagon:'pentágono',hexagon:'hexágono',star:'estrela',cross:'cruz',arrow:'seta',half:'meia-lua',flag:'bandeira'};
const POLY=['triangle','square','pentagon','hexagon'];
const SYMM=['circle','triangle','square','pentagon','hexagon','star','cross'];
const ASYM=['arrow','half','flag'];
const FILL_PT=['vazio','cinza','cheio'];
const ATTR_PT={count:'Quantidade',shape:'Forma',size:'Tamanho',fill:'Preenchimento',rot:'Rotação',mark:'Ponto externo',lines:'Linhas'};
const RULE_PT={prog:'progressão',alt:'alternância',cyc3:'ciclo de 3',inter:'séries intercaladas',row:'constante na linha',col:'constante na coluna',dist3:'distribuição de três',add:'soma',sub:'subtração',or:'união (OU)',xor:'diferença (XOU)',and:'interseção (E)',const:'mudou o que era fixo'};
const SPECIAL={
  'esp:espelho':'Espacial · espelhada tomada por girada','esp:forma':'Espacial · forma alterada não percebida',
  'esp:eixo':'Espacial · eixo do espelho trocado','esp:rotespelho':'Espacial · giro tomado por reflexo',
  'int:lados':'Intrusa · pontos = número de lados','int:interna':'Intrusa · forma interna = externa','int:espelho':'Intrusa · figura espelhada',
  'ana:count':'Analogia · quantidade','ana:size':'Analogia · tamanho','ana:fill':'Analogia · preenchimento','ana:rot':'Analogia · rotação',
  'ana:shape':'Analogia · número de lados','ana:lines':'Analogia · linhas','ana:mark':'Analogia · ponto externo','tempo':'Tempo esgotado'};
function keyLabel(k){if(SPECIAL[k])return SPECIAL[k];const[a,r]=k.split(':');return (ATTR_PT[a]||a)+' · '+(RULE_PT[r]||r);}
const FAMS={seq:'Sequência',mat:'Matriz 3×3',ana:'Analogia',esp:'Rotação e espelho',int:'Figura intrusa'};

/* pools: [atributo, regra, nível mínimo] */
const SEQ_POOL=[['count','prog',1],['fill','cyc3',1],['shape','alt',1],['fill','alt',2],['count','alt',3],['rot','prog',3],['mark','prog',3],['shape','cyc3',4],['size','alt',5],['size','cyc3',5],['count','cyc3',6],['mark','alt',6],['count','inter',7],['rot','inter',7],['mark','inter',7]];
const MAT_POOL=[['count','row',1],['count','prog',1],['size','prog',1],['fill','row',1],['shape','row',1],['fill','prog',2],['shape','dist3',3],['count','dist3',3],['fill','dist3',3],['size','dist3',3],['shape','col',3],['count','col',4],['rot','prog',5],['rot','dist3',5],['count','add',5],['lines','or',5],['count','sub',7],['lines','xor',7],['lines','and',9]];
const ANA_POOL=[['count','ana',1],['fill','ana',1],['size','ana',1],['rot','ana',3],['shape','ana',5],['lines','ana',5],['mark','ana',7]];
const ESP_KEYS={'esp:espelho':1,'esp:forma':1,'esp:eixo':3,'esp:rotespelho':3};
const INT_KEYS={'int:lados':1,'int:interna':1,'int:espelho':7};
function poolKey(e){return e[1]==='ana'?'ana:'+e[0]:e[0]+':'+e[1];}
/* em que famílias / nível mínimo uma chave pode aparecer (para treino focado) */
function whereKey(k){const out=[];
  SEQ_POOL.forEach(e=>{if(poolKey(e)===k)out.push(['seq',e[2]]);});
  MAT_POOL.forEach(e=>{if(poolKey(e)===k)out.push(['mat',e[2]]);});
  ANA_POOL.forEach(e=>{if(poolKey(e)===k)out.push(['ana',e[2]]);});
  if(ESP_KEYS[k])out.push(['esp',ESP_KEYS[k]]);if(INT_KEYS[k])out.push(['int',INT_KEYS[k]]);
  if(!out.length&&k.endsWith(':const'))out.push(['seq',1],['mat',1],['ana',1]);
  return out;}

function pickRules(rng,pool,L,n,prefer){
  const cand=pool.filter(e=>e[2]<=L);const pf=new Set(prefer||[]);
  const order=rng.shuffle(cand.filter(e=>pf.has(poolKey(e)))).concat(rng.shuffle(cand.filter(e=>!pf.has(poolKey(e)))));
  const out=[],used=new Set();
  for(const e of order){if(out.length>=n)break;if(used.has(e[0]))continue;used.add(e[0]);out.push({attr:e[0],rule:e[1],key:poolKey(e)});}
  return out;}

/* ---------- painel ---------- */
function P(o){return Object.assign({shape:'circle',count:1,size:2,fill:0,rot:0,mark:-1,lines:0},o);}
function normRot(p){const s=SH[p.shape].sym;if(!s)return 0;return ((p.rot*45)%s+s)%s;}
function vkey(p){return [p.shape,p.count,p.size,p.fill,normRot(p),p.mark,p.lines].join('|');}
const ATTRS=['shape','count','size','fill','rot','mark','lines'];
function popc(m){let c=0;while(m){c+=m&1;m>>=1;}return c;}
function randMask(rng,maxBits){let m=0;const n=rng.int(1,maxBits||3);rng.shuffle([0,1,2,3,4,5]).slice(0,n).forEach(b=>m|=1<<b);return m;}
const plural=(n,s,p)=>n===1?s:p;
const dirTxt=k=>(k>0?'horário':'anti-horário');

/* ---------- opções balanceadas (estilo I-RAVEN) ---------- */
function subsetsBalanced(rng,k,nOpts){
  if(nOpts===8&&k===3)return [[],[0],[1],[2],[0,1],[0,2],[1,2],[0,1,2]];
  const all=[];for(let m=1;m<(1<<k);m++){const s=[];for(let i=0;i<k;i++)if(m&(1<<i))s.push(i);all.push(s);}
  const need=nOpts-1;const combos=[];
  (function rec(start,acc){if(acc.length===need){combos.push(acc.slice());return;}for(let i=start;i<all.length;i++){acc.push(all[i]);rec(i+1,acc);acc.pop();}})(0,[]);
  const good=combos.filter(c=>{for(let i=0;i<k;i++){const right=1+c.filter(s=>!s.includes(i)).length;if(right<2||right>3)return false;}return true;});
  return [[]].concat(rng.pick(good.length?good:combos));}
function buildOptions(rng,ans,flips,nOpts){
  const subs=subsetsBalanced(rng,flips.length,nOpts);
  for(let t=0;t<16;t++){
    const wrong=flips.map(f=>t===0?f.cands[0]:rng.pick(f.cands.slice(0,Math.min(f.cands.length,2+t))));
    const opts=subs.map(S=>{const p=Object.assign({},ans);S.forEach(i=>p[flips[i].attr]=wrong[i]);return{p,errs:S.map(i=>flips[i].key)};});
    if(new Set(opts.map(o=>vkey(o.p))).size===opts.length)return opts;}
  return null;}
function finalize(rng,item,opts,mkFig){
  const order=rng.shuffle(opts.map((_,i)=>i));
  item.options=order.map(i=>Object.assign({fig:mkFig(opts[i]),errs:opts[i].errs,why:opts[i].why||''},opts[i].tr?{tr:opts[i].tr}:{}));
  item.answer=order.indexOf(0);
  const ks=new Set(item.ruleKeys||[]);item.options.forEach(o=>o.errs.forEach(e=>ks.add(e)));item.keys=[...ks];
  return item;}
function uniq(a){return [...new Set(a)];}
function near(rng,dom,x){return typeof x==='number'&&dom.length&&typeof dom[0]==='number'?rng.shuffle(dom).sort((a,b)=>Math.abs(a-x)-Math.abs(b-x)):rng.shuffle(dom);}

/* ======================= SEQUÊNCIA ======================= */
function seqPredict(attr,v){
  const preds=new Set(),n=v.length;
  const cyc=attr==='fill'?3:(attr==='rot'||attr==='mark')?8:0;
  const isNum=attr==='count'||attr==='size'||cyc>0;
  const mod=x=>cyc?((x%cyc)+cyc)%cyc:x;const diff=(a,b)=>mod(b-a);
  const inDom=x=>attr==='count'?x>=1&&x<=9:attr==='size'?x>=0&&x<=2:true;
  if(v.every(x=>x===v[0]))preds.add(v[0]);
  if(v.every((x,i)=>i<2||x===v[i-2]))preds.add(v[n-2]);
  if(v.every((x,i)=>i<3||x===v[i-3]))preds.add(v[n-3]);
  if(isNum&&!(attr==='mark'&&v.includes(-1))){
    const d=diff(v[0],v[1]);if(v.every((x,i)=>i===0||diff(v[i-1],x)===d)){const x=mod(v[n-1]+d);if(inDom(x))preds.add(x);}
    const dE=diff(v[0],v[2]);if(diff(v[2],v[4])===dE){const x=mod(v[3]+diff(v[1],v[3]));if(inDom(x))preds.add(x);}
  }
  return preds;}
function genSeq(rng,L,prefer){
  const nVar=L<=2?1:L<=5?2:L<=8?3:4;
  const rules=pickRules(rng,SEQ_POOL,L,nVar,prefer);const R={};rules.forEach(r=>R[r.attr]=r.rule);
  const N=6;const S={};const ex=[];
  const pool=R.rot?ASYM:(rng.chance(.25)?ASYM:SYMM);
  const rep=(f)=>[...Array(N)].map((_,i)=>f(i));
  // forma
  if(R.shape==='alt'){const s=rng.shuffle(pool).slice(0,2);S.shape=rep(i=>s[i%2]);ex.push('Forma: alterna entre '+SHAPE_PT[s[0]]+' e '+SHAPE_PT[s[1]]+'.');}
  else if(R.shape==='cyc3'){const s=rng.shuffle(pool).slice(0,3);S.shape=rep(i=>s[i%3]);ex.push('Forma: repete o ciclo '+s.map(x=>SHAPE_PT[x]).join(' → ')+'.');}
  else{const s=rng.pick(pool);S.shape=rep(()=>s);}
  // quantidade
  if(R.count==='prog'){const d=rng.pick([1,1,-1]);const s=d>0?rng.int(1,4):rng.int(6,9);S.count=rep(i=>s+i*d);ex.push('Quantidade: '+(d>0?'aumenta':'diminui')+' 1 a cada figura.');}
  else if(R.count==='alt'){const s=rng.shuffle([1,2,3,4,5,6]).slice(0,2);S.count=rep(i=>s[i%2]);ex.push('Quantidade: alterna entre '+s[0]+' e '+s[1]+'.');}
  else if(R.count==='cyc3'){const s=rng.shuffle([1,2,3,4,5,6]).slice(0,3);S.count=rep(i=>s[i%3]);ex.push('Quantidade: repete o ciclo '+s.join(', ')+'.');}
  else if(R.count==='inter'){let ok=false,e,o,dE,dO;for(let t=0;t<30&&!ok;t++){e=rng.int(1,5);o=rng.int(1,5);dE=rng.pick([1,2,-1,0]);dO=rng.pick([1,2,-1,0]);
      if(dE===dO)continue;const vals=rep(i=>i%2?o+((i-1)/2)*dO:e+(i/2)*dE);if(vals.every(x=>x>=1&&x<=9)){S.count=vals;ok=true;}}
    if(!ok)return null;ex.push('Quantidade: duas séries intercaladas — nas posições ímpares '+(dE?(dE>0?'soma ':'subtrai ')+Math.abs(dE):'fica igual')+', nas pares '+(dO?(dO>0?'soma ':'subtrai ')+Math.abs(dO):'fica igual')+'.');}
  else{const c=rng.int(1,3);S.count=rep(()=>c);}
  // tamanho
  if(R.size==='alt'){const s=rng.shuffle([0,1,2]).slice(0,2);S.size=rep(i=>s[i%2]);ex.push('Tamanho: alterna entre dois tamanhos.');}
  else if(R.size==='cyc3'){const s=rng.shuffle([0,1,2]);S.size=rep(i=>s[i%3]);ex.push('Tamanho: repete um ciclo de três tamanhos.');}
  else{const s=rng.pick([1,2]);S.size=rep(()=>s);}
  // preenchimento
  if(R.fill==='cyc3'){const s=rng.int(0,2),d=rng.pick([1,2]);S.fill=rep(i=>(s+i*d)%3);ex.push('Preenchimento: ciclo '+[0,1,2].map(i=>FILL_PT[(s+i*d)%3]).join(' → ')+'.');}
  else if(R.fill==='alt'){const s=rng.shuffle([0,1,2]).slice(0,2);S.fill=rep(i=>s[i%2]);ex.push('Preenchimento: alterna entre '+FILL_PT[s[0]]+' e '+FILL_PT[s[1]]+'.');}
  else{const s=rng.int(0,2);S.fill=rep(()=>s);}
  // rotação / ponto externo
  const cycRule=(attr,rule,name,unit)=>{
    if(rule==='prog'){const k=rng.pick(L<5?[1,2]:[1,2,3])*rng.pick([1,-1]);const s=rng.int(0,7);S[attr]=rep(i=>((s+i*k)%8+8)%8);
      ex.push(attr==='rot'?'Rotação: gira '+Math.abs(k)*45+'° no sentido '+dirTxt(k)+' a cada figura.':'Ponto externo: anda '+Math.abs(k)+' '+plural(Math.abs(k),'casa','casas')+' no sentido '+dirTxt(k)+' a cada figura.');}
    else if(rule==='alt'){const s=rng.shuffle([0,1,2,3,4,5,6,7]).slice(0,2);S[attr]=rep(i=>s[i%2]);ex.push(name+': alterna entre duas posições.');}
    else if(rule==='inter'){let kE,kO;do{kE=rng.pick([0,1,2,3,-1,-2]);kO=rng.pick([0,1,2,3,-1,-2]);}while(kE===kO);
      const e=rng.int(0,7),o=rng.int(0,7);S[attr]=rep(i=>((i%2?o+((i-1)/2)*kO:e+(i/2)*kE)%8+8)%8);
      const t=k=>k?(Math.abs(k)*unit)+(attr==='rot'?'°':' '+plural(Math.abs(k),'casa','casas'))+' '+dirTxt(k):'fica parado';
      ex.push(name+': duas séries intercaladas — posições ímpares: '+t(kE)+'; pares: '+t(kO)+'.');}
  };
  if(R.rot)cycRule('rot',R.rot,'Rotação',45);else{const r=pool===ASYM?rng.int(0,7):0;S.rot=rep(()=>r);}
  if(R.mark)cycRule('mark',R.mark,'Ponto externo',1);else{const m=(L>=6&&rng.chance(.35))?rng.int(0,7):-1;S.mark=rep(()=>m);}
  S.lines=rep(()=>0);
  const panels=rep(i=>P({shape:S.shape[i],count:S.count[i],size:S.size[i],fill:S.fill[i],rot:S.rot[i],mark:S.mark[i],lines:S.lines[i]}));
  const known=panels.slice(0,5),ans=panels[5];
  for(const a of ATTRS){const pr=seqPredict(a,known.map(p=>p[a]));if(pr.size!==1||!pr.has(ans[a]))return null;}
  // alternativas
  const ruleAttrs=rng.shuffle(rules.map(r=>r.attr)).slice(0,3);
  const constAttrs=rng.shuffle(['fill','size','count','shape'].filter(a=>!R[a]));
  const flipAttrs=ruleAttrs.concat(constAttrs).slice(0,3);
  const flips=[];
  for(const a of flipAttrs){
    const ctx=known.map(p=>p[a]),x=ans[a],last=ctx[4],prev=ctx[3];const rule=R[a]||'const';
    let c=[];const cyc=a==='fill'?3:(a==='rot'||a==='mark')?8:0;const mod=v=>cyc?((v%cyc)+cyc)%cyc:v;
    if(rule==='prog'||rule==='inter')c=[last,mod(x+(x-last)),prev];else c=[last,prev,ctx[2]];
    const dom=a==='shape'?pool:a==='count'?[1,2,3,4,5,6,7,8,9]:a==='size'||a==='fill'?[0,1,2]:[0,1,2,3,4,5,6,7];
    c=uniq(c.concat(a==='rot'||a==='mark'?rng.shuffle(dom):near(rng,dom,x))).filter(v=>v!==x&&dom.includes(v)&&vkey(Object.assign({},ans,{[a]:v}))!==vkey(ans));
    if(!c.length)return null;
    flips.push({attr:a,key:a+':'+rule,cands:c});}
  const opts=buildOptions(rng,ans,flips,5);if(!opts)return null;
  const compact=panels.some(p=>p.mark>=0);
  const item={fam:'seq',prompt:'Qual figura continua a sequência?',stim:{type:'seq',figs:known.map(p=>({k:'panel',p,compact}))},explain:ex,ruleKeys:rules.map(r=>r.key)};
  const it=finalize(rng,item,opts,o=>({k:'panel',p:o.p,compact}));it._ctx={R,vals:S,ans};return it;}

/* ======================= MATRIZ 3×3 ======================= */
function matPredict(attr,g){
  const preds=new Set();const cyc=attr==='rot'?8:0;const mod=x=>cyc?((x%cyc)+cyc)%cyc:x;const diff=(a,b)=>mod(b-a);
  const inDom=x=>attr==='count'?x>=1&&x<=9:(attr==='size'||attr==='fill')?x>=0&&x<=2:attr==='lines'?x>0:true;
  const k=[g[0][0],g[0][1],g[0][2],g[1][0],g[1][1],g[1][2],g[2][0],g[2][1]];
  if(k.every(x=>x===k[0]))preds.add(k[0]);
  if(g[0].every(x=>x===g[0][0])&&g[1].every(x=>x===g[1][0])&&g[2][0]===g[2][1])preds.add(g[2][0]);
  if([0,1].every(c=>g[0][c]===g[1][c]&&g[1][c]===g[2][c])&&g[0][2]===g[1][2])preds.add(g[0][2]);
  const T=[[g[0][0],g[1][0],g[2][0]],[g[0][1],g[1][1],g[2][1]],[g[0][2],g[1][2],null]];// colunas
  const rowsAndCols=[[g[0],g[1],g[2]],[T[0],T[1],T[2]]];
  for(const[a,b,c]of rowsAndCols){
    if(['count','size','fill','rot'].includes(attr)){
      const d=diff(a[0],a[1]);
      if([a,b].every(r=>diff(r[0],r[1])===d&&diff(r[1],r[2])===d)&&diff(c[0],c[1])===d){const x=mod(c[1]+d);if(inDom(x))preds.add(x);}}
    const sa=new Set(a);
    if(sa.size===3&&b.every(x=>sa.has(x))&&new Set(b).size===3&&c[0]!==c[1]&&sa.has(c[0])&&sa.has(c[1]))preds.add([...sa].find(x=>x!==c[0]&&x!==c[1]));
    if(attr==='count'){
      if([a,b].every(r=>r[0]+r[1]===r[2])){const x=c[0]+c[1];if(inDom(x))preds.add(x);}
      if([a,b].every(r=>r[0]-r[1]===r[2])){const x=c[0]-c[1];if(inDom(x))preds.add(x);}}
    if(attr==='lines'){
      if([a,b].every(r=>(r[0]|r[1])===r[2]))preds.add(c[0]|c[1]);
      if([a,b].every(r=>(r[0]^r[1])===r[2])){const x=c[0]^c[1];if(inDom(x))preds.add(x);}
      if([a,b].every(r=>(r[0]&r[1])===r[2])){const x=c[0]&c[1];if(inDom(x))preds.add(x);}}
  }
  return preds;}
function genMat(rng,L,prefer){
  const nR=L<=2?1:L<=5?2:L<=8?3:4;
  let rules=pickRules(rng,MAT_POOL,L,nR,prefer);
  if(rules.some(r=>r.attr==='lines'))rules=rules.filter(r=>r.attr!=='count');
  const R={};rules.forEach(r=>R[r.attr]=r.rule);
  const pool=R.rot?ASYM:SYMM;const ex=[];const G={};const prm={};
  const domOf=a=>a==='count'?[1,2,3,4,5,6]:a==='size'||a==='fill'?[0,1,2]:a==='rot'?[0,1,2,3,4,5,6,7]:a==='shape'?pool:null;
  const grid=f=>[0,1,2].map(r=>[0,1,2].map(c=>f(r,c)));
  const nm=a=>ATTR_PT[a].toLowerCase();
  for(const r of rules){const a=r.attr,dom=domOf(a);
    if(r.rule==='row'){const v=rng.shuffle(dom).slice(0,3);G[a]=grid(i=>v[i]);ex.push(ATTR_PT[a]+': é igual dentro de cada linha e muda de uma linha para a outra.');}
    else if(r.rule==='col'){const v=rng.shuffle(dom).slice(0,3);G[a]=grid((i,j)=>v[j]);ex.push(ATTR_PT[a]+': é igual dentro de cada coluna.');}
    else if(r.rule==='dist3'){const v=rng.shuffle(dom).slice(0,3);const p=rng.shuffle([0,1,2]),sh=rng.pick([1,2]);G[a]=grid((i,j)=>v[(p[j]+i*sh)%3]);ex.push(ATTR_PT[a]+': cada linha usa os mesmos três valores, sem repetir (distribuição de três).');}
    else if(r.rule==='prog'){
      if(a==='rot'){const d=rng.pick([1,2,3,-1,-2]);const st=rng.shuffle([0,1,2,3,4,5,6,7]).slice(0,3);G[a]=grid((i,j)=>((st[i]+j*d)%8+8)%8);ex.push('Rotação: em cada linha, gira '+Math.abs(d)*45+'° no sentido '+dirTxt(d)+' da esquerda para a direita.');}
      else if(a==='count'){const d=rng.pick([1,2,-1]);const starts=[1,2,3,4,5,6,7,8].filter(s=>s+2*d>=1&&s+2*d<=8);const st=rng.shuffle(starts);G[a]=grid((i,j)=>st[i%st.length]+j*d);ex.push('Quantidade: em cada linha, '+(d>0?'aumenta ':'diminui ')+Math.abs(d)+' da esquerda para a direita.');}
      else{const d=rng.pick([1,-1]);const s=d>0?0:2;G[a]=grid((i,j)=>s+j*d);ex.push(a==='size'?'Tamanho: em cada linha, '+(d>0?'cresce':'diminui')+' da esquerda para a direita.':'Preenchimento: em cada linha, vai de '+FILL_PT[s]+' a '+FILL_PT[s+2*d]+'.');}}
    else if(r.rule==='add'){G[a]=grid(()=>0);for(let i=0;i<3;i++){const x=rng.int(1,4),y=rng.int(1,4);G[a][i]=[x,y,x+y];}ex.push('Quantidade: em cada linha, a 3ª figura tem a soma das duas primeiras.');}
    else if(r.rule==='sub'){G[a]=grid(()=>0);for(let i=0;i<3;i++){const c=rng.int(1,3),y=rng.int(1,4);G[a][i]=[y+c,y,c];}ex.push('Quantidade: em cada linha, a 3ª figura tem a 1ª menos a 2ª.');}
    else if(a==='lines'){G[a]=grid(()=>0);for(let i=0;i<3;i++){let x,y,z,t=0;do{x=randMask(rng,3);y=randMask(rng,3);z=r.rule==='or'?x|y:r.rule==='xor'?x^y:x&y;t++;}while(t<50&&(x===y||!z||z===x||z===y));G[a][i]=[x,y,z];}
      ex.push(r.rule==='or'?'Linhas: a 3ª figura junta todas as linhas das duas primeiras.':r.rule==='xor'?'Linhas: a 3ª figura mostra só as linhas que aparecem em apenas uma das duas primeiras — as repetidas somem.':'Linhas: a 3ª figura mostra só as linhas que aparecem nas duas primeiras ao mesmo tempo.');}
    prm[a]=r.rule;}
  // constantes
  const cst={shape:rng.pick(pool),count:R.lines?1:rng.int(1,3),size:rng.pick([1,2]),fill:rng.int(0,2),rot:pool===ASYM?rng.int(0,7):0,mark:-1,lines:0};
  for(const a of ATTRS)if(!G[a])G[a]=grid(()=>cst[a]);
  const cells=grid((i,j)=>P({shape:G.shape[i][j],count:G.count[i][j],size:G.size[i][j],fill:G.fill[i][j],rot:G.rot[i][j],mark:-1,lines:G.lines[i][j]}));
  const ans=cells[2][2];
  for(const a of ATTRS){if(a==='mark')continue;const pr=matPredict(a,G[a]);if(pr.size!==1||!pr.has(ans[a]))return null;}
  // alternativas (8, todas as combinações de 3 atributos)
  const flipAttrs=rng.shuffle(rules.map(r=>r.attr)).slice(0,3).concat(rng.shuffle(['fill','size','shape','count'].filter(a=>!R[a]&&!(a==='count'&&R.lines)))).slice(0,3);
  const flips=[];
  for(const a of flipAttrs){const g=G[a],x=ans[a],rule=R[a]||'const';const g0=g[2][0],g1=g[2][1];let c;
    if(rule==='row')c=[g[0][0],g[1][0]];else if(rule==='col')c=[g0,g1];
    else if(rule==='prog'){const d=a==='rot'?((g1-g0)%8+8)%8:g1-g0;c=[g1,a==='rot'?(x+d)%8:x+d,g0];}
    else if(rule==='dist3')c=[g0,g1];else if(rule==='add')c=[Math.abs(g0-g1),g1,g0+g1+1];else if(rule==='sub')c=[g0+g1,g1,g0];
    else if(rule==='or')c=[g0^g1,g0&g1,g0,g1];else if(rule==='xor')c=[g0|g1,g0&g1,g1];else if(rule==='and')c=[g0|g1,g0^g1];else c=[];
    const dom=a==='lines'?null:a==='count'?[1,2,3,4,5,6,7,8,9]:domOf(a);
    c=uniq(c.concat(dom?(a==='rot'?rng.shuffle(dom):near(rng,dom,x)):[])).filter(v=>v!==x&&(dom?dom.includes(v):v>0)&&vkey(Object.assign({},ans,{[a]:v}))!==vkey(ans));
    if(!c.length)return null;flips.push({attr:a,key:a+':'+rule,cands:c});}
  if(flips.length<3)return null;
  const opts=buildOptions(rng,ans,flips,8);if(!opts)return null;
  const figs=[];for(let i=0;i<3;i++)for(let j=0;j<3;j++)if(i<2||j<2)figs.push({k:'panel',p:cells[i][j]});
  const item={fam:'mat',prompt:'Qual figura completa a matriz?',stim:{type:'mat',figs},explain:ex,ruleKeys:rules.map(r=>r.key)};
  const it=finalize(rng,item,opts,o=>({k:'panel',p:o.p}));it._ctx={R,G,ans};return it;}

/* ======================= ANALOGIA ======================= */
function genAna(rng,L,prefer){
  const nOps=L<=3?1:L<=6?2:L<=8?3:4;
  let ops=pickRules(rng,ANA_POOL,L,nOps,prefer);
  if(ops.some(o=>o.attr==='rot')&&ops.some(o=>o.attr==='shape'))ops=ops.filter(o=>o.attr!=='shape');
  const O={};ops.forEach(o=>O[o.attr]=true);
  const pool=O.rot?ASYM:O.shape?POLY:(rng.chance(.3)?ASYM:SYMM);
  const rp=()=>P({shape:rng.pick(pool),count:rng.int(1,4),size:rng.int(0,2),fill:rng.int(0,2),rot:pool===ASYM?rng.int(0,7):0,mark:O.mark?rng.int(0,7):-1,lines:O.lines?randMask(rng,2):0});
  const A=rp(),C=rp();if(O.fill)C.fill=A.fill;
  const T={};const ex=[];
  if(O.count){T.count=rng.pick([1,2,-1,-2]);}
  if(O.size){T.size=rng.pick([1,-1]);}
  if(O.fill){T.fill=rng.pick([0,1,2].filter(v=>v!==A.fill));}
  if(O.rot){T.rot=rng.pick([1,2,3,-1,-2,-3]);}
  if(O.mark){T.mark=rng.pick([1,2,3,-1,-2]);}
  if(O.shape){T.shape=rng.pick([1,-1]);}
  if(O.lines){T.lmode=L>=7?rng.pick(['add','xor']):'add';T.M=randMask(rng,2);}
  const apply=X=>{const Y=Object.assign({},X);
    if(O.count)Y.count=X.count+T.count;if(O.size)Y.size=X.size+T.size;if(O.fill)Y.fill=T.fill;
    if(O.rot)Y.rot=((X.rot+T.rot)%8+8)%8;if(O.mark)Y.mark=((X.mark+T.mark)%8+8)%8;
    if(O.shape){const i=POLY.indexOf(X.shape)+T.shape;Y.shape=POLY[i];}
    if(O.lines)Y.lines=T.lmode==='add'?X.lines|T.M:X.lines^T.M;return Y;};
  const B=apply(A),D=apply(C);
  const ok=X=>X.count>=1&&X.count<=6&&X.size>=0&&X.size<=2&&X.shape&&(!O.lines||X.lines>0);
  if(!ok(B)||!ok(D))return null;
  if(vkey(A)===vkey(B)||vkey(C)===vkey(D)||vkey(A)===vkey(C))return null;
  if(O.lines&&T.lmode==='add'&&(B.lines===A.lines||D.lines===C.lines))return null;
  if(ATTRS.filter(a=>A[a]!==C[a]).length<2)return null;
  // solucionador
  for(const a of ATTRS){const pr=new Set();
    if(A[a]===B[a])pr.add(C[a]);
    else{
      if(a==='count'||a==='size'){pr.add(C[a]+B[a]-A[a]);if(a==='count'&&A[a]>0&&B[a]%A[a]===0&&B[a]/A[a]>=2)pr.add(C[a]*B[a]/A[a]);if(a==='count'&&B[a]>0&&A[a]%B[a]===0&&A[a]/B[a]>=2&&C[a]%(A[a]/B[a])===0)pr.add(C[a]/(A[a]/B[a]));}
      if(a==='fill'){if(C.fill===A.fill)pr.add(B.fill);const x=C.fill+B.fill-A.fill;if(x>=0&&x<=2)pr.add(x);}
      if(a==='rot'||a==='mark')pr.add(((C[a]+B[a]-A[a])%8+8)%8);
      if(a==='shape'){if(C.shape===A.shape)pr.add(B.shape);if(POLY.includes(A.shape)&&POLY.includes(B.shape)&&POLY.includes(C.shape)){const s=POLY[POLY.indexOf(C.shape)+POLY.indexOf(B.shape)-POLY.indexOf(A.shape)];if(s)pr.add(s);}}
      if(a==='lines'){pr.add(C.lines^(A.lines^B.lines));if((A.lines&B.lines)===A.lines)pr.add(C.lines|B.lines&~A.lines);if((A.lines&B.lines)===B.lines)pr.add(C.lines&~(A.lines&~B.lines));}
    }
    if(pr.size!==1||!pr.has(D[a]))return null;}
  if(O.count)ex.push('Quantidade: de A para B '+(T.count>0?'aumenta ':'diminui ')+Math.abs(T.count)+'; faça o mesmo com C.');
  if(O.size)ex.push('Tamanho: de A para B a figura '+(T.size>0?'cresce':'diminui')+' um nível.');
  if(O.fill)ex.push('Preenchimento: o '+FILL_PT[A.fill]+' de A vira '+FILL_PT[B.fill]+' em B.');
  if(O.rot)ex.push('Rotação: de A para B gira '+Math.abs(T.rot)*45+'° no sentido '+dirTxt(T.rot)+'.');
  if(O.mark)ex.push('Ponto externo: anda '+Math.abs(T.mark)+' '+plural(Math.abs(T.mark),'casa','casas')+' no sentido '+dirTxt(T.mark)+'.');
  if(O.shape)ex.push('Forma: de A para B a figura '+(T.shape>0?'ganha':'perde')+' um lado.');
  if(O.lines)ex.push(T.lmode==='add'?'Linhas: as mesmas linhas são acrescentadas.':'Linhas: as linhas marcadas trocam — aparecem onde não havia e somem onde havia.');
  ex.push('Os demais atributos de C não mudam.');
  const flipAttrs=rng.shuffle(ops.map(o=>o.attr)).slice(0,3).concat(rng.shuffle(['fill','size','shape','count'].filter(a=>!O[a]))).slice(0,3);
  const flips=[];
  for(const a of flipAttrs){const x=D[a];let c;
    if(O[a]){c=[C[a],B[a]];if(a==='count')c.push(D.count+T.count);if(a==='rot')c.push(((D.rot+T.rot)%8+8)%8);}
    else c=[A[a],B[a]];
    const dom=a==='shape'?pool:a==='count'?[1,2,3,4,5,6]:a==='size'||a==='fill'?[0,1,2]:a==='lines'?[]:[0,1,2,3,4,5,6,7];
    c=uniq(c.concat(a==='rot'||a==='mark'?rng.shuffle(dom):near(rng,dom,x))).filter(v=>v!==x&&(a==='lines'?v>0:dom.includes(v))&&vkey(Object.assign({},D,{[a]:v}))!==vkey(D));
    if(!c.length)return null;flips.push({attr:a,key:O[a]?'ana:'+a:a+':const',cands:c});}
  const opts=buildOptions(rng,D,flips,5);if(!opts)return null;
  const compact=!!O.mark;
  const item={fam:'ana',prompt:'A está para B assim como C está para…',stim:{type:'ana',figs:[A,B,C].map(p=>({k:'panel',p,compact}))},explain:ex,ruleKeys:ops.map(o=>o.key)};
  const it=finalize(rng,item,opts,o=>({k:'panel',p:o.p,compact}));it._ctx={A,B,C,D,O,T};return it;}

/* ======================= POLIMINÓS (espacial) ======================= */
function pNorm(cs){const mx=Math.min(...cs.map(c=>c.x)),my=Math.min(...cs.map(c=>c.y));return cs.map(c=>({x:c.x-mx,y:c.y-my,m:c.m?1:0})).sort((a,b)=>a.y-b.y||a.x-b.x);}
function pKey(cs){return pNorm(cs).map(c=>c.x+','+c.y+(c.m?'*':'')).join(' ');}
function pRot(cs){return pNorm(cs.map(c=>({x:-c.y,y:c.x,m:c.m})));}
function pRotN(cs,n){for(let i=0;i<((n%4)+4)%4;i++)cs=pRot(cs);return pNorm(cs);}
function pMirH(cs){return pNorm(cs.map(c=>({x:-c.x,y:c.y,m:c.m})));}
function pMirV(cs){return pNorm(cs.map(c=>({x:c.x,y:-c.y,m:c.m})));}
function pAll(cs){const o=[];for(let r=0;r<4;r++){o.push(pRotN(cs,r));o.push(pRotN(pMirH(cs),r));}return o;}
function pConnected(cs){if(!cs.length)return false;const set=new Set(cs.map(c=>c.x+','+c.y));const seen=new Set([cs[0].x+','+cs[0].y]);const st=[cs[0]];
  while(st.length){const c=st.pop();for(const[dx,dy]of[[1,0],[-1,0],[0,1],[0,-1]]){const k=(c.x+dx)+','+(c.y+dy);if(set.has(k)&&!seen.has(k)){seen.add(k);st.push({x:c.x+dx,y:c.y+dy});}}}
  return seen.size===cs.length;}
function genPoly(rng,n,maxW,marks){
  for(let t=0;t<200;t++){const cs=[{x:0,y:0}];let g=0;
    while(cs.length<n&&g++<400){const b=rng.pick(cs),[dx,dy]=rng.pick([[1,0],[-1,0],[0,1],[0,-1]]);const x=b.x+dx,y=b.y+dy;
      if(cs.some(c=>c.x===x&&c.y===y))continue;const xs=cs.map(c=>c.x).concat(x),ys=cs.map(c=>c.y).concat(y);
      if(Math.max(...xs)-Math.min(...xs)>=maxW||Math.max(...ys)-Math.min(...ys)>=maxW)continue;cs.push({x,y});}
    if(cs.length<n)continue;
    rng.shuffle(cs.map((_,i)=>i)).slice(0,marks).forEach(i=>cs[i].m=1);
    const P0=pNorm(cs);if(new Set(pAll(P0).map(pKey)).size===8)return P0;}
  return null;}
function pAlter(rng,cs,forbidden){
  for(let t=0;t<60;t++){const marks=cs.filter(c=>c.m);
    if(marks.length&&rng.chance(.4)){const mi=cs.map((c,i)=>c.m?i:-1).filter(i=>i>=0),ui=cs.map((c,i)=>c.m?-1:i).filter(i=>i>=0);
      const a=rng.pick(mi),b=rng.pick(ui);const q=cs.map((c,j)=>({x:c.x,y:c.y,m:j===a?0:j===b?1:c.m}));
      if(!forbidden.has(pKey(q)))return{cs:pNorm(q),why:'A célula escura mudou de lugar.'};continue;}
    const i=rng.int(0,cs.length-1);const rest=cs.filter((_,j)=>j!==i);if(!pConnected(rest))continue;
    const b=rng.pick(rest),[dx,dy]=rng.pick([[1,0],[-1,0],[0,1],[0,-1]]);const x=b.x+dx,y=b.y+dy;
    if(cs.some(c=>c.x===x&&c.y===y))continue;const q=rest.concat([{x,y,m:cs[i].m}]);
    const k=pKey(q);if(!forbidden.has(k))return{cs:pNorm(q),why:'A forma foi alterada: um quadrado mudou de lugar.'};}
  return null;}
function polyLevel(L){return{n:L<=2?4:L<=4?5:L<=6?6:L<=8?7:8,w:L<=8?4:5,marks:L<=4?0:L<=7?1:2};}
function genEsp(rng,L,prefer){
  const pv=polyLevel(L);const base=genPoly(rng,pv.n,pv.w,pv.marks);if(!base)return null;
  const allSet=new Set(pAll(base).map(pKey));
  const pf=prefer||[];let mode=L>=3&&rng.chance(.5)?'esp':'rot';
  if(pf.includes('esp:eixo')||pf.includes('esp:rotespelho'))mode=L>=3?'esp':'rot';if(pf.includes('esp:espelho'))mode='rot';
  const nAlt=L<=2?2:L<=6?1:0;const opts=[];const ex=[];let prompt;let k=0;
  if(mode==='rot'){k=rng.int(1,3);opts.push({cs:pRotN(base,k),errs:[]});
    const mj=rng.shuffle([0,1,2,3]);for(let i=0;i<4-nAlt;i++)opts.push({cs:pRotN(pMirH(base),mj[i]),errs:['esp:espelho'],why:'É a figura espelhada (virada). Só girando não se chega nela.',tr:{m:'h',r:mj[i]}});
    prompt='Qual alternativa é o modelo apenas GIRADO, sem espelhar?';
    ex.push('A correta é o modelo girado '+k*90+'° no sentido horário.','As espelhadas parecem certas, mas exigiriam virar a peça — giro não faz isso. Dica: siga a célula da ponta e veja se ela fica do mesmo lado.');}
  else{opts.push({cs:pMirH(base),errs:[]});
    opts.push({cs:pMirV(base),errs:['esp:eixo'],why:'Foi refletida de cima para baixo — eixo errado.',tr:{m:'v',r:0}});
    const rj=rng.shuffle([1,2,3]);opts.push({cs:pRotN(base,rj[0]),errs:['esp:rotespelho'],why:'É o modelo apenas girado, não refletido.',tr:{m:'none',r:rj[0]}});
    if(nAlt<2){const r=rng.pick([1,3]);opts.push({cs:pRotN(pMirH(base),r),errs:['esp:eixo'],why:'Foi refletida e também girada.',tr:{m:'h',r}});}
    if(nAlt<1)opts.push({cs:pRotN(base,rj[1]),errs:['esp:rotespelho'],why:'É o modelo apenas girado, não refletido.',tr:{m:'none',r:rj[1]}});
    prompt='Qual alternativa é o modelo refletido num espelho colocado ao seu lado (esquerda ↔ direita)?';
    ex.push('A correta é o reflexo lateral: o que está à esquerda passa para a direita, e cima/baixo continuam iguais.');}
  while(opts.length<5){const src=mode==='rot'?pRotN(base,rng.int(0,3)):pRotN(pMirH(base),rng.pick([0,2]));const a=pAlter(rng,src,allSet);if(!a)return null;opts.push({cs:a.cs,errs:['esp:forma'],why:a.why,tr:{alt:1}});}
  if(new Set(opts.map(o=>pKey(o.cs))).size!==5)return null;
  const target=mode==='rot'?new Set([0,1,2,3].map(r=>pKey(pRotN(base,r)))):new Set([pKey(pMirH(base))]);
  if(opts.filter(o=>target.has(pKey(o.cs))).length!==1||!target.has(pKey(opts[0].cs)))return null;
  const item={fam:'esp',prompt,stim:{type:'model',figs:[{k:'poly',cs:base}]},explain:ex,ruleKeys:[]};
  const it=finalize(rng,item,opts,o=>({k:'poly',cs:o.cs}));it._ctx={base,mode,k};return it;}

/* ======================= INTRUSA ======================= */
function genInt(rng,L,prefer){
  const avail=['lados','interna'].concat(L>=7?['espelho']:[]);
  let rule=(prefer||[]).map(k=>k.replace('int:','')).find(r=>avail.includes(r));
  if(!rule)rule=L>=7&&rng.chance(.6)?'espelho':rng.pick(['lados','interna']);
  const noise=L>=4;const j=rng.int(0,4);const figs=[];const ex=[];let why;
  if(rule==='lados'){let sh;do{sh=[0,1,2,3,4].map(()=>rng.pick(POLY));}while(new Set(sh).size<3);
    for(let i=0;i<5;i++){const s=SH[sh[i]].sides;let k=s;if(i===j){k=s+rng.pick([1,-1]);}
      figs.push({k:'int',t:'lados',shape:sh[i],n:k,fill:noise?rng.int(0,1):0,rot:L>=7?rng.int(0,7):0});}
    ex.push('Nas demais, o número de pontos é igual ao número de lados da figura.','Na intrusa, a contagem não bate: '+figs[j].n+' pontos em um '+SHAPE_PT[figs[j].shape]+'.');
    why='Esta segue a regra: pontos = lados.';}
  else if(rule==='interna'){const pool=['circle','triangle','square','pentagon','hexagon'];let sh;do{sh=[0,1,2,3,4].map(()=>rng.pick(pool));}while(new Set(sh).size<3);
    for(let i=0;i<5;i++){let inn=sh[i];if(i===j)inn=rng.pick(pool.filter(s=>s!==sh[i]));figs.push({k:'int',t:'interna',shape:sh[i],inner:inn,fill:noise?rng.int(1,2):2});}
    ex.push('Nas demais, a figura de dentro tem a mesma forma da figura de fora.','Na intrusa, a forma de dentro é diferente.');
    why='Esta segue a regra: dentro e fora têm a mesma forma.';}
  else{const pv=polyLevel(L);const base=genPoly(rng,Math.max(5,pv.n-1),pv.w,L>=9?1:0);if(!base)return null;
    const rs=rng.shuffle([0,1,2,3]);let q=0;var ebase=base;for(let i=0;i<5;i++)figs.push({k:'poly',cs:i===j?pRotN(pMirH(base),rng.int(0,3)):pRotN(base,rs[q++])});
    ex.push('As demais são a mesma peça em posições diferentes (só giradas).','A intrusa é a peça espelhada: nenhum giro transforma as outras nela.');
    why='Esta é a mesma peça das outras, apenas girada.';}
  // checagem de "intrusa superficial" (alguma característica visível isolaria outra figura)
  if(rule!=='espelho'){const feats=rule==='lados'?['shape','fill','n',f=>normRot({shape:f.shape,rot:f.rot})]:['shape','inner','fill'];
    for(const ft of feats){const vals=figs.map(f=>typeof ft==='function'?ft(f):f[ft]);
      for(let i=0;i<5;i++){const others=vals.filter((_,q)=>q!==i);if(others.every(v=>v===others[0])&&vals[i]!==others[0])return null;}}}
  if(new Set(figs.map(f=>f.k==='poly'?pKey(f.cs):JSON.stringify(f))).size<5)return null;
  const opts=[figs[j]].concat(figs.filter((_,i)=>i!==j)).map((f,i)=>({f,errs:i?['int:'+rule]:[],why:i?why:''}));
  const item={fam:'int',prompt:'Qual figura NÃO segue a mesma regra das outras?',stim:{type:'none',figs:[]},explain:ex,ruleKeys:['int:'+rule]};
  // a ordem original das figuras é mantida (a intrusa fica na posição j)
  item.options=figs.map((f,i)=>({fig:f,errs:i===j?[]:['int:'+rule],why:i===j?'':why}));item.answer=j;item.keys=['int:'+rule];
  item._ctx={rule,figs,j,base:typeof ebase!=='undefined'?ebase:null};return item;}

/* ======================= EXPLICAÇÕES (método de observação) ======================= */
const SIZE_PT=['pequeno','médio','grande'];const DIR=['↑','↗','→','↘','↓','↙','←','↖'];const LINE_PT=['│','─','╲','╱','▔','▁'];
const ANAME={count:'quantidade',shape:'forma',size:'tamanho',fill:'preenchimento',rot:'direção',mark:'ponto de fora',lines:'traços'};
const cap1=s=>s[0].toUpperCase()+s.slice(1);
function chip(a,v){switch(a){case'count':return String(v);case'shape':return SHAPE_PT[v];case'size':return SIZE_PT[v];case'fill':return FILL_PT[v];
  case'rot':return DIR[v];case'mark':return v<0?'—':DIR[v];case'lines':return v?[0,1,2,3,4,5].filter(b=>v&(1<<b)).map(b=>LINE_PT[b]).join(' '):'nenhum';}return String(v);}
function chain(vals,a,ansIdx){const out=[];vals.forEach((v,i)=>{if(i)out.push({o:'›'});out.push({v:chip(a,v),ans:i===ansIdx});});return out;}
function turn(k){k=((k%8)+8)%8;const cw=k<=4;const n=cw?k:8-k;return{deg:n*45,dir:cw?'no sentido horário ↻':'no sentido anti-horário ↺',n};}
const TRAP={prog:'Armadilha comum: parar no último valor ou pular um passo a mais.',alt:'Armadilha comum: continuar subindo quando o padrão só vai e volta.',
  cyc3:'Armadilha comum: repetir o último valor em vez de voltar ao início do ciclo.',inter:'Armadilha comum: comparar figuras vizinhas — aqui a série pula uma figura.',
  row:'Armadilha comum: copiar o valor de outra linha.',col:'Armadilha comum: olhar a linha quando a regra está na coluna.',
  dist3:'Armadilha comum: repetir um valor que já apareceu na mesma linha.',add:'Armadilha comum: subtrair em vez de somar, ou copiar a 2ª figura.',
  sub:'Armadilha comum: somar em vez de subtrair.',or:'Armadilha comum: apagar os traços repetidos — nesta regra eles ficam.',
  xor:'Armadilha clássica: juntar tudo. Nesta regra, traço que aparece nas duas some.',and:'Armadilha comum: juntar tudo — aqui só fica o que é comum às duas.',
  const:'Essa característica é igual em todas as figuras; a alternativa mudou o que era fixo.',ana:'Aplique em C exatamente a mudança de A→B: nem mais, nem menos.'};
function panelDiag(it,ansP,ruleOf){it.options.forEach((o,i)=>{if(i===it.answer||o.fig.k!=='panel')return;const p=o.fig.p;const ds=[];
  for(const a of ATTRS){if(a==='rot'){if(p.shape===ansP.shape&&normRot(p)!==normRot(ansP))ds.push(a);}else if(p[a]!==ansP[a])ds.push(a);}
  o.diag={lines:ds.map(a=>cap1(ANAME[a])+': '+chip(a,p[a])+' — deveria ser '+chip(a,ansP[a])+'.'),traps:uniq(ds.map(a=>TRAP[ruleOf[a]||'const']))};});}
const lf=(m,gh)=>({fig:{k:'panel',p:P({count:0,lines:m,ghost:gh||0})}});
function annSeq(it,c){const R=c.R,V=c.vals;
  it.method='Compare as figuras uma característica de cada vez — quantidade, forma, preenchimento, tamanho, direção, ponto de fora — e pergunte: sobe? alterna? repete de 3 em 3?';
  const steps=[];
  for(const a of ATTRS){const r=R[a];if(!r)continue;const v=V[a];let t,ch=chain(v,a,5);
    if(r==='prog'){if(a==='count'){const d=v[1]-v[0];t='Conte as figuras de cada quadro: '+(d>0?'+':'−')+Math.abs(d)+' de um para o próximo.';}
      else{const tr=turn(v[1]-v[0]);t=a==='rot'?'Siga para onde a figura aponta: gira '+tr.deg+'° '+tr.dir+' a cada quadro.':'Siga o ponto de fora: anda '+tr.n+' '+plural(tr.n,'casa','casas')+' '+tr.dir+' a cada quadro.';}}
    else if(r==='alt')t='Vai e volta entre '+chip(a,v[0])+' e '+chip(a,v[1])+': a resposta repete o 4º quadro.';
    else if(r==='cyc3')t='Repete de 3 em 3 ('+[0,1,2].map(i=>chip(a,v[i])).join(' → ')+'): a resposta é igual ao 3º quadro.';
    else if(r==='inter'){t='Olhe pulando um quadro: 1º-3º-5º formam uma série; 2º-4º-resposta formam outra.';ch=[{lab:'1º · 3º · 5º'}].concat(chain([v[0],v[2],v[4]],a,-1),[{gap:1},{lab:'2º · 4º · ?'}],chain([v[1],v[3],v[5]],a,2));}
    steps.push({h:ATTR_PT[a],t,ch});}
  const fixed=['shape','count','size','fill'].filter(a=>!R[a]).map(a=>ANAME[a]+' ('+chip(a,V[a][0])+')');
  if(fixed.length)steps.push({h:'Não muda',t:cap1(fixed.join(', '))+' — a resposta mantém.'});
  it.steps=steps;panelDiag(it,c.ans,R);}
function annMat(it,c){const G=c.G,R=c.R;
  it.method='Leia a 1ª linha da esquerda para a direita, uma característica por vez. Confirme a mesma regra na 2ª linha. Só então aplique na 3ª.';
  const steps=[];
  for(const a of ATTRS){const r=R[a];if(!r)continue;const g=G[a];const row=(i,ai)=>chain(g[i],a,ai);let t,ch;
    if(r==='row'){t='Cada linha tem um único valor. A 3ª linha começa com '+chip(a,g[2][0])+', então termina com ele.';ch=[{lab:'Linha 1'}].concat(row(0,-1),[{gap:1},{lab:'Linha 3'}],row(2,2));}
    else if(r==='col'){t='Olhe de cima para baixo: cada coluna tem um único valor. A 3ª coluna é '+chip(a,g[0][2])+'.';ch=[{lab:'Coluna 3'}].concat(chain([g[0][2],g[1][2],g[2][2]],a,2));}
    else if(r==='prog'){let vb;if(a==='rot'){const tr=turn(g[0][1]-g[0][0]);vb='gira '+tr.deg+'° '+tr.dir;}else{const d=g[0][1]-g[0][0];vb=a==='count'?(d>0?'+':'−')+Math.abs(d)+' a cada passo':(d>0?'aumenta':'diminui')+' um passo de cada vez';}
      t='Na 1ª linha, da esquerda para a direita: '+vb+'. Faça o mesmo na 3ª.';ch=[{lab:'Linha 1'}].concat(row(0,-1),[{gap:1},{lab:'Linha 3'}],row(2,2));}
    else if(r==='dist3'){const S=[...new Set(g[0])];t='Cada linha tem os mesmos três ('+S.map(x=>chip(a,x)).join(', ')+'), um de cada. Na 3ª já apareceram '+chip(a,g[2][0])+' e '+chip(a,g[2][1])+': falta o que não apareceu.';ch=[{lab:'Linha 3'}].concat(row(2,2));}
    else if(r==='add'||r==='sub'){const op=r==='add'?'+':'−';t='Conte as figuras: em cada linha, 1ª '+op+' 2ª = 3ª.';const eq=(i,ans)=>[{v:String(g[i][0])},{o:op},{v:String(g[i][1])},{o:'='},{v:String(g[i][2]),ans}];ch=[{lab:'Linha 1'}].concat(eq(0,false),[{gap:1},{lab:'Linha 3'}],eq(2,true));}
    else{t=r==='or'?'Sobreponha as duas primeiras: todo traço que aparece em qualquer uma delas fica na 3ª.':r==='xor'?'Sobreponha as duas primeiras: traço que aparece nas DUAS some (tracejado); traço que aparece em só uma FICA.':'Sobreponha as duas primeiras: fica só o traço que aparece nas DUAS (os outros somem, tracejados).';
      const gh=i=>r==='xor'?(g[i][0]&g[i][1]):r==='and'?((g[i][0]|g[i][1])&~g[i][2]):0;
      const eq=(i,ans)=>[lf(g[i][0]),{o:'+'},lf(g[i][1]),{o:'='},Object.assign(lf(g[i][2],gh(i)),{ans})];ch=[{lab:'Linha 1'}].concat(eq(0,false),[{gap:1},{lab:'Linha 3'}],eq(2,true));}
    steps.push({h:a==='lines'?'Traços':ATTR_PT[a],t,ch});}
  const fixed=['shape','count','size','fill'].filter(a=>!R[a]&&!(a==='count'&&R.lines)).map(a=>ANAME[a]+' ('+chip(a,G[a][0][0])+')');
  if(fixed.length)steps.push({h:'Não muda',t:cap1(fixed.join(', '))+' — igual em todas as células.'});
  it.steps=steps;panelDiag(it,c.ans,R);}
function annAna(it,c){const{A,B,C,D,O,T}=c;
  it.method='Descubra o que muda de A para B, uma característica por vez, e faça exatamente a mesma mudança em C. O que não mudou de A para B fica igual a C.';
  const steps=[];
  for(const a of ATTRS){if(!O[a])continue;let t,ch;
    if(a==='lines'){t=T.lmode==='add'?'De A para B aparecem traços novos: acrescente os mesmos em C.':'Os traços marcados trocam: onde havia, some; onde não havia, aparece. Faça o mesmo em C.';
      ch=[{lab:'A › B'},lf(A.lines),{o:'›'},lf(B.lines),{gap:1},{lab:'C › ?'},lf(C.lines),{o:'›'},Object.assign(lf(D.lines),{ans:true})];}
    else{let vb;if(a==='rot'){const tr=turn(B.rot-A.rot);vb='gira '+tr.deg+'° '+tr.dir;}else if(a==='mark'){const tr=turn(B.mark-A.mark);vb='o ponto anda '+tr.n+' '+plural(tr.n,'casa','casas')+' '+tr.dir;}
      else if(a==='count'){const d=B.count-A.count;vb=(d>0?'+':'−')+Math.abs(d)+' '+plural(Math.abs(d),'figura','figuras');}
      else if(a==='shape')vb=(POLY.indexOf(B.shape)>POLY.indexOf(A.shape)?'ganha':'perde')+' um lado';
      else if(a==='size')vb=B.size>A.size?'cresce um tamanho':'diminui um tamanho';else vb=FILL_PT[A.fill]+' vira '+FILL_PT[B.fill];
      t='De A para B: '+vb+'. Em C, faça igual.';ch=[{lab:'A › B'},{v:chip(a,A[a])},{o:'›'},{v:chip(a,B[a])},{gap:1},{lab:'C › ?'},{v:chip(a,C[a])},{o:'›'},{v:chip(a,D[a]),ans:true}];}
    steps.push({h:a==='lines'?'Traços':ATTR_PT[a],t,ch});}
  const fixed=['shape','count','size','fill'].filter(a=>!O[a]).map(a=>ANAME[a]+' ('+chip(a,C[a])+')');
  if(fixed.length)steps.push({h:'Copie de C',t:cap1(fixed.join(', '))+' — não mudou de A para B, então fica como está em C.'});
  const R={};for(const a of ATTRS)if(O[a])R[a]='ana';it.steps=steps;panelDiag(it,D,R);}
function annEsp(it,c){const b=c.base,L=it.letters;const pf=cs=>({k:'poly',cs});
  if(c.mode==='rot'){it.method='Escolha um detalhe fácil de seguir — a ponta mais comprida ou a célula escura — e acompanhe para onde ele vai a cada giro. No fim, confira se ele caiu do mesmo lado.';
    const ch=[];for(let r=0;r<=c.k;r++){if(r)ch.push({o:'↻'});ch.push({fig:pf(pRotN(b,r)),cap:r?r*90+'°':'modelo',ans:r===c.k});}
    it.steps=[{h:'Gire o modelo',t:'Girando de 90° em 90° no sentido horário chega-se à alternativa '+L[it.answer]+'.',ch},
      {h:'Teste do espelho',t:'Na figura espelhada o detalhe fica do lado oposto, e nenhum giro resolve isso. Por isso as espelhadas estão erradas.',ch:[{fig:pf(b),cap:'modelo'},{o:'|'},{fig:pf(pMirH(b)),cap:'espelhada'}]}];}
  else{it.method='Imagine um espelho em pé ao lado do modelo: o que está à esquerda vai para a direita, e o que está em cima continua em cima. Não há giro.';
    it.steps=[{h:'Reflita',t:'Cada quadrado troca de lado (esquerda ↔ direita) e mantém a altura.',ch:[{fig:pf(b),cap:'modelo'},{o:'|'},{fig:pf(pMirH(b)),cap:'reflexo',ans:true}]}];}
  it.options.forEach((o,i)=>{if(i===it.answer||!o.tr)return;const t=o.tr;let vis=null,line=o.why;
    if(t.m==='h'){vis=[{fig:pf(b),cap:'modelo'},{o:'|'},{fig:pf(pMirH(b)),cap:'espelhado'}].concat(t.r?[{o:'↻'},{fig:o.fig,cap:L[i]}]:[]);
      line=c.mode==='rot'?L[i]+' é o modelo espelhado'+(t.r?' e depois girado':'')+': o detalhe ficou do lado oposto.':L[i]+' foi refletida e também girada '+t.r*90+'°.';}
    else if(t.m==='v'){vis=[{fig:pf(b),cap:'modelo'},{o:'—'},{fig:o.fig,cap:L[i]}];line=L[i]+' foi refletida de cima para baixo: o espelho ficou deitado, não em pé.';}
    else if(t.m==='none'){vis=[{fig:pf(b),cap:'modelo'},{o:'↻'},{fig:o.fig,cap:L[i]+' · '+t.r*90+'°'}];line=L[i]+' é só o modelo girado '+t.r*90+'°: nada foi refletido.';}
    o.diag={lines:[line],traps:[],vis};});}
function annInt(it,c){const L=it.letters,f=c.figs,j=c.j;
  it.method='Procure uma relação que valha para quase todas: conte lados e pontos, compare a figura de dentro com a de fora, gire as peças. A que quebra a relação é a intrusa.';
  let cp,t;
  if(c.rule==='lados'){cp=x=>SH[x.shape].sides+' lados, '+x.n+' pontos';t='Conte os lados e os pontos de cada figura: em quatro delas os números batem.';}
  else if(c.rule==='interna'){cp=x=>SHAPE_PT[x.shape]+' / '+SHAPE_PT[x.inner];t='Compare a figura de fora com a de dentro: em quatro delas é a mesma forma.';}
  else{t='Gire as peças mentalmente até ficarem na mesma posição. Abaixo, todas foram giradas para a posição de uma delas: quatro ficam idênticas; a intrusa continua diferente, porque é o espelho.';}
  if(c.rule==='espelho'&&c.base){const ref=f.find((x,i)=>i!==j).cs;const back=x=>{for(let r=0;r<4;r++){const y=pRotN(x,r);if(pKey(y)===pKey(ref))return y;}return null;};
    it.steps=[{h:'Relação',t,ch:f.map((x,i)=>{const y=i===j?(()=>{const m=pMirH(x.cs);for(let r=0;r<4;r++){if(pKey(pRotN(m,r))===pKey(ref))return pMirH(pRotN(m,r));}return x.cs;})():back(x.cs);return{fig:{k:'poly',cs:y||x.cs},cap:L[i]+(i===j?': não encaixa':': igual'),ans:i===j};})}];}
  else it.steps=[{h:'Relação',t,ch:f.map((x,i)=>({fig:x,cap:L[i]+': '+cp(x,i),ans:i===j}))}];
  it.options.forEach((o,i)=>{if(i===j)return;o.diag={lines:[c.rule==='lados'?L[i]+' tem '+SH[f[i].shape].sides+' lados e '+f[i].n+' pontos: segue a regra.':
    c.rule==='interna'?L[i]+' tem '+SHAPE_PT[f[i].shape]+' fora e '+SHAPE_PT[f[i].inner]+' dentro: segue a regra.':L[i]+' é a mesma peça das outras, só girada.'],traps:[]};});}
const ANN={seq:annSeq,mat:annMat,ana:annAna,esp:annEsp,int:annInt};

/* ======================= fábrica ======================= */
const GENS={seq:genSeq,mat:genMat,ana:genAna,esp:genEsp,int:genInt};
function make(fam,lvl,seed,prefer){
  for(let L=lvl;L>=1;L--){const rng=RNG((seed^(L*2654435761))>>>0);
    for(let t=0;t<400;t++){const it=GENS[fam](rng,L,prefer);if(it){it.lvl=lvl;it.realLvl=L;it.seed=seed;it.letters='ABCDEFGH'.slice(0,it.options.length).split('');ANN[fam](it,it._ctx);delete it._ctx;return it;}}}
  throw new Error('falha ao gerar '+fam);}

/* ======================= renderização SVG ======================= */
const LAY={1:[[50,50]],2:[[30,50],[70,50]],3:[[50,30],[30,68],[70,68]],4:[[32,32],[68,32],[32,68],[68,68]],5:[[30,30],[70,30],[50,50],[30,70],[70,70]],
  6:[[30,25],[70,25],[30,50],[70,50],[30,75],[70,75]],7:[[25,25],[50,25],[75,25],[50,50],[25,75],[50,75],[75,75]],
  8:[[25,25],[50,25],[75,25],[37,50],[63,50],[25,75],[50,75],[75,75]],9:[[25,25],[50,25],[75,25],[25,50],[50,50],[75,50],[25,75],[50,75],[75,75]]};
const BASE_R={1:30,2:17,3:16,4:15,5:12,6:11,7:10,8:10,9:10};
const SIZE_F=[0.55,0.78,1];
function shapePts(type){
  if(SH[type].sides){const n=SH[type].sides;const off=n%2?0:180/n;return[...Array(n)].map((_,i)=>{const a=(-90+off+i*360/n)*Math.PI/180;return[Math.cos(a),Math.sin(a)];});}
  if(type==='star')return[...Array(10)].map((_,i)=>{const a=(-90+i*36)*Math.PI/180,r=i%2?0.45:1;return[r*Math.cos(a),r*Math.sin(a)];});
  if(type==='cross'){const t=0.34;return[[-t,-1],[t,-1],[t,-t],[1,-t],[1,t],[t,t],[t,1],[-t,1],[-t,t],[-1,t],[-1,-t],[-t,-t]];}
  if(type==='arrow')return[[0,-1],[0.75,-0.1],[0.3,-0.1],[0.3,1],[-0.3,1],[-0.3,-0.1],[-0.75,-0.1]];
  if(type==='half')return[...Array(17)].map((_,i)=>{const a=Math.PI+Math.PI*i/16;return[Math.cos(a),Math.sin(a)*1.0+0.45];});
  if(type==='flag')return[[-0.65,1],[-0.65,-1],[0.85,-0.55],[-0.38,-0.1],[-0.38,1]];
  return null;}
function shapeSVG(type,cx,cy,r,rotDeg,cls){
  if(type==='circle')return'<circle cx="'+cx.toFixed(1)+'" cy="'+cy.toFixed(1)+'" r="'+(r*0.92).toFixed(1)+'" class="'+cls+'"/>';
  const a=rotDeg*Math.PI/180,ca=Math.cos(a),sa=Math.sin(a);
  const pts=shapePts(type).map(([x,y])=>[(cx+r*(x*ca-y*sa)).toFixed(1),(cy+r*(x*sa+y*ca)).toFixed(1)].join(',')).join(' ');
  return'<polygon points="'+pts+'" class="'+cls+'"/>';}
const LINE_SEG=[[50,8,50,92],[8,50,92,50],[14,14,86,86],[86,14,14,86],[14,14,86,14],[14,86,86,86]];
function panelSVG(p,compact){let s='';
  for(let b=0;b<6;b++)if(p.lines&(1<<b)){const l=LINE_SEG[b];s+='<line x1="'+l[0]+'" y1="'+l[1]+'" x2="'+l[2]+'" y2="'+l[3]+'" class="ln"/>';}
  if(p.ghost)for(let b=0;b<6;b++)if(p.ghost&(1<<b)){const l=LINE_SEG[b];s+='<line x1="'+l[0]+'" y1="'+l[1]+'" x2="'+l[2]+'" y2="'+l[3]+'" class="lg"/>';}
  if(!p.count)return s;
  const k=(compact?0.78:1)*(p.lines?0.6:1);const lay=LAY[p.count]||LAY[1];
  const r=BASE_R[p.count]*SIZE_F[p.size]*k;
  for(const[x,y]of lay){const cx=50+(x-50)*(compact?0.8:1),cy=50+(y-50)*(compact?0.8:1);s+=shapeSVG(p.shape,cx,cy,r,p.rot*45,'sh f'+p.fill);}
  if(p.mark>=0){const a=(-90+p.mark*45)*Math.PI/180;s+='<circle cx="'+(50+43*Math.cos(a)).toFixed(1)+'" cy="'+(50+43*Math.sin(a)).toFixed(1)+'" r="5" class="mk"/>';}
  return s;}
function polySVG(cs){const n=pNorm(cs);const w=Math.max(...n.map(c=>c.x))+1,h=Math.max(...n.map(c=>c.y))+1;const u=Math.min(80/w,80/h,20);
  const ox=50-w*u/2,oy=50-h*u/2;return n.map(c=>'<rect x="'+(ox+c.x*u).toFixed(1)+'" y="'+(oy+c.y*u).toFixed(1)+'" width="'+u.toFixed(1)+'" height="'+u.toFixed(1)+'" class="sh '+(c.m?'f2':'f0')+'"/>').join('');}
function intSVG(f){
  if(f.t==='lados'){let s=shapeSVG(f.shape,50,f.shape==='triangle'?56:50,f.shape==='triangle'?42:38,f.rot*45,'sh f'+f.fill);
    const lay=LAY[f.n]||LAY[1];const cy=f.shape==='triangle'?60:50;for(const[x,y]of lay)s+='<circle cx="'+(50+(x-50)*0.4).toFixed(1)+'" cy="'+(cy+(y-50)*0.4).toFixed(1)+'" r="3.6" class="mk"/>';return s;}
  return shapeSVG(f.shape,50,50,40,0,'sh f0')+shapeSVG(f.inner,50,f.shape==='triangle'?57:50,15,0,'sh f'+f.fill);}
function figSVG(f){const inner=f.k==='panel'?panelSVG(f.p,f.compact):f.k==='poly'?polySVG(f.cs):intSVG(f);
  return'<svg viewBox="0 0 100 100" class="fg" aria-hidden="true">'+inner+'</svg>';}

const API={make,figSVG,keyLabel,FAMS,whereKey,RNG,_seqPredict:seqPredict,_matPredict:matPredict,_vkey:vkey,_pKey:pKey,_pAll:pAll};
if(typeof module!=='undefined'&&module.exports)module.exports=API;else root.PV=API;
})(this);
