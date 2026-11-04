(function () {
  'use strict';
  const $ = id => document.getElementById(id);
  const $$ = selector => Array.from(document.querySelectorAll(selector));
  const Fit = window.ScoreFit;
  const NATIVE=Boolean(window.TangAndroid);
  let channelReady=false,connecting=false,txBusy=false,rxCount=0,lastAddress='',fileBusy=false;
  const deviceList = new window.TangBleDevices.DeviceList({
    root: $('deviceResults'), connect: address => window.TangAndroid.connectBle(address),
    disabled: () => connecting || state.connected, scanning: () => state.scanning,
    connected: () => channelReady
  });
  let lastStatus='', keyboardStamp='', fitStamp='', logTimer=null;
  const logQueue=[];
  function flushLogs(){
    logTimer=null;
    if(document.hidden || $('debug').hidden) return;
    const box=$('logOutput'), atBottom=box.scrollHeight-box.scrollTop-box.clientHeight<48;
    const fragment=document.createDocumentFragment();
    for(const row of logQueue.splice(0)) fragment.append(row);
    box.append(fragment); while(box.children.length>100) box.firstElementChild.remove();
    if(atBottom) box.scrollTop=box.scrollHeight;
  }
  function scheduleLogs(){if(logTimer===null && !document.hidden && !$('debug').hidden) logTimer=setTimeout(flushLogs,250);}
  window.addEventListener('tang:page',scheduleLogs);
  document.addEventListener('visibilitychange',scheduleLogs);
  const state = { keyMap:Array.from({length:32},(_,i)=>i+53), connected:false, scanning:false, everConnected:false, loaded:false, uploaded:false, uploading:false, progress:0, playing:null, format:'ascii', tx:0, settingsSaved:false, score:Fit.score('twinkle'), source:'sample', localName:'', settings:{track:'melody', transpose:0, speed:100, start:0, end:24} };
  let scanTimer, uploadTimer, playTimer, toastTimer;
  function toast(message) { clearTimeout(toastTimer); $('toast').textContent=message; $('toast').classList.add('show'); toastTimer=setTimeout(()=>$('toast').classList.remove('show'),3500); }
  function log(message,type) {
    const row=document.createElement('div'); row.className='log-entry log-'+(type||'info');
    const direction=document.createElement('span'); direction.className='log-direction'; direction.textContent=type==='tx'?'TX':type==='rx'?'RX':'INFO';
    const body=document.createElement('span'); body.textContent=(window.TangPreview?'[预览] ':NATIVE?'':'[演示] ')+message; row.append(direction,body); logQueue.push(row); if(logQueue.length>100)logQueue.shift(); scheduleLogs();
  }
  function nav(page) { if(!['scores','device','debug','session','recordings'].includes(page))return; $$('.page').forEach(el=>{el.hidden=el.id!==page;el.classList.toggle('active',el.id===page);}); $$('.bottom-nav [data-nav]').forEach(el=>{el.classList.toggle('active',el.dataset.nav===page);if(el.dataset.nav===page)el.setAttribute('aria-current','page');else el.removeAttribute('aria-current');});window.scrollTo({top:0,behavior:'instant'}); window.dispatchEvent(new CustomEvent('tang:page',{detail:{page}})); }
  $$('[data-nav]').forEach(el=>el.addEventListener('click',()=>nav(el.dataset.nav)));
  $$('[data-close]').forEach(el=>el.addEventListener('click',()=>$(el.dataset.close).close()));
  const noteName=Fit.name;
  function clockText(seconds){return String(Math.floor(seconds/60)).padStart(2,'0')+':'+String(Math.floor(seconds%60)).padStart(2,'0');}
  function shiftText(k){return k===0?'保持原音高':(k>0?'升高 ':'降低 ')+Math.abs(k)+' 个半音';}
  function rangeText(low,high){return noteName(low)+'–'+noteName(high);}
  function getTrack(settings){return state.score.tracks.find(t=>t.id===settings.track);}
  let notesCache={};
  function getNotes(settings){const t=getTrack(settings);if(notesCache.track===t&&notesCache.start===settings.start&&notesCache.end===settings.end)return notesCache.notes;const notes=t?TangMidiService.clip(t,settings.start,settings.end):[];notesCache={track:t,start:settings.start,end:settings.end,notes};return notes;}
  function fitResult(){return Fit.analyze(getNotes(state.settings),state.settings.transpose);}
  function scoreDuration(){return (state.settings.end-state.settings.start)*100/state.settings.speed;}
  function setProgress(value){state.progress=value;$('uploadBar').style.width=value+'%';$('uploadPercent').innerHTML=value+'<span>%</span>';$('uploadProgress').setAttribute('aria-valuenow',String(value));}
  function renderKeyboard(notes,shift){
    const used=new Set(notes.map(n=>n.midi+shift)); const stamp=[...used].sort((a,b)=>a-b).join(','); if(stamp===keyboardStamp && $('keyboardPreview').children.length)return; keyboardStamp=stamp; const keyboard=$('keyboardPreview'); keyboard.replaceChildren(); let whiteIndex=0;
    for(let midi=53;midi<=84;midi++){
      const black=[1,3,6,8,10].includes(midi%12);const key=document.createElement('span');key.className=(black?'piano-black':'piano-white')+(used.has(midi)?' used':'');key.title=noteName(midi)+' · MIDI '+midi;
      if(black)key.style.left='calc('+whiteIndex+' * (100% / 19) - 1.7%)';else whiteIndex++;
      keyboard.append(key);
    }
  }
  function renderFit(){
    const stamp=JSON.stringify([state.loaded,state.settingsSaved,state.localName,state.settings]);
    if(stamp===fitStamp && renderFit.score===state.score)return;
    fitStamp=stamp;renderFit.score=state.score;
    const has=state.loaded; const result=fitResult();const settings=state.settings;
    const pendingLocal=Boolean(state.localName);
    $('fitOrb').className='fit-orb '+(!has?'':result.ok?(state.settingsSaved?'good':'suggest'):'bad');
    $('fitOrb').textContent=!has?'·':result.ok?'✓':'!';
    $('fitTitle').textContent=!has?(pendingLocal?'文件已选择，等待 MIDI 解析':'先选择一首曲谱'):state.settingsSaved?'适配已确认 · 32 键可覆盖':result.ok?'片段音域可覆盖，等待确认':result.possible?'整体移调后可以适配':'整段跨度超出 32 键';
    $('fitDescription').textContent=!has?(pendingLocal?'真实文件尚未解析，不能生成演奏或发送。':'检查声部与片段，再决定是否整体移调。'):state.settingsSaved?'演奏将使用确认后的音符与时间。':result.ok?'打开设置，确认声部、片段和音高。':result.possible?'建议'+shiftText(result.suggestion)+'，确认后生效。':'请缩短片段或更换声部，不会自动删除音符。';
    $('originalRange').textContent=has&&!result.empty?rangeText(result.low,result.high):'—';
    $('originalMidi').textContent=has&&!result.empty?'MIDI '+result.low+'–'+result.high:'所选声部与片段';
    $('adaptedRange').textContent=has&&!result.empty?rangeText(result.afterLow,result.afterHigh):'—';
    $('adaptedMidi').textContent=has&&!result.empty?'MIDI '+result.afterLow+'–'+result.afterHigh+' · '+(state.settingsSaved?'已确认':'待确认'):'等待检测';
    $('originalOut').textContent=has?result.originalOut:'—';$('remainingOut').textContent=has?result.remaining:'—';
    $('remainingOut').parentElement.classList.toggle('warning-text',has&&!result.ok);
    $('transposeSummary').textContent=has?shiftText(settings.transpose):'尚未确认';
    $('settingsState').textContent=state.settingsSaved?'已确认':has?'待确认':pendingLocal?'待解析':'等待曲谱';
    $('settingsButtonLabel').textContent=state.settingsSaved?'修改声部、片段与移调':'选择声部与练习片段';
    $('settingsSummary').textContent=has?getTrack(settings).name+' · '+clockText(settings.start)+'–'+clockText(settings.end)+' · '+settings.speed+'% 速度':'最长 120 秒；按片段检测，不删除越界音符。';
    renderKeyboard(has?getNotes(settings):[],settings.transpose);
  }
  function refresh(){
    const ready=state.loaded&&state.settingsSaved&&fitResult().ok;const canPlay=state.connected&&state.uploaded&&!state.uploading;
    $('headerDevice').textContent=state.connected?'演示已连接':'未连接';$('headerDevice').parentElement.classList.toggle('connected',state.connected);
    $('deviceStatusBadge').textContent=state.connected?'演示已连接':'未连接';$('deviceStatusBadge').classList.toggle('ready',state.connected);$('connectionOrb').classList.toggle('connected',state.connected);
    $('scanDevices').disabled=state.scanning||state.connected;$('scanDevices').classList.toggle('busy',state.scanning);$('scanDevices').querySelector('span').textContent=state.scanning?'正在演示扫描…':'扫描演示设备';
    $('disconnectDevice').disabled=!state.connected;if($('connectDevice'))$('connectDevice').disabled=state.connected||state.scanning;$('reconnectDevice').disabled=!state.everConnected||state.connected||state.scanning;
    $('connectionTitle').textContent=state.connected?'演示设备已连接':state.scanning?'正在演示扫描':'准备连接';$('connectionDetail').textContent=state.connected?'仅模拟 BLE 连接；未验证 FPGA 协议。':state.scanning?'显示预设设备，不调用蓝牙。':'点击扫描，查看预设的演示设备。';
    $('scoreState').textContent=state.localName?'待解析':state.loaded?'示例已载入':'待载入';$('scoreState').classList.toggle('ready',state.loaded);
    ['loadSample','networkImport','importLocal'].forEach(id=>$(id).disabled=state.uploading);$('openSettings').disabled=!state.loaded||state.uploading;
    $('loadSample').hidden=state.loaded;$('loadSample').textContent=state.localName?'改用内置示例体验适配':'载入示例，开始适配';
    if(!NATIVE){$('uploadScore').disabled=!ready||!state.connected||state.uploading;$('uploadScore').classList.toggle('busy',state.uploading);}$('goConnect').hidden=state.connected;$('cancelAndDisconnect').disabled=!state.connected;
    if(!NATIVE){$('uploadBadge').textContent=state.uploading?'演示发送中':state.uploaded?'演示发送完成':!ready?'等待适配确认':'等待发送';
    $('uploadHelp').textContent=state.uploading?'模拟发送音符事件；不连接真实硬件。':state.uploaded?'演示发送完成，不代表 FPGA 接收确认。':!ready?'请先确认可覆盖 F3–C6 的适配方案。':!state.connected?'适配已完成，请连接演示设备。':'可以体验发送；真实传输与回复待接入。';
    }
    ['playOnly'].forEach(id=>$(id).disabled=!canPlay);$('stopPlayback').disabled=!state.playing;
    $('playOnly').classList.toggle('active',state.playing==='play');
    $('sendData').disabled=!state.connected||state.uploading;$('sendConnectionState').textContent=state.uploading?'发送演示期间暂缓调试':state.connected?'演示设备已连接':'请先连接演示设备';
    ['Load','Set','Upload','Play'].forEach(part=>{$('step'+part).classList.remove('current','done');});
    $('stepLoad').classList.toggle('done',state.loaded);$('stepSet').classList.toggle('done',ready);$('stepUpload').classList.toggle('done',state.uploaded);
    $(!state.loaded?'stepLoad':!ready?'stepSet':!state.uploaded?'stepUpload':'stepPlay').classList.add('current');
    $('summaryTempo').textContent=state.localName?'—':String(Math.round(state.score.bpm*state.settings.speed/100));$('tempoLabel').textContent='BPM · '+state.settings.speed+'% 速度';
    $('summaryDuration').textContent=state.localName?'—':clockText(state.score.duration);$('summaryCount').textContent=state.localName?'—':state.loaded?getNotes(state.settings).length:14;
    $('txCount').textContent=String(state.tx);renderFit();if(NATIVE)nativeRefresh();const status={connected:state.connected,uploading:state.uploading,playing:Boolean(state.playing)};const stamp=JSON.stringify(status);if(stamp!==lastStatus){lastStatus=stamp;window.dispatchEvent(new CustomEvent('tang:status',{detail:status}));}
  }
  function stopPlayback(message){clearInterval(playTimer);playTimer=null;state.playing=null;$('scorePlaybackProgress').style.width='0%';$('scorePlaybackProgress').style.transform='scaleX(0)';$('playTime').innerHTML='00:00 <b>/ '+clockText(Math.ceil(scoreDuration()))+'</b>';$('playStatus').textContent=message||(state.uploaded?'演示曲谱已就绪':'确认适配后，可预览片段时间');refresh();}
  function invalidateUpload(message){clearInterval(uploadTimer);uploadTimer=null;state.uploading=false;state.uploaded=false;setProgress(0);stopPlayback(message);}
  function loadScore(id,source){
    state.score=Fit.score(id);state.loaded=true;state.localName='';state.source=source||'sample';state.settingsSaved=false;
    state.settings={track:'melody',transpose:0,speed:100,start:0,end:Math.min(120,state.score.duration)};
    $('localImportNotice').hidden=true;$('scoreName').textContent=state.score.name;$('scoreDescription').textContent=state.score.subtitle;$('scoreCategory').textContent='32-KEY PRACTICE / '+state.score.tag;$('scoreSource').textContent=source==='catalog'?'曲库预览 · 内置示例':'内置练习示例';
    $('sourceNote').textContent=state.score.credit+' · 未联网，未读取真实 MIDI 文件';invalidateUpload('示例已载入，请先确认适配方案');renderCatalog();toast('示例已载入，请选择声部和片段并确认适配。');
  }
  $('loadSample').addEventListener('click',()=>loadScore('twinkle','sample'));
  function renderCatalog(){window.TangCatalogUI?.render();}
  $('networkImport').addEventListener('click',()=>window.TangCatalogUI.open());
  $('librarySearch').addEventListener('input',renderCatalog);
  $('networkForm').addEventListener('submit',event=>{event.preventDefault();if(NATIVE){downloadMidi();return;}let valid=false;try{const u=new URL($('midiUrl').value.trim());valid=u.protocol==='https:'&&Boolean(u.hostname);}catch(_){}$('networkError').textContent=valid?'链接格式有效。真实下载尚未接入，未联网或载入任何曲谱。':'请输入有效的 HTTPS MIDI 文件直链。';$('networkError').hidden=false;$('midiUrl').setAttribute('aria-invalid',String(!valid));});
  $('importLocal').addEventListener('click',()=>{if(NATIVE){if(!fileBusy){setFileBusy(true);window.TangLibrary.select();}}else $('localMidi').click();});
  $('localMidi').addEventListener('change',()=>{
    const file=$('localMidi').files[0];if(!file)return;
    if(!/\.(mid|midi)$/i.test(file.name)){toast('请选择 .mid 或 .midi 文件。');$('localMidi').value='';return;}
    state.loaded=false;state.settingsSaved=false;state.localName=file.name;$('scoreName').textContent=file.name;$('scoreDescription').textContent='已选择本地文件；MIDI 解析将在下一阶段接入。';$('scoreSource').textContent='本地 MIDI · 未解析';$('scoreCategory').textContent='LOCAL FILE / PENDING';$('sourceNote').textContent='文件大小 '+Math.ceil(file.size/1024)+' KB · 尚未生成音符事件';$('localImportNotice').textContent='已选择 '+file.name+'。真实解析待接入；可载入内置示例继续体验适配。';$('localImportNotice').hidden=false;invalidateUpload('本地 MIDI 尚未解析，不能开始演奏');$('localMidi').value='';
  });
  function readDraft(){return {track:$('trackSelect').value,start:Number($('clipStart').value),end:Number($('clipEnd').value),transpose:Number($('transposeInput').value),speed:Number($('tempoInput').value)};}
  function draftError(d){
    const track=getTrack(d);if(!track||track.percussion)return '请选择旋律或低音声部；鼓轨不参与键盘移调。';
    if(!$('clipStart').value.trim()||!$('clipEnd').value.trim()||!Number.isFinite(d.start)||!Number.isFinite(d.end)||d.start<0||d.end>d.start+120||d.end>state.score.duration||d.end<=d.start)return '片段需位于曲目内，结束晚于开始，长度最多 120 秒。';
    if(!$('transposeInput').value.trim()||!Number.isInteger(d.transpose)||Math.abs(d.transpose)>127)return '移调请填写 −127 至 +127 的整数。';
    if(!$('tempoInput').value.trim()||!Number.isInteger(d.speed)||d.speed<25||d.speed>200)return '速度请填写 25 至 200 的整数百分比。';
    if((d.end-d.start)*100/d.speed>120)return '当前放慢速度后的演奏片段超过 120 秒，请缩短片段或提高速度。';
    if(!getNotes(d).length)return '所选片段没有音符，请重新选择。';return '';
  }
  function renderDraft(){
    const draft=readDraft(),error=draftError(draft);$('settingsError').hidden=true;
    if(error){$('recommendation').textContent=error;$('recommendation').className='recommendation warn';$('applySuggestion').disabled=true;$('draftResult').textContent='请先修正上方设置';$('draftResult').className='fit-draft warn';$('saveSettings').disabled=true;return;}
    const result=Fit.analyze(getNotes(draft),draft.transpose);$('clipDurationHint').textContent='原片段 '+(draft.end-draft.start).toFixed(1)+' 秒 · 调速后 '+((draft.end-draft.start)*100/draft.speed).toFixed(1)+' 秒 · 最多 120 秒';
    $('recommendation').textContent=result.possible?'建议'+shiftText(result.suggestion)+(result.suggestion%12!==0?'；调性将随整体移调改变。':'；保持原调性。'):'原音域 '+rangeText(result.low,result.high)+'，跨度 '+(result.high-result.low)+' 个半音。整体移调无法放入 32 键，请缩短片段或更换声部。';
    $('recommendation').className='recommendation '+(result.possible?'':'warn');$('applySuggestion').disabled=!result.possible;$('applySuggestion').textContent=result.possible?'采用建议：'+shiftText(result.suggestion):'整体移调无法适配';
    $('effectiveTempo').textContent='当前 '+Math.round(state.score.bpm*draft.speed/100)+' BPM · 原速 '+state.score.bpm+' BPM 的 '+draft.speed+'%';
    $('draftResult').textContent='当前方案：'+rangeText(result.afterLow,result.afterHigh)+' · '+result.count+' 个音符事件 · '+result.remaining+' 次越界'+(result.ok?' · 可以确认':' · 暂不能发送');$('draftResult').className='fit-draft '+(result.ok?'good':'warn');$('saveSettings').disabled=!result.ok;
  }
  $('openSettings').addEventListener('click',()=>{
    $('trackSelect').replaceChildren();state.score.tracks.forEach(track=>{const option=document.createElement('option');option.value=track.id;option.textContent=track.name+' · '+(track.noteCount??track.notes.length)+' 个音符';option.disabled=track.percussion;$('trackSelect').append(option);});
    $('trackSelect').value=state.settings.track;$('transposeInput').value=String(state.settings.transpose);$('tempoInput').value=String(state.settings.speed);$('clipStart').value=String(state.settings.start);$('clipEnd').value=String(state.settings.end);$('clipStart').max=String(state.score.duration);$('clipEnd').max=String(state.score.duration);$('clipTotal').textContent='曲目共 '+clockText(state.score.duration);renderDraft();$('settingsDialog').showModal();
  });
  let draftFrame=null;['trackSelect','transposeInput','tempoInput','clipStart','clipEnd'].forEach(id=>$(id).addEventListener('input',()=>{if(draftFrame===null)draftFrame=requestAnimationFrame(()=>{draftFrame=null;renderDraft();});}));
  $$('[data-clip]').forEach(button=>button.addEventListener('click',()=>{$('clipStart').value='0';$('clipEnd').value=String(Math.min(state.score.duration,Number(button.dataset.clip)));renderDraft();}));
  $('applySuggestion').addEventListener('click',()=>{const d=readDraft();if(draftError(d))return;const result=Fit.analyze(getNotes(d),d.transpose);if(result.possible)$('transposeInput').value=String(result.suggestion);renderDraft();});
  $('settingsForm').addEventListener('submit',event=>{
    event.preventDefault();const draft=readDraft();let error=draftError(draft);if(!error&&!Fit.analyze(getNotes(draft),draft.transpose).ok)error='仍有超出 F3–C6 的音符，请修改方案。';
    if(error){$('settingsError').textContent=error;$('settingsError').hidden=false;return;}
    state.settings={...draft};state.settingsSaved=true;invalidateUpload('适配方案已确认，可在本机预览片段时间');$('settingsDialog').close();log('确认适配：'+shiftText(draft.transpose)+'，片段 '+draft.start+'–'+draft.end+' 秒。');toast('适配已确认，全部音符落在 F3–C6 内。');
  });
  $('scanDevices').addEventListener('click',()=>{if(NATIVE){deviceList.clear();renderDevices();window.TangAndroid.scanBle();return;}if(state.connected||state.scanning)return;state.scanning=true;$('deviceResults').hidden=true;refresh();scanTimer=setTimeout(()=>{state.scanning=false;$('deviceResults').hidden=false;refresh();log('扫描演示完成，显示预设设备。');},700);});
  function connect(){if(NATIVE){if(lastAddress)window.TangAndroid.connectBle(lastAddress);else toast('请扫描并选择真实 BLE 设备。');return;}if(state.connected)return;clearTimeout(scanTimer);state.scanning=false;state.connected=true;state.everConnected=true;$('deviceResults').hidden=true;refresh();log('演示连接已建立；不是实际硬件连接。');toast('演示设备已连接，确认适配后可体验发送。');}
  if($('connectDevice'))$('connectDevice').addEventListener('click',connect);$('reconnectDevice').addEventListener('click',connect);
  function disconnect(){if(NATIVE){window.TangAndroid.disconnectBle();return;}clearTimeout(scanTimer);state.scanning=false;state.connected=false;$('deviceResults').hidden=true;invalidateUpload('演示连接已断开，请重新演示发送');log('演示已断开，发送状态已清除。');toast('演示连接已断开。');}
  $('disconnectDevice').addEventListener('click',disconnect);$('cancelAndDisconnect').addEventListener('click',disconnect);
  $('uploadScore').addEventListener('click',()=>{if(NATIVE){window.TangScore?.upload();return;}if(!state.connected||!state.loaded||!state.settingsSaved||!fitResult().ok||state.uploading)return;invalidateUpload('正在演示发送适配曲谱');state.uploading=true;refresh();log('开始模拟发送，未向硬件传输。');uploadTimer=setInterval(()=>{if(!state.connected){invalidateUpload();return;}setProgress(Math.min(100,state.progress+10));if(state.progress>=100){clearInterval(uploadTimer);state.uploading=false;state.uploaded=true;$('playStatus').textContent='演示发送完成，可以体验演奏';refresh();log('模拟发送完成；不是 FPGA 接收确认。');toast('演示发送完成，可开始无声演奏。');}},140);});
  function play(){
    if(NATIVE?!(state.loaded&&state.settingsSaved&&fitResult().ok):(!state.connected||!state.uploaded||state.uploading))return;stopPlayback();state.playing='play';$('playStatus').textContent='曲谱时间预览中 · 不发声';const started=performance.now(),duration=scoreDuration();
    function tick(){const elapsed=Math.min(duration,(performance.now()-started)/1000);if(!document.hidden&&!$('scores').hidden){const label=clockText(elapsed)+' <b>/ '+clockText(Math.ceil(duration))+'</b>';if($('playTime').innerHTML!==label)$('playTime').innerHTML=label;$('scorePlaybackProgress').style.width='100%';$('scorePlaybackProgress').style.transform='scaleX('+(elapsed/duration)+')';}if(elapsed>=duration){stopPlayback('片段时间预览已结束');log('适配片段演奏结束。');}}
    tick();playTimer=setInterval(tick,50);refresh();
  }
  $('playOnly').addEventListener('click',play);$('stopPlayback').addEventListener('click',()=>stopPlayback('时间预览已停止'));
  function parseBytes(value, format, appendLf) {
    let bytes;
    if (!value.trim()) throw new Error('请输入要演示发送的内容。');
    if (format === 'hex') {
      const compact = value.replace(/\s/g, '');
      if (!/^[0-9a-fA-F]+$/.test(compact) || compact.length % 2) throw new Error('HEX 需为完整的十六进制字节，例如 AA 01 0F。');
      bytes = compact.match(/.{2}/g).map(function (pair) { return parseInt(pair, 16); });
    } else {
      if (Array.from(value).some(function (ch) { return ch.codePointAt(0) > 127; })) throw new Error('ASCII 仅支持英文、数字和 ASCII 符号，请修改内容或改用 HEX。');
      bytes = Array.from(value).map(function (ch) { return ch.charCodeAt(0); });
    }
    if (appendLf) bytes.push(10);
    if (bytes.length > 4096) throw new Error('发送内容不能超过 4096 字节（包含末尾 LF）。');
    return bytes;
  }
  function updateBytePreview() {
    try { $('bytePreview').textContent = parseBytes($('sendInput').value, state.format, $('appendLf').checked).length + ' 字节'; }
    catch (_) { $('bytePreview').textContent = $('sendInput').value.trim() ? '待校验' : '0 字节'; }
  }
  function setFormat(format) {
    state.format = format;
    $('formatAscii').classList.toggle('active', format === 'ascii'); $('formatAscii').setAttribute('aria-pressed', String(format === 'ascii'));
    $('formatHex').classList.toggle('active', format === 'hex'); $('formatHex').setAttribute('aria-pressed', String(format === 'hex'));
    $('inputFormatHint').textContent = format === 'hex' ? '例如 AA 01 0F，空格可选' : '例如 P，使用 ASCII 字符';
    $('sendInput').placeholder = format === 'hex' ? 'AA 01 0F' : 'P';
    $('sendError').hidden = true;
    $('sendInput').removeAttribute('aria-invalid');
    updateBytePreview();
  }
  $('formatAscii').addEventListener('click', function () { setFormat('ascii'); });
  $('formatHex').addEventListener('click', function () { setFormat('hex'); });
  $('sendInput').addEventListener('input', function () { $('sendError').hidden = true; $('sendInput').removeAttribute('aria-invalid'); updateBytePreview(); });
  $('appendLf').addEventListener('change', updateBytePreview);

  function send(value, format, appendLf, label) {
    if (!state.connected || state.uploading) return false;
    const bytes = parseBytes(value, format, appendLf);
    if(NATIVE){if(!channelReady||txBusy)return false;window.TangAndroid.sendHex(bytes.map(b=>b.toString(16).padStart(2,'0')).join(''));return true;}
    const hex = bytes.map(function (byte) { return byte.toString(16).toUpperCase().padStart(2, '0'); }).join(' ');
    state.tx += bytes.length;
    log((label ? label + ' · ' : '') + bytes.length + ' 字节 · HEX ' + hex + (format === 'ascii' ? '\nASCII ' + JSON.stringify(value) + (appendLf ? ' + LF' : '') : ''), 'tx');
    refresh();
    toast('已记录 ' + bytes.length + ' 字节演示数据，没有实际发包。');
    return true;
  }
  $('sendData').addEventListener('click', function () {
    try { send($('sendInput').value, state.format, $('appendLf').checked, '自定义发送'); $('sendError').hidden = true; $('sendInput').removeAttribute('aria-invalid'); }
    catch (error) { $('sendError').textContent = error.message; $('sendError').hidden = false; $('sendInput').setAttribute('aria-invalid', 'true'); $('sendInput').focus(); }
  });
  $('clearLog').addEventListener('click', function () { logQueue.length=0; $('logOutput').replaceChildren(); state.tx = 0;rxCount=0; refresh(); log(NATIVE?'本次收发记录和计数已清空。':'演示记录和计数已清空。'); toast('已清空记录。'); });

  function boardScore(){
    if(!state.loaded||!state.settingsSaved||!fitResult().ok)throw Error('Confirm score adaptation before uploading');
    const speed=100/state.settings.speed;
    const notes=getNotes(state.settings).map(n=>{const start=Math.round(n.time*speed*1e6),end=Math.round((n.time+n.duration)*speed*1e6);return {startUs:start,durationUs:Math.max(1,end-start),pitch:n.midi+state.settings.transpose,velocity:Math.max(1,Math.min(127,Math.round(n.velocity*127)))}}).sort((a,b)=>a.startUs-b.startUs||a.pitch-b.pitch);
    return {durationUs:Math.round(scoreDuration()*1e6),source:state.score.name,notes};
  }
  window.TangApp={toast,log,nav,native:NATIVE,boardScore,scoreAdapted(){return state.loaded&&state.settingsSaved&&fitResult().ok;},setBoardTransfer(busy){if(state.uploading===busy)return;state.uploading=busy;refresh();},get lastAddress(){return lastAddress;},get protocolReady(){return Boolean(window.MinlinkUI&&window.MinlinkUI.state.ready);},exportJson(name,data){if(NATIVE)window.TangAndroid.saveJson(name,JSON.stringify(data,null,2));},get connected(){return state.connected;},get playing(){return Boolean(state.playing);},get uploading(){return state.uploading;},get keyMap(){return state.keyMap.slice();},setKeyMap(mapping){if(mapping.length!==32||new Set(mapping).size!==32||mapping.some(n=>n<53||n>84))throw new Error('键位必须完整覆盖 MIDI 53–84。');state.keyMap=mapping.slice();if(NATIVE)localStorage.setItem('tang-keymap',JSON.stringify(state.keyMap));invalidateUpload('键位映射已修改，请重新发送曲谱');},noteName};

  function nativeRefresh(){
    $('headerDevice').textContent=channelReady?'蓝牙就绪':state.connected?'发现服务中':connecting?'连接中':'未连接';
    $('deviceStatusBadge').textContent=$('headerDevice').textContent;
    $('scanDevices').disabled=state.scanning||state.connected||connecting;
    $('scanDevices').querySelector('span').textContent=state.scanning?'扫描中（10 秒）':'扫描 BLE 设备';
    $('disconnectDevice').disabled=!state.connected&&!connecting;
    $('reconnectDevice').disabled=!lastAddress||connecting||state.scanning;
    $('connectionTitle').textContent=channelReady?'BLE 通道已就绪':state.connected?'正在配置收发通道':connecting?'正在连接':state.scanning?'正在扫描周围设备':'准备连接';
    $('connectionDetail').textContent=channelReady?'已建立共用通道，正在读取乐器和录音能力。':'请按蓝牙模块实际配置填写服务与特征 UUID。';
    $('scoreState').textContent=state.loaded?'已解析':'待载入';
    if(!window.TangScore){$('uploadScore').disabled=true;$('uploadBadge').textContent='等待读取曲谱能力';}
    $('playOnly').disabled=!(state.loaded&&state.settingsSaved&&fitResult().ok);
    $('sendData').disabled=!channelReady||txBusy;
    $('sendConnectionState').textContent=txBusy?'发送中':channelReady?'真实 BLE 收发':'请先建立 BLE 通道';
    $('rxCount').textContent=String(rxCount);
    $('tempoLabel').textContent=(state.score.variableTempo?'起始 BPM':'BPM')+' · '+state.settings.speed+'% 速度';
    ['importLocal','networkImport'].forEach(id=>$(id).disabled=fileBusy);
    $('simulateDownload').disabled=fileBusy;
    if(window.MinlinkUI)window.MinlinkUI.refresh({channelReady,connected:state.connected,connecting,scanning:state.scanning});
    $('exportScore').disabled=!(state.loaded&&state.settingsSaved&&fitResult().ok);
    window.TangScore?.refresh();
  }
  function setFileBusy(value){fileBusy=value;['importLocal','networkImport','simulateDownload'].forEach(id=>$(id).disabled=value);}
  function renderDevices(){deviceList.schedule();}
  function renderLibrary(items){window.TangCatalogUI?.render();}
  function downloadMidi(){
    if(fileBusy)return;let value=$('midiUrl').value.trim();
    try{const u=new URL(value);if(u.protocol!=='https:'||!u.hostname||u.username||u.password)throw Error();}catch(_){$('networkError').hidden=false;$('networkError').textContent='请输入不含账号密码的 HTTPS MIDI 文件直链。';return;}
    $('networkError').hidden=false;$('networkError').textContent='正在连接并下载 MIDI…';setFileBusy(true);window.TangLibrary.downloadUrl(value);
  }
  async function parseMidiFile(payload){
    setFileBusy(true);
    try{const score=await window.TangMidiService.parse(payload.base64,payload.name);await loadParsedMidi({...payload,score,size:payload.size||Math.floor(payload.base64.length*3/4)});}
    catch(error){toast(error.message);$('networkError').hidden=false;$('networkError').textContent=error.message;}
    finally{setFileBusy(false);}
  }
  async function loadParsedMidi(payload){
    const parsed=payload.score;
    state.score=parsed;state.loaded=true;state.localName='';state.source=payload.source;state.settingsSaved=false;
    const track=parsed.tracks.find(t=>!t.percussion);
    state.settings={track:track.id,transpose:0,speed:100,start:0,end:Math.min(120,Math.ceil(parsed.duration*10)/10)};
    // Round the score duration up as well, so a fractional final note is never lost.
    state.score.duration=Math.ceil(parsed.duration*10)/10;
    $('scoreName').textContent=payload.name;$('scoreDescription').textContent=parsed.subtitle;
    $('scoreCategory').textContent='STANDARD MIDI / '+parsed.tracks.length+' TRACKS';
    $('scoreSource').textContent=payload.fromCache?'本机曲库 · 离线打开':payload.source==='download'?'联网下载 · 已解析':'本地 MIDI · 已解析';
    $('sourceNote').textContent='真实音符与时间数据 · '+Math.ceil(payload.size/1024)+' KB · '+(parsed.variableTempo?'包含变速，时间变化按比例保留':'固定速度')+' · CC64 延音已处理';
    $('localImportNotice').hidden=true;
    await new Promise(resolve=>setTimeout(resolve,0));
    invalidateUpload('MIDI 已解析，请选择声部和片段并确认适配');
    await new Promise(resolve=>setTimeout(resolve,0));
    $('networkDialog').close();nav('scores');toast('MIDI 已解析，请确认演奏声部、片段和移调。');
    await new Promise(resolve=>setTimeout(resolve,0));
    $('openSettings').click();
  }
  window.TangNativeEvent=function(event){
    if(window.TangLibrary?.event(event))return;
    const d=event.data||{};
    switch(event.type){
      case 'protocolState': case 'protocolLog': case 'parameterResult':if(window.MinlinkUI)window.MinlinkUI.event(event);return;
      case 'ready': case 'configuration':
        $('bleService').value=d.service;$('bleTx').value=d.tx;$('bleRx').value=d.rx;lastAddress=d.lastAddress||'';
        if(event.type==='configuration')toast('UUID 已保存，请重新连接。');break;
      case 'scanStarted':state.scanning=true;renderDevices();nativeRefresh();return;
      case 'scanStopped':state.scanning=false;renderDevices();nativeRefresh();return;
      case 'deviceFound':deviceList.accept(d);return;
      case 'devicesFound':(d.items||[]).forEach(item=>deviceList.accept(item));return;
      case 'connecting':connecting=true;state.scanning=false;log('正在连接 '+d.address);renderDevices();break;
      case 'connected':state.connected=true;connecting=false;renderDevices();log('BLE 已连接，正在发现服务。');break;
      case 'services':$('bleDiscovered').textContent=JSON.stringify(d.items,null,2);log('已发现 '+d.items.length+' 个 GATT 服务。');break;
      case 'channelReady':state.connected=true;channelReady=true;lastAddress=d.address;state.everConnected=true;log('BLE 收发通道就绪，正在确认 FPGA 协议。');toast('通道已就绪，等待 FPGA 握手确认。');$('deviceResults').hidden=true;break;
      case 'disconnected':state.connected=false;connecting=false;channelReady=false;txBusy=false;invalidateUpload('蓝牙已断开；手机适配结果保留');log('BLE 已断开。');renderDevices();break;
      case 'txStarted':txBusy=true;log('提交 '+d.bytes+' 字节 · HEX '+d.hex,'tx');return;
      case 'txDone':txBusy=false;state.tx+=d.bytes;log('BLE 写入完成 '+d.bytes+' 字节；需板端回复才能确认执行。');if(!window.MinlinkUI||window.MinlinkUI.state.phase==='offline')toast('数据已写入，等待 FPGA 协议应答。');$('txCount').textContent=String(state.tx);return;
      case 'rx':rxCount+=d.bytes;log(d.bytes+' 字节 · HEX '+d.hex,'rx');if(!$('debug').hidden)$('rxCount').textContent=String(rxCount);return;
      case 'downloadProgress':$('networkError').textContent='已下载 '+Math.ceil(d.bytes/1024)+' KB'+(d.percent>=0?' · '+d.percent+'%':'');return;
      case 'midiFile':parseMidiFile(d);return;
      case 'midiParsed':return loadParsedMidi(d);
      case 'midiLibrary':renderLibrary(d.items||[]);return;
      case 'fileCancelled':case 'exportCancelled':setFileBusy(false);break;
      case 'exportDone':toast(d.message);break;
      case 'fileError':setFileBusy(false);$('networkError').hidden=false;$('networkError').textContent=d.message;toast(d.message);log(d.message);break;
      case 'error':txBusy=false;toast(d.message);log(d.message);break;
    }
    refresh();
  };
  window.addEventListener('tang:page',e=>{if(e.detail.page==='debug'){$('rxCount').textContent=String(rxCount);$('txCount').textContent=String(state.tx);}});
  window.addEventListener('tang:library',({detail})=>{if(fileBusy!==detail.busy)setFileBusy(detail.busy);});
  window.TangBack=function(){const dialog=document.querySelector('dialog[open]');if(dialog){dialog.close();return true;}const page=document.querySelector('.page.active');if(page&&page.id!=='scores'){nav('scores');return true;}return false;};
  if(NATIVE){
    try{const saved=JSON.parse(localStorage.getItem('tang-keymap'));if(Array.isArray(saved)&&saved.length===32&&new Set(saved).size===32&&saved.every(n=>Number.isInteger(n)&&n>=53&&n<=84))state.keyMap=saved;}catch(_){}
    $('saveBleConfig').addEventListener('click',()=>window.TangAndroid.configureBle($('bleService').value,$('bleTx').value,$('bleRx').value));
    $('exportScore').addEventListener('click',()=>{
      if(!state.loaded||!state.settingsSaved||!fitResult().ok)return;
      const speed=100/state.settings.speed,track=getTrack(state.settings);
      const result={version:1,type:'adapted-score',unit:'seconds',source:state.score.name,track:track.name,transpose:state.settings.transpose,speedPercent:state.settings.speed,durationSeconds:scoreDuration(),keyboardMap:state.keyMap.slice(),notes:getNotes(state.settings).map(n=>({midi:n.midi+state.settings.transpose,time:n.time*speed,duration:n.duration*speed,velocity:Math.max(1,Math.min(127,Math.round(n.velocity*127)))}))};
      window.TangAndroid.saveJson('TangMusic-适配音符.json',JSON.stringify(result,null,2));
    });
    
    $('logOutput').replaceChildren();log('手机端已就绪。连接后先完成 HELLO、PING 与参数回读。');
  }
  refresh();nav(['scores','device','session','recordings','debug'].includes(location.hash.slice(1))?location.hash.slice(1):'device');
})();
