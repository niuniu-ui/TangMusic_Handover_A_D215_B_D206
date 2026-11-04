package cn.tangmusic.app;

import android.Manifest;
import android.app.*;
import android.os.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.media.MediaPlayer;
import android.net.Uri;
import android.view.WindowManager;
import android.widget.*;
import android.graphics.Color;
import android.content.res.ColorStateList;
import cn.tangmusic.protocol.PianoRecorderProtocol;
import cn.tangmusic.protocol.PianoRecorderProtocol.*;
import cn.tangmusic.protocol.TangFrameCodec;
import cn.tangmusic.protocol.RecorderConnectionStatus;
import org.json.*;
import java.io.*;
import java.util.*;
import java.util.function.Consumer;

/** Phone-only BLE recorder workflow; USB is never an audio transport. */
public final class PianoRecorderActivity extends Activity {
    private final Handler handler=new Handler(Looper.getMainLooper());
    private final RecorderConnectionStatus connectionStatus=new RecorderConnectionStatus();
    private BleTransport ble;private Decoder decoder=new Decoder();private Snapshot snapshot;
    private Download download;private MediaPlayer player;private Pending pending;private BurstWindow window;
    private String address="",lastLoggedIdentity="";private int sequence=new Random().nextInt(60000)+1,retries;
    private boolean channel,closed;private long nextPoll,started,initialOffset,lastProgress;private File exported;
    private int repairBlocks,burstWindows;
    private TextView connection,state,progress,capacityLabel;private LinearLayout devices,files;
    private Button slotOne,slotTwo;private boolean releaseLeaseWhenIdle;
    private ProgressBar transferMeter;
    private Button record,stop,erase,boardPlay,boardStop,receive,cancel,refresh;
    private final Map<String,Button> deviceButtons=new LinkedHashMap<>();
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
    @Override public void onCreate(Bundle saved){super.onCreate(saved);
        LinearLayout content=new LinearLayout(this);content.setOrientation(1);content.setBackgroundColor(Color.rgb(250,243,231));getWindow().getDecorView().setSystemUiVisibility(android.view.View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|android.view.View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);content.setPadding(dp(22),dp(12),dp(22),dp(32));
        ScrollView scroll=new ScrollView(this);scroll.setBackgroundColor(Color.rgb(250,243,231));scroll.setFillViewport(true);scroll.setOnApplyWindowInsetsListener((v,in)->{v.setPadding(0,in.getSystemWindowInsetTop(),0,in.getSystemWindowInsetBottom());return in;});scroll.addView(content);setContentView(scroll);
        secondary(button(content,"← 返回我的录音",this::finish));
        TextView brand=label(content,"play!   /   RECORDING STUDIO",13);brand.setTextColor(Color.rgb(133,102,66));brand.setLetterSpacing(.08f);
        TextView title=label(content,"留住这一刻，\n再听一次。",32);title.setTypeface(android.graphics.Typeface.DEFAULT,android.graphics.Typeface.BOLD);title.setTextColor(Color.rgb(94,69,45));
        label(content,"声音录在乐器里，美好留在手机里。",14);
        LinearLayout link=card(content,0xfff4f1df,"01  连接录音设备");
        connection=label(link,"未连接，请扫描 E104",14);
        LinearLayout connectionActions=row(link);button(connectionActions,"扫描蓝牙",this::scan);secondary(button(connectionActions,"断开连接",()->ble.disconnect()));
        devices=new LinearLayout(this);devices.setOrientation(1);link.addView(devices);
        label(link,"支持 Studio 总工程和 BD01 / BD02 调试固件；录音容量以板端状态为准。",11);
        LinearLayout capture=card(content,0xfff0d6ad,"02  把这段旋律录下来");
        capture.addView(new TapeArt(),new LinearLayout.LayoutParams(-1,dp(100)));
        state=label(capture,"等待录音设备",17);
        capacityLabel=label(capture,"连接后读取录音槽数量与容量 · 保存于 FPGA DDR3",11);
        LinearLayout slots=row(capture);slotOne=button(slots,"录音槽 1",()->selectSlot(0));slotTwo=button(slots,"录音槽 2",()->selectSlot(1));secondary(slotOne);secondary(slotTwo);
        LinearLayout captureActions=row(capture);record=button(captureActions,"● 开始录音",()->command(2));stop=button(captureActions,"停止录音",()->command(3));secondary(stop);
        LinearLayout playActions=row(capture);boardPlay=button(playActions,"耳机回放",()->command(5));boardStop=button(playActions,"停止回放",()->command(6));secondary(boardPlay);secondary(boardStop);
        refresh=button(capture,"刷新 / 重新核对设备",this::refreshStatus);secondary(refresh);
        erase=button(capture,"删除板端录音",()->new AlertDialog.Builder(this).setTitle("删除板端录音？").setMessage("未回传的录音将无法恢复，手机里已保存的 WAV 不受影响。").setNegativeButton("取消",null).setPositiveButton("删除",(d,w)->command(4)).show());secondary(erase);
        LinearLayout transfer=card(content,0xffede4f3,"03  把声音带到手机");
        progress=label(transfer,"还没有开始接收",14);
        transferMeter=new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal);transferMeter.setMax(1000);transferMeter.setProgressTintList(ColorStateList.valueOf(0xff8250af));transferMeter.setProgressBackgroundTintList(ColorStateList.valueOf(0xffd7c8e2));transferMeter.setContentDescription("录音回传进度");LinearLayout.LayoutParams meterParams=new LinearLayout.LayoutParams(-1,dp(10));meterParams.setMargins(0,dp(10),0,dp(16));transfer.addView(transferMeter,meterParams);
        receive=button(transfer,"回传到手机 / 继续接收",this::beginDownload);
        cancel=button(transfer,"暂停回传，保留进度",this::pauseDownload);secondary(cancel);
        label(transfer,"请保持此页在前台。完整接收并校验后，录音会出现在下方；断线后可以继续接收同一段录音。",11);
        TextView libraryTitle=label(content,"我的录音带",22);libraryTitle.setTypeface(android.graphics.Typeface.DEFAULT,android.graphics.Typeface.BOLD);files=new LinearLayout(this);files.setOrientation(1);content.addView(files);
        secondary(button(content,"停止手机试听",this::stopPlayer));
        label(content,"板卡掉电会丢失未保存的录音。回传完成后，可将 WAV 另存到手机文件。",11);
        ble=new BleTransport(this,this::event,true);ble.binaryReceiver(this::receiveBytes);handler.post(timer);render();listFiles();
    }
    private int dp(int value){return Math.round(value*getResources().getDisplayMetrics().density);}
    private android.graphics.drawable.GradientDrawable shape(int color){android.graphics.drawable.GradientDrawable d=new android.graphics.drawable.GradientDrawable();d.setColor(color);d.setCornerRadius(dp(19));d.setStroke(dp(1),0xffded6bf);return d;}
    private LinearLayout card(LinearLayout parent,int color,String title){LinearLayout box=new LinearLayout(this);box.setOrientation(1);box.setPadding(dp(18),dp(14),dp(18),dp(18));box.setBackground(shape(color));LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);p.setMargins(0,dp(16),0,dp(8));parent.addView(box,p);TextView h=label(box,title,16);h.setTypeface(android.graphics.Typeface.DEFAULT,android.graphics.Typeface.BOLD);return box;}
    private void secondary(Button b){android.graphics.drawable.StateListDrawable states=new android.graphics.drawable.StateListDrawable();states.addState(new int[]{-android.R.attr.state_enabled},shape(0xffe9e5da));states.addState(new int[]{},shape(0xfffffcf1));b.setBackground(states);b.setTextColor(new ColorStateList(new int[][]{new int[]{-android.R.attr.state_enabled},new int[]{}},new int[]{0xffaba492,0xff785496}));}
    private final class TapeArt extends android.view.View {
        private final android.graphics.Paint pen=new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
        TapeArt(){super(PianoRecorderActivity.this);setImportantForAccessibility(android.view.View.IMPORTANT_FOR_ACCESSIBILITY_NO);}
        @Override protected void onDraw(android.graphics.Canvas c){super.onDraw(c);float w=getWidth(),h=getHeight(),cy=h*.49f,r=Math.min(h*.27f,w*.13f);pen.setStyle(android.graphics.Paint.Style.FILL);pen.setColor(0xffd0ac74);c.drawRoundRect(0,dp(9),w,h-dp(6),dp(15),dp(15),pen);pen.setColor(0xfffff3d8);c.drawRoundRect(0,dp(4),w,h-dp(12),dp(15),dp(15),pen);for(float x:new float[]{w*.20f,w*.80f}){pen.setColor(0xffb3915c);c.drawCircle(x,cy,r,pen);pen.setColor(0xfff5e7c5);c.drawCircle(x,cy,r*.76f,pen);pen.setColor(0xffa5804c);c.drawCircle(x,cy,r*.40f,pen);pen.setColor(0xfff5e7c5);c.drawCircle(x,cy,r*.18f,pen);}pen.setColor(0xffa88550);pen.setTextAlign(android.graphics.Paint.Align.CENTER);pen.setTypeface(android.graphics.Typeface.create("sans-serif",android.graphics.Typeface.BOLD));pen.setTextSize(dp(11));c.drawText("KEEP A LITTLE",w/2,cy-dp(3),pen);c.drawText("MELODY",w/2,cy+dp(13),pen);}
    }
    private LinearLayout row(LinearLayout parent){LinearLayout r=new LinearLayout(this);r.setOrientation(0);parent.addView(r);return r;}
    private TextView label(LinearLayout parent,String text,int size){TextView t=new TextView(this);t.setText(text);t.setTextSize(size);t.setTextColor(size>=17?0xff5d4531:0xff827052);t.setLineSpacing(dp(3),1);t.setPadding(0,dp(8),0,dp(8));parent.addView(t);return t;}
    private Button button(LinearLayout parent,String text,Runnable action){Button b=new Button(this);b.setText(text);b.setTextSize(14);b.setAllCaps(false);b.setMinHeight(dp(48));b.setOnClickListener(v->action.run());
        android.graphics.drawable.StateListDrawable states=new android.graphics.drawable.StateListDrawable();states.addState(new int[]{-android.R.attr.state_enabled},shape(0xffdfd9dd));states.addState(new int[]{},shape(0xff8250af));b.setBackgroundTintList(null);b.setBackground(states);b.setPadding(dp(10),dp(10),dp(10),dp(10));
        b.setTextColor(new ColorStateList(new int[][]{new int[]{-android.R.attr.state_enabled},new int[]{}},new int[]{Color.rgb(123,134,114),Color.WHITE}));
        LinearLayout.LayoutParams params=new LinearLayout.LayoutParams(parent.getOrientation()==0?0:-1,-2,parent.getOrientation()==0?1:0);params.setMargins(dp(3),dp(5),dp(3),dp(5));parent.addView(b,params);return b;}
    private void scan(){String[] needed=Build.VERSION.SDK_INT>=31?new String[]{Manifest.permission.BLUETOOTH_SCAN,Manifest.permission.BLUETOOTH_CONNECT}:new String[]{Manifest.permission.ACCESS_FINE_LOCATION};
        for(String p:needed)if(checkSelfPermission(p)!=PackageManager.PERMISSION_GRANTED){requestPermissions(needed,70);return;}
        if(!ble.enabled()){connection.setText("请打开手机系统蓝牙后再次扫描");return;}deviceButtons.clear();devices.removeAllViews();ble.scan();
    }
    @Override public void onRequestPermissionsResult(int request,String[] p,int[] r){super.onRequestPermissionsResult(request,p,r);if(request==70){for(int v:r)if(v!=PackageManager.PERMISSION_GRANTED){connection.setText("需要附近设备 / 蓝牙权限");return;}if(r.length>0)scan();}}
    private void event(String type,JSONObject data){if(closed)return;try{
        switch(type){
            case "devicesFound":JSONArray a=data.getJSONArray("items");for(int i=0;i<a.length();i++){JSONObject d=a.getJSONObject(i);String addr=d.getString("address"),name=d.optString("name");if(!name.contains("E104"))continue;
                Button b=deviceButtons.get(addr);if(b==null){b=button(devices,"",()->{pauseDownload();ble.connect(addr);});deviceButtons.put(addr,b);}b.setText(name+" · "+addr+" · "+d.optInt("rssi")+" dBm");}break;
            case "scanStarted":if(!channel)connectionStatus.scanning();break;
            case "scanStopped":if(!channel)connectionStatus.disconnected();break;
            case "connecting":connectionStatus.connecting();break;
            case "channelReady":channel=true;address=data.getString("address");snapshot=null;decoder.clear();pending=null;window=null;releaseLeaseWhenIdle=false;refreshStatus();break;
            case "mtu":android.util.Log.i("PianoRecorder","MTU value="+data.optInt("value")+" status="+data.optInt("status"));break;
            case "disconnected":channel=false;pending=null;window=null;snapshot=null;connectionStatus.disconnected();pauseDownload();break;
            case "error":fail(data.optString("message"));break;
            case "txDone":if(pending!=null){pending.written=true;pending.sent=SystemClock.elapsedRealtime();if(pending.cmd==8){if(window!=null&&window.ended())finishBurst();}else complete();}break;
            case "rx":receiveBytes(TangFrameCodec.fromHex(data.optString("hex")));break;
        }
    }catch(Exception e){fail(e.getMessage());}if(download==null)render();}
    private void receiveBytes(byte[] bytes){if(closed||!channel)return;try{
        if(pending!=null){pending.received+=bytes.length;pending.lastRx=SystemClock.elapsedRealtime();if(pending.cmd==1&&pending.statusRaw.size()+bytes.length<=128)pending.statusRaw.write(bytes,0,bytes.length);}
        for(Reply r:decoder.feed(bytes)){
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
        try{p.success.accept(p.reply);}catch(Exception e){fail(e.getMessage());}if(download==null)render();
    }
    private void acceptStatus(Reply reply){boolean wasReady=connectionStatus.ready();snapshot=new Snapshot(reply);connectionStatus.verified();if(!wasReady)android.util.Log.i("PianoRecorder","BOARD_READY state="+snapshot.state+" fault="+snapshot.fault+" take="+snapshot.take+" samples="+snapshot.samples);}
    private void refreshStatus(){if(!channel||pending!=null||download!=null)return;decoder.clear();connectionStatus.verifying(address);nextPoll=Long.MAX_VALUE;request(1,0,r->{acceptStatus(r);render();});}
    private void command(int cmd){if(!connectionStatus.ready()||snapshot==null||download!=null||pending!=null)return;request(cmd,0,r->{acceptStatus(r);android.util.Log.i("PianoRecorder","COMMAND_OK cmd="+cmd+" state="+snapshot.state+" take="+snapshot.take+" samples="+snapshot.samples);render();});}
    private void selectSlot(int slot){if(!connectionStatus.ready()||snapshot==null||snapshot.version!=3||download!=null||pending!=null||snapshot.leased)return;request(10,slot,r->{acceptStatus(r);render();});}
    private File directory(){return new File(getFilesDir(),"piano-recordings");}
    private void beginDownload(){if(!connectionStatus.ready()||snapshot==null||snapshot.state!=5||pending!=null||download!=null)return;
        if(snapshot.version==3){Snapshot expected=snapshot;request(11,0,r->{Snapshot held=new Snapshot(r);if(!expected.same(held)||!held.leased){fail("录音已变化，请刷新后重试");return;}snapshot=held;startDownload();});}
        else startDownload();
    }
    private void startDownload(){try{
        releaseLeaseWhenIdle=false;
        download=new Download(directory(),address,snapshot);started=SystemClock.elapsedRealtime();initialOffset=download.offset();retries=0;repairBlocks=0;burstWindows=0;lastProgress=0;ble.transferPriority(true);
        android.util.Log.i("PianoRecorder","DOWNLOAD_START version="+snapshot.version+" offset="+initialOffset+" uart_frame_errors="+snapshot.uartFrameErrors+" uart_crc_errors="+snapshot.uartCrcErrors+" busy_rx_bytes="+snapshot.busyRxBytes);render();
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);nextBlock();
    }catch(Exception e){fail(e.getMessage());}}
    private void nextBlock(){Download current=download;if(current==null)return;
        long elapsed=Math.max(1,SystemClock.elapsedRealtime()-started),bytes=current.offset()-initialOffset;
        transferMeter.setProgress((int)(1000*current.offset()/Math.max(1,current.meta.bytes())));
        if(SystemClock.elapsedRealtime()-lastProgress>=200){lastProgress=SystemClock.elapsedRealtime();progress.setText(String.format(Locale.CHINA,"回传 %.1f%% · %d / %d 字节 · %.1f KB/s · 补读 %d 块 · 重试 %d 次",100.0*current.offset()/current.meta.bytes(),current.offset(),current.meta.bytes(),bytes*1000.0/elapsed/1024,repairBlocks,retries));}
        if(current.meta.version==3&&snapshot.confirmedBytes!=current.offset()){
            request(14,current.offset(),r->{if(download!=current)return;snapshot=new Snapshot(r);nextBlock();});return;
        }
        if(current.offset()==current.meta.bytes())request(1,0,r->{if(download!=current)return;try{
            Snapshot finalState=new Snapshot(r);File wav=current.finish(finalState);download=null;snapshot=finalState;ble.transferPriority(false);getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);progress.setText("已保存 · 整段 CRC 校验通过\n"+wav.getName());android.util.Log.i("PianoRecorder","WAV_SAVED bytes="+finalState.bytes()+" crc="+Long.toHexString(finalState.crc)+" elapsed_ms="+(SystemClock.elapsedRealtime()-started)+" retries="+retries+" resumed_bytes="+initialOffset+" repair_blocks="+repairBlocks+" windows="+burstWindows+" uart_frame_errors="+finalState.uartFrameErrors+" uart_crc_errors="+finalState.uartCrcErrors+" busy_rx_bytes="+finalState.busyRxBytes);listFiles();
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
    private void pauseDownload(){Download old=download;download=null;getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);if(snapshot!=null&&snapshot.version==3)releaseLeaseWhenIdle=true;if(old!=null){ble.transferPriority(false);try{old.close();}catch(IOException e){progress.setText("保存接收进度失败："+e.getMessage());return;}progress.setText("已暂停；完整块已保存，重连后可继续接收。");}render();}
    private void fail(String message){pending=null;window=null;connectionStatus.failed(message);pauseDownload();nextPoll=Long.MAX_VALUE;progress.setText(message==null?"回传失败":message);android.util.Log.w("PianoRecorder",message==null?"failure":message);render();}
    private void render(){if(record==null)return;connection.setText(connectionStatus.text());boolean idle=channel&&connectionStatus.ready()&&pending==null&&download==null&&snapshot!=null;
        if(snapshot!=null&&snapshot.state==5&&snapshot.samples>0&&!snapshot.identity().equals(lastLoggedIdentity)){lastLoggedIdentity=snapshot.identity();android.util.Log.i("PianoRecorder","RECORDING_READY version="+snapshot.version+" take="+snapshot.take+" samples="+snapshot.samples+" crc="+Long.toHexString(snapshot.crc)+" gap_ms="+snapshot.gapMs);}
        refresh.setEnabled(channel&&pending==null&&download==null);record.setEnabled(idle&&snapshot.state==2&&snapshot.memoryReady&&!snapshot.leased);stop.setEnabled(idle&&snapshot.state==3);
        receive.setEnabled(idle&&snapshot.state==5&&snapshot.samples>0);erase.setEnabled(idle&&snapshot.state==5&&!snapshot.leased);boardPlay.setEnabled(idle&&snapshot.state==5&&snapshot.samples>0&&!snapshot.leased);boardStop.setEnabled(idle&&(snapshot.state==6||snapshot.state==7));cancel.setEnabled(download!=null);
        boolean dual=snapshot!=null&&snapshot.slotCount==2;slotOne.setVisibility(dual?android.view.View.VISIBLE:android.view.View.GONE);slotTwo.setVisibility(dual?android.view.View.VISIBLE:android.view.View.GONE);
        boolean canSelect=idle&&dual&&!snapshot.leased&&snapshot.memoryReady&&(snapshot.state==2||snapshot.state==5);
        slotOne.setEnabled(canSelect&&snapshot.selectedSlot!=0);slotTwo.setEnabled(canSelect&&snapshot.selectedSlot!=1);
        if(snapshot!=null){capacityLabel.setText(String.format(Locale.CHINA,"%d 个录音槽 · 每槽最长 %.0f 秒 · FPGA DDR3",snapshot.slotCount,snapshot.capacity*8.0/390625));String[] names={"DDR3 初始化","DDR3 自检","空录音位","录音中","保存到 DDR3","录音就绪","准备耳机回放","耳机回放中","板端故障","读取 DDR3"};state.setText(String.format(Locale.CHINA,"槽 %d · %s · 已写入 %.2f 秒\n录音编号 %d · 峰值 %d · 故障码 %d",snapshot.selectedSlot+1,names[snapshot.state],snapshot.committedSamples*8.0/390625,snapshot.take,snapshot.peak,snapshot.fault));}
        else state.setText("尚未核对录音固件");
    }
    private void listFiles(){files.removeAllViews();File[] all=directory().listFiles((d,n)->n.endsWith(".wav"));if(all==null||all.length==0){label(files,"给第一段灵感留个位置。\n完整接收的录音会出现在这里。",15);return;}Arrays.sort(all,Comparator.comparingLong(File::lastModified).reversed());
        PocketFiles checker=new PocketFiles(this,(type,data)->{});
        for(File f:all){try{checker.verified(f.getName());}catch(IOException invalid){continue;}String date=new java.text.SimpleDateFormat("MM-dd HH:mm",Locale.CHINA).format(new Date(f.lastModified()));LinearLayout saved=card(files,0xfffffcf1,"钢琴演奏 · "+date);label(saved,String.format(Locale.CHINA,"%.2f 秒 · %d KB · 已完整保存",(f.length()-44)/2.0*8/390625,Math.round(f.length()/1024.0)),12);LinearLayout actions=row(saved);button(actions,"▶ 试听",()->play(f));secondary(button(actions,"保存 WAV",()->{exported=f;Intent intent=new Intent(Intent.ACTION_CREATE_DOCUMENT).setType("audio/wav").addCategory(Intent.CATEGORY_OPENABLE).putExtra(Intent.EXTRA_TITLE,f.getName());startActivityForResult(intent,71);}));}}
    private void play(File f){try{stopPlayer();player=new MediaPlayer();player.setDataSource(f.getPath());player.setOnCompletionListener(p->stopPlayer());player.prepare();player.start();}catch(Exception e){progress.setText("播放失败："+e.getMessage());stopPlayer();}}
    private void stopPlayer(){if(player!=null){player.release();player=null;}}
    @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);if(request==71&&result==RESULT_OK&&data!=null&&data.getData()!=null&&exported!=null){try(InputStream in=new FileInputStream(exported);OutputStream out=getContentResolver().openOutputStream(data.getData(),"w")){if(out==null)throw new IOException("无法打开目标文件");byte[] b=new byte[8192];int n;while((n=in.read(b))!=-1)out.write(b,0,n);out.flush();progress.setText("WAV 已导出到所选位置");}catch(Exception e){progress.setText("导出失败："+e.getMessage());}}}
    @Override protected void onStop(){super.onStop();ble.stopScan();}
    @Override protected void onDestroy(){closed=true;handler.removeCallbacks(timer);pauseDownload();stopPlayer();ble.close();super.onDestroy();}
}
