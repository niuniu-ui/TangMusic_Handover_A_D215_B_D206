'use strict';
importScripts('vendor/midi-2.0.28.js', 'midi-adapter.js');
self.onmessage = ({data}) => {
  try {
    const bytes=typeof data.buffer==='string'?Uint8Array.from(atob(data.buffer),c=>c.charCodeAt(0)):new Uint8Array(data.buffer);
    const score=TangMidi.parse(bytes,data.name),transfers=[];
    // Transfer numeric buffers; cloning tens of thousands of note objects can stall the UI.
    for(const track of score.tracks){
      const packed=new Float64Array(track.notes.length*4);
      track.notes.forEach((note,index)=>{const offset=index*4;packed[offset]=note.midi;packed[offset+1]=note.time;packed[offset+2]=note.duration;packed[offset+3]=note.velocity;});
      track.noteCount=track.notes.length;track.packedNotes=packed;delete track.notes;transfers.push(packed.buffer);
    }
    self.postMessage({score},transfers);
  }
  catch (error) {self.postMessage({error:error.message || 'MIDI 解析失败'});}
};
