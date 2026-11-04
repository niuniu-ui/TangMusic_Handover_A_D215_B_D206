(function(root) {
  'use strict';
  class SessionEngine {
    constructor(now) {
      this.now=now||(()=>performance.now()); this.bpm=100;this.bars=1;this.grid=0.25;this.countIn=4;
      this.running=false;this.origin=0;this.recording=null;this.pending=new Map();this.stopBeat=null;this.notice='先录入一个乐句，再逐轨叠加。';
      this.accompaniment=false;this.pattern=0;this.nextPattern=null;this.tracks=Array.from({length:4},(_,i)=>({name:['旋律','和弦','低音','打击'][i],instrument:['钢琴','弦乐','贝斯','鼓'][i],events:[],mute:false,solo:false,volume:80,history:null}));
    }
    get length(){return this.bars*4;}
    beat(){return this.running?(this.now()-this.origin)*this.bpm/60000:0;}
    configure({bpm,bars,grid,countIn}){
      if(this.running)throw new Error('请先结束循环，再修改速度、长度和量化。');
      if(!Number.isFinite(bpm)||bpm<40||bpm>240||![1,2,4].includes(bars)||![0,0.25,0.5].includes(grid)||![0,4].includes(countIn))throw new Error('循环参数无效。');
      if(bars!==this.bars&&this.tracks.some(t=>t.events.length))throw new Error('已有乐句时，请先清空各轨或创建新合奏，再修改循环长度。');
      Object.assign(this,{bpm,bars,grid,countIn});
    }
    startClock(){this.origin=this.now()+this.countIn*60000/this.bpm;this.running=true;this.stopBeat=null;}
    record(index){
      this.tick();if(this.recording)throw new Error('当前已有一条轨道等待或正在录入。');
      const track=this.tracks[index];if(!track)throw new Error('轨道不存在。');
      const wasRunning=this.running;if(!wasRunning)this.startClock();
      const beat=this.beat();const start=beat<0?0:wasRunning?(Math.floor(beat/this.length)+1)*this.length:0;
      track.history=track.events.map(e=>({...e}));
      this.recording={index,start,end:start+this.length,added:0};this.notice=track.name+'：'+(wasRunning?'下一轮开始录入':'预备拍后开始录入')+'，一轮后自动循环。';
    }
    noteOn(note,velocity,key,percussion){
      this.tick();const rec=this.recording,beat=this.beat();if(!rec||beat<rec.start||beat>=rec.end)return false;
      if(!Number.isInteger(note)||note<0||note>127)return false;
      const id=key||String(note);if(this.pending.has(id))return false;
      this.pending.set(id,{note,velocity:Math.max(1,Math.min(127,velocity||100)),beat,track:rec.index,percussion:Boolean(percussion)||this.tracks[rec.index].instrument==='鼓'});return true;
    }
    noteOff(key,atBeat){
      const note=this.pending.get(key);if(!note)return;
      this.pending.delete(key);const rec=this.recording;if(!rec||note.track!==rec.index)return;
      const end=Math.min(atBeat===undefined?this.beat():atBeat,rec.end);
      let start=Math.max(0,note.beat-rec.start),duration=Math.max(0.04,end-note.beat);
      if(this.grid){start=Math.round(start/this.grid)*this.grid;duration=Math.max(this.grid,Math.round(duration/this.grid)*this.grid);}
      start=Math.min(this.length-0.04,Math.max(0,start));duration=Math.min(duration,this.length-start);
      this.tracks[rec.index].events.push({note:note.note,velocity:note.velocity,percussion:note.percussion,start,duration});rec.added++;
    }
    finishRecord(atBeat){
      const rec=this.recording;if(!rec)return;
      for(const id of [...this.pending.keys()])this.noteOff(id,atBeat);
      this.tracks[rec.index].events.sort((a,b)=>a.start-b.start);this.notice=rec.added?'已录入 '+rec.added+' 个事件，乐句进入循环。':'本轮未录到事件，原有乐句保留。';this.recording=null;
    }
    start(){if(this.running)return;if(!this.tracks.some(t=>t.events.length)&&!this.accompaniment)throw new Error('请先录入乐句，或开启鼓伴奏。');this.startClock();this.notice='预备拍后播放循环；可继续选择其他轨叠录。';}
    normalStop(){if(!this.running)return;const beat=this.beat();if(beat<0){this.stop();return;}this.stopBeat=(Math.floor(beat/4)+1)*4;this.notice='已请求结束，将在当前小节结束后停止。';}
    stop(){
      if(this.recording)this.finishRecord(Math.max(0,this.beat()));
      this.pending.clear();this.running=false;this.stopBeat=null;this.nextPattern=null;this.notice='已停止；循环轨道保留，活动音符已清理。';
    }
    clear(index){if(this.running)throw new Error('请先停止，再清空轨道。');const t=this.tracks[index];t.history=t.events.map(e=>({...e}));t.events=[];this.notice='已清空 '+t.name+'，可撤销。';}
    undo(index){if(this.running)throw new Error('请先停止，再撤销上一轮。');const t=this.tracks[index];if(t.history===null)throw new Error('这条轨道没有可撤销的录入。');const previous=t.events;t.events=t.history;t.history=previous;this.notice='已撤销／恢复 '+t.name+' 的上一轮修改。';}
    setPattern(index){
      if(![0,1].includes(index))return;
      if(this.running&&this.beat()>=0){this.nextPattern={index,beat:(Math.floor(this.beat()/4)+1)*4};this.notice='鼓型将在下一小节切换。';}
      else {this.pattern=index;this.nextPattern=null;}
    }
    tick(){
      if(!this.running)return;const beat=this.beat();
      if(this.stopBeat!==null&&beat>=this.stopBeat){const boundary=this.stopBeat;if(this.recording)this.finishRecord(boundary);this.running=false;this.pending.clear();this.stopBeat=null;this.nextPattern=null;this.notice='已在小节边界结束，循环轨道保留。';return;}
      if(this.nextPattern&&beat>=this.nextPattern.beat){this.pattern=this.nextPattern.index;this.nextPattern=null;}
      if(this.recording&&beat>=this.recording.end)this.finishRecord(this.recording.end);
      if(beat>=0&&!this.recording&&!this.accompaniment&&!this.tracks.some(t=>t.events.length)){this.running=false;this.notice='没有录到事件，请重新录入。';}
    }
    view(){
      this.tick();const beat=this.beat(),phase=((beat%this.length)+this.length)%this.length;const solo=this.tracks.some(t=>t.solo);
      const drumRules=this.pattern===0?[[0,36],[1,38],[2,36],[3,38],[0,42],[0.5,42],[1,42],[1.5,42],[2,42],[2.5,42],[3,42],[3.5,42]]:[[0,36],[1.5,36],[2.5,36],[1,38],[3,38],[0,42],[0.5,42],[1,42],[1.5,42],[2,42],[2.5,42],[3,42],[3.5,42]];
      const drums=this.running&&beat>=0&&this.accompaniment?drumRules.filter(([at])=>phase%4>=at&&phase%4<at+0.12).map(([,note])=>note):[];
      return {running:this.running,beat,phase,counting:this.running&&beat<0,remaining:this.running&&beat<0?Math.ceil(-beat):0,bar:this.running&&beat>=0?Math.floor(phase/4)+1:1,pulse:this.running&&beat>=0?Math.floor(phase%4)+1:1,progress:this.running&&beat>=0?phase/this.length:0,
        sounding:this.running&&beat>=0?[...this.tracks.flatMap(t=>(!t.mute&&t.volume>0&&(!solo||t.solo))?t.events.filter(e=>phase>=e.start&&phase<e.start+e.duration).map(e=>e.note):[]),...drums]:[]};
    }
    export(){return {version:1,type:'note-event-looper',bpm:this.bpm,timeSignature:[4,4],bars:this.bars,gridBeats:this.grid,accompaniment:{enabled:this.accompaniment,pattern:this.pattern},tracks:this.tracks.map(t=>({name:t.name,instrument:t.instrument,mute:t.mute,solo:t.solo,volume:t.volume,events:t.events.map(e=>({...e}))}))};}
  }
  root.SessionEngine=SessionEngine;
})(typeof window==='undefined'?globalThis:window);
