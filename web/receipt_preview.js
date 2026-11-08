(() => {
  window.gymproReceiptPreview = (html, title) => {
    document.getElementById('gympro-receipt-preview')?.remove();
    // Disable active content and remote resources before putting HTML into an isolated frame.
    const doc = new DOMParser().parseFromString(html, 'text/html');
    doc.querySelectorAll('script,base,meta,iframe,object,embed,link,form,input,button,textarea,select,svg,math,audio,video,source').forEach(node => node.remove());
    for (const node of doc.querySelectorAll('*')) {
      for (const attribute of [...node.attributes]) {
        const name = attribute.name.toLowerCase();
        if (name.startsWith('on') || ['href','srcdoc','action','formaction','target','ping','background','srcset','poster'].includes(name) ||
            (name === 'src' && !(node.tagName === 'IMG' && /^data:image\/(png|jpeg|gif|webp);base64,/i.test(attribute.value)))) node.removeAttribute(attribute.name);
      }
    }
    const policy = document.createElement('meta');
    policy.httpEquiv = 'Content-Security-Policy';
    policy.content = "default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src 'none'; base-uri 'none'; form-action 'none'";
    doc.head.prepend(policy);
    const overlay = document.createElement('section');
    overlay.id = 'gympro-receipt-preview';
    overlay.setAttribute('role','dialog'); overlay.setAttribute('aria-label',title); overlay.setAttribute('aria-modal','true');
    overlay.style.cssText='position:fixed;inset:0;z-index:2147483647;background:#f3f5f8;display:flex;flex-direction:column;font:14px Arial;color:#08152f';
    const toolbar=document.createElement('div');toolbar.style.cssText='display:flex;align-items:center;flex-wrap:wrap;gap:8px;padding:12px;background:white;border-bottom:1px solid #e5e8ee';
    const heading=document.createElement('strong');heading.textContent=title;heading.style.cssText='flex:1;min-width:120px';toolbar.append(heading);
    const frame=document.createElement('iframe');frame.title=title;frame.setAttribute('sandbox','allow-same-origin allow-modals');frame.style.cssText='flex:1;width:100%;border:0;background:white;min-height:0';
    frame.srcdoc='<!doctype html>'+doc.documentElement.outerHTML;
    const previousFocus=document.activeElement;
    function button(label,action){const b=document.createElement('button');b.textContent=label;b.style.cssText='padding:10px 14px;min-height:44px;border:1px solid #dce3ed;border-radius:10px;background:#ebf2ff;color:#1c5ebf;cursor:pointer';b.onclick=action;toolbar.append(b);return b;}
    const print=button('Print / Save PDF',()=>{frame.contentWindow.focus();frame.contentWindow.print();});
    button('Download HTML',()=>{const url=URL.createObjectURL(new Blob([frame.srcdoc],{type:'text/html'}));const link=document.createElement('a');link.href=url;link.download=(title.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'' )||'gympro-document')+'.html';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);});
    const close=()=>{overlay.remove();previousFocus?.focus();};
    button('Close',close);
    overlay.addEventListener('keydown',event=>{if(event.key==='Escape')close();});
    overlay.append(toolbar,frame);document.body.append(overlay);print.focus();
  };
})();
