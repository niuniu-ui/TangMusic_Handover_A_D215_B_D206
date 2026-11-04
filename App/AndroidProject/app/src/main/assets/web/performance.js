(function(){
  'use strict';
  const $=id=>document.getElementById(id), $$=s=>Array.from(document.querySelectorAll(s));
  const app=window.TangApp, E=new window.SessionEngine();
  const actions=['四次敲击定速','开始循环','切换鼓型','小节结束','立即停止','录入所选轨'];
  let padMap=[36,38,42,46,49,51], draftMap=[], draftPads=[], selectedKey=0, selectedTrack=0, taps=[];
  let lastTrackState='', live=new Map(), captureStart=null, captureSlot=null, selectedCaptureSlot=null, recordingSequence=2, captureNumber=null, returnTimer=null, returning=null;
  const phone=[];
  const recordings=app.native?[]:[{slot:1,id:'sample-a',name:'演奏片段 01',seconds:64,size:'12.3 MB',source:'预置缓冲元数据'},{slot:2,id:'sample-b',name:'合奏练习 02',seconds:92,size:'17.7 MB',source:'预置缓冲元数据'}];
  if(app.native){try{const p=JSON.parse(localStorage.getItem('tang-padmap'));if(Array.isArray(p)&&p.length===6&&new Set(p).size===6&&p.every(n=>Number.isInteger(n)&&n>=0&&n<=127))padMap=p;}catch(_){}}
  const clock=s=>String(Math.floor(s/60)).padStart(2,'0')+':'+String(Math.floor(s%60)).padStart(2,'0');
  const notice=message=>{E.notice=message;app.toast(message);};
  const safe=fn=>{try{fn();}catch(error){app.toast(error.message);}};
  function showTrack(index){selectedTrack=index;$('inputTrackName').textContent=E.tracks[index].name;renderTracks();}

  function renderPhysicalKeys(){
    $('physicalKeyGrid').replaceChildren();
    draftMap.forEach((note,index)=>{const key=document.createElement('button');key.type='button';key.className='physical-key'+(selectedKey===index?' selected':'');key.dataset.keyIndex=index;const label=document.createElement('small');label.textContent='键 '+(index+1);const pitch=document.createElement('strong');pitch.textContent=app.noteName(note);key.append(label,pitch);key.addEventListener('click',()=>{selectedKey=index;renderPhysicalKeys();});$('physicalKeyGrid').append(key);});
    $('selectedPhysicalKey').textContent=String(selectedKey+1);$('keyNoteSelect').value=String(draftMap[selectedKey]);
  }
  $('openKeyMap').addEventListener('click',()=>{
    if(E.running||app.playing||app.uploading){app.toast('请先停止演奏和循环，再修改演奏键位。');return;}
    draftMap=app.keyMap;draftPads=padMap.slice();selectedKey=0;$('keyMapError').hidden=true;$('keySwapNotice').textContent='更改音高时会交换占用此音高的另一实体键。';
    $('keyNoteSelect').replaceChildren();for(let n=53;n<=84;n++){const option=document.createElement('option');option.value=String(n);option.textContent=app.noteName(n)+' · MIDI '+n;$('keyNoteSelect').append(option);}
    $('padMappingFields').replaceChildren();actions.forEach((label,index)=>{const row=document.createElement('label');row.className='pad-mapping-row';const title=document.createElement('span');title.textContent=label;const input=document.createElement('input');input.type='number';input.min='0';input.max='127';input.step='1';input.value=String(draftPads[index]);input.id='padMap'+index;input.setAttribute('aria-label',label+'的 MIDI 编号');row.append(title,input);$('padMappingFields').append(row);});renderPhysicalKeys();$('keyMapDialog').showModal();
  });
  $('keyNoteSelect').addEventListener('change',()=>{const target=Number($('keyNoteSelect').value),other=draftMap.indexOf(target),old=draftMap[selectedKey];if(other<0)return;draftMap[other]=old;draftMap[selectedKey]=target;$('keySwapNotice').textContent=other===selectedKey?'音高未改变。':'已交换键 '+(selectedKey+1)+' 与键 '+(other+1)+'，32 个音高仍完整覆盖。';renderPhysicalKeys();});
  $('resetKeys').addEventListener('click',()=>{draftMap=Array.from({length:32},(_,i)=>i+53);renderPhysicalKeys();});
  $('reverseKeys').addEventListener('click',()=>{draftMap=Array.from({length:32},(_,i)=>84-i);renderPhysicalKeys();});
  $('keyMapForm').addEventListener('submit',event=>{
    event.preventDefault();const pads=actions.map((_,i)=>$('padMap'+i).value.trim()===''?NaN:Number($('padMap'+i).value));let error='';
    if(E.running||app.playing||app.uploading)error='请先停止演奏和循环，再保存映射。';
    else if(pads.some(n=>!Number.isInteger(n)||n<0||n>127))error='Pad MIDI 编号必须为 0–127 的整数。';
    else if(new Set(pads).size!==pads.length)error='Pad 控制编号存在冲突，请为每个功能分配不同编号。';
    if(error){$('keyMapError').textContent=error;$('keyMapError').hidden=false;return;}
    app.setKeyMap(draftMap);padMap=pads;if(app.native)localStorage.setItem('tang-padmap',JSON.stringify(pads));$('keyMapState').textContent=draftMap.every((n,i)=>n===i+53)?'默认键盘 · 自定义 Pad':'自定义映射';renderControlPads();$('keyMapDialog').close();app.toast('映射已保存在手机；板端映射协议待接入。');
  });

  function releaseLive(id){E.noteOff(id);live.delete(id);}
  function clearLive(){for(const id of [...live.keys()])releaseLive(id);}
  function inputButton(label,note,id,percussion){
    const button=document.createElement('button');button.type='button';button.className=percussion?'phrase-pad':'phrase-key';button.textContent=label;button.dataset.note=note;
    button.addEventListener('pointerdown',event=>{if(event.button!==0)return;event.preventDefault();button.setPointerCapture(event.pointerId);button.classList.add('pressed');live.set(id,note);E.noteOn(note,100,id,percussion);});
    const release=()=>{button.classList.remove('pressed');releaseLive(id);};button.addEventListener('pointerup',release);button.addEventListener('pointercancel',release);button.addEventListener('lostpointercapture',release);
    button.addEventListener('keydown',event=>{if((event.key===' '||event.key==='Enter')&&!event.repeat){event.preventDefault();button.classList.add('pressed');live.set(id,note);E.noteOn(note,100,id,percussion);}});
    button.addEventListener('keyup',event=>{if(event.key===' '||event.key==='Enter'){event.preventDefault();release();}});
    button.addEventListener('blur',release);return button;
  }
  [60,62,64,65,67,69,71,72].forEach((n,i)=>$('phraseKeys').append(inputButton(app.noteName(n),n,'key-'+i,false)));
  [['底鼓',36],['军鼓',38],['踩镲',42]].forEach(([label,n],i)=>$('phrasePads').append(inputButton(label,n,'drum-'+i,true)));
  window.addEventListener('blur',clearLive);
  function buildTracks(){
    $('loopTracks').replaceChildren();E.tracks.forEach((track,index)=>{
      const card=document.createElement('article');card.className='card loop-track';card.id='loopTrack'+index;
      card.innerHTML='<div class="track-heading"><button class="track-select" type="button" aria-label="选择'+track.name+'轨"><span>'+String(index+1).padStart(2,'0')+'</span><strong>'+track.name+'</strong></button><span class="track-state" id="trackState'+index+'">空轨</span></div><div class="event-timeline" id="trackTimeline'+index+'"></div><div class="track-meta"><span id="trackEvents'+index+'">0 个事件</span><label>音色 <select id="trackInstrument'+index+'" aria-label="'+track.name+'轨音色"><option>钢琴</option><option>弦乐</option><option>贝斯</option><option>鼓</option></select></label></div><div class="track-actions"><button type="button" class="record-track" id="trackRecord'+index+'">录入</button><button type="button" id="trackMute'+index+'" aria-pressed="false">静音</button><button type="button" id="trackSolo'+index+'" aria-pressed="false">独奏</button><button type="button" id="trackUndo'+index+'">撤销</button><button type="button" id="trackClear'+index+'">清空</button></div><label class="track-volume">音量<input id="trackVolume'+index+'" aria-label="'+track.name+'轨音量" type="range" min="0" max="100" value="80"><span id="trackVolumeValue'+index+'">80%</span></label>';
      $('loopTracks').append(card);card.querySelector('.track-select').addEventListener('click',()=>showTrack(index));$('trackInstrument'+index).value=track.instrument;
      $('trackInstrument'+index).addEventListener('change',()=>{if(E.running){$('trackInstrument'+index).value=track.instrument;return;}track.instrument=$('trackInstrument'+index).value;});
      $('trackRecord'+index).addEventListener('click',()=>safe(()=>{selectedTrack=index;$('inputTrackName').textContent=track.name;E.record(index);renderTracks();$('inputTrackName').scrollIntoView({block:'start',behavior:'instant'});}));
      $('trackMute'+index).addEventListener('click',()=>{track.mute=!track.mute;renderTracks();});$('trackSolo'+index).addEventListener('click',()=>{track.solo=!track.solo;renderTracks();});
      $('trackClear'+index).addEventListener('click',()=>safe(()=>{E.clear(index);renderTracks();}));$('trackUndo'+index).addEventListener('click',()=>safe(()=>{E.undo(index);renderTracks();}));
      $('trackVolume'+index).addEventListener('input',()=>{track.volume=Number($('trackVolume'+index).value);$('trackVolumeValue'+index).textContent=track.volume+'%';});
    });renderTracks();
  }
  function renderTracks(){
    E.tracks.forEach((track,index)=>{
      $('loopTrack'+index).classList.toggle('selected',index===selectedTrack);const rec=E.recording&&E.recording.index===index;
      $('trackState'+index).textContent=rec?(E.beat()<E.recording.start?'等待下一轮':'正在录入'):track.events.length?(E.running?'循环中':'已录入'):'空轨';$('trackState'+index).classList.toggle('recording',Boolean(rec));
      $('trackEvents'+index).textContent=track.events.length+' 个事件 · '+E.bars+' 小节';$('trackRecord'+index).textContent=rec?'已安排录入':track.events.length?'叠录':'录入';$('trackRecord'+index).disabled=Boolean(E.recording)||E.stopBeat!==null;
      for(const [name,value] of [['Mute',track.mute],['Solo',track.solo]]){$('track'+name+index).classList.toggle('active',value);$('track'+name+index).setAttribute('aria-pressed',String(value));}
      $('trackUndo'+index).disabled=E.running||track.history===null;$('trackClear'+index).disabled=E.running||!track.events.length;$('trackInstrument'+index).disabled=E.running;
      const timeline=$('trackTimeline'+index);timeline.replaceChildren();
      if(!track.events.length){const empty=document.createElement('small');empty.textContent='等待现场乐句';timeline.append(empty);}
      track.events.forEach(event=>{const bar=document.createElement('i');bar.style.left=(event.start/E.length*100)+'%';bar.style.width=Math.max(1,event.duration/E.length*100)+'%';bar.style.top=(7+(event.note%5)*4)+'px';bar.title=app.noteName(event.note)+' · '+event.start.toFixed(2)+' 拍';timeline.append(bar);});
    });
  }
  function configure(){safe(()=>{E.configure({bpm:Number($('loopBpm').value),bars:Number($('loopBars').value),grid:Number($('loopQuantize').value),countIn:Number($('loopCount').value)});});$('loopBpm').value=String(E.bpm);$('loopBars').value=String(E.bars);$('loopQuantize').value=String(E.grid);$('loopCount').value=String(E.countIn);renderTracks();}
  ['loopBpm','loopBars','loopQuantize','loopCount'].forEach(id=>$(id).addEventListener('change',configure));
  function tap(){
    if(E.running){app.toast('请先停止循环，再重新定速。');return;}
    const now=performance.now();if(taps.length===4||(taps.length&&now-taps[taps.length-1]>2000))taps=[];taps.push(now);$('tapProgress').textContent=taps.length+'/4';
    if(taps.length===4){const gaps=taps.slice(1).map((t,i)=>t-taps[i]).sort((a,b)=>a-b),bpm=Math.round(60000/gaps[1]);if(bpm<40||bpm>240){taps=[];$('tapProgress').textContent='请重试';notice('敲击间隔需对应 40–240 BPM，请重新敲四次。');return;}$('loopBpm').value=String(bpm);configure();notice('四次敲击完成：'+bpm+' BPM。');}
  }
  $('tapTempo').addEventListener('click',tap);
  function panic(){E.stop();clearLive();$$('.pressed').forEach(el=>el.classList.remove('pressed'));renderTracks();}
  $('loopPlay').addEventListener('click',()=>safe(()=>E.start()));$('loopEnd').addEventListener('click',()=>E.normalStop());$('loopPanic').addEventListener('click',panic);
  $('inputEnd').addEventListener('click',()=>E.normalStop());$('inputPanic').addEventListener('click',panic);$('backToTracks').addEventListener('click',()=>$('loopTracks').scrollIntoView({block:'start',behavior:'instant'}));
  $('drumEnable').addEventListener('change',()=>{E.accompaniment=$('drumEnable').checked;});
  $$('[data-pattern]').forEach(button=>button.addEventListener('click',()=>{E.setPattern(Number(button.dataset.pattern));renderTimeline();}));
  function renderControlPads(){
    $('controlPads').replaceChildren();padMap.forEach((note,index)=>{const button=document.createElement('button');button.type='button';button.innerHTML='<strong>Pad '+(index+1)+'</strong><span></span><small>MIDI '+note+'</small>';button.querySelector('span').textContent=$('padMode').value==='control'?actions[index]:'鼓事件 '+note;button.addEventListener('click',()=>{
      if($('padMode').value==='drum'){const id='control-pad-'+index;E.noteOn(note,100,id,true);E.noteOff(id,E.beat()+0.1);live.set(id,note);setTimeout(()=>live.delete(id),160);return;}
      safe(()=>{if(index===0)tap();if(index===1)E.start();if(index===2)E.setPattern(1-E.pattern);if(index===3)E.normalStop();if(index===4){E.stop();clearLive();}if(index===5)E.record(selectedTrack);renderTracks();});
    });$('controlPads').append(button);});
  }
  $('padMode').addEventListener('change',renderControlPads);
  $('exportLoop').addEventListener('click',()=>{
    const data={...E.export(),previewOnly:true,keyboardMap:app.keyMap,padControlMap:padMap.slice()};if(app.native){app.exportJson('TangMusic-乐句事件.json',data);return;}const blob=new Blob([JSON.stringify(data,null,2)],{type:'application/json'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='TangMusic-乐句事件.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);app.toast('已导出本机乐句事件 JSON，未生成音频。');
  });

  function chooseCaptureSlot(slot,scroll){
    if(captureStart!==null||returning||app.uploading||![1,2].includes(slot))return;
    selectedCaptureSlot=slot;renderRecordings();
    if(scroll)$('captureTargets').scrollIntoView({block:'center',behavior:'instant'});
  }
  function renderCaptureTargets(){
    $('captureTargets').replaceChildren();const locked=captureStart!==null||Boolean(returning)||app.uploading;
    const current=captureStart!==null?captureSlot:selectedCaptureSlot;
    for(let slot=1;slot<=2;slot++){
      const file=recordings.find(item=>item.slot===slot),active=captureStart!==null&&captureSlot===slot;
      const button=document.createElement('button');button.type='button';button.className='capture-target'+(current===slot?' selected':'')+(file?' occupied':'');button.id='captureTarget'+slot;button.dataset.targetSlot=String(slot);button.disabled=locked;button.setAttribute('aria-pressed',String(current===slot));
      const number=document.createElement('span');number.className='target-slot-number';number.textContent='录音位 '+slot;
      const name=document.createElement('strong');name.textContent=app.native?'状态待查询':active?'正在录入第 '+captureNumber+' 首':file?file.name:'空闲位置';
      const info=document.createElement('small');info.textContent=app.native?'预留配置，尚未读取板端目录':active?'录音结束前位置已锁定':file?clock(file.seconds)+' · '+(current===slot?'开始后覆盖':'已有录音'):'直接录入，不覆盖其他录音';
      button.append(number,name,info);button.addEventListener('click',()=>chooseCaptureSlot(slot,false));$('captureTargets').append(button);
    }
  }
  function updateRecordingPolicy(){
    const busy=captureStart!==null||Boolean(returning)||app.uploading;
    $('startCapture').disabled=app.native||!app.connected||busy||selectedCaptureSlot===null;
    $('capturePolicyNote').classList.remove('is-overwrite');if(app.native){$('capturePolicyNote').textContent=selectedCaptureSlot===null?'请选择计划使用的录音位；真实占用状态待设备上报。':'已选择录音位 '+selectedCaptureSlot+'；录音与覆盖操作待接入板端协议。';return;}
    if(captureStart!==null){$('capturePolicyNote').textContent='正在录入录音位 '+captureSlot+'，目标已锁定；另一录音位保留。';$('startCapture').textContent='录音位 '+captureSlot+' 录入中';return;}
    if(selectedCaptureSlot===null){$('capturePolicyNote').textContent='请先选择录音位。只有点击开始录音后，才会替换选中位置的旧音频。';$('startCapture').textContent='请先选择录音位';return;}
    const slot=selectedCaptureSlot,previous=recordings.find(file=>file.slot===slot);
    $('capturePolicyNote').textContent=previous?'已选择录音位 '+slot+'。开始录音将覆盖「'+previous.name+'」；另一录音位不受影响。':'已选择空闲的录音位 '+slot+'，开始后将录入此位置；另一录音位不受影响。';
    $('capturePolicyNote').classList.toggle('is-overwrite',Boolean(previous));
    $('startCapture').textContent=previous?'覆盖位 '+slot+' 并录音':'录入位 '+slot+'（预览）';
  }
  function renderRecordings(){
    $('recordingList').replaceChildren();
    for(let slot=1;slot<=2;slot++){
      const file=recordings.find(item=>item.slot===slot),active=captureStart!==null&&captureSlot===slot;
      const row=document.createElement('article');row.className='card recording-item recording-slot';row.dataset.slot=String(slot);
      const top=document.createElement('div');top.className='recording-slot-title';const label=document.createElement('strong');label.textContent='录音位 '+slot;const policy=document.createElement('span');policy.textContent=active?'正在录入':selectedCaptureSlot===slot?'本次录音目标':file?'已有录音':app.native?'预留位置':'空闲位置';policy.className=active?'slot-replace':'slot-neutral';row.classList.toggle('target-chosen',selectedCaptureSlot===slot);top.append(label,policy);row.append(top);
      if(!file){
        const message=document.createElement('p');message.className='hint';message.textContent=app.native?'等待板端上报此位置的占用状态':active?'正在录入第 '+captureNumber+' 首…':'空闲，等待录入';row.classList.toggle('slot-recording',active);row.append(message);const pick=document.createElement('button');pick.className='secondary wide slot-pick';pick.type='button';pick.textContent='录入此位';pick.dataset.selectSlot=String(slot);pick.disabled=captureStart!==null||Boolean(returning)||app.uploading;pick.addEventListener('click',()=>chooseCaptureSlot(slot,true));row.append(pick);$('recordingList').append(row);continue;
      }
      const heading=document.createElement('strong');heading.textContent=file.name;const meta=document.createElement('small');meta.textContent=clock(file.seconds)+' · '+file.size+' · '+file.source;const footer=document.createElement('div');footer.className='recording-item-actions';const badge=document.createElement('span');badge.textContent='示例 · 无音频文件';const button=document.createElement('button');button.className='secondary';button.textContent='演示回传';button.dataset.returnId=file.id;button.disabled=!app.connected||Boolean(returning)||captureStart!==null||app.uploading;button.addEventListener('click',()=>startReturn(file));
      const release=document.createElement('button');release.className='text-link compact';release.textContent='释放此位示例缓存';release.dataset.releaseId=file.id;release.disabled=Boolean(returning)||captureStart!==null;release.addEventListener('click',()=>{if(returning||captureStart!==null)return;const index=recordings.findIndex(item=>item.id===file.id);if(index>=0)recordings.splice(index,1);renderRecordings();app.toast('已释放录音位 '+slot+' 的示例缓存，未操作真实内存。');});const choose=document.createElement('button');choose.className='secondary slot-pick';choose.type='button';choose.textContent=selectedCaptureSlot===slot?'已选择覆盖':'覆盖这首';choose.dataset.selectSlot=String(slot);choose.disabled=captureStart!==null||Boolean(returning)||app.uploading;choose.addEventListener('click',()=>chooseCaptureSlot(slot,true));const commands=document.createElement('div');commands.className='slot-management';commands.append(choose,release);footer.append(badge,button);row.append(heading,meta,footer,commands);$('recordingList').append(row);
    }
    $('emptyBuffer').hidden=recordings.length>0||captureStart!==null;$('bufferEstimate').textContent=(recordings.reduce((sum,file)=>sum+file.seconds*192000,0)/1000000).toFixed(2)+' MB · '+recordings.length+'/2 位 · 非实测';renderCaptureTargets();updateRecordingPolicy();if(app.native){$('startCapture').textContent='录音协议待接入';$('bufferEstimate').textContent='待设备上报，尚未查询';$('captureStatus').textContent='板端协议待接入';$('emptyBuffer').textContent='尚未从设备读取录音目录。两个位置为预留配置。';}
    $('phoneRecordCount').textContent=phone.length+(app.native?' 条已保存音频':' 条回传流程记录');$('phoneRecordings').replaceChildren();
    if(!phone.length){const p=document.createElement('p');p.className='hint';p.textContent=app.native?'尚无音频。接入回传协议后，接收完整数据并校验，再保存为 WAV。':'完成回传预览后，在这里查看流程结果。';$('phoneRecordings').append(p);}
    phone.forEach(file=>{const row=document.createElement('div');row.className='phone-record-row';const title=document.createElement('strong');title.textContent=file.name+' · WAV 保存待接入';const desc=document.createElement('p');desc.textContent='回传流程预览已完成；未接收或保存真实音频。';const buttons=document.createElement('div');buttons.className='phone-actions';for(const text of ['回放待接入','分享待接入']){const button=document.createElement('button');button.className='secondary';button.textContent=text;button.disabled=true;buttons.append(button);}row.append(title,desc,buttons);$('phoneRecordings').append(row);});
  }
  function syncConnection(){
    const connected=app.connected;$('captureConnection').textContent=connected?'已连接演示设备；真实内存缓冲与蓝牙回传待接入。':'请先在设备页连接演示设备。';$('startCapture').disabled=!connected||captureStart!==null||Boolean(returning)||app.uploading;$('stopCapture').disabled=captureStart===null;
    if(app.native){$('captureConnection').textContent='录音、内存状态查询与回传命令待板端协议接入。此页不生成模拟录音。';$('stopCapture').disabled=true;}
    if(returning&&!connected)cancelReturn('连接已断开，回传预览中止；未保存文件。');renderRecordings();
  }
  window.addEventListener('tang:status',syncConnection);
  $('startCapture').addEventListener('click',()=>{
    if(app.native||!app.connected||app.uploading||returning||captureStart!==null||![1,2].includes(selectedCaptureSlot))return;
    captureSlot=selectedCaptureSlot;selectedCaptureSlot=null;const oldIndex=recordings.findIndex(file=>file.slot===captureSlot);
    if(oldIndex>=0)recordings.splice(oldIndex,1);
    captureNumber=++recordingSequence;captureStart=performance.now();$('captureTime').textContent='00:00';$('captureStatus').textContent='录音位 '+captureSlot+' 录入中';$('captureStatus').classList.add('recording');$('captureTime').parentElement.classList.add('recording');syncConnection();
  });
  function finishCapture(){
    if(captureStart===null)return;const seconds=Math.min(120,(performance.now()-captureStart)/1000),slot=captureSlot,number=captureNumber;
    captureStart=null;captureSlot=null;captureNumber=null;
    const existing=recordings.findIndex(file=>file.slot===slot);if(existing>=0)recordings.splice(existing,1);
    recordings.push({slot,id:'local-'+number+'-'+Date.now(),name:'现场演奏 '+String(number).padStart(2,'0'),seconds,size:(seconds*192000/1000000).toFixed(2)+' MB（估算）',source:'本次缓冲流程元数据'});recordings.sort((a,b)=>a.slot-b.slot);
    $('captureStatus').textContent='已录入位 '+slot+'（预览）';$('captureStatus').classList.remove('recording');$('captureTime').parentElement.classList.remove('recording');syncConnection();app.toast('录音位 '+slot+' 已更新；当前只保存预览元数据。');
  }
  $('stopCapture').addEventListener('click',finishCapture);
  function cancelReturn(message){clearInterval(returnTimer);returnTimer=null;returning=null;$('returnStatus').textContent=message||'回传预览已取消，没有保存文件。';$('cancelReturn').disabled=true;syncConnection();}
  function startReturn(file){
    if(app.native||!app.connected||returning||captureStart!==null||app.uploading)return;returning={file,progress:0};$('recordingTransfer').hidden=false;$('returnFileName').textContent=file.name;$('returnPercent').textContent='0%';$('returnProgress').style.width='0%';$('returnStatus').textContent='正在模拟从临时缓冲区分包回传，不传输真实音频。';$('cancelReturn').disabled=false;syncConnection();
    returnTimer=setInterval(()=>{if(!app.connected){cancelReturn('连接已断开，回传预览中止；未保存文件。');return;}returning.progress=Math.min(100,returning.progress+10);$('returnPercent').textContent=returning.progress+'%';$('returnProgress').style.width=returning.progress+'%';if(returning.progress===100){const done=returning.file;clearInterval(returnTimer);returnTimer=null;returning=null;if(!phone.some(item=>item.id===done.id))phone.push(done);$('returnStatus').textContent='回传流程预览完成；没有接收、校验或保存真实音频文件。';$('cancelReturn').disabled=true;syncConnection();}},120);
  }
  $('cancelReturn').addEventListener('click',()=>cancelReturn());$('refreshRecordings').addEventListener('click',()=>{renderRecordings();app.toast(app.native?'录音目录查询协议待接入，尚未访问板端内存。':'已刷新临时缓冲示例，没有访问真实内存。');});
  function renderTimeline(){
    if(document.hidden || $('session').hidden)return;
    const view=E.view();$('loopStatus').textContent=!view.running?'待录入 / 已停止':view.counting?'预备拍':E.recording?(view.beat<E.recording.start?'等待叠录':'录入中'):E.stopBeat!==null?'等待小节结束':'循环合奏中';$('loopStatus').classList.toggle('recording',Boolean(E.recording&&!view.counting&&view.beat>=E.recording.start));
    $('loopBpmDisplay').textContent=String(E.bpm);const position=view.bar+' <em>/ '+view.pulse+'</em>';if($('loopPosition').innerHTML!==position)$('loopPosition').innerHTML=position;$('loopCountIn').textContent=view.counting?String(view.remaining):'4/4';$('loopCountIn').classList.toggle('counting',view.counting);$('loopProgress').style.width='100%';$('loopProgress').style.transform='scaleX('+view.progress+')';$('loopNotice').textContent=E.notice;
    $$('#beatDots i').forEach((dot,i)=>dot.classList.toggle('active',view.running&&!view.counting&&i===view.pulse-1));
    ['loopBpm','loopBars','loopQuantize','loopCount','tapTempo','padMode'].forEach(id=>$(id).disabled=view.running);$('loopBars').disabled=view.running||E.tracks.some(t=>t.events.length);$('loopPlay').disabled=view.running||(!E.tracks.some(t=>t.events.length)&&!E.accompaniment);$('loopEnd').disabled=!view.running||E.stopBeat!==null;$('loopPanic').disabled=!view.running;
    $('loopConfigSummary').textContent=E.bars+' 小节 · '+(E.grid===0?'自由节奏':E.grid===0.25?'1/16 量化':'1/8 量化')+' · '+E.countIn+' 拍预备';$('liveInputStatus').textContent=view.counting?'预备拍 '+view.remaining:E.recording?(view.beat<E.recording.start?'下一轮开始录入':'录入中，松开结束音符'):'自由演奏预览';
    $('inputEnd').disabled=!view.running||E.stopBeat!==null;$('inputPanic').disabled=!view.running;
    const notes=[...new Set([...view.sounding,...live.values()])];$('soundingNotes').textContent='当前合奏音符：'+(notes.length?notes.map(app.noteName).join(' · '):'—');
    $$('[data-pattern]').forEach(button=>button.classList.toggle('active',Number(button.dataset.pattern)===E.pattern));$('patternPending').textContent=E.nextPattern?'等待下一小节切换到鼓型 '+(E.nextPattern.index===0?'A':'B'):'当前鼓型 '+(E.pattern===0?'A':'B')+'；运行中切换在下一小节生效。';
    const stamp=JSON.stringify([E.running,E.recording&&E.recording.index,E.recording&&view.beat>=E.recording.start,E.stopBeat,E.tracks.map(t=>[t.events.length,t.mute,t.solo])]);if(stamp!==lastTrackState){lastTrackState=stamp;renderTracks();}
  }
  // Engine timing continues offscreen; DOM painting runs only on the visible page.
  let visualFrame=null,engineTimer=null;
  function paint(){
    visualFrame=null;
    if(document.hidden)return;
    renderTimeline();
    if(captureStart!==null&&!$('recordings').hidden){
      const text=clock(Math.min(120,(performance.now()-captureStart)/1000));
      if($('captureTime').textContent!==text)$('captureTime').textContent=text;
    }
  }
  function requestPaint(){if(!document.hidden&&visualFrame===null)visualFrame=requestAnimationFrame(paint);}
  function tickEngine(){
    engineTimer=null;E.tick();
    if(captureStart!==null&&(performance.now()-captureStart)>=120000)finishCapture();
    if((!$('session').hidden&&E.running)||(!$('recordings').hidden&&captureStart!==null))requestPaint();
    if(E.running||captureStart!==null)engineTimer=setTimeout(tickEngine,50);else requestPaint();
  }
  function wake(){requestPaint();if(engineTimer===null&&(E.running||captureStart!==null))engineTimer=setTimeout(tickEngine,50);}
  ['click','input','change','pointerdown','pointerup','pointercancel','keydown','keyup'].forEach(type=>document.addEventListener(type,wake));
  window.addEventListener('tang:page',wake);document.addEventListener('visibilitychange',wake);
  buildTracks();renderControlPads();syncConnection();wake();
  window.TangSession={engine:E,get phone(){return phone.slice();},get recordings(){return recordings.slice();}};
})();
