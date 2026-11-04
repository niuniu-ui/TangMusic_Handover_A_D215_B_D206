package cn.tangmusic.protocol;

import java.io.Closeable;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.zip.CRC32;

/** Complete recording body codec and bounded-memory PCM sink; no BLE/UI emulation.
 * Call through the common session/request queue. Bodies exclude the u16 status.
 */
public final class TangRecordingV1 {
    private TangRecordingV1() {}
    private static void require(boolean value,String message){if(!value)throw new IllegalArgumentException(message);}
    private static long u32(byte[] b,int at){return TangFrameCodec.get(b,at,4);}
    public static final class Caps {
        public final boolean enabled;
        public final int maxPayload,blockBytes;
        public final long maxSamples;
        public Caps(byte[] body){
            require(body.length==46&&body[45]==0,"Caps length/reserved");
            enabled=(u32(body,4)&8)!=0;
            maxPayload=(int)TangFrameCodec.get(body,8,2);blockBytes=(int)TangFrameCodec.get(body,10,2);maxSamples=u32(body,30);
            require(maxPayload>=96&&maxPayload<=256&&blockBytes>=2&&(blockBytes&1)==0&&blockBytes<=maxPayload-12,"PCM negotiation");
            if(enabled){
                require(body[18]==2&&body[19]==1&&body[20]==1&&body[21]==16&&maxSamples>=1&&maxSamples<=5859375,"Recording capacity/format");
                require(u32(body,22)==390625&&u32(body,26)==8&&TangFrameCodec.get(body,38,2)==12,"Audio profile");
            }else require(body[18]==0&&maxSamples==0,"Disabled recording must advertise zero capacity");
        }
        public void requireRecording(){require(enabled,"Board has not enabled PCM recording");}
    }
    public static final class Record {
        public final int slot,state,stopReason;
        public final long id,samples,bytes,crc32,maxSamples;
        private final byte[] raw;
        public Record(byte[] body){
            require(body.length==40&&body[3]==0&&body[35]==0,"Record length/reserved");raw=body.clone();
            slot=body[0]&255;state=body[1]&255;stopReason=body[2]&255;id=TangFrameCodec.get(body,4,8);
            samples=u32(body,12);bytes=u32(body,16);crc32=u32(body,20);maxSamples=u32(body,36);
            require(slot<=1&&state<=3,"Record slot/state");
            require(u32(body,24)==390625&&u32(body,28)==8&&body[32]==1&&body[33]==1&&body[34]==16,"Expected mono S16LE profile 12");
            require(maxSamples>=1&&maxSamples<=5859375&&samples<=maxSamples&&bytes==samples*2,"Record size/capacity");
            if(state==0)require(id==0&&samples==0&&bytes==0&&crc32==0&&stopReason==0,"EMPTY contains data");
            else require(id!=0,"Nonempty record requires opaque u64 identity");
            if(state==1)require(stopReason==0&&crc32==0,"RECORDING not finalized");
            if(state==2){
                require(stopReason==1||stopReason==2,"READY stop reason");
                require(stopReason!=2||samples==maxSamples,"LIMIT sample count");
                require(bytes!=0||crc32==0,"Empty PCM checksum");
            }
            if(state==3)require((stopReason==3||stopReason==4)&&crc32==0,"ERROR descriptor");
        }
        public byte[] encode(){return raw.clone();}
        public String idHex(){return TangFrameCodec.recordIdHex(id);}
        public void requireReady(){require(state==2,"Only READY may be downloaded");}
        public boolean same(Record other){return Arrays.equals(raw,other.raw);}
    }
    public static Record[] list(byte[] body){
        require(body.length==81&&body[0]==2,"REC_LIST length/count");
        Record a=new Record(Arrays.copyOfRange(body,1,41)),b=new Record(Arrays.copyOfRange(body,41,81));
        require(a.slot==0&&b.slot==1&&(a.id==0||a.id!=b.id)&&!(a.state==1&&b.state==1),"Atomic recording directory");
        return new Record[]{a,b};
    }
    public static byte[] identity(long id){require(id!=0,"Zero recording identity");byte[] b=new byte[8];TangFrameCodec.put(b,0,id,8);return b;}
    public static byte[] start(Record current,int maxSamples,Caps caps){
        caps.requireRecording();require(current.state!=1&&maxSamples>=1&&maxSamples<=caps.maxSamples,"Capture busy/capacity");
        return TangFrameCodec.recordStart(current.slot,current.state!=0,current.id,maxSamples);
    }
    public static byte[] delete(int slot,long expectedId){
        require(slot>=0&&slot<=1,"Slot");byte[] b=new byte[9];b[0]=(byte)slot;TangFrameCodec.put(b,1,expectedId,8);return b;
    }
    public static byte[] close(long transfer){require(transfer>0&&transfer<=0xffffffffL,"Transfer identity");byte[] b=new byte[4];TangFrameCodec.put(b,0,transfer,4);return b;}
    public static long startAck(byte[] body,int expectedSlot){
        require(body.length==9&&(body[0]&255)==expectedSlot,"START echo/length");long id=TangFrameCodec.get(body,1,8);identity(id);return id;
    }
    public static long openAck(byte[] body,Record expected){
        expected.requireReady();require(body.length==44,"OPEN length");long transfer=u32(body,0);close(transfer);
        Record current=new Record(Arrays.copyOfRange(body,4,44));current.requireReady();require(current.same(expected),"Recording changed before OPEN");return transfer;
    }
    public static byte[] read(long transfer,long offset,int count,Record record,Caps caps){
        caps.requireRecording();record.requireReady();require(offset>=0&&offset<=record.bytes,"Read past EOF");
        return TangFrameCodec.recordRead(transfer,offset,count,caps.blockBytes);
    }
    public static byte[] block(byte[] body,long transfer,long offset,int requested,Record record,Caps caps){
        read(transfer,offset,requested,record,caps);require(body.length>=10&&body.length+2<=caps.maxPayload,"DATA length");
        int actual=(int)TangFrameCodec.get(body,8,2);
        require(u32(body,0)==transfer&&u32(body,4)==offset,"DATA identity/offset");
        require(actual==Math.min((long)requested,record.bytes-offset)&&(actual&1)==0&&body.length==10+actual,"DATA count/EOF");
        return Arrays.copyOfRange(body,10,body.length);
    }
    public static byte[] wavHeader(Record record){
        record.requireReady();byte[] b=new byte[44];
        System.arraycopy("RIFF".getBytes(StandardCharsets.US_ASCII),0,b,0,4);TangFrameCodec.put(b,4,36+record.bytes,4);
        System.arraycopy("WAVEfmt ".getBytes(StandardCharsets.US_ASCII),0,b,8,8);TangFrameCodec.put(b,16,16,4);TangFrameCodec.put(b,20,1,2);TangFrameCodec.put(b,22,1,2);
        TangFrameCodec.put(b,24,48828,4);TangFrameCodec.put(b,28,97656,4);TangFrameCodec.put(b,32,2,2);TangFrameCodec.put(b,34,16,2);
        System.arraycopy("data".getBytes(StandardCharsets.US_ASCII),0,b,36,4);TangFrameCodec.put(b,40,record.bytes,4);return b;
    }
    /** Store bytes in a private .part file. Never send PCM through JavaScript. */
    public static final class Download implements Closeable {
        public final Record record;
        private final RandomAccessFile file;
        private final CRC32 crc=new CRC32();
        private long offset;
        private boolean failed;
        public Download(Path part,Record record)throws IOException{
            record.requireReady();this.record=record;
            Path parent=part.toAbsolutePath().getParent();Files.createDirectories(parent);
            Path meta=part.resolveSibling(part.getFileName()+".record");String signature=TangFrameCodec.toHex(record.encode()).replace(" ","");
            if(Files.exists(meta))require(new String(Files.readAllBytes(meta),StandardCharsets.US_ASCII).trim().equals(signature),"Resume metadata changed");
            else{
                require(!Files.exists(part),"Existing PCM has no descriptor");
                Files.write(meta,(signature+"\n").getBytes(StandardCharsets.US_ASCII),java.nio.file.StandardOpenOption.CREATE_NEW);
            }
            file=new RandomAccessFile(part.toFile(),"rw");
            try{
                require(file.length()<=record.bytes,"Temporary PCM too long");offset=file.length()&~1L;file.setLength(offset);file.seek(0);
                byte[] buffer=new byte[16384];long left=offset;
                while(left>0){int n=file.read(buffer,0,(int)Math.min(buffer.length,left));if(n<1)throw new IOException("Truncated PCM");crc.update(buffer,0,n);left-=n;}
                file.seek(offset);
            }catch(IOException|RuntimeException error){file.close();throw error;}
        }
        public long offset(){return offset;}
        public long accept(byte[] body,long transfer,long requestedOffset,int requested,Caps caps)throws IOException{
            require(!failed&&requestedOffset==offset,"Closed/failed, duplicate or out-of-order block");
            byte[] data=block(body,transfer,requestedOffset,requested,record,caps);
            try{file.write(data);}catch(IOException error){failed=true;throw error;}
            crc.update(data);offset+=data.length;return offset;
        }
        public Path finish(Path destination)throws IOException{
            require(!failed&&offset==record.bytes&&crc.getValue()==record.crc32,"Incomplete recording/PCM CRC mismatch");
            require(file.length()==record.bytes,"Stored PCM length changed");
            require(!Files.exists(destination),"Destination exists");Path parent=destination.toAbsolutePath().getParent();Files.createDirectories(parent);
            Path temp=Files.createTempFile(parent,".tmcp-",".tmp");file.getFD().sync();file.seek(0);
            try{
                CRC32 stored=new CRC32();
                try(RandomAccessFile out=new RandomAccessFile(temp.toFile(),"rw")){
                    out.write(wavHeader(record));byte[] buffer=new byte[16384];int n;
                    while((n=file.read(buffer))!=-1){out.write(buffer,0,n);stored.update(buffer,0,n);}out.getFD().sync();
                }
                require(stored.getValue()==record.crc32,"Stored PCM was modified/corrupted");
                Files.move(temp,destination); // No REPLACE_EXISTING: preserve an existing phone file.
                String metadata="{\"record_id\":\""+record.idHex()+"\",\"sample_rate_num\":390625,\"sample_rate_den\":8,\"wav_sample_rate\":48828,\"sample_count\":"+record.samples+",\"byte_count\":"+record.bytes+",\"pcm_crc32\":\""+String.format(java.util.Locale.ROOT,"%08X",record.crc32)+"\"}\n";
                Files.write(destination.resolveSibling(destination.getFileName()+".json"),metadata.getBytes(StandardCharsets.UTF_8));
                return destination;
            }finally{file.seek(offset);Files.deleteIfExists(temp);}
        }
        @Override public void close()throws IOException{file.close();}
    }
}
