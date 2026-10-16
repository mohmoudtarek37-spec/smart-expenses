/* UI preferences only. Financial records remain in their own storage. */
(()=>{
'use strict';
const root=document.documentElement;
const get=k=>{try{return localStorage.getItem(k)||''}catch(e){return ''}};
const put=(k,v)=>{try{localStorage.setItem(k,v)}catch(e){}};
const keyAr='hesabaty_ui_user_name_ar',keyEn='hesabaty_ui_user_name_en',legacyKey='hesabaty_ui_user_name';
const colorKey='hesabaty_ui_accent',glassKey='hesabaty_ui_glass';
const accents=['yellow','mint','orange','blue','pink'];
const known=[
['محمود','Mahmoud'],['محمد','Mohamed'],['أحمد','Ahmed'],['احمد','Ahmed'],
['إبراهيم','Ibrahim'],['ابراهيم','Ibrahim'],['علي','Ali'],['عمر','Omar'],
['يوسف','Youssef'],['كريم','Karim'],['أحمد محمد','Ahmed Mohamed'],['نور','Nour'],
['مصطفى','Mostafa'],['فاطمة','Fatma'],['سارة','Sara'],['مريم','Mariam'],
['عبدالله','Abdallah'],['عبد الله','Abdallah'],['خالد','Khaled'],['حسن','Hassan'],
['ياسمين','Yasmin'],['أسماء','Asmaa'],['أسماء محمد','Asmaa Mohamed']
];
const arChars={'ا':'a','أ':'a','إ':'i','آ':'a','ب':'b','ت':'t','ث':'th','ج':'g','ح':'h','خ':'kh','د':'d','ذ':'z','ر':'r','ز':'z','س':'s','ش':'sh','ص':'s','ض':'d','ط':'t','ظ':'z','ع':'a','غ':'gh','ف':'f','ق':'q','ك':'k','ل':'l','م':'m','ن':'n','ه':'h','ة':'a','و':'ou','ي':'y','ى':'a','ئ':'e','ء':''};
const enSyllables=[['sh','ش'],['kh','خ'],['gh','غ'],['th','ث'],['ph','ف'],['ou','و'],['ee','ي'],['oo','و'],['ch','تش']];
function toEnglish(name){
 name=(name||'').trim();if(!name)return '';
 const direct=known.find(([ar])=>ar===name);if(direct)return direct[1];
 return name.split(/\s+/).map(w=>{
   const k=known.find(([ar])=>ar===w);if(k)return k[1];
   if(!/[\u0600-\u06FF]/.test(w))return w;
   const output=[...w].map(ch=>arChars[ch]??ch).join('').replace(/aa+/g,'a');
   return output.charAt(0).toUpperCase()+output.slice(1);
 }).join(' ').slice(0,42);
}
function toArabic(name){
 name=(name||'').trim();if(!name)return '';
 const direct=known.find(([,en])=>en.toLowerCase()===name.toLowerCase());if(direct)return direct[0];
 return name.split(/\s+/).map(word=>{
   const exact=known.find(([,en])=>en.toLowerCase()===word.toLowerCase());if(exact)return exact[0];
   if(/[\u0600-\u06FF]/.test(word))return word;
   let w=word.toLowerCase(),out='';
   while(w){
     const digraph=enSyllables.find(([e])=>w.startsWith(e));
     if(digraph){out+=digraph[1];w=w.slice(digraph[0].length);continue}
     const c=w[0];
     const letters={a:'ا',b:'ب',c:'ك',d:'د',e:'ي',f:'ف',g:'ج',h:'ه',i:'ي',j:'ج',k:'ك',l:'ل',m:'م',n:'ن',o:'و',p:'ب',q:'ق',r:'ر',s:'س',t:'ت',u:'و',v:'ف',w:'و',x:'كس',y:'ي',z:'ز'};
     out+=letters[c]||c;w=w.slice(1);
   }
   return out;
 }).join(' ').slice(0,42);
}
let arName=get(keyAr).trim(),enName=get(keyEn).trim();
if(!arName&&!enName){
  const old=get(legacyKey).trim();
  if(/[\u0600-\u06FF]/.test(old)){arName=old;enName=toEnglish(old)}
  else if(old){enName=old;arName=toArabic(old)}
}
const currentLang=()=>root.lang==='en'?'en':'ar';
let animationFrame=0;
function updateGreeting(){
 const en=currentLang()==='en';
 const val=en?(enName||toEnglish(arName)):(arName||toArabic(enName));
 const title=document.getElementById('welcomeName');
 if(title)title.textContent=val?(en?'Welcome, ':'أهلاً يا ')+val+' 👋':(en?'Welcome 👋':'أهلًا بيك 👋');
 const caption=document.getElementById('profileNameCaption');
 if(caption)caption.textContent=en?(enName||'Edit your name in both languages'):(arName||'عدّل اسمك بالعربي والإنجليزي');
}
function updateSettings(){
 document.querySelectorAll('[data-pref-accent]').forEach(btn=>btn.setAttribute('aria-pressed',String(btn.dataset.prefAccent===root.dataset.accent)));
 document.querySelectorAll('[data-pref-glass]').forEach(btn=>btn.setAttribute('aria-pressed',String(btn.dataset.prefGlass===root.dataset.glass)));
 updateGreeting();
}
function updateNav(){
 if(animationFrame)cancelAnimationFrame(animationFrame);
 animationFrame=requestAnimationFrame(()=>{
  animationFrame=0;
  const nav=document.querySelector('.bottom-nav'),marker=nav?.querySelector('.nav-glider'),active=nav?.querySelector('.nav-button.active');
  if(!nav||!marker)return;
  if(!active){marker.style.opacity='0';return}
  const nr=nav.getBoundingClientRect(),ar=active.getBoundingClientRect();
  marker.style.width=Math.round(ar.width)+'px';
  marker.style.transform='translate3d('+Math.round(ar.left-nr.left)+'px,0,0)';
  marker.style.opacity='1';
 });
}
function applyAccent(val){
 if(!accents.includes(val))return;root.dataset.accent=val;put(colorKey,val);updateSettings();
}
function applyGlass(val){
 if(!['clear','blur'].includes(val))return;root.dataset.glass=val;put(glassKey,val);updateSettings();
}
function profileDialog(force=false){
 if(document.querySelector('.profile-overlay'))return;
 const en=currentLang()==='en';
 const dialog=document.createElement('div');dialog.className='profile-overlay';
 dialog.innerHTML='<section class="profile-dialog" role="dialog" aria-modal="true" aria-labelledby="profileTitle">'+
  '<h2 id="profileTitle"></h2><p id="profileHint"></p><form id="profileForm">'+
  '<label for="profileNameAr">الاسم بالعربي</label><input id="profileNameAr" maxlength="42" dir="rtl" autocomplete="given-name">'+
  '<label for="profileNameEn">Name in English</label><input id="profileNameEn" maxlength="42" dir="ltr" autocomplete="given-name">'+
  '<button type="submit" class="btn block" id="profileSubmit"></button></form></section>';
 const set=(id,value)=>dialog.querySelector('#'+id).textContent=value;
 set('profileTitle',en?'Welcome to My Accounts 👋':'أهلًا بيك في حساباتي 👋');
 set('profileHint',en?'Add or adjust your name in Arabic and English. We can suggest the other spelling automatically.':'اكتب اسمك بأي لغة، وهنقترح الكتابة التانية تلقائيًا، وتقدر تصححها.');
 set('profileSubmit',en?'Save name':'حفظ الاسم');
 const ar=dialog.querySelector('#profileNameAr'),eng=dialog.querySelector('#profileNameEn');
 ar.value=arName;eng.value=enName;
 let editedAr=Boolean(arName),editedEn=Boolean(enName);
 ar.addEventListener('input',()=>{editedAr=true;if(!editedEn)eng.value=toEnglish(ar.value)});
 eng.addEventListener('input',()=>{editedEn=true;if(!editedAr)ar.value=toArabic(eng.value)});
 dialog.querySelector('#profileForm').addEventListener('submit',e=>{
  e.preventDefault();
  let av=ar.value.trim().replace(/\s+/g,' ').slice(0,42),ev=eng.value.trim().replace(/\s+/g,' ').slice(0,42);
  if(!av&&!ev){(en?eng:ar).focus();return}
  if(!av)av=toArabic(ev);
  if(!ev)ev=toEnglish(av);
  arName=av;enName=ev;
  put(keyAr,av);put(keyEn,ev);put(legacyKey,av);
  dialog.remove();updateGreeting();
 });
 if(!force)dialog.addEventListener('click',e=>{if(e.target===dialog)dialog.remove()});
 document.body.appendChild(dialog);
 requestAnimationFrame(()=>(en?eng:ar).focus());
}
document.addEventListener('click',e=>{
 const a=e.target.closest('[data-pref-accent]');
 if(a){applyAccent(a.dataset.prefAccent);return}
 const g=e.target.closest('[data-pref-glass]');
 if(g){applyGlass(g.dataset.prefGlass);return}
 if(e.target.closest('[data-profile-edit]')){profileDialog(false);return}
 if(e.target.closest('#langToggle'))requestAnimationFrame(()=>{updateGreeting();updateSettings();updateNav()});
});
window.addEventListener('resize',updateNav,{passive:true});
window.addEventListener('pageshow',()=>{updateGreeting();updateNav()});
function init(){

 if(!accents.includes(root.dataset.accent))root.dataset.accent='yellow';
 if(!['clear','blur'].includes(root.dataset.glass))root.dataset.glass='clear';
 updateGreeting();updateSettings();updateNav();
 if(!arName&&!enName)profileDialog(true);
}
window.hesabatyUI={updateNav,updateSettings,updateGreeting,applyAccent,applyGlass};
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();
