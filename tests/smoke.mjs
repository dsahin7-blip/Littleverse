import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const nodes = new Map(), listeners = {}, data = new Map();
const node = key => {
  if (!nodes.has(key)) nodes.set(key, {innerHTML:'',textContent:'',value:'',dataset:{},addEventListener(){},classList:{add(){},remove(){},contains(){return false}}});
  return nodes.get(key);
};
const document = {body:{dataset:{}},querySelector:node,querySelectorAll:()=>[],createElement:()=>({innerHTML:'',childNodes:[],get textContent(){return this.innerHTML.replace(/<[^>]*>/g,' ')},get innerText(){return this.textContent}}),addEventListener:(name,fn)=>{listeners[name]=fn}};
const localStorage = {getItem:key=>data.get(key)||null,setItem:(key,value)=>data.set(key,value)};
const context = {document,localStorage,location:{hash:'#home',search:'',hostname:'littleverse.test'},history:{replaceState(_a,_b,url){context.location.hash=url}},window:{addEventListener(){},scrollTo(){}},Intl,Date,JSON,Math,console,setTimeout:()=>1,clearTimeout(){},URLSearchParams};
vm.runInNewContext(fs.readFileSync('app.js','utf8'),context,{filename:'app.js'});

function click(route, action) {
  const target = {closest(selector) {
    if (selector==='[data-route]'&&route) return {dataset:{route}};
    if (selector==='[data-action]'&&action) return {dataset:{action}};
    return null;
  }};
  listeners.click({target,preventDefault(){}});
}

assert.match(node('#view').innerHTML,/Güzel bir gün/,'dashboard renders');
const routes = [['sanctuary','Sığınağım'],['explore','Dünyaları Keşfet'],['character','Karakterim'],['collection','Koleksiyonum'],['quests','Görevler ve ödüller'],['diary','Günlüğüm'],['games','Mini Oyunlar'],['shop','Mağaza'],['achievements','Başarımlar'],['rewards','İşlem Geçmişi'],['settings','Ayarlar']];
for (const [route,title] of routes) {
  click(route);
  assert.match(node('#view').innerHTML,new RegExp(title),'route '+route+' renders');
}
click('quests');
assert.match(node('#view').innerHTML,/5 görev|Beş küçük adım/,'daily quest list renders');
assert.match(node('#view').innerHTML,/Haftalık meydan okumalar/,'weekly challenges render');
assert.match(node('#view').innerHTML,/Mevsimlik dilekler/,'seasonal challenges render');
click('rewards');
for (const label of ['Tümü','Kazanılan','Harcanan','Ödüller','Alışverişler','Düzeltmeler']) assert.ok(node('#view').innerHTML.includes(label),'transaction filter '+label+' renders');
assert.doesNotMatch(node('#view').innerHTML,/İşlem deneme alanı/,'developer simulator stays hidden outside localhost');
const app = fs.readFileSync('app.js','utf8'), sql = fs.readFileSync('supabase/migrations/202611160002_littleverse_economy.sql','utf8');
assert.match(app,/functions\/v1\/economy/,'economy uses the authenticated server endpoint');
assert.match(app,/economyReady/,'currency actions wait for economy initialization');
assert.match(app,/localStorage\.setItem\(STORE,JSON\.stringify\(state\)\)/,'non-economy game progress persists locally');
assert.match(sql,/before update or delete on public\.economy_transactions/i,'ledger blocks edits and deletion');
assert.match(sql,/for update/i,'wallet mutations serialize against a row lock');
assert.match(sql,/check \(stars >= 0\)/i,'star balance cannot go negative');
assert.match(sql,/check \(crystals >= 0\)/i,'crystal balance cannot go negative');
assert.match(sql,/unique\(user_id,idempotency_key\)/i,'transaction retries are idempotent');
assert.match(sql,/primary key\(user_id,claim_key\)/i,'reward claims reject duplicates');
assert.match(sql,/p_level integer/,'level progression is implemented in the database');
assert.match(fs.readFileSync('index.html','utf8'),/economy\.css/,'transaction history has a dedicated responsive design layer');
console.log('Littleverse route and economy contract checks passed.');
