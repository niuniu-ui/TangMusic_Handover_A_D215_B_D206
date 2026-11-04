package cn.tangmusic.protocol;

import java.util.List;
import java.util.zip.CRC32;

/** Final, quantized note object. Invalid or overlapping notes are never silently dropped. */
public final class ScoreObject {
    public record Note(long startUs,long durationUs,int pitch,int velocity) {}
    public final byte[] bytes;
    public final int count;public final long durationUs,crc32;
    public ScoreObject(List<Note> notes,long durationUs,int limit){
        if(notes.isEmpty()||notes.size()>limit||durationUs<1||durationUs>120000000)throw new IllegalArgumentException("曲谱最多 120 秒，音符数量不能超过设备容量，请缩短片段");
        this.count=notes.size();this.durationUs=durationUs;this.bytes=new byte[count*10];
        long previous=-1;int previousPitch=-1;long[] ends=new long[32];int i=0;
        for(Note n:notes){
            if(n.pitch<53||n.pitch>84||n.velocity<1||n.velocity>127||n.startUs<0||n.durationUs<1||n.startUs>durationUs||n.durationUs>durationUs-n.startUs)throw new IllegalArgumentException("第 "+(i+1)+" 个音符的音域、力度或时长无效");
            if(n.startUs<previous||(n.startUs==previous&&n.pitch<=previousPitch))throw new IllegalArgumentException("音符需按时间和音高排序，不能重复");
            if(n.startUs<ends[n.pitch-53])throw new IllegalArgumentException("同音高的音符发生重叠，请换声部或调整练习片段");
            TangFrameCodec.put(bytes,i*10,n.startUs,4);TangFrameCodec.put(bytes,i*10+4,n.durationUs,4);bytes[i*10+8]=(byte)n.pitch;bytes[i*10+9]=(byte)n.velocity;
            ends[n.pitch-53]=n.startUs+n.durationUs;previous=n.startUs;previousPitch=n.pitch;i++;
        }
        CRC32 crc=new CRC32();crc.update(bytes);this.crc32=crc.getValue();
    }
}
