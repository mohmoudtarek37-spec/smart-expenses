/* Appearance preference only; financial data remains untouched in IndexedDB. */
(()=>{
  'use strict';
  const KEY='hesabaty_ui_theme';
  const root=document.documentElement;
  const button=document.getElementById('themeToggle');
  const meta=document.querySelector('meta[name="theme-color"]');
  const svg=body=>'<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">'+body+'</svg>';
  const moon=svg('<path d="M20.7 15.6A8.5 8.5 0 0 1 8.4 3.3a8.6 8.6 0 1 0 12.3 12.3Z"/>');
  const sun=svg('<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.42 1.42m11.3 11.3 1.42 1.42M2 12h2m16 0h2M4.93 19.07l1.42-1.42m11.3-11.3 1.42-1.42"/>');
  const apply=(theme,save)=>{
    const dark=theme==='dark';
    root.dataset.theme=dark?'dark':'light';
    if(button){button.innerHTML=dark?sun:moon;button.setAttribute('aria-label',dark?'تفعيل الوضع الفاتح':'تفعيل الوضع الداكن');button.setAttribute('title',dark?'تفعيل الوضع الفاتح':'تفعيل الوضع الداكن');button.setAttribute('aria-pressed',String(dark));}
    if(meta)meta.setAttribute('content',dark?'#0b1017':'#ffffff');
    if(save)try{localStorage.setItem(KEY,dark?'dark':'light')}catch(e){}
  };
  apply(root.dataset.theme==='dark'?'dark':'light',false);
  if(button)button.addEventListener('click',()=>apply(root.dataset.theme==='dark'?'light':'dark',true));
})();
