(function(root){
  'use strict';
  function text(value){
    if(!value||Array.from(value).some(c=>c.charCodeAt(0)>255))return value;
    const bytes=Uint8Array.from(value,c=>c.charCodeAt(0));
    try{return new TextDecoder('utf-8',{fatal:true}).decode(bytes);}catch(_){try{return new TextDecoder('gb18030',{fatal:true}).decode(bytes);}catch(_){return value;}}
  }
  function parse(bytes,name){
    if(!bytes||bytes.length<14||bytes.length>2*1024*1024)throw Error('MIDI 大小无效，最多 2 MB。');
    if(String.fromCharCode(...bytes.slice(0,4))!=='MThd')throw Error('请选择标准 MIDI 文件。');
    if(bytes[8]!==0||bytes[9]>1)throw Error('仅支持 MIDI 类型 0 / 1。');
    if(bytes[12]&128)throw Error('暂不支持 SMPTE 时间制，请转换为 PPQ。');
    if(((bytes[12]<<8)|bytes[13])===0)throw Error('MIDI 时间分辨率无效。');
    const midi=new root.Midi(bytes),tracks=[];
    let total=0,duration=0;
    for(let index=0;index<midi.tracks.length;index++){
      const source=midi.tracks[index];if(!source.notes.length)continue;
      total+=source.notes.length;if(total>50000)throw Error('音符超过 50000 个，请先选择较短的 MIDI。');
      const percussion=Boolean(source.instrument.percussion);
      const pedal=(source.controlChanges[64]||[]).slice().sort((a,b)=>a.time-b.time);
      const intervals=[];let down=null;
      for(const event of pedal){if(event.value>=0.5){if(down===null)down=event.time;}else if(down!==null){intervals.push([down,event.time]);down=null;}}
      const trackEnd=source.notes.reduce((max,n)=>Math.max(max,n.time+n.duration),0);
      if(down!==null)intervals.push([down,trackEnd]);
      const notes=source.notes.map(n=>({midi:n.midi,time:n.time,duration:n.duration,velocity:n.velocity})).sort((a,b)=>a.time-b.time||a.midi-b.midi);
      // A pedal-held note ends at pedal release or the next strike of the same pitch.
      const next=new Map();
      for(let i=notes.length-1;i>=0;i--){const n=notes[i];let end=n.time+n.duration;
        if(!Number.isInteger(n.midi)||n.midi<0||n.midi>127||!Number.isFinite(n.time)||!Number.isFinite(end)||n.time<0||n.duration<0)throw Error('MIDI 含无效音符或时间。');
        if(!percussion){let lo=0,hi=intervals.length;while(lo<hi){const mid=(lo+hi)>>1;if(intervals[mid][0]<=end)lo=mid+1;else hi=mid;}const hold=intervals[lo-1];if(hold&&end<hold[1])end=Math.min(hold[1],next.has(n.midi)?next.get(n.midi):Infinity);}
        n.duration=Math.max(0,end-n.time);duration=Math.max(duration,end);next.set(n.midi,n.time);
      }
      tracks.push({id:'track-'+index,name:(text(source.name)||source.instrument.name||'声部 '+(index+1))+(percussion?'（鼓轨）':''),percussion,channel:source.channel,program:source.instrument.number,notes:notes.filter(n=>n.duration>0)});
    }
    if(!tracks.some(t=>!t.percussion&&t.notes.length))throw Error('此文件没有可供 32 键演奏的旋律声部。鼓轨不参与移调。');
    if(!Number.isFinite(duration)||duration<=0||duration>6*3600)throw Error('曲谱时长无效或超过 6 小时。');
    const tempos=midi.header.tempos||[],bpm=tempos.length?tempos[0].bpm:120;
    return {id:'midi-'+Date.now(),name,subtitle:tracks.length+' 个含音符声部 · '+total+' 个音符 · 请选择演奏声部',tag:'MIDI',bpm:Math.round(bpm*100)/100,duration,variableTempo:tempos.length>1,credit:'用户导入的标准 MIDI',tracks};
  }
  root.TangMidi={parse};
})(typeof window==='undefined'?globalThis:window);
