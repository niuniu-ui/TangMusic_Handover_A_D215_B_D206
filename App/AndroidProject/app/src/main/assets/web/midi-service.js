(() => {
  'use strict';
  window.TangMidiService = {
    clip(track,start,end) {
      if(!track.packedNotes)return window.ScoreFit.clip(track.notes,start,end);
      const data=track.packedNotes,notes=[];
      for(let i=0;i<data.length;i+=4){const at=data[i+1],until=at+data[i+2];if(at>=end)break;if(until>start)notes.push({midi:data[i],time:Math.max(at,start)-start,duration:Math.min(until,end)-Math.max(at,start),velocity:data[i+3]});}
      return notes;
    },
    parse(buffer, name, signal) {
      return new Promise((resolve, reject) => {
        if (signal?.aborted) return reject(new DOMException('已取消', 'AbortError'));
        let worker, timeout;
        const cleanup = () => {clearTimeout(timeout); signal?.removeEventListener('abort', abort); worker?.terminate();};
        const fail = error => {cleanup(); reject(error);};
        const abort = () => fail(new DOMException('已取消', 'AbortError'));
        try {worker = new Worker('midi-worker.js');}
        catch (_) {return fail(Error('曲谱解析线程无法启动，请更新 Android System WebView 后重试。'));}
        signal?.addEventListener('abort', abort, {once:true});
        worker.onmessage = ({data}) => {cleanup(); data.error ? reject(Error(data.error)) : resolve(data.score);};
        worker.onerror = () => fail(Error('曲谱解析线程无法启动，请更新 Android System WebView 后重试。'));
        timeout = setTimeout(() => fail(Error('曲谱解析超时，请选择较短的 MIDI 文件。')), 15000);
        // Transfer a copy: retain the original buffer for offline storage and export.
        const copy = buffer.slice(0); worker.postMessage({buffer:copy,name}, typeof copy==='string'?[]:[copy]);
      });
    }
  };
})();
