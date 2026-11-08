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

  window.gymproReceiptSharePdf = async (html, title) => {
    window.gymproReceiptPreview(html, title);
    const overlay = document.getElementById('gympro-receipt-preview');
    const toolbar = overlay.firstElementChild;
    const frame = overlay.querySelector('iframe');
    // Render at a stable A4 width even on small phones.
    frame.style.flex = 'none';
    frame.style.width = '794px';
    frame.style.height = '1123px';
    overlay.style.overflow = 'auto';
    toolbar.style.position = 'sticky';
    toolbar.style.top = '0';
    toolbar.style.zIndex = '1';
    const status = document.createElement('span');
    status.setAttribute('role', 'status');
    status.textContent = 'Preparing PDF…';
    toolbar.append(status);
    try {
      await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => reject(new Error('Document load timed out')), 15000);
        frame.addEventListener('load', () => { clearTimeout(timeout); resolve(); }, { once: true });
      });
      if (typeof window.html2pdf !== 'function') throw new Error('PDF renderer unavailable');
      const doc = frame.contentDocument;
      await doc.fonts.ready;
      const blob = await window.html2pdf().set({
        margin: 10,
        image: { type: 'jpeg', quality: 0.98 },
        html2canvas: {
          scale: 2, backgroundColor: '#ffffff', logging: false,
          // html2pdf moves the body into its own document. Carry the saved
          // template's stylesheet into the isolated canvas clone as well.
          onclone: cloned => {
            doc.head.querySelectorAll('style').forEach(style =>
              cloned.head.append(style.cloneNode(true)));
          },
        },
        jsPDF: { unit: 'mm', format: 'a4', orientation: 'portrait' },
        pagebreak: { mode: ['css', 'legacy'], avoid: ['tr', 'header', 'footer'] },
      }).from(doc.body).outputPdf('blob');
      if (!overlay.isConnected) return;
      const filename = (title.replace(/[^a-z0-9_-]+/gi, '-') || 'document') + '.pdf';
      const file = new File([blob], filename, { type: 'application/pdf' });
      const canShare = !!navigator.share && !!navigator.canShare?.({ files: [file] });
      status.textContent = canShare
        ? 'PDF ready. Choose WhatsApp, then select the member.'
        : 'PDF ready. Download it and attach it in WhatsApp.';
      const download = () => {
        const url = URL.createObjectURL(file);
        const link = document.createElement('a');
        link.href = url; link.download = filename; link.click();
        setTimeout(() => URL.revokeObjectURL(url), 1000);
      };
      const button = document.createElement('button');
      button.textContent = canShare ? 'Share PDF via WhatsApp' : 'Download PDF';
      button.style.cssText = 'padding:10px 14px;min-height:44px;border:0;border-radius:10px;background:#167a43;color:white;cursor:pointer';
      button.onclick = async () => {
        if (!canShare) { download(); return; }
        try {
          await navigator.share({ files: [file], title });
        } catch (error) {
          if (error.name !== 'AbortError') {
            status.textContent = 'Sharing is unavailable. Download the PDF and attach it in WhatsApp.';
            button.textContent = 'Download PDF'; button.onclick = download;
          }
        }
      };
      toolbar.append(button);
      button.focus();
    } catch (error) {
      status.textContent = 'Unable to create PDF. Use Print / Save PDF or try again.';
      throw error;
    }
  };
})();
