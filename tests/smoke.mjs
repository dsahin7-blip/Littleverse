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
const app = fs.readFileSync('app.js','utf8'), sql = fs.readFileSync('supabase/migrations/202611160002_littleverse_economy.sql','utf8'), hardening = fs.readFileSync('supabase/migrations/202611160005_littleverse_idempotent_economy_events.sql','utf8'), rewardGuards = fs.readFileSync('supabase/migrations/202611160006_littleverse_reward_validation_hardening.sql','utf8');
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
assert.match(app,/event_id:crypto\.randomUUID\(\)/,'progress is sent with an idempotent event key');
assert.match(hardening,/primary key\(user_id,event_key\)/i,'server rejects duplicate progress events');
assert.match(hardening,/DAILY_CAP_REACHED/,'server caps daily progress events');
assert.match(hardening,/world-unlock:/,'server checks access before world rewards');
assert.match(rewardGuards,/world-first:/,'server requires a first visit before world rewards');
assert.match(rewardGuards,/world-quest:%/,'world quests require their real discovery');
const access = fs.readFileSync('supabase/migrations/202611160007_littleverse_economy_access_tightening.sql','utf8');
assert.match(access,/read own economy event keys/,'progress audit keys remain private to each player');
assert.match(access,/revoke all on function public\.littleverse_level_for_xp/,'XP helpers are not exposed as public APIs');
const worldFirst = fs.readFileSync('supabase/migrations/202611160008_littleverse_atomic_world_first_rewards.sql','utf8');
const claimGuards = fs.readFileSync('supabase/migrations/202611160009_littleverse_early_duplicate_rejection.sql','utf8');
assert.match(worldFirst,/world-first:'\|\|v_unlock_id/,'unlocking a world grants the first-visit reward atomically');
assert.ok(claimGuards.indexOf('ALREADY_CLAIMED')<claimGuards.indexOf("v_claim.reward_key like 'world-point:%'"),'duplicate claims are rejected before progress validation');
assert.match(fs.readFileSync('index.html','utf8'),/economy\.css/,'transaction history has a dedicated responsive design layer');
console.log('Littleverse route and economy contract checks passed.');
