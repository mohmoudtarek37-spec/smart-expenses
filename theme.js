/* Appearance preference only; financial data remains untouched in IndexedDB. */
(()=>{
  'use strict';
  const KEY='hesabaty_ui_theme';
  const root=document.documentElement;
  const button=document.getElementById('themeToggle');
  const meta=document.querySelector('meta[name="theme-color"]');
  const svg=body=>'<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">'+body+'</svg>';
  const moon=svg('<path d="M19.8 16.9A9.2 9.2 0 0 1 7.1 4.2 9.1 9.1 0 1 0 19.8 16.9Z" fill="currentColor" stroke="none"/><circle cx="18.5" cy="5.5" r="1.4" fill="currentColor" stroke="none"/>');
  const sun=svg('<circle cx="12" cy="12" r="4.5" fill="currentColor" stroke="none"/><path d="M12 1.5v3M12 19.5v3M1.5 12h3m15 0h3M4.57 4.57l2.12 2.12m10.62 10.62 2.12 2.12M19.43 4.57l-2.12 2.12M6.69 17.31l-2.12 2.12" stroke-width="2" stroke-linecap="round"/>');
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
