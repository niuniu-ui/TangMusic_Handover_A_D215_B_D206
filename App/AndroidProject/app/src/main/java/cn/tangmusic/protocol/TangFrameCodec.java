package cn.tangmusic.protocol;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.zip.CRC32;

/** Transport-independent TMCP codec. It does not mark any FPGA feature as implemented. */
public final class TangFrameCodec {
    private TangFrameCodec() {}

    public static final class Frame {
        public final int major,kind,command,sequence;
        public final long session;
        private final byte[] data;
        public Frame(int major,int kind,int command,int sequence,long session,byte[] payload){
            check(major,255);check(command,65535);check(sequence,65535);check(session,0xFFFFFFFFL);
            if(kind<0||kind>2||(sequence==0)!=(kind==2))throw new IllegalArgumentException("Invalid kind or sequence shape");
            if(payload==null||payload.length>TangProtocolV1.MAX_PAYLOAD)throw new IllegalArgumentException("Payload exceeds 256 bytes");
            this.major=major;this.kind=kind;this.command=command;this.sequence=sequence;this.session=session;this.data=payload.clone();
        }
        public byte[] payload(){return data.clone();}
        public byte[] encode(){
            byte[] wire=new byte[16+data.length];wire[0]=0x54;wire[1]=0x4D;
            wire[2]=(byte)major;wire[3]=(byte)kind;put(wire,4,command,2);put(wire,6,sequence,2);put(wire,8,session,4);put(wire,12,data.length,2);
            System.arraycopy(data,0,wire,14,data.length);put(wire,wire.length-2,crc16(wire,2,wire.length-4),2);return wire;
        }
    }

    private static void check(long value,long maximum){if(value<0||value>maximum)throw new IllegalArgumentException("Unsigned value out of range");}
    public static int crc16(byte[] data,int offset,int length){
        if(offset<0||length<0||offset>data.length-length)throw new IllegalArgumentException("CRC range");
        int crc=0xFFFF;for(int i=offset;i<offset+length;i++){crc^=(data[i]&255)<<8;for(int bit=0;bit<8;bit++)crc=((crc&0x8000)!=0?(crc<<1)^0x1021:crc<<1)&0xFFFF;}return crc;
    }
    public static long crc32(byte[] data){CRC32 crc=new CRC32();crc.update(data);return crc.getValue();}
    public static void put(byte[] data,int offset,long value,int width){
        if(width<1||width>8||offset<0||offset>data.length-width)throw new IllegalArgumentException("LE write range");
        for(int i=0;i<width;i++)data[offset+i]=(byte)(value>>>(8*i));
    }
    public static long get(byte[] data,int offset,int width){
        if(width<1||width>8||offset<0||offset>data.length-width)throw new IllegalArgumentException("LE read range");
        long value=0;for(int i=0;i<width;i++)value|=(long)(data[offset+i]&255)<<(8*i);return value;
    }
    public static Frame decode(byte[] wire){
        if(wire.length<16||wire[0]!=0x54||wire[1]!=0x4D)throw new IllegalArgumentException("Magic or length");
        int length=(int)get(wire,12,2);
        if(length>TangProtocolV1.MAX_PAYLOAD||wire.length!=length+16)throw new IllegalArgumentException("Payload length");
        if(get(wire,wire.length-2,2)!=crc16(wire,2,wire.length-4))throw new IllegalArgumentException("CRC mismatch");
        return new Frame(wire[2]&255,wire[3]&255,(int)get(wire,4,2),(int)get(wire,6,2),get(wire,8,4),Arrays.copyOfRange(wire,14,wire.length-2));
    }
    public static Frame hello(long nonce){
        check(nonce,0xFFFFFFFFL);if(nonce==0)throw new IllegalArgumentException("Zero nonce");
        byte[] payload=new byte[6];payload[0]=1;payload[1]=1;put(payload,2,nonce,4);return new Frame(1,0,TangProtocolV1.CMD_HELLO,1,0,payload);
    }
    public static final class DeviceError extends IllegalArgumentException {
        public final int status;public final long detail;
        DeviceError(int status,long detail){super("Device status="+status+", detail="+detail);this.status=status;this.detail=detail;}
    }
    public static byte[] responsePayload(Frame response){
        byte[] data=response.data;if(response.kind!=1||data.length<2)throw new IllegalArgumentException("Response missing status");
        int status=(int)get(data,0,2);if(status!=0){if(data.length!=6)throw new IllegalArgumentException("Error response length");throw new DeviceError(status,get(data,2,4));}return Arrays.copyOfRange(data,2,data.length);
    }
    public static String recordIdHex(long bits){return String.format(java.util.Locale.ROOT,"%016X",bits);}
    public static long recordIdFromHex(String hex){if(hex==null||!hex.matches("[0-9a-fA-F]{16}"))throw new IllegalArgumentException("Record ID requires 16 hex digits");return Long.parseUnsignedLong(hex,16);}

    public static byte[] recordStart(int slot,boolean overwrite,long expectedRecordId,int maxSamples){
        if(slot<0||slot>1||overwrite!=(expectedRecordId!=0)||maxSamples<1||maxSamples>5859375)throw new IllegalArgumentException("Invalid recording target");
        byte[] data=new byte[14];data[0]=(byte)slot;data[1]=(byte)(overwrite?1:0);put(data,2,expectedRecordId,8);put(data,10,maxSamples,4);return data;
    }
    public static byte[] recordRead(long transferId,long offset,int length,int blockBytes){
        check(transferId,0xFFFFFFFFL);check(offset,0xFFFFFFFFL);
        if(transferId==0||(offset&1)!=0||(length&1)!=0||length<2||length>Math.min(blockBytes,244))throw new IllegalArgumentException("Invalid PCM read");
        byte[] data=new byte[10];put(data,0,transferId,4);put(data,4,offset,4);put(data,8,length,2);return data;
    }
    /** Includes positive-time half-up rounding, matching App/Python export semantics. */
    public static long microseconds(double seconds){
        if(!Double.isFinite(seconds)||seconds<0||seconds>120)throw new IllegalArgumentException("Time out of range");return Math.round(seconds*1000000.0);
    }
    public static int internalNote(int standardNote){if(standardNote<53||standardNote>84)throw new IllegalArgumentException("MIDI outside F3..C6");return standardNote-12;}

    public static final class StreamDecoder {
        private final byte[] buffer=new byte[272];private int used=0;private long lastMs=-1;
        private void discard(int count){System.arraycopy(buffer,count,buffer,0,used-count);used-=count;}
        private void extract(List<Frame> output){
            while(used>0){
                if(buffer[0]!=0x54){discard(1);continue;}if(used<2)return;
                if(buffer[1]!=0x4D){discard(1);continue;}if(used<14)return;
                int length=(buffer[12]&255)|((buffer[13]&255)<<8);
                if(length>256){discard(1);continue;}int size=length+16;if(used<size)return;
                try{output.add(decode(Arrays.copyOf(buffer,size)));discard(size);}catch(IllegalArgumentException error){discard(1);}
            }
        }
        public List<Frame> expire(long nowMs){
            List<Frame> output=new ArrayList<>();if(used>0&&lastMs>=0&&nowMs-lastMs>=1000){discard(1);lastMs=nowMs;extract(output);}return output;
        }
        public List<Frame> feed(byte[] input,long nowMs){
            List<Frame> output=expire(nowMs);
            for(byte value:input){if(used==buffer.length)throw new IllegalStateException("Parser buffer invariant");buffer[used++]=value;extract(output);}if(input.length>0)lastMs=nowMs;return output;
        }
        public int bufferedBytes(){return used;}
    }

    public static byte[] fromHex(String text){
        String hex=text.replaceAll("\\s","");if(hex.length()%2!=0||!hex.matches("[0-9a-fA-F]*"))throw new IllegalArgumentException("HEX format");
        byte[] data=new byte[hex.length()/2];for(int i=0;i<data.length;i++)data[i]=(byte)Integer.parseInt(hex.substring(i*2,i*2+2),16);return data;
    }
    public static String toHex(byte[] data){StringBuilder hex=new StringBuilder();for(byte b:data){if(hex.length()>0)hex.append(' ');hex.append(String.format(java.util.Locale.ROOT,"%02X",b&255));}return hex.toString();}
}
