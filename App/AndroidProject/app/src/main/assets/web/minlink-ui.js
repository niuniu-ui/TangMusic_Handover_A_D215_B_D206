(() => {
  'use strict';
  const $=id=>document.getElementById(id), desktop=Boolean(window.TangDesktopLab),preview=Boolean(window.TangPreview);
  const groups=[['输出',[[1,'总音量',127],[2,'电子琴音量',127],[3,'静音',1],[4,'音区组',3]]],['混响',[[16,'开启混响',1],[17,'空间',127],[18,'衰减',127],[19,'混合',127]]],['延迟',[[32,'开启延迟',1],[33,'延迟时间',127],[34,'反馈',127],[35,'混合',127]]],['合唱',[[48,'开启合唱',1],[49,'速率',127],[50,'深度',127],[51,'混合',127]]]];
  let state={phase:'offline',ready:false,busy:false,parameters:{},revision:0},channel=false,dirty=false,draftRevision=0,message='',tone='',awaiting=false;
  const inputs=new Map();let transport={},reading=false,readStarted=false;
  const disable=(id,value)=>{const element=$(id);value=Boolean(value);if(element.disabled!==value)element.disabled=value;};
  for(const [name,params] of groups){
    const section=document.createElement('section');section.className='parameter-section';const heading=document.createElement('h3');heading.textContent=name;section.append(heading);
    for(const [id,label,max] of params){
      const row=document.createElement('div');row.className='parameter-control';const text=document.createElement('label');text.htmlFor='param-'+id;text.textContent=label+(max===127?' · 0–127':'');
      const input=document.createElement(id===4?'select':'input');input.id='param-'+id;input.dataset.parameter=id;
      if(id===4){['C1–G3','C2–G4','C3–G5（默认）','C4–G6'].forEach((label,value)=>{const o=new Option(label,String(value));input.append(o);});}
      else if(max===1)input.type='checkbox';else{input.type='number';input.min=0;input.max=max;input.step=1;input.required=true;}
      input.addEventListener('input',()=>{if(!dirty)draftRevision=state.revision;dirty=true;message='有未提交修改；点击应用后等待设备确认。';tone='dirty';render();});
      inputs.set(id,input);row.append(text,input);section.append(row);
    }
    $('parameterInputs').append(section);
  }
  // Only the raw group number is normative; exact sounding range follows board key mapping.
  [...inputs.get(4).options].forEach((o,i)=>o.textContent='组 '+i+(i===2?'（当前工程默认）':''));
  function invoke(name,...args){try{window.TangAndroid[name](...args);}catch(e){awaiting=false;reading=false;readStarted=false;message=e.message;tone='error';render();}}
  function render(){
    const ready=channel&&state.ready,phase=state.phase;
    const label=ready?(preview?'预览已连接':'FPGA 已确认'):phase==='error'?'连接失效':channel?'确认协议中':transport.connecting?'连接中':transport.scanning?'扫描中':'未连接';
    $('protocolPhase').textContent=label;
    $('protocolDetail').textContent=preview&&ready?'已模拟 HELLO、PING 和参数回读，可体验下方参数修改。':state.error||(ready?(desktop?'Java 客户端与 RTL 端已确认，当前为电脑字节通道。':'HELLO、PING 与参数回读已完成。'):channel?'等待设备完成握手与参数回读。':desktop?'使用上方联调按钮连接，或扫描电脑 RTL 端。':'请先扫描并连接 BLE 模块。');
    $('helloStep').className=phase==='confirming'||ready?'done':phase==='hello'?'current':'';
    $('pingStep').className=ready||phase==='confirming'&&state.pendingCommand===257?'done':phase==='confirming'?'current':'';
    $('paramsStep').className=ready?'done':phase==='confirming'&&state.pendingCommand===257?'current':'';
    $('protocolSession').textContent=channel&&state.session?state.session:'—';$('protocolLatency').textContent=state.pingMs>=0?state.pingMs+' ms':'—';
    // TMCP already queues user requests behind heartbeat/status traffic. Those
    // background transactions must not repeatedly dim the controls.
    disable('protocolReconnect',!channel);disable('protocolPing',!ready);
    disable('parameterFields',!ready||awaiting||reading);disable('applyParameters',!ready||!dirty||awaiting||reading);disable('readParameters',!ready||awaiting||reading);
    $('parameterRevision').textContent=Object.keys(state.parameters).length?'版本 '+state.revision:'尚未读取';
    if(!dirty)for(const [id,input] of inputs){const value=state.parameters[id];if(value!==undefined){if(input.type==='checkbox')input.checked=Boolean(value);else input.value=value;}}
    const conflict=dirty&&state.revision!==draftRevision;
    $('parameterMessage').textContent=conflict?'设备已更新至版本 '+state.revision+'；当前草稿基于版本 '+draftRevision+'，提交将检查冲突。':message||(ready?'已读取设备当前值。音量以百分比显示，音效参数范围为 0–127。':'完成握手后读取设备当前值。');
    $('parameterMessage').className='parameter-message '+(conflict?'dirty':tone);
    $('headerDevice').textContent=label;$('headerDevice').parentElement.classList.toggle('connected',ready);$('deviceStatusBadge').textContent=label;$('deviceStatusBadge').classList.toggle('ready',ready);$('connectionOrb').classList.toggle('connected',ready);
    $('connectionTitle').textContent=ready?(preview?'连接流程预览完成':'FPGA 通信已就绪'):channel?'通道已建立，等待 FPGA 确认':'准备连接';
    $('connectionDetail').textContent=preview?'模拟设备连接与参数读写，未向真实 FPGA 发送数据。':desktop?'电脑联调：Java 客户端 ↔ RTL 仿真；未连接真实无线模块。':ready?'可读取和修改设备参数，连接状态由心跳维持。':'BLE 连通后仍须完成 FPGA 协议握手。';
    if(!channel){$('connectionTitle').textContent=transport.connecting?'正在连接设备':transport.connected?'正在配置收发通道':transport.scanning?'正在扫描周围设备':'准备连接';$('connectionDetail').textContent='点击扫描后选择你的乐器模块，已自动隐藏其他蓝牙设备。';} if(channel){$('sendData').disabled=true;$('sendConnectionState').textContent='协议会话中，使用参数面板发送';}
  }
  $('parameterForm').addEventListener('submit',e=>{e.preventDefault();if(!dirty||!state.ready)return;const values={};for(const [id,input] of inputs){if(!input.checkValidity())return input.reportValidity();values[id]=input.type==='checkbox'?(input.checked?1:0):Number(input.value);}awaiting=true;message='等待 FPGA 应答，尚未确认应用。';tone='dirty';render();invoke('setParameters',JSON.stringify({expectedRevision:draftRevision,values}));});
  $('readParameters').onclick=()=>{dirty=false;awaiting=false;reading=true;readStarted=false;message='正在读取设备当前值，草稿已放弃。';tone='';render();invoke('readParameters');};
  $('protocolPing').onclick=()=>invoke('protocolPing');$('protocolReconnect').onclick=()=>invoke('protocolReconnect');
  window.MinlinkUI={get state(){return state;},refresh(value){transport=value;channel=Boolean(value.channelReady);render();},event(event){const d=event.data||{};if(event.type==='protocolState'){const wasReady=state.ready;state=d;if(!state.ready){awaiting=false;reading=false;readStarted=false;if(state.phase==='offline'){dirty=false;message='';tone='';}}else if(reading){if(state.pendingCommand===0x101)readStarted=true;else if(readStarted){reading=false;readStarted=false;message='设备当前参数已读取。';}}render();if(preview&&state.ready&&!wasReady)window.TangApp.toast('连接流程预览完成，可体验参数读写。');}else if(event.type==='parameterResult'){awaiting=false;reading=false;readStarted=false;if(d.success){dirty=false;message=preview?'预览参数已更新。':'设备已确认参数修改。';tone='success';}else{message=d.message||'设备拒绝修改。';tone='error';}render();}else if(event.type==='protocolLog'&&window.TangApp)window.TangApp.log(d.message);}};
  render();
})();
