(function (root) {
  'use strict';
  const MIN = 53, MAX = 84;
  function makeNotes(pitches, duration) {
    const step = duration / pitches.length;
    return pitches.map((midi, index) => ({ midi, time: index * step, duration: step * 0.85, velocity: 0.8 }));
  }
  const catalog = [
    { id: 'twinkle', name: '小星星', subtitle: '熟悉的旋律，先体验完整流程。', tag: '直接适配', bpm: 100, duration: 24, pitches: [60,60,67,67,69,69,67,65,65,64,64,62,62,60], credit: '传统旋律 · 内置教学片段' },
    { id: 'high', name: '高音旋律练习', subtitle: '体验整体降八度，让高音落回键盘。', tag: '需要移调', bpm: 120, duration: 72, pitches: [84,86,88,89,91,93,95,96,95,93,91,89,88,86,84,88,91,96], credit: '项目自编 · 内置音符序列' },
    { id: 'wide', name: '宽音域挑战', subtitle: '先检查整段，再尝试截取前 60 秒。', tag: '需要选片段', bpm: 90, duration: 108, pitches: [48,52,55,60,62,60,55,52,48,55,60,64,72,79,84,88,84,72], credit: '项目自编 · 内置音符序列' }
  ];
  function score(id) {
    const item = catalog.find(item => item.id === id) || catalog[0];
    return { ...item, tracks: [
      { id: 'melody', name: '主旋律', percussion: false, notes: makeNotes(item.pitches, item.duration) },
      { id: 'bass', name: '低音声部', percussion: false, notes: makeNotes([36,43,41,43,36,43,41,36], item.duration) },
      { id: 'drums', name: '鼓轨（不参与旋律适配）', percussion: true, notes: makeNotes([36,42,38,42], item.duration) }
    ] };
  }
  function clip(notes, start, end) {
    return notes.filter(n => n.time < end && n.time + n.duration > start).map(n => ({ ...n, time: Math.max(n.time, start) - start, duration: Math.min(n.time + n.duration, end) - Math.max(n.time, start) }));
  }
  function analyze(notes, shift) {
    if (!notes.length) return { empty: true, ok: false, count: 0 };
    let low=Infinity,high=-Infinity,originalOut=0,remaining=0;
    for(const note of notes){const value=note.midi;low=Math.min(low,value);high=Math.max(high,value);if(value<MIN||value>MAX)originalOut++;if(value+shift<MIN||value+shift>MAX)remaining++;}
    const shifts = [];
    for (let k = MIN - low; k <= MAX - high; k++) shifts.push(k);
    const octaves = shifts.filter(k => k % 12 === 0);
    const choices = octaves.length ? octaves : shifts;
    choices.sort((a,b) => Math.abs(a) - Math.abs(b) || a - b);
    return { empty: false, count: notes.length, low, high, afterLow: low + shift, afterHigh: high + shift,
      originalOut, remaining,
      suggestion: choices.length ? choices[0] : null, possible: shifts.length > 0,
      ok: Number.isInteger(shift) && remaining===0 };
  }
  function name(value) {
    if (value === -1) return '禁用';
    if (!Number.isInteger(value) || value < 0 || value > 127) return '—';
    return ['C','C♯','D','D♯','E','F','F♯','G','G♯','A','A♯','B'][value % 12] + (Math.floor(value / 12) - 1);
  }
  root.ScoreFit = { MIN, MAX, catalog, score, clip, analyze, name };
})(typeof window === 'undefined' ? globalThis : window);
