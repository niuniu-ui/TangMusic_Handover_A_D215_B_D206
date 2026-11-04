(()=>{'use strict';
const $=id=>document.getElementById(id),call=(method,...args)=>{if(!window.TangAndroid){TangApp.toast('请在手机 App 中连接乐器');return}try{TangAndroid[method](...args)}catch(e){TangApp.toast(e.message)}};
let keyState={},draft=Array.from({length:32},(_,i)=>53+i),baseRevision=null,dirty=false;
const keyDialog=document.createElement('dialog');keyDialog.id='keymapDialog';keyDialog.className='performance-dialog';keyDialog.innerHTML=`<div class="section-heading"><h2>让琴键按你的习惯排列</h2><button class="text-link" id="keymapClose">关闭</button></div><p class="hint">从左到右编号 1–32。选择音高会与占用该音高的琴键交换，保证没有重复。下方音名按音区组 2 显示。</p><p id="keymapMessage" role="status"></p><div class="keymap-grid" id="keymapGrid"></div><div class="connection-actions"><button class="secondary" id="keymapDefault">默认排列</button><button class="secondary" id="keymapReverse">反向排列</button><button class="secondary" id="keymapSave">保存手机草稿</button><button class="secondary" id="keymapLoad">载入手机草稿</button></div><div class="connection-actions"><button class="secondary" id="keymapRead">重新读取设备</button><button class="primary" id="keymapApply">应用到琴键</button></div><p class="hint">松开所有琴键并停止引导、录音或循环后再应用。设备重启后恢复默认；手机草稿可再次下发。</p>`;document.body.append(keyDialog);
const options=draft.map(n=>`<option value="${n}">${TangApp.noteName(n)} · ${n}</option>`).join('');
$('keymapGrid').innerHTML=draft.map((_,i)=>`<label><span>琴键 ${String(i+1).padStart(2,'0')}</span><select data-key="${i}" aria-label="琴键 ${i+1} 音高">${options}</select></label>`).join('');
function keyRender(){
 document.querySelectorAll('[data-key]').forEach(e=>e.value=draft[+e.dataset.key]);
 const ready=!!window.MinlinkUI?.state.ready;
 $('keymapApply').disabled=!ready||!keyState.supported||keyState.busy||baseRevision===null||!dirty;
 $('keymapRead').disabled=!ready||!keyState.supported||keyState.busy;
 $('keymapMessage').textContent=(keyState.message||'请连接并读取设备映射')+(dirty?' · 有未应用的草稿':'');
 $('keyMapState').textContent=dirty?'有草稿':baseRevision===null?'未读取':'设备已读取';
}
$('keymapGrid').onchange=e=>{const i=+e.target.dataset.key,n=+e.target.value,j=draft.indexOf(n);[draft[i],draft[j]]=[draft[j],draft[i]];dirty=true;keyRender()};
$('openKeyMap').onclick=()=>{keyDialog.showModal();call('keymapStatus')};$('keymapClose').onclick=()=>keyDialog.close();
$('keymapDefault').onclick=()=>{draft=Array.from({length:32},(_,i)=>53+i);dirty=true;keyRender()};
$('keymapReverse').onclick=()=>{draft.reverse();dirty=true;keyRender()};
$('keymapSave').onclick=()=>{try{localStorage.setItem('tang-keymap-draft-v1',JSON.stringify(draft));TangApp.toast('草稿已保存在手机，尚未修改设备')}catch(e){TangApp.toast('草稿保存失败：'+e.message)}};
$('keymapLoad').onclick=()=>{try{const a=JSON.parse(localStorage.getItem('tang-keymap-draft-v1'));if(!Array.isArray(a)||a.length!==32||new Set(a).size!==32||a.some(n=>!Number.isInteger(n)||n<53||n>84))throw Error('没有有效的手机草稿');draft=a;dirty=true;keyRender()}catch(e){TangApp.toast(e.message)}};
$('keymapRead').onclick=()=>{if(dirty&&!confirm('重新读取会放弃未保存的编辑，继续？'))return;dirty=false;call('readKeymap')};
$('keymapApply').onclick=()=>call('setKeymap',JSON.stringify({mapping:draft,expectedRevision:baseRevision}));

let loop={tracks:[]},configDirty=false;const panel=document.createElement('section');panel.id='audioLoops';panel.innerHTML=`<div class="section-heading"><h2>把乐句叠起来</h2><span class="badge">四轨 · 实际声音</span></div><article class="card loop-controls"><p class="hint">录下电子琴、电子笛或空气鼓，再一轨一轨合奏。声音保存在 FPGA DDR3，断电清空；录入的声音不包含已有循环。</p><div class="loop-config"><label>BPM<input id="loopBpm" type="number" min="40" max="240" value="120"></label><label>小节<select id="loopBars"><option>1</option><option selected>2</option><option>4</option></select></label><label>预备拍<select id="loopCount"><option value="0">无</option><option value="4">4 拍</option></select></label></div><button class="secondary wide" id="loopConfigure">应用循环长度</button><p class="hint">4/4 拍。已有录音时不能改变长度或速度；需先停止并清空四轨。预备拍以页面倒计时提示，不发出节拍声。</p><p id="loopMessage" role="status">连接后读取四轨状态</p><div class="loop-position"><span id="loopTime">—</span><span id="loopCountStatus"></span></div><progress id="loopProgress" max="1000" value="0" aria-label="循环位置"></progress><div class="connection-actions"><button class="primary" id="loopPlay">开始循环</button><button class="secondary" id="loopStop">本轮结束停止</button><button class="secondary" id="loopAbort">立即停止</button></div><div class="connection-actions"><button class="secondary" id="loopRefresh">刷新</button><button class="secondary" data-nav="device">连接乐器</button><button class="text-link" id="loopClearAll">清空四轨</button></div></article><div id="loopTracks" class="loop-tracks"></div><p class="hint">先应用长度，再点击某轨录音；运行中会等待下一轮起点，录满一轮后自动加入合奏。覆盖前一轨时保留其他轨道，停止后可撤销／重做上一次完整覆盖。想保存整个合奏，可在录音页录制并回传 WAV。</p>`;$('session').append(panel);
for(const id of ['loopBpm','loopBars','loopCount'])$(id).addEventListener('input',()=>configDirty=true);
$('loopTracks').innerHTML=Array.from({length:4},(_,i)=>`<article class="card loop-track" data-track="${i}"><div class="section-heading"><h3>轨道 ${i+1}</h3><span class="badge" id="trackState${i}">未读取</span></div><div class="connection-actions"><button class="primary" data-loop="record">录入一轮</button><button class="secondary" data-loop="mute" aria-pressed="false">静音</button><button class="secondary" data-loop="solo" aria-pressed="false">独奏</button></div><label class="track-volume">音量 <output id="trackVolume${i}">—</output><input type="range" min="0" max="128" value="100" data-loop="volume" aria-label="轨道 ${i+1} 音量"></label><div class="connection-actions"><button class="text-link" data-loop="undo">撤销／重做</button><button class="text-link" data-loop="clear">清空此轨</button></div></article>`).join('');
const active=()=>loop.running||loop.preparing||loop.armed||loop.recording||loop.finalizing;
const act=(action,extra={})=>call('loopAction',JSON.stringify({action,...extra}));
function loopRender(){
 const available=!!window.MinlinkUI?.state.ready&&loop.supported&&loop.known,can=available&&!loop.pending,busy=active(),has=loop.tracks?.some(t=>t.valid);
 if(loop.known&&!loop.pending){if(+$('loopBpm').value===loop.bpm&&+$('loopBars').value===loop.bars&&+$('loopCount').value===loop.countIn)configDirty=false;if(!configDirty){$('loopBpm').value=loop.bpm;$('loopBars').value=loop.bars;$('loopCount').value=loop.countIn}}
 $('loopMessage').textContent=loop.message||'请连接支持四轨音频的固件';
 $('loopPlay').disabled=!can||busy||!has||!!loop.fault;$('loopStop').disabled=!can||!busy||loop.stopRequested;$('loopAbort').disabled=!can||(!busy&&!loop.fault);$('loopAbort').textContent=loop.fault?'重置循环状态':'立即停止';
 $('loopConfigure').disabled=!can||busy||has;$('loopRefresh').disabled=!available||loop.pending;$('loopClearAll').disabled=!can||busy||!has;
 $('loopTime').textContent=loop.known?`${((loop.position||0)/48828.125).toFixed(1)} / ${(loop.lengthSamples/48828.125).toFixed(2)} 秒 · ${loop.bpm} BPM`:'—';
 $('loopCountStatus').textContent=loop.countRemaining?`准备 ${(loop.countRemaining/48828.125).toFixed(1)} 秒`:loop.stopRequested?'本轮结束后停止':'';
 $('loopProgress').value=loop.lengthSamples?Math.floor(1000*loop.position/loop.lengthSamples):0;
 document.querySelectorAll('[data-track]').forEach(card=>{const i=+card.dataset.track,t=loop.tracks?.[i]||{},recording=loop.recordTrack===i&&(loop.recording||loop.armed||loop.finalizing);
  $('trackState'+i).textContent=recording?loop.recording?'录音中':loop.finalizing?'核验中':'等待起点':t.valid?'有录音':loop.known?'空轨':'未读取';
  card.classList.toggle('is-recording',recording);
  card.querySelector('[data-loop=record]').disabled=!can||loop.recording||loop.armed||loop.finalizing||loop.preparing||!!loop.fault;
  card.querySelector('[data-loop=record]').textContent=t.valid?'覆盖一轮':'录入一轮';
  for(const a of ['mute','solo']){const el=card.querySelector(`[data-loop=${a}]`);el.disabled=!can;el.setAttribute('aria-pressed',String(!!t[a==='mute'?'muted':'solo']))}
  const range=card.querySelector('[data-loop=volume]');range.disabled=!can;if(document.activeElement!==range)range.value=t.volume??100;$('trackVolume'+i).textContent=t.volume==null?'—':Math.round(100*t.volume/128)+'%';
  card.querySelector('[data-loop=undo]').disabled=!can||busy||!t.undo;card.querySelector('[data-loop=clear]').disabled=!can||busy||!t.valid;
 });
}
$('loopConfigure').onclick=()=>act('configure',{bpm:Number($('loopBpm').value),bars:Number($('loopBars').value),countIn:Number($('loopCount').value),revision:loop.revision});
for(const [id,action] of [['loopPlay','play'],['loopStop','stop'],['loopAbort','abort'],['loopRefresh','refresh']])$(id).onclick=()=>act(action);
$('loopClearAll').onclick=()=>{if(confirm('清空 FPGA 中全部四轨循环？此操作不可撤销，手机录音文件不受影响。'))act('clear',{track:255})};
function mixTrack(i,change){const t=loop.tracks[i];act('mix',{track:i,muted:t.muted,solo:t.solo,volume:t.volume,revision:loop.revision,...change})}
$('loopTracks').onclick=e=>{const b=e.target.closest('button[data-loop]');if(!b)return;const i=+b.closest('[data-track]').dataset.track,a=b.dataset.loop,t=loop.tracks[i];
 if(a==='mute'||a==='solo'){mixTrack(i,{[a==='mute'?'muted':'solo']:!t[a==='mute'?'muted':'solo']});return}
 if(a==='record'&&t.valid&&!confirm(`覆盖轨道 ${i+1} 的实际声音？完整录制后可撤销；中途停止保留原轨。`))return;
 if(a==='clear'&&!confirm(`清空轨道 ${i+1}？不可撤销。`))return;act(a,{track:i});
};
$('loopTracks').onchange=e=>{if(e.target.dataset.loop==='volume')mixTrack(+e.target.closest('[data-track]').dataset.track,{volume:+e.target.value})};
const previous=window.TangNativeEvent;window.TangNativeEvent=event=>{
 if(event.type==='keymapState'){keyState=event.data||{};const m=keyState.mapping;if(m?.length===32&&!keyState.busy){if(!dirty||m.every((n,i)=>n===draft[i])){draft=m.slice();baseRevision=keyState.revision;dirty=false}}if(!m?.length)baseRevision=null;keyRender();return}
 if(event.type==='loopState'){loop=event.data||{};loopRender();return}
 previous?.(event);if(['protocolState','disconnected','ready'].includes(event.type)){keyRender();loopRender()}if(event.type==='ready'){call('keymapStatus');call('loopStatus')}
};keyRender();loopRender();if(window.TangAndroid){call('keymapStatus');call('loopStatus')}
})();
