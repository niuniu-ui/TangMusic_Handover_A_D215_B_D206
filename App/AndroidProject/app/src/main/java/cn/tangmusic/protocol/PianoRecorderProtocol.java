package cn.tangmusic.protocol;

import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.zip.CRC32;

/** PRB1: BD01/BD02 diagnostics and Studio v3 mixed-audio recorder. */
public final class PianoRecorderProtocol {
    public static long get(byte[] b,int p,int n){long v=0;for(int i=0;i<n;i++)v|=(b[p+i]&255L)<<(8*i);return v;}
    public static void put(byte[] b,int p,long v,int n){for(int i=0;i<n;i++)b[p+i]=(byte)(v>>(8*i));}
    public static long crc(byte[] b,int n){CRC32 c=new CRC32();c.update(b,0,n);return c.getValue();}
    public static byte[] request(int cmd,int seq,long arg,long take){
        byte[] b=new byte[20];put(b,0,0x31515250L,4);b[4]=(byte)cmd;put(b,6,seq,2);put(b,8,arg,4);put(b,12,take,4);put(b,16,crc(b,16),4);return b;
    }
    public static final class Reply {
        public final int command,status,sequence;public final long argument,take;public final byte[] body;
        Reply(byte[] b){command=b[4]&255;status=b[5]&255;sequence=(int)get(b,6,2);argument=get(b,8,4);take=get(b,12,4);body=Arrays.copyOfRange(b,20,b.length-4);}
    }
    public static byte[] replyWire(Reply r){byte[] f=new byte[24+r.body.length];put(f,0,0x31535250L,4);f[4]=(byte)r.command;f[5]=(byte)r.status;put(f,6,r.sequence,2);put(f,8,r.argument,4);put(f,12,r.take,4);put(f,16,r.body.length,2);System.arraycopy(r.body,0,f,20,r.body.length);put(f,f.length-4,crc(f,f.length-4),4);return f;}
    /** Bounded selective-repeat window. Only CRC-verified replies enter here. */
    public static final class BurstWindow {
        public final long start,end,take,total;public final int sequence;
        private final Map<Long,Reply> blocks=new TreeMap<>();private boolean ended;
        public BurstWindow(Snapshot meta,long start,int sequence){
            if(meta.burstBlocks!=16||start%192!=0||start>=meta.bytes())throw new IllegalArgumentException("连续回传窗口无效");
            this.start=start;this.end=Math.min(meta.bytes(),start+16*192);this.total=meta.bytes();this.take=meta.take;this.sequence=sequence;
        }
        public boolean offer(Reply r){
            if(r.command!=8||r.sequence!=sequence||r.take!=take)return false;
            if(r.status!=0)throw new IllegalArgumentException("连续回传被板端拒绝："+r.status);
            if(r.body.length==0){if(r.argument!=end)return false;ended=true;return true;}
            if(r.argument<start||r.argument>=end||(r.argument-start)%192!=0||r.body.length!=Math.min(192,total-r.argument))return false;
            blocks.putIfAbsent(r.argument,r);return true;
        }
        public boolean ended(){return ended;}
        public int receivedBlocks(){return blocks.size();}
        public Reply remove(long offset){return blocks.remove(offset);}
    }
    public static final class Decoder {
        private byte[] buffer=new byte[0];
        public void clear(){buffer=new byte[0];}
        public List<Reply> feed(byte[] data){
            if(data.length>4096)throw new IllegalArgumentException("蓝牙数据包过大");
            int old=buffer.length;buffer=Arrays.copyOf(buffer,old+data.length);System.arraycopy(data,0,buffer,old,data.length);
            List<Reply> out=new ArrayList<>();int p=0;
            while(buffer.length-p>=20){
                if(get(buffer,p,4)!=0x31535250L||get(buffer,p+18,2)!=0){p++;continue;}
                int n=(int)get(buffer,p+16,2);if(n>192){p++;continue;}int size=24+n;
                if(buffer.length-p<size)break;
                byte[] frame=Arrays.copyOfRange(buffer,p,p+size);
                if(crc(frame,size-4)!=get(frame,size-4,4)){p++;continue;}
                out.add(new Reply(frame));p+=size;
            }
            buffer=Arrays.copyOfRange(buffer,p,buffer.length);return out;
        }
    }
    public static final class Snapshot {
        public final int state,fault,peak,block,version,burstBlocks,gapMs;public final long take,samples,crc,rateNum,rateDen,capacity,uartFrameErrors,uartCrcErrors,busyRxBytes;
        public final boolean memoryReady;
        public final int selectedSlot,slotCount,otherState;
        public final long committedSamples,otherSamples,otherTake,confirmedBytes;
        public final boolean leased,savedOnPhone;
        public Snapshot(Reply r){
            byte[] b=r.body;if(r.status!=0||!((b.length==32&&b[3]==1)||(b.length==44&&b[3]==2)||(b.length==64&&b[3]==3)))throw new IllegalArgumentException("需要 BD01 / BD02 或 Studio 录音固件");
            version=b[3];burstBlocks=version>=2?b[26]&255:0;gapMs=version>=2?b[27]&255:0;
            uartFrameErrors=version>=2?get(b,32,4):0;uartCrcErrors=version>=2?get(b,36,4):0;busyRxBytes=version>=2?get(b,40,4):0;
            state=b[0]&255;fault=b[1]&255;memoryReady=b[2]==1;take=r.take;samples=get(b,4,4);crc=get(b,8,4);peak=(int)get(b,16,2);block=(int)get(b,18,2);
            rateNum=get(b,20,4);rateDen=get(b,24,2);capacity=get(b,28,4);
            selectedSlot=version==3?b[44]&255:0;slotCount=version==3?b[45]&255:1;
            leased=version==3&&(b[46]&1)!=0;savedOnPhone=version==3&&(b[46]&2)!=0;otherState=version==3?b[47]&255:2;
            committedSamples=version==3?get(b,48,4):samples;otherSamples=version==3?get(b,52,4):0;otherTake=version==3?get(b,56,4):0;confirmedBytes=version==3?get(b,60,4):0;
            if(state>9||block!=192||rateNum!=390625||rateDen!=8||capacity!=(version==3?5859375:244144)||samples>capacity)throw new IllegalArgumentException("录音格式或容量不匹配");
            if(version>=2&&(burstBlocks!=16||gapMs<2||gapMs>30))throw new IllegalArgumentException("连续回传参数无效");
            if(version==3&&(slotCount!=2||selectedSlot>1||otherState>9||otherSamples>capacity||committedSamples>samples||confirmedBytes>samples*2||(b[46]&252)!=0))throw new IllegalArgumentException("双槽录音状态无效");
        }
        public long bytes(){return samples*2;}
        public boolean same(Snapshot x){return version==x.version&&selectedSlot==x.selectedSlot&&take==x.take&&samples==x.samples&&crc==x.crc&&rateNum==x.rateNum&&rateDen==x.rateDen&&capacity==x.capacity;}
        public String identity(){return take+"-"+samples+"-"+Long.toHexString(crc)+"-"+rateNum+"-"+rateDen;}
    }
    /** Native file receiver. No PCM is passed to a WebView or written to logs. */
    public static final class Download implements AutoCloseable {
        public final Snapshot meta;public final File partial;private final RandomAccessFile file;
        private long offset;private boolean closed;
        public Download(File directory,String device,Snapshot meta)throws IOException{
            if(meta.state!=5||meta.fault!=0||meta.bytes()==0)throw new IOException("录音尚未就绪");this.meta=meta;
            if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法创建录音目录");
            String name=device.replaceAll("[^a-zA-Z0-9]","")+"-"+meta.identity();
            partial=new File(directory,name+".pcm.part");file=new RandomAccessFile(partial,"rw");
            long length=file.length();offset=length==meta.bytes()?length:Math.min(length,meta.bytes())/192*192;
            file.setLength(offset);file.seek(offset);
        }
        public long offset(){return offset;}
        public void accept(Reply reply)throws IOException{
            if(closed||(reply.command!=7&&reply.command!=8)||reply.status!=0||reply.take!=meta.take||reply.argument!=offset)throw new IOException("录音块身份或偏移不一致");
            int expected=(int)Math.min(192,meta.bytes()-offset);
            if(expected<=0||reply.body.length!=expected||(expected&1)!=0)throw new IOException("录音块长度不一致");
            file.write(reply.body);offset+=expected;if(offset%12288==0)file.getFD().sync();
        }
        public File finish(Snapshot current)throws IOException{
            if(!meta.same(current)||current.state!=5||current.fault!=0||offset!=meta.bytes())throw new IOException("录音已变化或回传未完成");
            file.getFD().sync();file.seek(0);CRC32 check=new CRC32();byte[] buffer=new byte[8192];int n;
            while((n=file.read(buffer))!=-1)check.update(buffer,0,n);
            if(check.getValue()!=meta.crc){file.setLength(0);offset=0;throw new IOException("整段 CRC 校验失败，未发布 WAV；请重新回传");}
            File wav=new File(partial.getParentFile(),"piano-"+System.currentTimeMillis()+"-"+meta.identity()+".wav");
            File temp=new File(wav.getPath()+".tmp");byte[] head=new byte[44];
            put(head,0,0x46464952L,4);put(head,4,meta.bytes()+36,4);put(head,8,0x45564157L,4);put(head,12,0x20746d66L,4);put(head,16,16,4);put(head,20,1,2);put(head,22,1,2);
            long hz=Math.round((double)meta.rateNum/meta.rateDen);put(head,24,hz,4);put(head,28,hz*2,4);put(head,32,2,2);put(head,34,16,2);put(head,36,0x61746164L,4);put(head,40,meta.bytes(),4);
            try(FileOutputStream out=new FileOutputStream(temp)){out.write(head);file.seek(0);while((n=file.read(buffer))!=-1)out.write(buffer,0,n);out.getFD().sync();}
            CRC32 disk=new CRC32();try(RandomAccessFile in=new RandomAccessFile(temp,"r")){if(in.length()!=44+meta.bytes())throw new IOException("WAV 文件长度错误");in.seek(44);while((n=in.read(buffer))!=-1)disk.update(buffer,0,n);}
            if(disk.getValue()!=meta.crc)throw new IOException("WAV 磁盘校验失败");
            Files.move(temp.toPath(),wav.toPath());close();Files.deleteIfExists(partial.toPath());return wav;
        }
        @Override public void close()throws IOException{if(!closed){closed=true;try{file.getFD().sync();}finally{file.close();}}}
    }
}
