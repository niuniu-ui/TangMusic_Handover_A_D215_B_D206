(()=>{'use strict';
const $=id=>document.getElementById(id),native=window.TangAndroid;
let playing='',files=[],rendered='',lastPage='session',lastReady=false;
const node=(tag,cls,text)=>{const e=document.createElement(tag);e.className=cls||'';if(text!==undefined)e.textContent=text;return e};
const invoke=(method,...args)=>{if(!native){TangApp.toast('请在手机 App 中连接真实设备。');return}try{native[method](...args)}catch(e){TangApp.toast(e.message)}};
const linkCard=document.querySelector('#device .connection-card'),linkHome=linkCard.parentNode,linkNext=linkCard.nextSibling;
const linkDialog=node('dialog','shared-connection-dialog'),linkHeading=node('h2','','连接我的乐器'),linkHint=node('p','hint','调音、曲谱与录音共用这一个连接。'),linkClose=node('button','secondary wide','返回当前页面');
linkClose.type='button';linkClose.onclick=()=>linkDialog.close();linkDialog.append(linkHeading,linkHint,linkClose);document.body.append(linkDialog);
linkDialog.addEventListener('close',()=>linkHome.insertBefore(linkCard,linkNext));
function openConnection(){if(linkDialog.open)return;linkDialog.insertBefore(linkCard,linkClose);linkDialog.showModal();window.dispatchEvent(new CustomEvent('tang:connection-open'))}
document.addEventListener('click',e=>{const trigger=e.target.closest('[data-nav="device"]');if(trigger&&!trigger.closest('.bottom-nav')&&lastPage!=='device'){e.preventDefault();e.stopImmediatePropagation();openConnection()}},true);
// Keep the existing protocol client and its revision/conflict checks intact.
for(const section of document.querySelectorAll('.parameter-section')){
 const heading=section.querySelector('h3');
 if(heading.textContent!=='输出'){
  const detail=node('details',section.className),summary=node('summary'),state=node('span','effect-state','等待读取');
  summary.append(heading,state);detail.append(summary);while(section.firstChild)detail.append(section.firstChild);
  detail.dataset.effect=detail.querySelector('[data-parameter]').dataset.parameter;section.replaceWith(detail);
 }
}
for(const input of document.querySelectorAll('#parameterInputs input[type=number]')){
 input.type='range';const output=node('output','','—');output.htmlFor=input.id;output.id=input.id+'-value';input.before(output);
 input.addEventListener('input',syncControls);
 input.closest('.parameter-control').querySelector('label').textContent=input.closest('.parameter-control').querySelector('label').textContent.replace(' · 0–127','');
}
for(const input of document.querySelectorAll('#parameterInputs input[type=checkbox]')){input.setAttribute('role','switch');input.addEventListener('change',syncControls)}
function syncControls(){
 const state=window.MinlinkUI?.state||{},ready=!!state.ready&&TangApp.connected;
 document.body.classList.toggle('instrument-ready',ready);
 $('studioConnection').textContent=ready?'乐器已就绪。调整后应用，听听新的声音。':'连接乐器后，读取当前音量与音效。';
 for(const input of document.querySelectorAll('#parameterInputs input[type=range]')){
  const has=Object.hasOwn(state.parameters||{},input.dataset.parameter),volume=['1','2'].includes(input.dataset.parameter),percent=Math.round(Number(input.value)/127*100);
  const text=has?(volume?percent+'%':input.value):'—';const output=$(input.id+'-value');if(output.textContent!==text)output.textContent=text;
  input.style.setProperty('--fill',has?`${Number(input.value)/127*100}%`:'0%');input.setAttribute('aria-valuetext',has?(volume?percent+'%，范围 0 到 100%':input.value+'，范围 0 到 127'):'尚未读取设备');
 }
 for(const detail of document.querySelectorAll('details[data-effect]')){const check=detail.querySelector('input[type=checkbox]');detail.querySelector('.effect-state').textContent=ready?(check.checked?'已开启':'已关闭'):'等待读取'}
}
function nav(page){TangApp.nav(page)}
window.addEventListener('tang:page',e=>{
 lastPage=e.detail.page;document.body.dataset.page=lastPage;history.replaceState(null,'','#'+lastPage);
 document.title=({session:'演奏调音',scores:'我的曲库',recordings:'录音与回放',device:'我的乐器',debug:'连接诊断'}[lastPage]||'Tang Music')+' · Tang Music';
 if(lastPage==='recordings'){invoke('listPocketRecordings');invoke('recorderStatus')}else if(playing)invoke('stopPocketAudio');
});
function renderFiles(){
 const signature=JSON.stringify([files,playing]);if(signature===rendered)return;rendered=signature;
 const box=$('savedAudioList');box.replaceChildren();$('savedAudioCount').textContent=files.length?`${files.length} 段声音，已经好好保存在手机。`:'第一段声音，等你来收藏。';
 if(!files.length){const empty=node('div','empty-audio');empty.append(node('strong','','给灵感留个位置。'),node('p','','完整接收的录音会出现在这里。断开蓝牙后，也能试听和导出。'));box.append(empty);return}
 for(const file of files){const card=node('article','audio-card'+(playing===file.name?' playing':'')),top=node('div','audio-card-top'),copy=node('div');copy.append(node('h3','',file.title),node('p','',`${file.seconds.toFixed(2)} 秒 · ${Math.round(file.bytes/1024)} KB · 已完整保存`));top.append(node('span','audio-disc','♪'),copy);card.append(top);const row=node('div','audio-actions');for(const [label,action] of [[playing===file.name?'■ 停止试听':'▶ 试听',()=>playing===file.name?invoke('stopPocketAudio'):invoke('playPocketRecording',file.name)],['保存 WAV',()=>invoke('exportPocketRecording',file.name)]]){const b=node('button',label==='保存 WAV'?'secondary':'primary',label);b.type='button';b.onclick=action;row.append(b)}card.append(row);const info=node('details');info.append(node('summary','','文件详情'),node('p','',file.name));card.append(info);box.append(card)}
}
$('openRecorder').onclick=()=>invoke('recorderAction','refresh',0);$('refreshSavedAudio').onclick=()=>invoke('listPocketRecordings');
$('recConnect').onclick=openConnection;
for(const [id,action] of Object.entries({recStart:'start',recStop:'stop',recPlay:'play',recStopPlay:'stopPlay',recDownload:'download',recPause:'pause'}))$(id).onclick=()=>invoke('recorderAction',action,0);
$('recErase').onclick=()=>{if(confirm('删除当前板端录音？尚未回传的声音将无法恢复。手机里已保存的 WAV 不受影响。'))invoke('recorderAction','erase',0)};
for(let i=0;i<2;i++)$('recSlot'+i).onclick=()=>invoke('recorderAction','slot',i);
function renderRecorder(s){
 $('recConnection').textContent=s.connection||'等待连接';
 $('recState').textContent=s.ready?`槽 ${(s.slot||0)+1} · ${['DDR3 初始化','DDR3 自检','空录音位','录音中','正在保存','录音就绪','准备回放','耳机回放中','板端故障','读取 DDR3'][s.state]||'等待状态'}`:'连接后核对录音功能';
 $('recCapacity').textContent=s.slots?`${s.slots} 个录音槽 · 每槽 ${Math.round(s.capacitySeconds)} 秒 · 已写入 ${(s.seconds||0).toFixed(2)} 秒 · 故障码 ${s.fault}`:'与调音、曲谱共用同一个蓝牙连接。';
 $('recSlots').hidden=s.slots!==2;for(let i=0;i<2;i++){$('recSlot'+i).disabled=!s.canSelect||s.slot===i;$('recSlot'+i).setAttribute('aria-pressed',String(s.slot===i))}
 for(const [id,key] of Object.entries({openRecorder:'canRefresh',recStart:'canRecord',recStop:'canStop',recPlay:'canPlay',recStopPlay:'canStopPlay',recErase:'canErase',recDownload:'canDownload',recPause:'downloading'})){const disabled=!s[key];if($(id).disabled!==disabled)$(id).disabled=disabled}
 $('recConnect').disabled=!!s.downloading;
 $('recMessage').textContent=s.message||'完整接收并校验后，录音会出现在下方。';$('recProgress').value=s.progress||0;
}
const previous=window.TangNativeEvent;
window.TangNativeEvent=event=>{
 const d=event.data||{};
 if(event.type==='recorderState'){renderRecorder(d);if(d.ready&&linkDialog.open)linkDialog.close();return}
 if(event.type==='pocketRecordings'){files=d.items||[];renderFiles();return}
 if(event.type==='pocketAudio'){playing=d.playing?d.name||'':'';renderFiles();if(d.message)TangApp.toast(d.message);return}
 previous?.(event);
 // WebView may re-emit cached channel state after a fragment navigation.
 if(event.type==='channelReady'&&window.MinlinkUI?.state.ready)$('toast').classList.remove('show');
 if(event.type==='protocolState'){if(d.ready&&!lastReady)TangApp.toast('乐器已就绪，当前参数已读取。');lastReady=!!d.ready;if(d.ready&&linkDialog.open)linkDialog.close()}
 if(event.type==='disconnected')lastReady=false;
 if(['protocolState','parameterResult','channelReady','disconnected','ready','error'].includes(event.type))syncControls();
 if(event.type==='ready'){invoke('listPocketRecordings');invoke('recorderStatus')}
};
window.TangBack=()=>{const dialog=document.querySelector('dialog[open]');if(dialog){dialog.close();return true}if(lastPage!=='session'){nav('session');return true}return false};
document.addEventListener('visibilitychange',()=>{if(document.hidden&&playing)invoke('stopPocketAudio')});
document.addEventListener('click',e=>{if(!native&&e.target.closest('#scanDevices,#reconnectDevice')){e.stopImmediatePropagation();TangApp.toast('请在手机 App 中扫描真实蓝牙设备。')}},true);
syncControls();renderFiles();nav(['session','scores','recordings','device','debug'].includes(location.hash.slice(1))?location.hash.slice(1):'session');if(native)invoke('listPocketRecordings');
window.addEventListener('load',()=>scrollTo({top:0,behavior:'instant'}),{once:true});
})();
