/* Browser-native monthly PDF export. Renders Arabic through canvas font shaping;
   pages are embedded as JPEG image objects inside an A4 PDF. No network required. */
'use strict';
async function exportMonthlyPdf(){
 const month=viewMonth;
 const txns=state.transactions.filter(t=>t.date&&t.date.slice(0,7)===month)
  .slice().sort((a,b)=>(a.date||'').localeCompare(b.date||'')||(a.createdAt||'').localeCompare(b.createdAt||''));
 const en=document.documentElement.lang==='en';
 const langFont=en?'Inter,Arial,sans-serif':'Alexandria,Tahoma,Arial,sans-serif';
 const figures=totals(month);
 const W=1120,H=1584,P=16;
 const A4W=595.28,A4H=841.89;
 const totalPages=Math.max(1,Math.ceil(txns.length/P));
 const pages=[];
 const reportTitle=en?'Monthly transactions report':'تقرير المعاملات الشهري';
 const monthLabel=monthName(month);
 const fmt=n=>money(Number(n)||0);
 const text=(ctx,value,x,y,size=25,color='#172334',weight=500,align='right')=>{
   ctx.font=weight+' '+size+'px '+langFont;ctx.fillStyle=color;
   ctx.textAlign=align;ctx.direction=en?'ltr':'rtl';
   ctx.fillText(String(value||''),x,y);
 };
 const clip=(ctx,value,max)=>{
   let s=String(value||'—').replace(/\s+/g,' ');
   while(s.length>2&&ctx.measureText(s).width>max)s=s.slice(0,-2)+'…';
   return s;
 };
 try{
   if(document.fonts?.ready)await document.fonts.ready;
   for(let p=0;p<totalPages;p++){
     const canvas=document.createElement('canvas');canvas.width=W;canvas.height=H;
     const ctx=canvas.getContext('2d',{alpha:false});
     if(!ctx)throw new Error('تعذر إنشاء التقرير على هذا الجهاز');
     ctx.fillStyle='#ffffff';ctx.fillRect(0,0,W,H);
     ctx.fillStyle='#fafbfe';ctx.fillRect(0,0,W,270);
     ctx.fillStyle='#d9e0e9';ctx.fillRect(65,269,990,2);
     if(en){
       text(ctx,reportTitle,70,105,45,'#111827',700,'left');
       text(ctx,monthLabel,70,162,32,'#485567',600,'left');
       text(ctx,'HESABATY  |  SMART EXPENSES',70,224,19,'#738096',500,'left');
       text(ctx,'Page '+(p+1)+' / '+totalPages,1040,224,18,'#738096',500,'right');
     }else{
       text(ctx,reportTitle,1050,105,45,'#111827',700);
       text(ctx,monthLabel,1050,162,32,'#485567',600);
       text(ctx,'حساباتي  |  تقرير شهري محفوظ على جهازك',1050,224,19,'#738096',500);
       text(ctx,'صفحة '+(p+1)+' / '+totalPages,75,224,18,'#738096',500,'left');
     }
     const headerY=330;
     ctx.fillStyle='#edf1f6';ctx.fillRect(65,295,990,62);
     const titles=en?['Date / Time','Type','Description / Merchant','Amount (EGP)']:['التاريخ والوقت','النوع','المكان أو الوصف','المبلغ (جنيه)'];
     if(en){
       text(ctx,titles[0],82,headerY,21,'#344254',700,'left');
       text(ctx,titles[1],300,headerY,21,'#344254',700,'left');
       text(ctx,titles[2],460,headerY,21,'#344254',700,'left');
       text(ctx,titles[3],1038,headerY,21,'#344254',700);
     }else{
       text(ctx,titles[0],1040,headerY,21,'#344254',700);
       text(ctx,titles[1],805,headerY,21,'#344254',700);
       text(ctx,titles[2],650,headerY,21,'#344254',700);
       text(ctx,titles[3],80,headerY,21,'#344254',700,'left');
     }
     const batch=txns.slice(p*P,(p+1)*P);
     if(!batch.length)text(ctx,en?'No transactions recorded this month':'لا توجد معاملات مسجلة لهذا الشهر',en?75:1040,442,27,'#6b7788',500,en?'left':'right');
     for(let k=0;k<batch.length;k++){
       const t=batch[k],y=404+k*63;
       if(k%2===0){ctx.fillStyle='#f7f9fc';ctx.fillRect(65,y-37,990,57)}
       const date=String(t.date||'');
       let hhmm='';
       if(t.time&&/^\d\d:\d\d/.test(t.time))hhmm=t.time.slice(0,5);
       else if(t.createdAt&&/^\d{4}-\d{2}-\d{2}T\d\d:\d\d/.test(t.createdAt)){
         const stamp=new Date(t.createdAt);
         if(Number.isFinite(stamp.getTime()))hhmm=stamp.toLocaleTimeString(en?'en-GB':'ar-EG',{hour:'2-digit',minute:'2-digit',hour12:false});
       }
       const dateText=date+(hhmm?' '+hhmm:'');
       const kind=t.type==='deposit'?(en?'Deposit':'إيداع'):(en?'Withdrawal':'سحب');
       const name=(t.note||t.category||t.source||'—')+(t.excluded?(en?' (excluded)':' (مستبعدة)'):'');
       const amt=(t.type==='deposit'?'+':'−')+fmt(t.amount);
       if(en){
         text(ctx,dateText,82,y,20,'#344254',500,'left');
         text(ctx,kind,300,y,20,t.type==='deposit'?'#047857':'#b42340',600,'left');
         ctx.font='500 21px '+langFont;
         text(ctx,clip(ctx,name,340),460,y,21,'#111827',500,'left');
         text(ctx,amt,1040,y,22,t.type==='deposit'?'#047857':'#b42340',700);
       }else{
         text(ctx,dateText,1040,y,20,'#344254',500);
         text(ctx,kind,805,y,20,t.type==='deposit'?'#047857':'#b42340',600);
         ctx.font='500 21px '+langFont;
         text(ctx,clip(ctx,name,335),650,y,21,'#111827',500);
         text(ctx,amt,80,y,22,t.type==='deposit'?'#047857':'#b42340',700,'left');
       }
     }
     if(p===totalPages-1){
       const y=1414;
       ctx.fillStyle='#edf1f6';ctx.fillRect(65,y,990,124);
       if(en){
         text(ctx,'Deposits  '+fmt(figures.deposit),87,y+45,23,'#047857',700,'left');
         text(ctx,'Withdrawals  '+fmt(figures.withdrawal),87,y+93,23,'#b42340',700,'left');
         text(ctx,'Remaining  '+fmt(figures.remaining),1034,y+68,25,'#111827',700);
       }else{
         text(ctx,'إجمالي الإيداعات  '+fmt(figures.deposit),1034,y+45,23,'#047857',700);
         text(ctx,'إجمالي السحب  '+fmt(figures.withdrawal),1034,y+93,23,'#b42340',700);
         text(ctx,'المتبقي  '+fmt(figures.remaining),87,y+68,25,'#111827',700,'left');
       }
     }
     text(ctx,(en?'Generated locally · '+txns.length+' records':'تم إعداد التقرير محليًا · عدد العمليات: '+txns.length),en?80:1040,1565,17,'#748296',500,en?'left':'right');
     const encoded=canvas.toDataURL('image/jpeg',0.78).split(',')[1];
     const binary=atob(encoded),jpeg=new Uint8Array(binary.length);
     for(let j=0;j<binary.length;j++)jpeg[j]=binary.charCodeAt(j);
     pages.push(jpeg);
     canvas.width=canvas.height=0;
     await new Promise(resolve=>setTimeout(resolve,0));
   }
   /* Minimal, standards-compliant PDF with one DCTDecode image XObject per page. */
   const encoder=new TextEncoder(),parts=[],offsets=[0];
   let length=0;
   const put=bytes=>{parts.push(bytes);length+=bytes.length};
   const write=s=>put(encoder.encode(s));
   const obj=id=>{offsets[id]=length;write(id+' 0 obj\n')};
   const children=pages.map((_,i)=>(3+i*3)+' 0 R').join(' ');
   write('%PDF-1.4\n%PDFDATA\n');
   obj(1);write('<< /Type /Catalog /Pages 2 0 R >>\nendobj\n');
   obj(2);write('<< /Type /Pages /Kids [ '+children+' ] /Count '+pages.length+' >>\nendobj\n');
   for(let i=0;i<pages.length;i++){
     const page=3+i*3,image=page+1,stream=page+2,jpeg=pages[i];
     obj(page);write('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 '+A4W+' '+A4H+'] /Resources << /XObject << /Im0 '+image+' 0 R >> >> /Contents '+stream+' 0 R >>\nendobj\n');
     obj(image);write('<< /Type /XObject /Subtype /Image /Width '+W+' /Height '+H+' /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length '+jpeg.length+' >>\nstream\n');put(jpeg);write('\nendstream\nendobj\n');
     const commands='q\n'+A4W+' 0 0 '+A4H+' 0 0 cm\n/Im0 Do\nQ\n';
     obj(stream);write('<< /Length '+encoder.encode(commands).length+' >>\nstream\n'+commands+'endstream\nendobj\n');
   }
   const count=3+pages.length*3,xref=length;
   write('xref\n0 '+count+'\n0000000000 65535 f \n');
   for(let id=1;id<count;id++)write(String(offsets[id]).padStart(10,'0')+' 00000 n \n');
   write('trailer\n<< /Size '+count+' /Root 1 0 R >>\nstartxref\n'+xref+'\n%%EOF');
   const pdf=new Blob(parts,{type:'application/pdf'});
   downloadBlob(pdf,'hesabaty-'+month+'.pdf');
   toast(en?'Monthly PDF is ready':'تم تجهيز تقرير PDF للشهر');
 }catch(e){
   console.error('Monthly PDF export error',e);
   toast(en?'Unable to prepare PDF on this device':'تعذر إنشاء PDF على هذا الجهاز');
 }
}
