import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const nodes = new Map();
const listeners = {};
const data = new Map();
const node = key => {
  if(!nodes.has(key)) nodes.set(key,{innerHTML:'',textContent:'',value:'',dataset:{},addEventListener(){},classList:{add(){},remove(){},contains(){return false}}});
  return nodes.get(key);
};
const document = {body:{dataset:{}},querySelector:node,querySelectorAll:()=>[],addEventListener:(event,fn)=>{listeners[event]=fn}};
const localStorage={getItem:k=>data.get(k)||null,setItem:(k,v)=>data.set(k,v)};
const context={document,localStorage,location:{hash:'#home'},history:{replaceState(_a,_b,url){context.location.hash=url}},window:{addEventListener(){},scrollTo(){}},Intl,Date,JSON,Math,console,setTimeout:()=>1,clearTimeout(){}};
vm.runInNewContext(fs.readFileSync('app.js','utf8'),context,{filename:'app.js'});

function click(attrs){
  const target={closest(selector){
    if(selector==='[data-route]'&&attrs.route)return {dataset:{route:attrs.route}};
    if(selector==='[data-action]'&&attrs.action)return {dataset:{action:attrs.action}};
    if(selector==='[data-buy]'&&attrs.buy)return {dataset:{buy:attrs.buy}};
    if(selector==='[data-world]'&&attrs.world)return {dataset:{world:attrs.world}};
    if(selector==='[data-room-mode]'&&attrs.roomMode)return {dataset:{roomMode:attrs.roomMode}};
    if(selector==='[data-mood]'&&attrs.mood)return {dataset:{mood:attrs.mood}};
    return null;
  }};
  listeners.click({target,preventDefault(){}});
}

assert.match(node('#view').innerHTML,/Güzel bir gün/,'dashboard renders');
click({route:'quests'});
assert.equal(node('#current-section').textContent,'Günlük Görevler');
assert.match(node('#view').innerHTML,/Bir yıldız yakala/,'daily quests render');
click({route:'games'});
click({action:'tap-star'});click({action:'tap-star'});click({action:'tap-star'});
let saved=JSON.parse(data.get('littleverse-save-v1'));
assert.equal(saved.quests[0].progress,3,'star quest reaches target');
click({action:'claim-quest:stars'});
saved=JSON.parse(data.get('littleverse-save-v1'));
assert.equal(saved.quests[0].claimed,true,'quest reward is claimable');
assert.equal(saved.stars,285,'star rewards are credited');
click({route:'shop'});click({buy:'soft-sofa'});
saved=JSON.parse(data.get('littleverse-save-v1'));
assert.ok(saved.owned.includes('soft-sofa'),'purchased item enters collection');
assert.equal(saved.stars,200,'purchase subtracts the price');
click({route:'sanctuary'});click({roomMode:'bahçe'});
assert.match(node('#view').innerHTML,/küçük bahçesi/,'garden preview is selectable');
click({route:'diary'});click({mood:'Neşeli'});node('#diary-text').value='Bugün çiçekler çok güzeldi.';
listeners.submit({target:{id:'diary-form'},preventDefault(){}});
saved=JSON.parse(data.get('littleverse-save-v1'));
assert.equal(saved.diary[0].text,'Bugün çiçekler çok güzeldi.','diary entry is saved');
click({route:'home'});click({action:'surprise'});
saved=JSON.parse(data.get('littleverse-save-v1'));
assert.equal(saved.crystals,20,'daily surprise grants crystals');
click({route:'settings'});click({action:'reset'});click({action:'modal-confirm'});
saved=JSON.parse(data.get('littleverse-save-v1'));
assert.equal(saved.stars,240,'confirmed reset restores initial progress');
console.log('Littleverse smoke checks passed.');

