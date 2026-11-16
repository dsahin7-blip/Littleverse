(() => {
  'use strict';

  const STORE = 'littleverse-save-v1';
  const SESSION = 'littleverse-cloud-session-v1';
  const NAV = [
    ['home', 'Ana Sayfa', '⌂'], ['sanctuary', 'Sığınağım', '⌂'], ['explore', 'Dünyaları Keşfet', '✧'],
    ['character', 'Karakterim', '♙'], ['collection', 'Koleksiyonum', '▧'], ['quests', 'Günlük Görevler', '☼'],
    ['diary', 'Günlüğüm', '▤'], ['games', 'Mini Oyunlar', '✹'], ['shop', 'Mağaza', '♧'], ['achievements', 'Başarımlar', '✦'],
    ['settings', 'Ayarlar', '⚙']
  ];
  const WORLDS = [
    { id:'moon-garden', title:'Ay Işığı Bahçesi', desc:'Gecenin en yumuşak köşesi', emoji:'🌙', scene:'scene-moonlit', unlocked:true },
    { id:'whisper-meadow', title:'Fısıltı Çayırı', desc:'Çiçeklerin küçük sırları', emoji:'🦋', scene:'scene-meadow', unlocked:true },
    { id:'cloud-isles', title:'Bulut Adaları', desc:'Gökyüzüne yakın bir kaçış', emoji:'☁️', scene:'scene-cloud', unlocked:true },
    { id:'crystal-cove', title:'Kristal Koyu', desc:'Dalgaların sakladığı ışık', emoji:'🪸', scene:'scene-moonlit', unlocked:false, unlockLevel:5, requirement:'5. seviye' },
    { id:'star-forest', title:'Yıldız Ormanı', desc:'Göğe uzanan gümüş ağaçlar', emoji:'🌲', scene:'scene-meadow', unlocked:false, unlockLevel:8, requirement:'8. seviye' },
    { id:'dream-library', title:'Düş Kütüphanesi', desc:'Henüz yazılmamış hikâyeler', emoji:'📚', scene:'scene-cloud', unlocked:false, unlockLevel:12, requirement:'12. seviye' }
  ];
  const ITEMS = [
    {id:'soft-sofa',name:'Bulut Koltuk',category:'Mobilya',kind:'furniture',emoji:'🛋️',price:85,currency:'stars',rarity:'Nadir'},
    {id:'moon-lamp',name:'Ay Işığı Lambası',category:'Dekor',kind:'furniture',emoji:'🏮',price:65,currency:'stars',rarity:'Sıradan'},
    {id:'fern-pot',name:'Orman Eğreltisi',category:'Bitkiler',kind:'furniture',emoji:'🪴',price:45,currency:'stars',rarity:'Sıradan'},
    {id:'dream-cushion',name:'Düş Bulutu Minderi',category:'Dekor',kind:'furniture',emoji:'☁️',price:35,currency:'stars',rarity:'Sıradan'},
    {id:'lilac-chair',name:'Leylak Berjer',category:'Mobilya',kind:'furniture',emoji:'🪑',price:115,currency:'stars',rarity:'Nadir'},
    {id:'mushroom-stool',name:'Mantar Tabure',category:'Mobilya',kind:'furniture',emoji:'🍄',price:3,currency:'crystals',rarity:'Nadir'},
    {id:'starlight-dress',name:'Yıldız Tozu Elbise',category:'Kıyafet',kind:'outfit',emoji:'👗',price:120,currency:'stars',rarity:'Nadir'},
    {id:'lavender-cape',name:'Lavanta Pelerini',category:'Kıyafet',kind:'outfit',emoji:'🧥',price:95,currency:'stars',rarity:'Sıradan'},
    {id:'moon-crown',name:'Hilal Tacı',category:'Aksesuar',kind:'accessory',emoji:'👑',price:4,currency:'crystals',rarity:'Destansı'},
    {id:'pearl-earrings',name:'İnci Küpeler',category:'Aksesuar',kind:'accessory',emoji:'✨',price:70,currency:'stars',rarity:'Nadir'},
    {id:'butterfly-pin',name:'Kelebek Broş',category:'Aksesuar',kind:'accessory',emoji:'🦋',price:40,currency:'stars',rarity:'Sıradan'},
    {id:'blue-teacup',name:'Bulut Çayı Fincanı',category:'Dekor',kind:'furniture',emoji:'🫖',price:2,currency:'crystals',rarity:'Destansı'}
  ];
  const QUEST_SEED = [
    {id:'stars',title:'Bir yıldız yakala',desc:'Gökyüzünde parlayanlara dokun',emoji:'✦',target:3,progress:0,reward:30,xp:25,route:'games'},
    {id:'diary',title:'Kendine küçük bir not bırak',desc:'Bugün nasıl hissettiğini yaz',emoji:'✿',target:1,progress:0,reward:25,xp:20,route:'diary'},
    {id:'world',title:'Yeni bir köşeyi keşfet',desc:'Yakınındaki dünyalardan birini ziyaret et',emoji:'☁',target:1,progress:0,reward:35,xp:30,route:'explore'}
  ];
  const freshState = () => ({
    version:1, name:'Luna', level:4, xp:68, stars:240, crystals:18, avatar:'🌙', mood:'Sakin', theme:'gündüz',
    owned:['moon-lamp','fern-pot','dream-cushion','lavender-cape','butterfly-pin'],
    equipped:{ furniture:'moon-lamp', outfit:'lavender-cape', accessory:'butterfly-pin' },
    quests:QUEST_SEED.map(q=>({...q})), diary:[], visited:['moon-garden','whisper-meadow'], surpriseDate:'', tapsToday:0,
    tapsDate:new Date().toLocaleDateString('en-CA'), quizDone:false, roomTab:'Mobilya', roomMode:'oda', nameChanged:false
  });
  let state = readLocal();
  let route = location.hash.replace('#','') || 'home';
  let collectionFilter = 'Tümü';
  let shopFilter = 'Tümü';
  let toastTimer;
  let cloud = { enabled:false, userId:null, accessToken:null, syncing:false };
  const $ = (sel,root=document) => root.querySelector(sel);
  const $$ = (sel,root=document) => [...root.querySelectorAll(sel)];
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const itemById = id => ITEMS.find(item=>item.id===id);
  function readLocal(){ try{const s=JSON.parse(localStorage.getItem(STORE)||'null');return s&&s.version===1?{...freshState(),...s}:freshState()}catch{return freshState()} }
  function save(){
    try{localStorage.setItem(STORE,JSON.stringify(state));}catch{showToast('Bu tarayıcıda kayıt alanı kullanılamıyor.','gold')}
    if(cloud.enabled) cloudSave();
    updateHud();
  }
  function showToast(message, tone=''){
    const root=$('#toast-root'); if(!root)return; root.innerHTML=`<div class="toast ${tone}">${esc(message)}</div>`;
    clearTimeout(toastTimer);toastTimer=setTimeout(()=>root.innerHTML='',3000);
  }
  function setStatus(text,online=false){const el=$('#storage-status');if(el){el.innerHTML=`<i style="background:${online?'#95c6a7':'#d4b77b'}"></i>${esc(text)}`}}
  function currencyIcon(type){return type==='crystals'?'✧':'✦'}
  function updateHud(){
    $('#top-stars').textContent=state.stars;$('#top-crystals').textContent=state.crystals;
    $('#sidebar-name').textContent=state.name;$('.top-avatar').textContent=state.avatar;
    const mobile=$('.mobile-brand'); if(mobile){};
  }
  function renderNav(){
    const nav=$('#primary-nav');nav.innerHTML=NAV.map(([id,label,icon])=>`<button class="nav-link ${route===id?'active':''}" data-route="${id}" aria-current="${route===id?'page':'false'}"><span class="nav-icon">${icon}</span><span class="nav-label">${label}</span></button>`).join('');
    const mobileIds=['home','sanctuary','explore','collection','character'];
    $('#mobile-nav').innerHTML=mobileIds.map(id=>{const [key,label,icon]=NAV.find(n=>n[0]===id);return `<button class="nav-link ${route===key?'active':''}" data-route="${key}" aria-current="${route===key?'page':'false'}"><span class="nav-icon">${icon}</span><span class="nav-label">${label==='Dünyaları Keşfet'?'Keşfet':label==='Koleksiyonum'?'Koleksiyon':label==='Karakterim'?'Karakter':label==='Sığınağım'?'Sığınağım':'Ana Sayfa'}</span></button>`}).join('');
  }
  function navigate(to){if(!NAV.some(n=>n[0]===to))to='home';route=to;history.replaceState(null,'',`#${to}`);render();window.scrollTo({top:0,behavior:'smooth'})}
  function pageHeading(eyebrow,title,sub,extra=''){return `<div class="page-heading"><div><div class="eyebrow">${eyebrow}</div><h1>${title}</h1><p>${sub}</p></div>${extra}</div>`}
  function dateLabel(){return new Intl.DateTimeFormat('tr-TR',{weekday:'long',day:'numeric',month:'long'}).format(new Date())}
  function levelInfo(){let lv=state.level,xp=state.xp;while(xp>=100){xp-=100;lv++}state.level=lv;state.xp=xp;return {level:lv,xp}}
  function grant({stars=0,crystals=0,xp=0}={}){
    state.stars+=stars;state.crystals+=crystals;let info=levelInfo();state.xp+=xp;let level=state.level;info=levelInfo();
    if(state.level>level)showToast(`Yeni seviye! Artık ${state.level}. seviyedesin ✨`);
    save();
  }
  function incrementQuest(id,amount=1){const q=state.quests.find(q=>q.id===id);if(q&&!q.claimed)q.progress=Math.min(q.target,q.progress+amount)}
  function taskCards(limit=3){return state.quests.slice(0,limit).map(q=>{
    let label=q.claimed?'✓ Alındı':q.progress>=q.target?'Ödülü al':q.route==='games'?'Oyna':q.route==='diary'?'Not yaz':'Keşfet';
    let action=q.claimed?'':q.progress>=q.target?`claim-quest:${q.id}`:`route:${q.route}`;
    return `<article class="quest-card"><div class="quest-icon">${q.emoji}</div><div class="quest-info"><strong>${esc(q.title)}</strong><small>${q.progress>=q.target?'Görev tamamlandı · ':''}${esc(q.desc)} · ${Math.min(q.progress,q.target)}/${q.target}</small></div><div style="display:grid;justify-items:end;gap:5px"><span class="quest-reward">✦ ${q.reward} · ${q.xp} XP</span><button class="quest-action" data-action="${action}" ${q.claimed?'disabled':''}>${label}</button></div></article>`
  }).join('')}
  function levelCard(){const {level,xp}=levelInfo();return `<aside class="level-card"><div class="level-top"><div class="level-badge">${level}</div><div><small>YILDIZ YOLCUSU</small><strong>${level}. Seviye</strong></div></div><p>Her küçük iyilik, dünyanı biraz daha büyütür. Bir sonraki seviyeye çok yaklaştın!</p><div class="progress-meta"><span>Yolculuk deneyimi</span><span>${xp} / 100 XP</span></div><div class="progress-track"><div class="progress-fill" style="width:${xp}%"></div></div><div class="level-foot"><span>✦ ${state.stars} yıldız</span><span>✧ ${state.crystals} kristal</span></div></aside>`}
  function statStrip(){return `<div class="stat-strip"><div class="stat-card"><div class="stat-icon">✦</div><div><strong>${state.stars}</strong><small>Yıldız</small></div></div><div class="stat-card"><div class="stat-icon">✧</div><div><strong>${state.crystals}</strong><small>Kristal</small></div></div><div class="stat-card"><div class="stat-icon">♧</div><div><strong>${state.owned.length}</strong><small>Koleksiyon parçası</small></div></div></div>`}
  function surpriseCard(){const used=state.surpriseDate===new Date().toLocaleDateString('en-CA');return `<div class="surprise-card"><div class="surprise-art">🎁</div><div><strong>Bugünün küçük sürprizi</strong><p>${used?'Sürprizini açtın. Yarın yeni bir tane seni bekliyor.':'Sana özel minicik bir hediye sakladık.'}</p><button class="primary-button" data-action="surprise" ${used?'disabled':''}>${used?'Bugün açıldı':'Sürprizi aç  ✨'}</button></div></div>`}
  function worldCard(w){const locked=!!w.unlockLevel&&state.level<w.unlockLevel;return `<button class="world-card" data-world="${w.id}" aria-label="${esc(w.title)}${locked?' kilitli':''}"><span class="world-scene ${w.scene} ${locked?'scene-locked':''}"></span><span class="world-emoji">${w.emoji}</span><span class="world-tag">${locked?'YAKINDA':state.visited.includes(w.id)?'YENİDEN ZİYARET':'KEŞFEDİLDİ'}</span>${locked?`<span class="world-lock">🔒 ${w.requirement}</span>`:''}<span class="world-copy"><strong>${esc(w.title)}</strong><small>${esc(w.desc)}</small></span></button>`}
  function homePage(){return `${pageHeading(dateLabel().toLocaleUpperCase('tr-TR').replace(' ',' · '),`Merhaba, ${esc(state.name)} <span style="color:#af8bc0">✧</span>`,'Bugün küçük dünyanda seni neler bekliyor? ',`<span class="date-chip">☼ &nbsp;${dateLabel()}</span>`)}<div class="dashboard-layout"><div><section class="welcome-card"><div class="welcome-copy"><div class="eyebrow">AY IŞIĞI BAHÇESİ</div><h1>Güzel bir gün,<br/>küçük yıldız.</h1><p>Biraz keşfet, biraz hayal kur. Dünyan seni bekliyor.</p><button class="primary-button" data-route="sanctuary">Sığınağıma dön &nbsp; ↗</button></div><div class="welcome-art" aria-hidden="true"><div class="welcome-moon">☾</div><span class="firefly f1">✦</span><span class="firefly f2">✧</span><span class="firefly f3">✦</span><div class="art-hill hill-back"></div><div class="art-hill hill-front"></div><div class="little-house"><span class="house-window"></span></div><div class="welcome-mascot">${state.avatar}</div></div></section>${statStrip()}<div class="section-row"><div><h2>Bugünün küçük adımları</h2><p>Minik görevler, tatlı ödüller.</p></div><button class="text-button" data-route="quests">Tüm görevler →</button></div><div class="quest-list">${taskCards(3)}</div></div><div><div style="margin-bottom:13px">${levelCard()}</div>${surpriseCard()}<div class="section-row"><div><h2>Son ziyaretler</h2><p>Dönmek isteyeceğin yerler.</p></div><button class="text-button" data-route="explore">Tümünü gör →</button></div><div class="world-grid" style="grid-template-columns:repeat(2,minmax(0,1fr));gap:9px">${WORLDS.filter(w=>w.unlocked&&state.visited.includes(w.id)).slice(0,2).map(worldCard).join('')}</div><div class="section-row"><div><h2>Küçük koleksiyonun</h2><p>Son eklenen, sevilen parçalar.</p></div><button class="text-button" data-route="collection">Tümünü gör →</button></div><div style="display:grid;gap:7px">${ownedItems().slice(0,3).map(i=>`<div class="stat-card" style="min-height:45px;padding:7px 10px"><div class="stat-icon">${i.emoji}</div><div style="flex:1"><strong style="font:600 11px var(--sans)">${esc(i.name)}</strong><small>${esc(i.category)} · ${i.rarity}</small></div><span style="color:#ad91bb">✧</span></div>`).join('')}</div></div></div>`}
  function questPage(){return `${pageHeading('GÜNÜN RİTMİ','Günlük Görevler','Küçük adımlarla yıldızlarını ve deneyimini topla.',`<span class="date-chip">☼ &nbsp;${dateLabel()}</span>`)}<div class="dashboard-layout"><div><div class="quest-list">${taskCards(99)}</div><div class="section-row"><div><h2>Günün hatırası</h2><p>Her gün yeniden başlar, dünya seninle kalır.</p></div></div>${surpriseCard()}</div><div>${levelCard()}<div class="section-row"><div><h2>Minik not</h2></div></div><div class="empty-state"><div>🌱</div><strong>Küçük adımlar da ilerlemedir</strong><p>Bir görevi tamamlamak için yanındaki düğmeye dokun. Ödül hazır olduğunda yıldızlarını alabilirsin.</p></div></div></div>`}
  function explorePage(){return `${pageHeading('UZAKTAKİ YAKINLIK','Dünyaları Keşfet','Her kapının ardında başka bir güzellik var.')}<div class="world-grid">${WORLDS.map(worldCard).join('')}</div><div class="section-row"><div><h2>Keşif notu</h2><p>Yeni dünyalar, yolculuğun ilerledikçe açılır.</p></div></div><div class="empty-state"><div>🗺️</div><strong>Yıldızların seni yeni yerlere götürür</strong><p>Kilitli dünyalar için seviye şartını tamamla. İlk sürümde dünyaları ziyaret edip koleksiyonunda anı olarak saklayabilirsin.</p></div>`}
  function ownedItems(){return state.owned.map(itemById).filter(Boolean)}
  function roomPreview(){const outfit=itemById(state.equipped.outfit);const furn=itemById(state.equipped.furniture);if(state.roomMode==='bahçe')return `<div class="room-panel garden-panel"><div class="garden-sun"></div><div class="garden-moon">✧</div><div class="garden-flower flower-a">✿</div><div class="garden-flower flower-b">✿</div><div class="garden-tree">🌳</div><div class="garden-path"></div><div class="room-furniture garden-feature">${furn?.emoji||'🪴'}</div><div class="room-character">${state.avatar}</div><div class="room-label">${esc(state.name)}’in küçük bahçesi</div></div>`;return `<div class="room-panel"><div class="room-sun"></div><div class="room-window"></div><div class="room-shelf"><span class="room-furniture">${furn?.emoji||'🏮'}</span></div><div class="room-rug"></div><div class="room-sofa">🛋️</div><div class="room-plant">${state.owned.includes('fern-pot')?'🪴':'🌿'}</div><div class="room-character">${state.avatar}</div><div class="room-label">${esc(state.name)}’in odası · ${outfit?.emoji||''}</div></div>`}
  function sanctuaryPage(){let cat=state.roomTab||'Mobilya';let furniture=ownedItems().filter(i=>i.kind==='furniture'&&(cat==='Hepsi'||i.category===cat));return `${pageHeading('SANA AİT BİR KÖŞE','Sığınağım','Küçük yuvanı, sana iyi hissettiren parçalarla düzenle.')}<div class="dashboard-layout"><div><div class="room-tabs"><button class="room-tab ${state.roomMode==='oda'?'active':''}" data-room-mode="oda">Odam</button><button class="room-tab ${state.roomMode==='bahçe'?'active':''}" data-room-mode="bahçe">Bahçem</button></div>${roomPreview()}<div class="section-row"><div><h2>${state.roomMode==='bahçe'?'Bahçeni güzelleştir':'Odanı güzelleştir'}</h2><p>Sahip olduğun eşyayı seçerek sığınağına yerleştir.</p></div></div><div class="room-tabs">${['Mobilya','Dekor','Bitkiler','Hepsi'].map(c=>`<button class="room-tab ${cat===c?'active':''}" data-room-tab="${c}">${c}</button>`).join('')}</div><div class="room-grid">${furniture.length?furniture.map(i=>`<button class="room-item ${state.equipped.furniture===i.id?'selected':''}" data-equip="${i.id}"><span>${i.emoji}</span><strong>${esc(i.name)}</strong><small>${state.equipped.furniture===i.id?'Yerleştirildi':'Yerleştir'}</small></button>`).join(''):'<div class="empty-state" style="grid-column:1/-1;padding:20px"><div>🪴</div><strong>Bu köşe henüz boş</strong><p>Mağazada yeni parçalar bulabilirsin.</p></div>'}</div></div><div>${levelCard()}<div class="section-row"><div><h2>Bahçeden bir yıldız</h2><p>Küçük bir mola ver.</p></div></div><div class="game-arena"><div style="font-size:34px">🌙</div><p>Bahçende parlayan bir şey var.</p><button class="soft-button" data-route="games">Yıldızları yakala →</button></div><div class="section-row"><div><h2>Biraz daha keşfet</h2><p>Yeni parçalar seni bekliyor.</p></div></div><button class="secondary-button" data-route="shop">Mağazaya git ↗</button></div></div>`}
  function characterPage(){const outfits=ownedItems().filter(i=>i.kind==='outfit'||i.kind==='accessory');return `${pageHeading('BU DÜNYANIN KAHRAMANI','Karakterim','Kendini en iyi hissettiren hâlini seç.')}<div class="profile-card"><div class="profile-portrait">${state.avatar}<span class="portrait-spark one">✧</span><span class="portrait-spark two">✦</span></div><div class="profile-copy"><div class="eyebrow">YILDIZ YOLCUSU · ${state.level}. SEVİYE</div><h2>${esc(state.name)}</h2><p>Meraklı bir kalp, yumuşacık bir dünya. Her gün yeni bir şey keşfetmeyi seviyorsun.</p><div class="detail-pills"><span class="detail-pill">☾ ${esc(state.mood)} ruh hâli</span><span class="detail-pill">✦ ${state.visited.length} dünya ziyareti</span><span class="detail-pill">♧ ${state.owned.length} koleksiyon parçası</span></div></div></div><div class="section-row"><div><h2>Görünüşünü seç</h2><p>Karakterin, seçtiğin tarzla kendi hikâyesini anlatsın.</p></div><button class="text-button" data-route="shop">Mağazada keşfet →</button></div><div class="room-tabs">${['🌙','🦋','🌷','🪄','☁️','🧚'].map(a=>`<button class="room-tab ${state.avatar===a?'active':''}" data-avatar="${a}" title="Karakter görünümü">${a}</button>`).join('')}</div><div class="item-grid">${outfits.length?outfits.map(i=>`<article class="item-card"><div class="item-visual">${i.emoji}<span class="rarity ${i.rarity==='Destansı'?'epic':i.rarity==='Nadir'?'rare':''}">${i.rarity}</span></div><div class="item-body"><strong>${esc(i.name)}</strong><small>${i.kind==='outfit'?'Kıyafet':'Aksesuar'}</small><div class="item-price"><span></span><button class="buy-button" data-equip="${i.id}" style="${state.equipped[i.kind]===i.id?'background:#edf4ef;color:#6b977e':''}">${state.equipped[i.kind]===i.id?'Üzerinde':'Giy'}</button></div></div></article>`).join(''):'<div class="empty-state"><div>👗</div><strong>Gardırobun henüz boş</strong><p>Mağazadan ilk görünüşünü seçebilirsin.</p></div>'}</div>`}
  function collectionPage(){const filters=['Tümü','Mobilya','Dekor','Bitkiler','Kıyafet','Aksesuar'];const all=ownedItems().filter(i=>collectionFilter==='Tümü'||i.category===collectionFilter);return `${pageHeading('KÜÇÜK ŞEYLER, GÜZEL ANILAR','Koleksiyonum',`${state.owned.length} parça dünyanda kendine yer buldu.`)}<div class="filters">${filters.map(f=>`<button class="filter-chip ${collectionFilter===f?'active':''}" data-collection-filter="${f}">${f}</button>`).join('')}</div>${all.length?`<div class="collection-grid">${all.map(i=>`<article class="collectible-card"><div class="collectible-visual">${i.emoji}<span class="rarity ${i.rarity==='Destansı'?'epic':i.rarity==='Nadir'?'rare':''}">${i.rarity}</span>${i.kind!=='accessory'?`<span class="item-type-pill">${state.equipped[i.kind]===i.id?'Kullanımda':'Sana ait'}</span>`:''}</div><div class="item-body"><strong>${esc(i.name)}</strong><small>${esc(i.category)} · ${esc(i.kind==='outfit'?'Giyilebilir':i.kind==='accessory'?'Aksesuar':'Sığınak eşyası')}</small>${i.kind!=='accessory'?`<div class="item-price"><span></span><button class="buy-button" data-equip="${i.id}">${state.equipped[i.kind]===i.id?'Seçildi':'Kullan'}</button></div>`:''}</div></article>`).join('')}</div>`:`<div class="empty-state"><div>✧</div><strong>Burada henüz bir şey yok</strong><p>Mağazada sana göz kırpan ilk parçayı bul.</p><button class="primary-button" data-route="shop">Mağazaya göz at</button></div>`}`}
  function shopPage(){const cats=['Tümü','Mobilya','Dekor','Bitkiler','Kıyafet','Aksesuar'];const list=ITEMS.filter(i=>shopFilter==='Tümü'||i.category===shopFilter);return `${pageHeading('KÜÇÜK DÜNYA MAĞAZASI','Mağaza','Yıldızlarını, sana ait küçük güzelliklere dönüştür.',`<span class="date-chip">✦ ${state.stars} &nbsp;·&nbsp; ✧ ${state.crystals}</span>`)}<div class="filters">${cats.map(c=>`<button class="filter-chip ${shopFilter===c?'active':''}" data-shop-filter="${c}">${c}</button>`).join('')}</div><div class="shop-grid">${list.map(i=>{let owned=state.owned.includes(i.id);let balance=i.currency==='crystals'?state.crystals:state.stars;let affordable=balance>=i.price;return `<article class="item-card"><div class="item-visual">${i.emoji}<span class="rarity ${i.rarity==='Destansı'?'epic':i.rarity==='Nadir'?'rare':''}">${i.rarity}</span><span class="item-type-pill">${i.category}</span></div><div class="item-body"><strong>${esc(i.name)}</strong><small>${i.kind==='outfit'?'Karakter görünümü':i.kind==='accessory'?'Karakter aksesuarı':'Sığınak eşyası'}</small><div class="item-price"><span class="price">${currencyIcon(i.currency)} ${i.price}</span><button class="buy-button" data-buy="${i.id}" ${owned||!affordable?'disabled':''}>${owned?'Koleksiyonunda':affordable?'Satın al':'Yıldız biriktir'}</button></div></div></article>`}).join('')}</div><div class="section-row"><div><h2>Alışverişin küçük bir iyilik</h2><p>Bir parça satın aldığında koleksiyonuna eklenir.</p></div></div>`}
  function diaryPage(){return `${pageHeading('KENDİNE AYIRDIĞIN BİR AN','Günlüğüm','Duygularına yer aç. Bu sayfa yalnızca senin.')}<div class="dashboard-layout"><div><form class="diary-form" id="diary-form"><label><strong style="font:600 16px var(--serif)">Şu an nasıl hissediyorsun?</strong></label><div class="mood-row">${[['Sakin','🌙'],['Neşeli','🌷'],['Meraklı','🦋'],['Yorgun','☁️'],['Umutlu','✨']].map(([m,e])=>`<button type="button" class="mood-button ${state.mood===m?'active':''}" data-mood="${m}"><span>${e}</span><small>${m}</small></button>`).join('')}</div><label for="diary-text" class="eyebrow" style="display:block;margin-top:15px">KÜÇÜK NOTUN</label><textarea id="diary-text" placeholder="Bugün aklından neler geçti? Bir cümle bile yeter…"></textarea><div style="display:flex;justify-content:space-between;align-items:center;margin-top:10px"><small style="color:#aaa2b2">Notun otomatik saklanır.</small><button type="submit" class="primary-button">Günlüğe ekle ✦</button></div></form><div class="section-row"><div><h2>Geçmiş notların</h2><p>${state.diary.length} küçük anı saklı.</p></div></div><div class="diary-list">${state.diary.length?state.diary.slice().reverse().map(e=>`<article class="diary-entry"><div class="diary-entry-head"><span>${e.emoji} ${esc(e.mood)}</span><span>${esc(e.date)}</span></div><p>${esc(e.text)}</p></article>`).join(''):'<div class="empty-state"><div>📖</div><strong>İlk sayfan seni bekliyor</strong><p>Bir ruh hâli seç ve kendine küçük bir not bırak.</p></div>'}</div></div><div>${levelCard()}<div class="section-row"><div><h2>Yazmak da bir görev</h2><p>Bir not bırakınca ilerler.</p></div></div>${taskCards(3)}</div></div>`}
  function gamesPage(){return `${pageHeading('BİR NEFESLİK MOLALAR','Mini Oyunlar','Küçük oyunlar, büyük gülümsemeler.')}<div class="game-grid"><article class="game-card"><div class="game-icon">✦</div><h3>Yıldız Avcısı</h3><p>Uçuşan yıldızlara dokun. Her parıltı sana küçük bir ödül bırakır.</p><button class="soft-button" data-action="play-stars">Oynamaya başla →</button></article><article class="game-card"><div class="game-icon">🔮</div><h3>Ruhunun Rengi</h3><p>Bugünkü küçük seçimlerin sana içindeki masalı anlatsın.</p><button class="soft-button" data-action="play-quiz">Testi başlat →</button></article><article class="game-card"><div class="game-icon">🧩</div><h3>Ay Işığı Bulmacası</h3><p>Sakin bir eşleştirme oyunu üzerinde çalışıyoruz. Yakında burada!</p><span class="coming-soon">YAKINDA</span></article></div><div id="game-stage" style="margin-top:15px"></div>`}
  function achievementsPage(){const achieved=[['🌱','İlk adım','Littleverse’e hoş geldin.',1,1],['🗺️','Gezgin ruh','Üç farklı dünyayı ziyaret et.',state.visited.length,3],['🎀','Küçük koleksiyoncu','Beş parçayı koleksiyonuna ekle.',state.owned.length,5],['📖','Kendine kulak ver','Günlüğüne üç not bırak.',state.diary.length,3],['✦','Yıldız avcısı','Bugün beş yıldız yakala.',state.tapsToday,5],['🏡','Yuva kuran','Sığınağına bir parça yerleştir.',state.equipped.furniture?1:0,1]];return `${pageHeading('HER KÜÇÜK ŞEY SAYILIR','Başarımlar','Yol boyunca bıraktığın tatlı izler.')}<div class="achievement-grid">${achieved.map(([icon,title,desc,progress,target])=>`<article class="achievement-card ${progress<target?'locked':''}"><div class="achievement-icon">${icon}</div><div style="flex:1"><strong>${title}</strong><p>${desc}</p><div class="progress-meta" style="color:#a19aaa"><span>${progress>=target?'Tamamlandı':'İlerleme'}</span><span>${Math.min(progress,target)}/${target}</span></div><div class="achievement-progress"><span style="width:${Math.min(100,progress/target*100)}%"></span></div></div></article>`).join('')}</div>`}
  function settingsPage(){return `${pageHeading('KÜÇÜK DÜNYAN, SENİN KURALLARIN','Ayarlar','Dünyanı kendine göre düzenle.')}<div class="dashboard-layout"><div class="setting-list"><div class="setting-row"><div><strong>Oyuncu adı</strong><small>Littleverse’te sana nasıl seslenelim?</small></div><input type="text" id="name-input" maxlength="18" value="${esc(state.name)}" aria-label="Oyuncu adı" /></div><div class="setting-row"><div><strong>Dünya ışığı</strong><small>Gündüzün yumuşaklığı veya gecenin dinginliği.</small></div><select id="theme-select"><option value="gündüz" ${state.theme==='gündüz'?'selected':''}>Gündüz lavantası</option><option value="gece" ${state.theme==='gece'?'selected':''}>Gece moru</option></select></div><div class="setting-row"><div><strong>Kaydetme durumu</strong><small>İlerlemen otomatik kaydedilir.</small></div><span class="storage-status" id="storage-status"><i></i>${cloud.enabled?'Bulutla eşitleniyor':'Bu cihazda saklanıyor'}</span></div><div class="setting-row"><div><strong>İlerlemeni sıfırla</strong><small>Dünyanı ilk günkü hâline döndürür.</small></div><button class="danger-button" data-action="reset">Sıfırlama seçenekleri</button></div></div><div><div class="empty-state"><div>🔒</div><strong>Güvenli ve sana özel</strong><p>İlerlemen bu tarayıcıda saklanır; Supabase anonim oturumu açıksa özel bulut kaydına da eşitlenir. E-posta veya parola gerekmez. Anonim kayıt başka bir cihaza taşınamaz.</p></div><div class="section-row"><div><h2>Yardım</h2></div></div><div class="empty-state" style="padding:22px"><strong>Littleverse’in ilk sürümü</strong><p>Bu sürümde görevler, envanter, mağaza, oda ve bahçe düzenleme, günlük, kişiselleştirme ve iki mini oyun çalışır. Bulmaca ve yeni dünyalar yeni güncellemelerle açılacak.</p></div></div></div>`}
  function render(){
    if(!NAV.some(n=>n[0]===route))route='home';document.body.dataset.theme=state.theme==='gece'?'gece':'gündüz';
    renderNav();$('#current-section').textContent=NAV.find(n=>n[0]===route)?.[1]||'Ana Sayfa';updateHud();
    const pages={home:homePage,sanctuary:sanctuaryPage,explore:explorePage,character:characterPage,collection:collectionPage,quests:questPage,diary:diaryPage,games:gamesPage,shop:shopPage,achievements:achievementsPage,settings:settingsPage};
    $('#view').innerHTML=pages[route]();
    if(route==='settings')setStatus(cloud.enabled?'Bulutla eşitleniyor':'Bu cihazda saklanıyor',cloud.enabled);
  }
  function modal(title,body,confirmText='Tamam',onConfirm=null){const root=$('#modal-root');root.innerHTML=`<div class="modal-backdrop" role="presentation"><section class="modal-card" role="dialog" aria-modal="true" aria-labelledby="modal-title"><h2 id="modal-title">${title}</h2><p>${body}</p><div class="modal-actions"><button class="secondary-button" data-action="close-modal">Vazgeç</button><button class="${confirmText==='Dünyamı sıfırla'?'danger-button':'primary-button'}" data-action="modal-confirm">${confirmText}</button></div></section></div>`;root._confirm=onConfirm;$('.modal-backdrop').addEventListener('click',e=>{if(e.target.classList.contains('modal-backdrop'))closeModal()});$('#modal-root').onkeydown=e=>{if(e.key==='Escape')closeModal()}}
  function closeModal(){$('#modal-root').innerHTML=''}
  function awardQuest(id){const q=state.quests.find(q=>q.id===id);if(!q||q.claimed||q.progress<q.target)return;q.claimed=true;grant({stars:q.reward,xp:q.xp});showToast(`Görev tamamlandı! +${q.reward} yıldız, +${q.xp} XP ✦`);render()}
  function openStars(){route='games';render();$('#game-stage').innerHTML=`<section class="game-arena"><div class="eyebrow">GÖKYÜZÜNDEKİ PARILTILAR</div><h3>Yıldız Avcısı</h3><p>Bir yıldıza dokun. Her dokunuş küçük bir ödül!</p><button class="star-target" data-action="tap-star" aria-label="Yıldızı yakala">✦</button><p>Bugün yakaladıkların: <strong>${state.tapsToday}</strong> · ✦ +5</p><button class="text-button" data-action="close-game">Oyundan çık</button></section>`;window.scrollTo({top:0,behavior:'smooth'})}
  function openQuiz(){route='games';render();if(state.quizDone){$('#game-stage').innerHTML=`<div class="empty-state"><div>🔮</div><strong>Bugünün ruh rengi açıldı!</strong><p>Yarın yeni bir seçim seni bekliyor.</p></div>`;return}$('#game-stage').innerHTML=`<section class="game-arena"><div style="font-size:36px">🔮</div><h3>Bugün hangisi sana iyi gelir?</h3><p>Kalbine en yakın olanı seç.</p><div class="quiz-options">${[['🌙','Sessiz bir köşe'],['🌷','Bir buket çiçek'],['🦋','Yeni bir yol'],['☁️','Yumuşak bir bulut']].map(([e,t])=>`<button class="quiz-option" data-quiz="${e} ${t}">${e} &nbsp; ${t}</button>`).join('')}</div></section>`}
  function buy(id){const item=itemById(id);if(!item)return;if(state.owned.includes(id)){showToast('Bu parça zaten koleksiyonunda.');return}let bal=item.currency==='crystals'?'crystals':'stars';if(state[bal]<item.price){showToast('Biraz daha yıldız biriktirmen gerek ✨','gold');return}state[bal]-=item.price;state.owned.push(id);grant({xp:8});showToast(`${item.name} koleksiyonuna eklendi!`);render()}
  function equip(id){const item=itemById(id);if(!item||!state.owned.includes(id))return;state.equipped[item.kind]=id;save();showToast(`${item.name} seçildi ✦`);render()}
  function visitWorld(id){const w=WORLDS.find(w=>w.id===id);if(!w)return;if(w.unlockLevel&&state.level<w.unlockLevel){showToast(`${w.title} ${w.requirement} olduğunda açılacak.`,`gold`);return}if(!state.visited.includes(id)){state.visited.push(id);incrementQuest('world');grant({stars:10,xp:12});showToast(`${w.title} keşfedildi! +10 yıldız`)}else showToast(`${w.title}’e tekrar hoş geldin ☾`);save();render()}
  function reset(){closeModal();state=freshState();save();render();showToast('Dünyan yeni bir başlangıca hazır.')}
  function onAction(action){
    if(action.startsWith('route:')){navigate(action.split(':')[1]);return}
    if(action.startsWith('claim-quest:')){awardQuest(action.split(':')[1]);return}
    if(action==='surprise'){const today=new Date().toLocaleDateString('en-CA');if(state.surpriseDate===today)return;state.surpriseDate=today;grant({stars:25,crystals:2,xp:15});showToast('Sürprizinde 25 yıldız ve 2 kristal var! ✨');render()}
    if(action==='play-stars'){openStars()}
    if(action==='play-quiz'){openQuiz()}
    if(action==='tap-star'){const today=new Date().toLocaleDateString('en-CA');if(state.tapsDate!==today){state.tapsToday=0;state.tapsDate=today}state.tapsToday++;incrementQuest('stars');grant({stars:5,xp:2});showToast('Bir yıldız daha yakaladın! +5 ✦');openStars()}
    if(action==='close-game'){navigate('games')}
    if(action==='reset'){modal('Dünyanı nasıl sıfırlayalım?','Tüm ilerlemeni, yıldızlarını ve koleksiyonunu silip başlangıç değerlerine dönmek üzeresin. Bu işlem geri alınamaz.','Dünyamı sıfırla',reset)}
    if(action==='close-modal')closeModal();
    if(action==='modal-confirm'){const fn=$('#modal-root')._confirm;fn?.()}
  }
  document.addEventListener('click',e=>{
    const routeEl=e.target.closest('[data-route]');if(routeEl){e.preventDefault();navigate(routeEl.dataset.route);return}
    const act=e.target.closest('[data-action]');if(act){onAction(act.dataset.action);return}
    const world=e.target.closest('[data-world]');if(world){visitWorld(world.dataset.world);return}
    const buyEl=e.target.closest('[data-buy]');if(buyEl){buy(buyEl.dataset.buy);return}
    const equipEl=e.target.closest('[data-equip]');if(equipEl){equip(equipEl.dataset.equip);return}
    const q=e.target.closest('[data-quiz]');if(q){state.quizDone=true;grant({crystals:3,xp:10});showToast('Ruh rengin: '+q.dataset.quiz+' · +3 kristal');openQuiz();return}
    const mood=e.target.closest('[data-mood]');if(mood){state.mood=mood.dataset.mood;save();render();return}
    const avatar=e.target.closest('[data-avatar]');if(avatar){state.avatar=avatar.dataset.avatar;save();render();showToast('Karakter görünüşün güncellendi.');return}
    const room=e.target.closest('[data-room-tab]');if(room){state.roomTab=room.dataset.roomTab;save();render();return}
    const roomMode=e.target.closest('[data-room-mode]');if(roomMode){state.roomMode=roomMode.dataset.roomMode;save();render();return}
    const c=e.target.closest('[data-collection-filter]');if(c){collectionFilter=c.dataset.collectionFilter;render();return}
    const s=e.target.closest('[data-shop-filter]');if(s){shopFilter=s.dataset.shopFilter;render();return}
  });
  document.addEventListener('submit',e=>{
    if(e.target.id==='diary-form'){e.preventDefault();const text=$('#diary-text').value.trim();if(!text){showToast('Küçük bir not yaz, sonra günlüğüne ekle.','gold');return}const moods={Sakin:'🌙',Neşeli:'🌷',Meraklı:'🦋',Yorgun:'☁️',Umutlu:'✨'};state.diary.push({text,mood:state.mood,emoji:moods[state.mood]||'🌙',date:new Intl.DateTimeFormat('tr-TR',{day:'numeric',month:'long',year:'numeric'}).format(new Date())});incrementQuest('diary');grant({xp:12});save();render();showToast('Notun günlüğüne eklendi. Kendine iyi baktın ✿')}
  });
  document.addEventListener('change',e=>{
    if(e.target.id==='theme-select'){state.theme=e.target.value;save();render();showToast('Dünyanın ışığı değişti.')}
    if(e.target.id==='name-input'){const name=e.target.value.trim();state.name=name||'Luna';save();render();showToast('İsmin güncellendi.')}
  });
  $('#surprise-shortcut').addEventListener('click',()=>{navigate('home');setTimeout(()=>onAction('surprise'),0)});
  window.addEventListener('hashchange',()=>{route=location.hash.replace('#','')||'home';render()});

  async function cloudInit(){
    const conf=window.LITTLEVERSE_SUPABASE;if(!conf?.url||!conf?.anonKey){setStatus('Bu cihazda saklanıyor');return}
    try{
      let sess;try{sess=JSON.parse(localStorage.getItem(SESSION)||'null')}catch{}
      if(sess?.refresh_token&&sess.expires_at<Date.now()/1000+60){
        const refresh=await fetch(conf.url+'/auth/v1/token?grant_type=refresh_token',{method:'POST',headers:{'apikey':conf.anonKey,'Content-Type':'application/json'},body:JSON.stringify({refresh_token:sess.refresh_token})});
        if(refresh.ok){const data=await refresh.json();sess={access_token:data.access_token,refresh_token:data.refresh_token,user:data.user,expires_at:data.expires_at||Math.floor(Date.now()/1000)+(data.expires_in||3600)};localStorage.setItem(SESSION,JSON.stringify(sess))}else sess=null;
      }
      if(!sess?.access_token){
        const res=await fetch(conf.url+'/auth/v1/signup',{method:'POST',headers:{'apikey':conf.anonKey,'Content-Type':'application/json'},body:'{}'});
        const data=await res.json();if(!res.ok||!data.access_token)throw new Error(data.msg||data.message||data.error_description||'Anonim oturum açılamadı');
        sess={access_token:data.access_token,refresh_token:data.refresh_token,user:data.user,expires_at:data.expires_at||Math.floor(Date.now()/1000)+(data.expires_in||3600)};localStorage.setItem(SESSION,JSON.stringify(sess));
      }
      cloud={enabled:true,userId:sess.user.id,accessToken:sess.access_token,syncing:false};
      const res=await fetch(conf.url+`/rest/v1/player_saves?user_id=eq.${encodeURIComponent(cloud.userId)}&select=state`,{headers:{'apikey':conf.anonKey,'Authorization':'Bearer '+cloud.accessToken}});
      if(res.ok){const rows=await res.json();if(rows[0]?.state){state={...freshState(),...rows[0].state};save() }else await cloudSave()}
      else throw new Error('Kayıt tablosuna erişilemedi');
      setStatus('Bulutla eşitleniyor',true);if(route==='settings')render();
    }catch(err){cloud.enabled=false;setStatus('Bu cihazda saklanıyor');console.info('Littleverse cloud sync unavailable:',err.message)}
  }
  let cloudTimer;
  async function cloudSave(){
    if(!cloud.enabled||cloud.syncing)return;clearTimeout(cloudTimer);cloudTimer=setTimeout(async()=>{
      cloud.syncing=true;const conf=window.LITTLEVERSE_SUPABASE;
      try{const res=await fetch(conf.url+'/rest/v1/player_saves?on_conflict=user_id',{method:'POST',headers:{'apikey':conf.anonKey,'Authorization':'Bearer '+cloud.accessToken,'Content-Type':'application/json','Prefer':'resolution=merge-duplicates,return=minimal'},body:JSON.stringify({user_id:cloud.userId,state,updated_at:new Date().toISOString()})});if(!res.ok)throw new Error('Eşitleme tamamlanamadı');setStatus('Bulutla eşitleniyor',true)}catch(e){setStatus('Bu cihazda saklanıyor');console.info(e.message)}finally{cloud.syncing=false}
    },450);
  }

  // Daily quest list is refreshed by calendar date while long-term keeps remain untouched.
  const questDay=new Date().toLocaleDateString('en-CA');
  if(state.questDay!==questDay){state.quests=QUEST_SEED.map(q=>({...q}));state.questDay=questDay;state.quizDone=false;state.surpriseDate=state.surpriseDate||'';}
  if(state.tapsDate!==new Date().toLocaleDateString('en-CA')){state.tapsToday=0;state.tapsDate=new Date().toLocaleDateString('en-CA')}
  render();save();cloudInit();
})();

