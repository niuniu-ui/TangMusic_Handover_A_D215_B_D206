package cn.tangmusic.protocol;

import java.util.Arrays;
import java.util.function.Consumer;

/** All operations use the existing TMCP session/sequence/replay checks. */
public final class ScoreUploadClient {
    public interface Listener { void changed(); }
    private final TmcpClient link;private final Listener listener;private final java.util.concurrent.Executor callbacks;
    private ScoreObject object;private long uploadId,scoreId,scoreCrc;private int offset,generation;
    private boolean uploading,cancelRequested,valid,active,waiting,polling,completed,operating;
    private String message="";private long elapsedUs,targetKeys,lastPoll;private int current,total;
    public ScoreUploadClient(TmcpClient link,Listener listener,java.util.concurrent.Executor callbacks){this.link=link;this.listener=listener;this.callbacks=callbacks;}
    public synchronized boolean supported(){return (link.features()&66)==66;}
    public synchronized boolean uploading(){return uploading;}
    public synchronized boolean busy(){return uploading||operating;}
    public synchronized boolean valid(){return valid;}
    public synchronized boolean active(){return active;}
    public synchronized boolean waiting(){return waiting;}
    public synchronized boolean completed(){return completed;}
    public synchronized String message(){return message;}
    public synchronized int progress(){return object==null?0:(int)(1000L*offset/object.bytes.length);}
    public synchronized long elapsedUs(){return elapsedUs;}
    public synchronized long targetKeys(){return targetKeys;}
    public synchronized int current(){return current;}
    public synchronized int total(){return total;}
    public synchronized int limit(){return link.maxScoreNotes();}
    private void update(String text){message=text;listener.changed();}
    private void fail(String text){uploading=false;polling=false;operating=false;update(text==null?"操作失败，请刷新设备状态":text);}
    private void request(int cmd,byte[] payload,Consumer<byte[]> success){
        int epoch=generation;
        link.command(cmd,payload,body->callbacks.execute(()->{synchronized(this){if(epoch!=generation)return;try{success.accept(body);}catch(Exception e){fail(e.getMessage());}}}),error->callbacks.execute(()->{synchronized(this){if(epoch==generation)fail(error);}}));
    }
    public synchronized void disconnected(){generation++;operating=false;uploading=false;valid=false;active=false;polling=false;uploadId=0;scoreId=0;object=null;update("蓝牙已断开，手机曲谱保留；重连后请重新上传或读取板端曲谱");}
    public synchronized void sessionReady(){generation++;operating=false;uploading=false;polling=false;object=null;uploadId=0;valid=false;active=false;if(supported())refresh();else update("当前固件没有曲谱引导接口；请在统一编译后烧录支持曲谱的新固件");}
    public synchronized void upload(ScoreObject score){
        if(!supported()){fail("当前固件不支持曲谱上传与引导");return;}
        if(uploading||active||operating){update("请先结束当前上传或引导");return;}
        if(score.count>link.maxScoreNotes()||link.blockBytes()<1){fail("曲谱超过设备容量");return;}
        object=score;offset=0;uploadId=0;cancelRequested=false;uploading=true;update("准备上传；成功开始后会替换板端原曲谱");
        byte[] begin=new byte[14];put(begin,0,score.bytes.length,4);put(begin,4,score.count,2);put(begin,6,score.durationUs,4);put(begin,10,score.crc32,4);
        request(0x201,begin,b->{if(b.length!=8||get(b,4,4)!=0||get(b,0,4)==0)throw new IllegalArgumentException("曲谱开始应答无效");uploadId=get(b,0,4);valid=false;next();});
    }
    private void next(){
        if(cancelRequested){abort();return;}
        if(offset==object.bytes.length){update("上传完成，正在校验曲谱");request(0x203,id(uploadId),b->{
            acceptInfo(b);if(!valid||scoreId!=uploadId||scoreCrc!=object.crc32||get(b,4,4)!=object.durationUs||get(b,12,2)!=object.count)throw new IllegalArgumentException("板端曲谱核对失败");
            uploading=false;total=object.count;update(cancelRequested?"曲谱已经完成提交；本次取消未中止已完成的校验":"曲谱已校验，可开始 FPGA 引导");
        });return;}
        int n=Math.min(Math.min(50,link.blockBytes()),object.bytes.length-offset),expected=offset+n;
        byte[] block=new byte[10+n];put(block,0,uploadId,4);put(block,4,offset,4);put(block,8,n,2);System.arraycopy(object.bytes,offset,block,10,n);
        request(0x202,block,b->{if(b.length!=8||get(b,0,4)!=uploadId||get(b,4,4)!=expected)throw new IllegalArgumentException("板端上传偏移不一致，请重新上传");offset=expected;update("已确认 "+offset+" / "+object.bytes.length+" 字节");next();});
    }
    public synchronized void cancel(){if(!uploading)return;cancelRequested=true;update("正在取消上传，等待当前应答");}
    private void abort(){request(0x204,id(uploadId),b->{uploading=false;valid=false;update("已取消上传，手机曲谱保留");});}
    private void acceptInfo(byte[] b){
        if(b.length!=20||(b[14]&255)!=10||(b[15]&255)>1)throw new IllegalArgumentException("板端曲谱信息无效");
        valid=b[15]==1;scoreId=get(b,0,4);scoreCrc=get(b,8,4);total=(int)get(b,12,2);
    }
    public synchronized void refresh(){if(!supported()||uploading||polling)return;polling=true;request(0x205,new byte[0],b->{acceptInfo(b);polling=false;update(valid?"板端已有曲谱，可开始引导":"板端尚无曲谱，请先上传");poll();});}
    public synchronized void start(boolean waitForKeys){
        if(!valid||uploading||active||operating){update("请先上传并核对曲谱，或等待当前操作完成");return;}
        operating=true;update("正在请求 FPGA 开始引导");
        byte[] b=new byte[9];put(b,0,scoreId,4);put(b,4,scoreCrc,4);b[8]=(byte)(waitForKeys?1:0);
        request(0x220,b,r->{if(r.length!=4||get(r,0,4)!=scoreId)throw new IllegalArgumentException("引导开始应答无效");operating=false;active=true;waiting=waitForKeys;completed=false;update(waitForKeys?"FPGA 等待正确按键；请在板端查看高亮琴键":"FPGA 正在按曲谱时间引导");poll();});
    }
    public synchronized void stop(){if(!valid||uploading||operating)return;operating=true;update("正在请求停止引导");request(0x221,id(scoreId),b->{if(b.length!=4||get(b,0,4)!=scoreId)throw new IllegalArgumentException("引导停止应答无效");operating=false;active=false;targetKeys=0;update("引导已停止");});}
    public synchronized void tick(long now){if(link.ready()&&supported()&&active&&!polling&&!uploading&&now-lastPoll>=700){lastPoll=now;poll();}}
    private void poll(){if(polling)return;polling=true;request(0x222,new byte[0],b->{
        if(b.length!=20)throw new IllegalArgumentException("引导状态长度错误");
        scoreId=get(b,0,4);elapsedUs=get(b,4,4);targetKeys=get(b,8,4);active=b[12]==1;waiting=b[13]==1;completed=b[14]==1;valid=b[15]==1;current=(int)get(b,16,2);total=(int)get(b,18,2);polling=false;
        if(completed)message="这段曲谱引导已结束";listener.changed();
    });}
    private static long get(byte[] b,int at,int n){return TangFrameCodec.get(b,at,n);}
    private static void put(byte[] b,int at,long value,int n){TangFrameCodec.put(b,at,value,n);}
    private static byte[] id(long value){byte[] b=new byte[4];put(b,0,value,4);return b;}
}
