(()=>{'use strict';
const $=id=>document.getElementById(id);let state={};
const call=(method,...args)=>{if(!window.TangAndroid){TangApp.toast('请在手机 App 中连接真实设备');return}try{TangAndroid[method](...args)}catch(e){TangApp.toast(e.message)}};
function render(){
 const ready=!!window.MinlinkUI?.state.ready&&TangApp.connected,available=ready&&state.supported;
 const disabled=!!(!available||!TangApp.scoreAdapted()||state.busy||state.uploading||state.active);
 if($('uploadScore').disabled!==disabled)$('uploadScore').disabled=disabled;
 $('uploadScore').classList.toggle('busy',!!state.uploading);
 $('uploadBadge').textContent=state.uploading?'上传中':state.valid?'板端已保存':available?'可以上传':ready?'需要新版固件':'先连接乐器';
 $('uploadHelp').textContent=state.message||'确认声部、片段和移调后，将曲谱发送到 FPGA。';
 const percent=Math.floor((state.progress||0)/10);$('uploadPercent').textContent=percent+'%';$('uploadBar').style.width=percent+'%';$('uploadProgress').setAttribute('aria-valuenow',String(percent));
 $('cancelScoreUpload').disabled=!state.uploading;
 $('refreshBoardScore').disabled=!available||state.busy||state.uploading;
 const group=Number(window.MinlinkUI?.state.parameters?.[4]);
 $('guideWait').disabled=$('guideTimed').disabled=!available||!state.valid||state.active||state.busy||state.uploading||group!==2;
 $('guideStop').disabled=!available||!state.valid||state.busy||state.uploading;
 $('guideStatus').textContent=!available?'连接支持曲谱引导的固件后可用':group!==2?'请在调音页将音区设为组 2 并应用，再开始引导。':state.active?`${state.waiting?'弹对再继续':'跟随曲谱'} · ${(state.elapsedUs/1e6).toFixed(1)} 秒 · ${state.current}/${state.total} 音符`:state.completed?'这一段引导已结束':state.valid?`FPGA 中已保存 ${state.total} 个音符，可独立引导`:'先上传一段已适配的曲谱';
 const names=[];for(let k=0;k<32;k++)if((Number(state.targetKeys)>>>k)&1)names.push(TangApp.noteName(53+k));$('guideTargets').textContent=names.length?'当前琴键：'+names.join(' · '):'当前没有需要按下的琴键';
}
window.TangScore={refresh:render,upload(){try{const score=TangApp.boardScore();if(confirm('发送后会替换 FPGA 中原有的曲谱。手机曲库不会删除，继续上传？'))call('uploadScore',JSON.stringify(score))}catch(e){TangApp.toast(e.message)}}};
$('cancelScoreUpload').onclick=()=>call('scoreAction','cancel');$('refreshBoardScore').onclick=()=>call('scoreAction','refresh');
$('guideWait').onclick=()=>call('scoreAction','wait');$('guideTimed').onclick=()=>call('scoreAction','timed');$('guideStop').onclick=()=>call('scoreAction','stop');
const previous=window.TangNativeEvent;window.TangNativeEvent=event=>{if(event.type==='scoreState'){state=event.data||{};TangApp.setBoardTransfer(!!state.uploading);render();return}previous?.(event);if(['protocolState','channelReady','disconnected','ready'].includes(event.type))render();if(event.type==='ready')call('scoreStatus')};
render();if(window.TangAndroid)call('scoreStatus');
})();
