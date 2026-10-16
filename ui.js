/* Personalization and lightweight glass navigation. No access to financial records. */
(()=>{
  'use strict';
  const root=document.documentElement;
  const keyName='hesabaty_ui_user_name';
  const keyAccent='hesabaty_ui_accent';
  const keyGlass='hesabaty_ui_glass';
  const accents=['yellow','mint','orange','blue','pink'];
  const keyPhotoMode='hesabaty_ui_wallpaper_mode';
  const keyPhotoEffect='hesabaty_ui_wallpaper_effect';
  const photoDbName='hesabaty_ui_wallpaper_assets';
  let photoStored=false,photoUrl='';
  const get=(key)=>{try{return localStorage.getItem(key)||''}catch(e){return ''}};
  const put=(key,value)=>{try{localStorage.setItem(key,value)}catch(e){}};
  const currentLang=()=>root.lang==='en'?'en':'ar';
  let userName=get(keyName).trim().slice(0,42);
  let raf=0;

  function updateGreeting(){
    const label=document.getElementById('welcomeName');
    const en=currentLang()==='en';
    if(label)label.textContent=userName?(en?'Welcome, ':'أهلاً يا ')+userName+' 👋':(en?'Welcome 👋':'أهلًا بيك 👋');
    const caption=document.getElementById('profileNameCaption');
    if(caption)caption.textContent=userName?userName:(en?'Add your name':'اكتب اسمك');
  }
  function updateSettings(){
    document.querySelectorAll('[data-pref-accent]').forEach(b=>{
      b.setAttribute('aria-pressed',String(b.dataset.prefAccent===root.dataset.accent));
    });
    document.querySelectorAll('[data-pref-glass]').forEach(b=>{
      b.setAttribute('aria-pressed',String(b.dataset.prefGlass===root.dataset.glass));
    });
    updateGreeting();
    updateWallpaperSettings();
  }
  function updateNav(){
    if(raf)cancelAnimationFrame(raf);
    raf=requestAnimationFrame(()=>{
      raf=0;
      const nav=document.querySelector('.bottom-nav');
      const marker=nav?.querySelector('.nav-glider');
      const active=nav?.querySelector('.nav-button.active');
      if(!nav||!marker)return;
      if(!active){marker.style.opacity='0';return;}
      const nb=nav.getBoundingClientRect(),ab=active.getBoundingClientRect();
      const left=Math.round(ab.left-nb.left);
      marker.style.width=Math.round(ab.width)+'px';
      marker.style.transform='translate3d('+left+'px,0,0)';
      marker.style.opacity='1';
    });
  }
  function applyAccent(value){
    if(!accents.includes(value))return;
    root.dataset.accent=value;
    put(keyAccent,value);
    updateSettings();
  }
  function applyGlass(value){
    if(value!=='clear'&&value!=='blur')return;
    root.dataset.glass=value;
    put(keyGlass,value);
    updateSettings();
  }

  /* Photo wallpaper lives in its own IndexedDB database, separate from expenses. */
  function photoDb(){
    return new Promise((resolve,reject)=>{
      if(!('indexedDB' in window))return reject(new Error('حفظ الصور غير متاح على هذا الجهاز'));
      const request=indexedDB.open(photoDbName,1);
      request.onupgradeneeded=()=>{
        const db=request.result;
        if(!db.objectStoreNames.contains('images'))db.createObjectStore('images');
      };
      request.onsuccess=()=>resolve(request.result);
      request.onerror=()=>reject(request.error||new Error('تعذر فتح مساحة حفظ الصورة'));
    });
  }
  async function storedPhoto(operation,blob){
    const db=await photoDb();
    try{
      return await new Promise((resolve,reject)=>{
        const transaction=db.transaction('images',operation==='read'?'readonly':'readwrite');
        const store=transaction.objectStore('images');
        const req=operation==='read'?store.get('wallpaper'):operation==='delete'?store.delete('wallpaper'):store.put(blob,'wallpaper');
        let result;
        req.onsuccess=()=>{result=req.result};
        transaction.oncomplete=()=>resolve(result);
        transaction.onerror=()=>reject(transaction.error||new Error('تعذر حفظ صورة الخلفية'));
        transaction.onabort=()=>reject(transaction.error||new Error('تعذر حفظ صورة الخلفية'));
      });
    }finally{db.close()}
  }
  function showWallpaperMessage(text){
    const el=document.getElementById('wallpaperMessage');
    if(el)el.textContent=text;
  }
  function updateWallpaperSettings(){
    const isPhoto=root.dataset.wallpaper==='photo';
    document.querySelectorAll('[data-wallpaper-mode]').forEach(btn=>{
      btn.setAttribute('aria-pressed',String(btn.dataset.wallpaperMode===(isPhoto?'photo':'default')));
      btn.disabled=btn.dataset.wallpaperMode==='photo'&&!photoStored;
    });
    document.querySelectorAll('[data-wallpaper-effect]').forEach(btn=>{
      btn.setAttribute('aria-pressed',String(btn.dataset.wallpaperEffect===(root.dataset.wallpaperBlur||'clear')));
    });
    const remove=document.querySelector('[data-wallpaper-remove]');
    if(remove)remove.disabled=!photoStored;
    showWallpaperMessage(photoStored?'صورتك محفوظة على الجهاز، وتقدر تبدّلها أو تحذفها.':'اختار صورة من موبايلك عشان تستخدمها كخلفية.');
  }
  function releasePhotoUrl(){
    if(photoUrl){URL.revokeObjectURL(photoUrl);photoUrl=''}
    root.style.removeProperty('--user-wallpaper');
  }
  function presentPhoto(blob){
    if(!(blob instanceof Blob))return false;
    const url=URL.createObjectURL(blob);
    releasePhotoUrl();
    photoUrl=url;
    root.style.setProperty('--user-wallpaper','url("'+url+'")');
    root.dataset.wallpaper='photo';
    photoStored=true;
    put(keyPhotoMode,'photo');
    updateWallpaperSettings();
    return true;
  }
  async function loadPhoto(){
    try{
      const blob=await storedPhoto('read');
      photoStored=blob instanceof Blob;
      if(photoStored && get(keyPhotoMode)==='photo')presentPhoto(blob);
      else{
        root.dataset.wallpaper='default';
        if(!photoStored)put(keyPhotoMode,'default');
      }
      updateWallpaperSettings();
    }catch(e){
      root.dataset.wallpaper='default';photoStored=false;
      updateWallpaperSettings();
      showWallpaperMessage('تعذر قراءة الخلفية المحفوظة من الجهاز.');
    }
  }
  async function compressPhoto(file){
    if(!file||!file.type.startsWith('image/'))throw new Error('اختار ملف صورة من المعرض.');
    if(file.size>25*1024*1024)throw new Error('الصورة كبيرة جدًا، اختار صورة أصغر من 25 ميجابايت.');
    const uri=URL.createObjectURL(file);
    const img=new Image();
    try{
      await new Promise((resolve,reject)=>{
        img.onload=resolve;
        img.onerror=()=>reject(new Error('مش قادر أفتح الصورة. جرّب صورة JPG أو PNG.'));
        img.src=uri;
      });
      if(!img.naturalWidth||!img.naturalHeight)throw new Error('الصورة غير صالحة.');
      const limit=Math.min(1,1280/img.naturalWidth,1920/img.naturalHeight);
      const canvas=document.createElement('canvas');
      canvas.width=Math.max(1,Math.round(img.naturalWidth*limit));
      canvas.height=Math.max(1,Math.round(img.naturalHeight*limit));
      const ctx=canvas.getContext('2d',{alpha:false});
      if(!ctx)throw new Error('الجهاز مش قادر يجهز الصورة.');
      ctx.drawImage(img,0,0,canvas.width,canvas.height);
      const blob=await new Promise((resolve,reject)=>{
        canvas.toBlob(out=>out?resolve(out):reject(new Error('تعذر تجهيز الصورة')),'image/jpeg',.78);
      });
      canvas.width=canvas.height=0;
      return blob;
    }finally{URL.revokeObjectURL(uri)}
  }
  async function handlePhotoUpload(file){
    if(!file)return;
    showWallpaperMessage('جاري تجهيز الصورة على جهازك...');
    try{
      const blob=await compressPhoto(file);
      await storedPhoto('write',blob);
      presentPhoto(blob);
      showWallpaperMessage('تم حفظ الصورة على جهازك.');
    }catch(e){
      showWallpaperMessage(e.message||'تعذر حفظ الخلفية.');
    }
  }
  async function removePhoto(){
    try{
      await storedPhoto('delete');
      releasePhotoUrl();photoStored=false;root.dataset.wallpaper='default';
      put(keyPhotoMode,'default');updateWallpaperSettings();
      showWallpaperMessage('تم حذف صورة الخلفية.');
    }catch(e){showWallpaperMessage('تعذر حذف صورة الخلفية.')}
  }
  function chooseWallpaper(mode){
    if(mode==='default'){
      root.dataset.wallpaper='default';put(keyPhotoMode,'default');updateWallpaperSettings();
    }else if(mode==='photo'&&photoStored){
      if(photoUrl){root.dataset.wallpaper='photo';put(keyPhotoMode,'photo');updateWallpaperSettings();}
      else{put(keyPhotoMode,'photo');loadPhoto().catch(()=>{});}
    }
  }
  function chooseWallpaperEffect(effect){
    if(effect!=='clear'&&effect!=='blur')return;
    root.dataset.wallpaperBlur=effect;
    put(keyPhotoEffect,effect);
    updateWallpaperSettings();
  }

  function profileDialog(force){
    if(document.querySelector('.profile-overlay'))return;
    const en=currentLang()==='en';
    const overlay=document.createElement('div');
    overlay.className='profile-overlay';
    overlay.innerHTML='<section class="profile-dialog" role="dialog" aria-modal="true" aria-labelledby="profileTitle">'+
      '<h2 id="profileTitle"></h2><p id="profileHint"></p>'+
      '<form id="profileForm"><label for="profileInput" id="profileLabel"></label>'+
      '<input id="profileInput" type="text" maxlength="42" autocomplete="given-name" required />'+
      '<button class="btn block" type="submit" id="profileSubmit"></button></form></section>';
    const set=(id,text)=>{overlay.querySelector('#'+id).textContent=text;};
    set('profileTitle',en?'Welcome to My Accounts 👋':'أهلًا بيك في حساباتي 👋');
    set('profileHint',en?'What should we call you? Your name stays on this device.':'تحب نناديك بإيه؟ اسمك هيتحفظ على جهازك بس.');
    set('profileLabel',en?'Your name':'اسمك');
    set('profileSubmit',en?'Continue':'ابدأ');
    const input=overlay.querySelector('#profileInput');
    input.value=userName;
    overlay.querySelector('#profileForm').addEventListener('submit',e=>{
      e.preventDefault();
      const value=input.value.trim().replace(/\s+/g,' ').slice(0,42);
      if(!value){input.focus();return;}
      userName=value;
      put(keyName,userName);
      overlay.remove();
      updateGreeting();
    });
    if(!force && userName)overlay.addEventListener('click',e=>{if(e.target===overlay)overlay.remove()});
    document.body.appendChild(overlay);
    requestAnimationFrame(()=>input.focus());
  }
  document.addEventListener('click',e=>{
    const a=e.target.closest('[data-pref-accent]');
    if(a){applyAccent(a.dataset.prefAccent);return;}
    const g=e.target.closest('[data-pref-glass]');
    if(g){applyGlass(g.dataset.prefGlass);return;}
    if(e.target.closest('[data-profile-edit]')){profileDialog(false);return;}
    if(e.target.closest('[data-wallpaper-upload]')){document.getElementById('wallpaperFileInput')?.click();return;}
    if(e.target.closest('[data-wallpaper-remove]')){removePhoto();return;}
    const wall=e.target.closest('[data-wallpaper-mode]');
    if(wall){chooseWallpaper(wall.dataset.wallpaperMode);return;}
    const effect=e.target.closest('[data-wallpaper-effect]');
    if(effect){chooseWallpaperEffect(effect.dataset.wallpaperEffect);return;}
    if(e.target.closest('#langToggle')){
      requestAnimationFrame(()=>{updateGreeting();updateSettings();updateNav()});
    }
  });
  document.addEventListener('change',e=>{
    if(e.target.id==='wallpaperFileInput'){
      const photo=e.target.files?.[0];
      e.target.value='';
      handlePhotoUpload(photo);
    }
  });
  window.addEventListener('resize',updateNav,{passive:true});
  window.addEventListener('pageshow',()=>{updateGreeting();updateNav()});
  const init=()=>{
    if(root.dataset.accent==='green'){root.dataset.accent='pink';put(keyAccent,'pink');}
    if(!accents.includes(root.dataset.accent))root.dataset.accent='yellow';
    if(!['clear','blur'].includes(root.dataset.glass))root.dataset.glass='clear';
    root.dataset.wallpaperBlur=get(keyPhotoEffect)==='blur'?'blur':'clear';
    root.dataset.wallpaper='default';
    updateGreeting();updateSettings();updateNav();
    loadPhoto();
    if(!userName)profileDialog(true);
  };
  window.hesabatyUI={updateNav,updateSettings,updateGreeting,applyAccent,applyGlass};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});
  else init();
})();
