/* Personalization and lightweight glass navigation. No access to financial records. */
(()=>{
  'use strict';
  const root=document.documentElement;
  const keyName='hesabaty_ui_user_name';
  const keyAccent='hesabaty_ui_accent';
  const keyGlass='hesabaty_ui_glass';
  const accents=['yellow','mint','orange','blue','green'];
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
    if(e.target.closest('#langToggle')){
      requestAnimationFrame(()=>{updateGreeting();updateSettings();updateNav()});
    }
  });
  window.addEventListener('resize',updateNav,{passive:true});
  window.addEventListener('pageshow',()=>{updateGreeting();updateNav()});
  const init=()=>{
    if(!accents.includes(root.dataset.accent))root.dataset.accent='yellow';
    if(!['clear','blur'].includes(root.dataset.glass))root.dataset.glass='clear';
    updateGreeting();updateSettings();updateNav();
    if(!userName)profileDialog(true);
  };
  window.hesabatyUI={updateNav,updateSettings,updateGreeting,applyAccent,applyGlass};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});
  else init();
})();
