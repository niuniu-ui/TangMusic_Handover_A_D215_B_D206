/* Android library: one native file store, worker parsing, commit after validation. */
(() => {
  'use strict';
  let files=[],operation=null,status={phase:'idle',message:'下载一次，即可从本机曲库离线打开。',percent:0};
  const notify=()=>window.dispatchEvent(new CustomEvent('tang:library',{detail:{...status,files:files.map(f=>({...f})),busy:!!operation}}));
  const report=(phase,message,percent=0)=>{status={phase,message,percent};notify();};
  function finish(phase,message){if(operation)clearTimeout(operation.timer);operation=null;report(phase,message,phase==='done'?100:0);}
  function begin(catalog){
    if(operation)return null;
    const op={token:Date.now().toString(36)+'-'+Math.random().toString(36).slice(2),controller:new AbortController(),catalog};
    operation=op;op.timer=setTimeout(()=>{if(operation!==op)return;op.controller.abort();TangAndroid.cancelMidi(op.token);finish('error','文件操作超时，请重试。');},60000);
    report('starting','正在准备曲谱…');return op;
  }
  function startDownload(url,catalog){const op=begin(catalog);if(!op)return;report('downloading','正在连接曲谱来源…');TangAndroid.downloadMidi(url,op.token,catalog?.sha256||'',catalog?catalog.title+'.mid':'');}
  async function accept(payload,op){
    try{
      report('parsing','正在解析音符与节奏…',100);
      const score=await TangMidiService.parse(payload.base64,payload.name,op.controller.signal);
      if(operation!==op)return;
      if(!score.tracks.some(t=>!t.percussion&&t.noteCount>0))throw Error('曲谱没有可用于键盘适配的旋律声部。');
      op.score=score;op.payload=payload;
      if(payload.fromCache){finish('done','已从本机曲库打开，无需联网。');await TangNativeEvent({type:'midiParsed',data:{...payload,score}});return;}
      report('saving','正在保存到本机曲库…',100);
      TangAndroid.commitMidi(op.token,JSON.stringify({duration:score.duration,tracks:score.tracks.filter(t=>!t.percussion).length,catalogId:op.catalog?.id||'',sourceUrl:op.catalog?.sourceUrl||'',license:op.catalog?.license||''}));
    }catch(error){if(operation!==op)return;TangAndroid.cancelMidi(op.token);finish('error',error.message||'曲谱解析失败。');}
  }
  window.TangLibrary={
    get files(){return files.map(f=>({...f}));},get busy(){return !!operation;},
    async list(){TangAndroid.listMidi();},
    select(){const op=begin();if(op){clearTimeout(op.timer);report('reading','请选择 MIDI 文件。');TangAndroid.selectMidi(op.token);}},
    download(item){startDownload(item.url,item);},
    downloadUrl(value){try{const url=new URL(value);if(url.protocol!=='https:'||url.username||url.password)throw Error();startDownload(url.href,TangCatalog.items.find(i=>i.url===url.href));}catch(_){report('error','请输入不含账号密码的 HTTPS MIDI 文件直链。');}},
    open(id){const op=begin();if(op){report('reading','正在打开本机曲谱…');TangAndroid.openCachedMidi(id,op.token);}},
    remove(id){if(!operation)TangAndroid.removeCachedMidi(id);},
    exportMidi(id){const meta=files.find(f=>f.id===id);if(meta&&!operation)TangAndroid.exportMidi(id,meta.name);},
    cancel(){const op=operation;if(!op||status.phase==='saving')return;op.controller.abort();TangAndroid.cancelMidi(op.token);finish('cancelled','已取消，原曲谱保持不变。');},
    event({type,data={}}){
      if(type==='midiLibrary'){
        files=(data.items||[]).map(item=>{const c=TangCatalog.items.find(c=>c.sha256===item.id);return {...item,catalogId:item.catalogId||c?.id||'',duration:item.duration||c?.duration||0,tracks:item.tracks||c?.tracks?.length||0};});notify();return true;
      }
      if(type==='fileCancelled'){finish('cancelled','已取消选择文件。');return true;}
      if(!['midiFile','midiCommitted','downloadProgress','fileError'].includes(type))return false;
      if(type==='fileError'&&!data.token){report('error',data.message);return true;}
      const op=operation;if(!op||op.token!==data.token)return true;
      if(type==='fileError'){op.controller.abort();TangAndroid.cancelMidi(op.token);finish('error',data.message);}
      else if(type==='downloadProgress')report('downloading','已下载 '+Math.ceil(data.bytes/1024)+' KB',Math.max(0,data.percent));
      else if(type==='midiFile')accept(data,op);
      else if(type==='midiCommitted'){const score=op.score;finish('done','已保存，可离线打开并适配。');TangNativeEvent({type:'midiParsed',data:{...data.meta,score}});}
      return true;
    }
  };
  window.addEventListener('DOMContentLoaded',()=>TangLibrary.list());
})();
