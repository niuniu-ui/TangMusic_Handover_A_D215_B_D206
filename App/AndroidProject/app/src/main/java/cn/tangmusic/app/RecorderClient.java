package cn.tangmusic.app;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import cn.tangmusic.protocol.PianoRecorderProtocol;
import cn.tangmusic.protocol.PianoRecorderProtocol.*;
import cn.tangmusic.protocol.RecorderConnectionStatus;
import cn.tangmusic.protocol.TangFrameCodec;
import org.json.JSONObject;
import java.io.*;
import java.util.*;
import java.util.function.Consumer;

/** Recorder transactions share the main Activity's single physical BLE link. */
final class RecorderClient {
    interface Link { void send(String hex); void transferPriority(boolean active); }
    interface Listener { void state(JSONObject state); void filesChanged(); void keepAwake(boolean awake); }
    private final Context context; private final Link ble; private final Listener listener;
    private final Handler handler=new Handler(Looper.getMainLooper());
    private final RecorderConnectionStatus connectionStatus=new RecorderConnectionStatus();
    private final Decoder decoder=new Decoder(); private Snapshot snapshot;
    private Download download;private Pending pending;private BurstWindow window;
    private String address="",message="",lastLoggedIdentity="",lastRendered="";
    private String deferredAction;private int deferredSlot;
    private int sequence=new Random().nextInt(60000)+1,retries,repairBlocks,burstWindows,progressPermille;
    private boolean channel,closed,releaseLeaseWhenIdle;
    private long nextPoll,started,initialOffset,lastProgress;
    private static final class Pending {
        int cmd,seq,retries,received;long arg,sent,lastRx;byte[] wire;boolean written;Reply reply;Consumer<Reply> success;
        ByteArrayOutputStream statusRaw=new ByteArrayOutputStream();byte[] firstBadStatus;
    }
    private final Runnable timer=new Runnable(){public void run(){if(closed)return;
        long now=SystemClock.elapsedRealtime();
        if(pending!=null&&pending.cmd==8){
            if(!pending.written&&now-pending.sent>10000)fail("蓝牙写入超时，接收进度已保留");
            else if(pending.written&&(now-pending.sent>1800||(pending.received>0&&now-pending.sent>650&&now-pending.lastRx>220)))finishBurst();
        }else if(pending!=null && (now-pending.sent>(pending.written?800:10000) || (pending.written&&pending.received>0&&now-pending.lastRx>100))){
            if(!pending.written||pending.retries>=8)fail("设备应答超时；已保留接收进度。请重新连接并刷新状态。录音指令是否执行以板端状态为准。");
            else {android.util.Log.i("PianoRecorder","RETRY cmd="+pending.cmd+" seq="+pending.seq+" bytes="+pending.received);if(pending.cmd==1&&pending.firstBadStatus==null&&pending.statusRaw.size()>0)pending.firstBadStatus=pending.statusRaw.toByteArray();pending.statusRaw.reset();pending.retries++;retries++;pending.written=false;pending.reply=null;pending.received=0;pending.sent=now;decoder.clear();ble.send(TangFrameCodec.toHex(pending.wire));}
        }else if(pending==null&&channel&&releaseLeaseWhenIdle&&snapshot!=null&&snapshot.version==3){
            releaseLeaseWhenIdle=false;request(12,0,r->{snapshot=new Snapshot(r);render();});
        }else if(pending==null&&channel&&download==null&&now>=nextPoll){nextPoll=now+1000;request(1,0,r->{acceptStatus(r);render();});}
        handler.postDelayed(this,25);
    }};
    void receiveBytes(byte[] bytes){if(closed||!channel)return;try{
        for(Reply r:decoder.feed(bytes)){
            if(pending!=null&&r.sequence==pending.seq){pending.received+=r.body.length+24;pending.lastRx=SystemClock.elapsedRealtime();}
            if(pending!=null&&pending.cmd==8&&window!=null){if(window.offer(r)&&window.ended()&&pending.written)finishBurst();}
            else if(pending!=null&&r.sequence==pending.seq&&r.command==pending.cmd&&r.argument==pending.arg){pending.reply=r;complete();}
        }
    }catch(Exception e){fail(e.getMessage());}}
    private void request(int cmd,long arg,Consumer<Reply> done){if(!channel||pending!=null)return;
        Pending p=new Pending();p.cmd=cmd;p.seq=sequence;sequence=sequence==65535?1:sequence+1;p.arg=arg;p.success=done;p.sent=SystemClock.elapsedRealtime();p.wire=PianoRecorderProtocol.request(cmd,p.seq,arg,snapshot==null?0:snapshot.take);pending=p;
        if(cmd==8)window=new BurstWindow(snapshot,arg,p.seq);
        ble.send(TangFrameCodec.toHex(p.wire));if(download==null)render();
    }
    private void complete(){Pending p=pending;if(p==null||!p.written||p.reply==null)return;pending=null;nextPoll=SystemClock.elapsedRealtime()+1000;
        if(p.reply.status!=0){fail("板端拒绝操作，状态码 "+p.reply.status+"；请刷新状态后重试。");return;}
        if(p.cmd==1&&p.firstBadStatus!=null){byte[] expected=PianoRecorderProtocol.replyWire(p.reply),bad=p.firstBadStatus;int missing=-1;
            if(bad.length==expected.length-1)for(int i=0;i<expected.length;i++){boolean same=true;for(int j=0;j<bad.length;j++)if(bad[j]!=expected[j<i?j:j+1]){same=false;break;}if(same){missing=i;break;}}
            android.util.Log.i("PianoRecorder","STATUS_RECOVERY raw="+bad.length+" expected="+expected.length+" missing_index="+missing+" missing_value="+(missing<0?-1:expected[missing]&255));}
        try{p.success.accept(p.reply);}catch(Exception e){fail(e.getMessage());}
        if(deferredAction!=null){String action=deferredAction;int slot=deferredSlot;deferredAction=null;action(action,slot);}
        if(download==null)render();
    }
    private void acceptStatus(Reply reply){boolean wasReady=connectionStatus.ready();snapshot=new Snapshot(reply);connectionStatus.verified();if(!wasReady)android.util.Log.i("PianoRecorder","BOARD_READY state="+snapshot.state+" fault="+snapshot.fault+" take="+snapshot.take+" samples="+snapshot.samples);}
    private void refreshStatus(){if(!channel||pending!=null||download!=null)return;decoder.clear();connectionStatus.verifying(address);nextPoll=Long.MAX_VALUE;request(1,0,r->{acceptStatus(r);render();});}
    private void command(int cmd){
        if(!connectionStatus.ready()||snapshot==null||download!=null||pending!=null)return;
        boolean allowed=switch(cmd){case 2->snapshot.state==2&&snapshot.memoryReady&&!snapshot.leased;case 3->snapshot.state==3;case 4->snapshot.state==5&&!snapshot.leased;case 5->snapshot.state==5&&snapshot.samples>0&&!snapshot.leased;case 6->snapshot.state==6||snapshot.state==7;default->false;};
        if(!allowed)return;
        request(cmd,0,r->{acceptStatus(r);android.util.Log.i("PianoRecorder","COMMAND_OK cmd="+cmd+" state="+snapshot.state+" take="+snapshot.take+" samples="+snapshot.samples);render();});}
    private void selectSlot(int slot){if(!connectionStatus.ready()||snapshot==null||snapshot.version!=3||download!=null||pending!=null||snapshot.leased||!snapshot.memoryReady||(snapshot.state!=2&&snapshot.state!=5)||slot<0||slot>=snapshot.slotCount)return;request(10,slot,r->{acceptStatus(r);render();});}
    private File directory(){return new File(context.getFilesDir(),"piano-recordings");}
    private void beginDownload(){if(!connectionStatus.ready()||snapshot==null||snapshot.state!=5||pending!=null||download!=null)return;
        if(snapshot.version==3){Snapshot expected=snapshot;request(11,0,r->{Snapshot held=new Snapshot(r);if(!expected.same(held)||!held.leased){fail("录音已变化，请刷新后重试");return;}snapshot=held;startDownload();});}
        else startDownload();
    }
    private void startDownload(){try{
        releaseLeaseWhenIdle=false;
        download=new Download(directory(),address,snapshot);started=SystemClock.elapsedRealtime();initialOffset=download.offset();retries=0;repairBlocks=0;burstWindows=0;lastProgress=0;ble.transferPriority(true);
        android.util.Log.i("PianoRecorder","DOWNLOAD_START version="+snapshot.version+" offset="+initialOffset+" uart_frame_errors="+snapshot.uartFrameErrors+" uart_crc_errors="+snapshot.uartCrcErrors+" busy_rx_bytes="+snapshot.busyRxBytes);render();
        listener.keepAwake(true);nextBlock();
    }catch(Exception e){fail(e.getMessage());}}
    private void nextBlock(){Download current=download;if(current==null)return;
        long elapsed=Math.max(1,SystemClock.elapsedRealtime()-started),bytes=current.offset()-initialOffset;
        setProgress((int)(1000*current.offset()/Math.max(1,current.meta.bytes())));
        if(SystemClock.elapsedRealtime()-lastProgress>=200){lastProgress=SystemClock.elapsedRealtime();setMessage(String.format(Locale.CHINA,"回传 %.1f%% · %d / %d 字节 · %.1f KB/s · 补读 %d 块 · 重试 %d 次",100.0*current.offset()/current.meta.bytes(),current.offset(),current.meta.bytes(),bytes*1000.0/elapsed/1024,repairBlocks,retries));}
        if(current.meta.version==3&&snapshot.confirmedBytes!=current.offset()){
            request(14,current.offset(),r->{if(download!=current)return;snapshot=new Snapshot(r);nextBlock();});return;
        }
        if(current.offset()==current.meta.bytes())request(1,0,r->{if(download!=current)return;try{
            Snapshot finalState=new Snapshot(r);File wav=current.finish(finalState);download=null;snapshot=finalState;ble.transferPriority(false);listener.keepAwake(false);setMessage("已保存 · 整段 CRC 校验通过\n"+wav.getName());android.util.Log.i("PianoRecorder","WAV_SAVED bytes="+finalState.bytes()+" crc="+Long.toHexString(finalState.crc)+" elapsed_ms="+(SystemClock.elapsedRealtime()-started)+" retries="+retries+" resumed_bytes="+initialOffset+" repair_blocks="+repairBlocks+" windows="+burstWindows+" uart_frame_errors="+finalState.uartFrameErrors+" uart_crc_errors="+finalState.uartCrcErrors+" busy_rx_bytes="+finalState.busyRxBytes);listener.filesChanged();
            if(finalState.version==3)request(13,finalState.crc,ack->{snapshot=new Snapshot(ack);releaseLeaseWhenIdle=true;render();});
        }catch(Exception e){fail(e.getMessage());}});
        else if(current.meta.burstBlocks==16){burstWindows++;request(8,current.offset(),r->{});}
        else request(7,current.offset(),r->{if(download!=current)return;try{current.accept(r);nextBlock();}catch(Exception e){fail(e.getMessage());}});
    }
    private void finishBurst(){
        Pending p=pending;if(p==null||p.cmd!=8||!p.written)return;
        if(download==null){pending=null;window=null;render();return;}
        if(window.receivedBlocks()==0&&!window.ended()&&p.retries<2){p.retries++;retries++;p.written=false;p.received=0;p.sent=SystemClock.elapsedRealtime();decoder.clear();ble.send(TangFrameCodec.toHex(p.wire));return;}
        pending=null;fillWindow();
    }
    private void fillWindow(){Download current=download;BurstWindow active=window;if(current==null||active==null)return;try{
        Reply chunk;while((chunk=active.remove(current.offset()))!=null)current.accept(chunk);
        if(current.offset()<active.end){repairBlocks++;request(7,current.offset(),r->{if(download!=current||window!=active)return;try{current.accept(r);fillWindow();}catch(Exception e){fail(e.getMessage());}});}
        else{window=null;nextBlock();}
    }catch(Exception e){fail(e.getMessage());}}
    private void pauseDownload(){Download old=download;download=null;listener.keepAwake(false);if(snapshot!=null&&snapshot.version==3)releaseLeaseWhenIdle=true;if(old!=null){ble.transferPriority(false);try{old.close();}catch(IOException e){setMessage("保存接收进度失败："+e.getMessage());return;}setMessage("已暂停；完整块已保存，重连后可继续接收。");}render();}
    private void fail(String message){deferredAction=null;pending=null;window=null;connectionStatus.failed(message);pauseDownload();nextPoll=Long.MAX_VALUE;setMessage(message==null?"回传失败":message);android.util.Log.w("PianoRecorder",message==null?"failure":message);render();}

    RecorderClient(Context context,Link link,Listener listener){this.context=context;this.ble=link;this.listener=listener;handler.post(timer);}
    void channelReady(String address){deferredAction=null;this.address=address;channel=true;snapshot=null;pending=null;window=null;decoder.clear();releaseLeaseWhenIdle=false;message="";refreshStatus();}
    void disconnected(){deferredAction=null;channel=false;pending=null;window=null;connectionStatus.disconnected();pauseDownload();snapshot=null;nextPoll=Long.MAX_VALUE;render();}
    void writeComplete(){if(pending!=null){pending.written=true;pending.sent=SystemClock.elapsedRealtime();if(pending.cmd==8){if(window!=null&&window.ended())finishBurst();}else complete();}}
    void transportError(String message){if(channel)fail(message);}
    void action(String action,int slot){
        // A status poll must not flash the controls or swallow a tap. Execute one
        // user action after its reply, using the newly verified board state.
        if(pending!=null&&pending.cmd==1&&connectionStatus.ready()&&download==null&&!action.equals("pause")){
            if(deferredAction==null){deferredAction=action;deferredSlot=slot;render();}return;
        }
        switch(action){case "refresh":refreshStatus();break;case "start":command(2);break;case "stop":command(3);break;case "erase":command(4);break;case "play":command(5);break;case "stopPlay":command(6);break;case "slot":selectSlot(slot);break;case "download":beginDownload();break;case "pause":pauseDownload();break;default:throw new IllegalArgumentException("Unknown recorder action");}}
    boolean downloading(){return download!=null;}
    private void setMessage(String text){message=text;}
    private void setProgress(int progress){progressPermille=progress;render();}
    void publish(){lastRendered="";render();}
    private void render(){if(closed)return;try{
        boolean userBusy=deferredAction!=null||(pending!=null&&(pending.cmd!=1||!connectionStatus.ready()));
        boolean idle=channel&&connectionStatus.ready()&&!userBusy&&download==null&&snapshot!=null;
        JSONObject out=new JSONObject().put("connected",channel).put("ready",connectionStatus.ready()).put("connection",connectionStatus.text()).put("message",message).put("downloading",download!=null).put("progress",progressPermille).put("busy",userBusy).put("canRefresh",channel&&!userBusy&&download==null);
        if(snapshot!=null){
            out.put("version",snapshot.version).put("state",snapshot.state).put("fault",snapshot.fault).put("slot",snapshot.selectedSlot).put("slots",snapshot.slotCount).put("capacitySeconds",snapshot.capacity*8.0/390625).put("seconds",snapshot.committedSamples*8.0/390625).put("samples",snapshot.samples).put("take",snapshot.take).put("peak",snapshot.peak).put("leased",snapshot.leased);
            out.put("canRecord",idle&&snapshot.state==2&&snapshot.memoryReady&&!snapshot.leased).put("canStop",idle&&snapshot.state==3).put("canErase",idle&&snapshot.state==5&&!snapshot.leased).put("canPlay",idle&&snapshot.state==5&&snapshot.samples>0&&!snapshot.leased).put("canStopPlay",idle&&(snapshot.state==6||snapshot.state==7)).put("canDownload",idle&&snapshot.state==5&&snapshot.samples>0).put("canSelect",idle&&snapshot.slotCount==2&&!snapshot.leased&&snapshot.memoryReady&&(snapshot.state==2||snapshot.state==5));
            if(snapshot.state==5&&snapshot.samples>0&&!snapshot.identity().equals(lastLoggedIdentity)){lastLoggedIdentity=snapshot.identity();android.util.Log.i("PianoRecorder","RECORDING_READY version="+snapshot.version+" take="+snapshot.take+" samples="+snapshot.samples+" crc="+Long.toHexString(snapshot.crc));}
        }
        String serialized=out.toString();if(!serialized.equals(lastRendered)){lastRendered=serialized;listener.state(out);}
    }catch(Exception e){android.util.Log.e("PianoRecorder","Cannot render recorder state",e);}}
    void close(){handler.removeCallbacks(timer);pauseDownload();closed=true;}
}
