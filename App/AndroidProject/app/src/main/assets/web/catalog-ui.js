(() => {
  'use strict';
  const $=id=>document.getElementById(id), rows=new Map();let files=[],busy=false,tab='online',scheduled=null,cacheSignature='';
  function node(tag,className,text){const e=document.createElement(tag);e.className=className||'';if(text!==undefined)e.textContent=text;return e;}
  const time=seconds=>Math.floor(Math.round(seconds)/60)+':'+String(Math.round(seconds)%60).padStart(2,'0');
  function fitLabel(item){
    const track=item.tracks[0];
    if(!track?.possible)return '需选择片段';
    return track.shift===0?'原音高可用':'需整体移调';
  }
  function fitDescription(item){
    const track=item.tracks[0];if(!track)return '请下载后选择声部并检测音域。';
    const span=item.duration>120?'前 120 秒':'全曲';
    const prefix='首个声部 · '+span+' · MIDI '+track.low+'–'+track.high+' · ';
    if(!track.possible)return prefix+'音域较宽，请截取片段或换声部';
    if(track.shift===0)return prefix+'原音高可用';
    return prefix+'建议 '+(track.shift>0?'+':'')+track.shift+' 半音'+(track.shift%12?'（调性改变，需确认）':'（八度移动，需确认）');
  }
  $('catalogCountNote').textContent=TangCatalog.items.length+' 首已验证 MIDI · 原音符保留 · 选择声部后确认适配';
  function openTrack(item){const cached=files.find(f=>f.catalogId===item.id);cached?TangLibrary.open(cached.id):TangLibrary.download(item);}
  for(const [index,item] of TangCatalog.items.entries()){
    const card=node('article','curated-card');card.dataset.catalog=item.id;
    const top=node('div','curated-top'),number=node('span','curated-number',String(index+1).padStart(2,'0')),title=node('div','grow');
    title.append(node('h3','',item.title),node('p','curated-composer',item.composer));const badge=node('span','library-tag',fitLabel(item));top.append(number,title,badge);
    const desc=node('p','curated-desc',item.description),meta=node('p','curated-meta',time(item.duration)+' · '+item.bpm+' BPM · '+item.tracks.length+' 个声部');
    const actions=node('div','curated-actions'),button=node('button','primary','下载并适配');button.type='button';button.addEventListener('click',()=>openTrack(item));
    const source=node('a','source-credit','来源与许可 ↗');source.href=item.sourceUrl;source.target='_blank';source.rel='noopener noreferrer';
    actions.append(button,source);card.append(top,desc,meta,node('p','curated-range',fitDescription(item)),actions);$('libraryList').append(card);
    rows.set(item.id,{card,button,badge,item});
  }
  function renderCache(query){
    const signature=JSON.stringify([files.map(f=>[f.id,f.name,f.updated]),query]);
    if(signature!==cacheSignature){
      cacheSignature=signature;const fragment=document.createDocumentFragment(),filtered=files.filter(f=>f.name.toLowerCase().includes(query));
      for(const file of filtered){
        const card=node('article','cached-card');card.dataset.cache=file.id;
        card.append(node('strong','',file.name),node('p','hint',time(file.duration)+' · '+file.tracks+' 个声部 · '+(file.size/1024).toFixed(1)+' KB'));
        const actions=node('div','cached-actions');
        for(const [label,action] of [['打开并适配',()=>TangLibrary.open(file.id)],['导出 MIDI',()=>TangLibrary.exportMidi(file.id)],['删除',()=>TangLibrary.remove(file.id)]]){const button=node('button',label==='删除'?'text-link':'secondary',label);button.type='button';button.onclick=action;actions.append(button);}
        card.append(actions);fragment.append(card);
      }
      if(!filtered.length)fragment.append(node('p','catalog-empty',query?'没有找到匹配的本机曲谱。':'还没有保存曲谱。下载或导入 MIDI 后，会显示在这里。'));
      $('cachedMidiList').replaceChildren(fragment);
    }
    $('cachedMidiList').querySelectorAll('button').forEach(button=>{if(button.disabled!==busy)button.disabled=busy;});
  }
  function render(){
    scheduled=null;const query=$('librarySearch').value.trim().toLowerCase();let visible=0;
    for(const row of rows.values()){
      const cached=files.some(f=>f.catalogId===row.item.id);row.card.hidden=!(row.item.title+row.item.composer).toLowerCase().includes(query);if(!row.card.hidden)visible++;
      const text=cached?'打开并适配':'下载并适配';if(row.button.textContent!==text)row.button.textContent=text;
      row.button.disabled=busy;const badge=cached?'已保存 · 可离线':fitLabel(row.item);if(row.badge.textContent!==badge)row.badge.textContent=badge;
    }
    $('libraryEmpty').hidden=visible>0;$('cacheCount').textContent=files.length;
    $('catalogOnline').hidden=tab!=='online';$('catalogSaved').hidden=tab!=='saved';$('catalogLink').hidden=tab!=='link';$('catalogSite').hidden=tab!=='site';$('catalogSearchBox').hidden=tab==='link'||tab==='site';
    document.querySelectorAll('[data-library-tab]').forEach(button=>{button.classList.toggle('active',button.dataset.libraryTab===tab);button.setAttribute('aria-selected',String(button.dataset.libraryTab===tab));});
    renderCache(query);$('catalogImport').disabled=busy;$('simulateDownload').disabled=busy;
  }
  function schedule(){if(scheduled===null)scheduled=requestAnimationFrame(render);}
  document.querySelectorAll('[data-library-tab]').forEach(button=>button.addEventListener('click',()=>{tab=button.dataset.libraryTab;render();}));
  $('catalogImport').onclick=()=>$('importLocal').click();
  $('browseScoreWebsite').onclick=()=>{if(busy)return;if(window.TangAndroid?.browseScores)TangAndroid.browseScores();else window.open('https://www.mutopiaproject.org/cgibin/make-table.cgi?Instrument=Piano','_blank','noopener,noreferrer');};
  $('cancelMidiDownload').onclick=()=>TangLibrary.cancel();
  window.addEventListener('tang:library',({detail})=>{
    files=detail.files;busy=detail.busy;
    $('catalogTask').hidden=detail.phase==='idle';$('catalogTask').classList.toggle('has-error',detail.phase==='error');
    $('catalogTaskText').textContent=detail.message;$('catalogTaskBar').style.transform='scaleX('+(detail.percent/100)+')';
    $('cancelMidiDownload').hidden=!busy||detail.phase==='done';$('cancelMidiDownload').disabled=detail.phase==='saving';
    schedule();
  });
  window.TangCatalogUI={render:schedule,open(){render();$('networkDialog').showModal();TangLibrary.list().catch(error=>TangApp.toast(error.message));}};
  render();
})();
