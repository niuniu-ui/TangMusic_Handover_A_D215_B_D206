package cn.tangmusic.app;

import android.Manifest;
import cn.tangmusic.protocol.TmcpClient;
import cn.tangmusic.protocol.TangFrameCodec;
import cn.tangmusic.protocol.BleWriteQueue;
import cn.tangmusic.protocol.ScoreObject;
import cn.tangmusic.protocol.ScoreUploadClient;
import cn.tangmusic.protocol.KeymapClient;
import cn.tangmusic.protocol.AudioLoopClient;
import java.util.LinkedHashMap;
import java.util.Map;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import org.json.JSONObject;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class MainActivity extends Activity {
    private static final String ORIGIN="https://appassets.androidplatform.net";
    private static final int PICK_MIDI=10, CREATE_FILE=11, BLE_PERMISSIONS=12, ENABLE_BLUETOOTH=13, PICK_POCKET=14;
    private final Handler ui=new Handler(Looper.getMainLooper());
    private final ExecutorService io=Executors.newSingleThreadExecutor();
    private WebView web;
    private BleTransport ble;
    private TmcpClient protocol;
    private RecorderClient recorder;
    private BleWriteQueue writes;
    private ScoreUploadClient scores;private String scoreSession="";private volatile int linkGeneration;
    private KeymapClient keymap;private AudioLoopClient loops;
    private final Runnable scoreTimer=new Runnable(){public void run(){if(destroyed)return;long now=android.os.SystemClock.elapsedRealtime();if(scores!=null)scores.tick(now);if(loops!=null)loops.tick(now);ui.postDelayed(this,200);}};
    private MidiRepository files;
    private boolean destroyed=false, scanAfterPermission=false;
    private String exportName,exportMessage,importToken;
    private byte[] exportContent;
    private PocketFiles pocket;private android.media.MediaPlayer pocketPlayer;
    private final ScoreBrowser scoreBrowser=new ScoreBrowser();
    private android.webkit.ValueCallback<Uri[]> pocketChooser;private JSONObject lastProtocolState;

    @Override public void onCreate(Bundle state){
        super.onCreate(state);
        ble=new BleTransport(this,this::handleBleEvent,true);
        writes=new BleWriteQueue(bytes->ble.send(TangFrameCodec.toHex(bytes)),owner->{
            if(owner==BleWriteQueue.Owner.CONTROL)protocol.writeComplete();
            else if(owner==BleWriteQueue.Owner.RECORDER)recorder.writeComplete();
        });
        recorder=new RecorderClient(this,new RecorderClient.Link(){
            public void send(String hex){writes.send(BleWriteQueue.Owner.RECORDER,TangFrameCodec.fromHex(hex));}
            public void transferPriority(boolean active){ble.transferPriority(active);}
        },new RecorderClient.Listener(){
            public void state(JSONObject value){emit("recorderState",value);}
            public void filesChanged(){if(pocket!=null)io.execute(()->pocket.list());}
            public void keepAwake(boolean awake){if(awake)getWindow().addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);else getWindow().clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);}
        });
        protocol=new TmcpClient(bytes->{int epoch=linkGeneration;ui.post(()->{if(!destroyed&&epoch==linkGeneration&&ble.channelReady())writes.send(BleWriteQueue.Owner.CONTROL,bytes);});},new TmcpClient.Listener(){
            @Override public void state(TmcpClient.State state){try{JSONObject data=new JSONObject();data.put("phase",state.phase);data.put("ready",state.ready);data.put("busy",state.busy);data.put("error",state.error);data.put("session",state.sessionHex);data.put("revision",state.revision);data.put("pingMs",state.pingMs);data.put("pendingCommand",state.pendingCommand);JSONObject values=new JSONObject();for(Map.Entry<Integer,Integer> item:state.parameters.entrySet())values.put(String.valueOf(item.getKey()),item.getValue());data.put("parameters",values);emit("protocolState",data);}catch(Exception ignored){}}
            @Override public void log(String message){android.util.Log.i("TangProtocol",message);try{emit("protocolLog",new JSONObject().put("message",message));}catch(Exception ignored){}}
            @Override public void result(boolean success,int status,long detail,String message){try{emit("parameterResult",new JSONObject().put("success",success).put("status",status).put("detail",detail).put("message",message));}catch(Exception ignored){}}
        });
        scores=new ScoreUploadClient(protocol,this::publishScore,task->ui.post(task));ui.post(scoreTimer);
        keymap=new KeymapClient(protocol,this::publishKeymap,task->ui.post(task));
        loops=new AudioLoopClient(protocol,this::publishLoops,task->ui.post(task));
        ble.binaryReceiver(bytes->{protocol.receive(bytes);recorder.receiveBytes(bytes);try{emit("rx",new JSONObject().put("bytes",bytes.length).put("hex",TangFrameCodec.toHex(java.util.Arrays.copyOf(bytes,Math.min(bytes.length,32)))));}catch(Exception ignored){}});
        files=new MidiRepository(this,(type,data)->emit(type,data));
        FrameLayout root=new FrameLayout(this);root.setBackgroundColor(Color.rgb(9,21,34));
        root.setOnApplyWindowInsetsListener((view,insets)->{view.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());return insets;});
        pocket=new PocketFiles(this,this::emit);
        root.setBackgroundColor(Color.rgb(247,246,232));
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        web=new WebView(this);root.addView(web,new FrameLayout.LayoutParams(-1,-1));setContentView(root);
        web.setBackgroundColor(Color.rgb(247,246,232));
        WebSettings s=web.getSettings();s.setJavaScriptEnabled(true);s.setDomStorageEnabled(true);s.setAllowFileAccess(false);s.setAllowContentAccess(true);s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);s.setSupportMultipleWindows(false);
        WebView.setWebContentsDebuggingEnabled(BuildConfig.DEBUG);
        web.addJavascriptInterface(new NativeBridge(),"TangAndroid");
        web.setWebChromeClient(new WebChromeClient(){@Override public boolean onShowFileChooser(WebView view,android.webkit.ValueCallback<Uri[]> callback,FileChooserParams params){if(pocketChooser!=null)pocketChooser.onReceiveValue(null);pocketChooser=callback;Intent pick=new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*").addCategory(Intent.CATEGORY_OPENABLE);pick.putExtra(Intent.EXTRA_MIME_TYPES,new String[]{"application/json","text/plain"});try{startActivityForResult(pick,PICK_POCKET);}catch(Exception e){pocketChooser.onReceiveValue(null);pocketChooser=null;error("无法打开文件选择器");}return true;}});
        web.setWebViewClient(new WebViewClient(){
            @Override public WebResourceResponse shouldInterceptRequest(WebView view,WebResourceRequest req){
                Uri uri=req.getUrl();String path=uri.getPath();
                if(!"https".equals(uri.getScheme())||!"appassets.androidplatform.net".equals(uri.getHost())||path==null||!path.startsWith("/assets/")||path.contains(".."))return denied();
                try {String relative=path.substring("/assets/".length());return new WebResourceResponse(mime(relative),"UTF-8",getAssets().open("web/"+relative));}catch(IOException e){return new WebResourceResponse("text/plain","UTF-8",404,"Not found",null,new ByteArrayInputStream(new byte[0]));}
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest req){
                String value=req.getUrl().toString();if(value.startsWith(ORIGIN+"/assets/"))return false;
                if("https".equals(req.getUrl().getScheme())){try{startActivity(new Intent(Intent.ACTION_VIEW,req.getUrl()));}catch(Exception e){error("没有可打开网页的浏览器");}}
                return true;
            }
            @Override public void onPageFinished(WebView view,String url){if(url.startsWith(ORIGIN+"/assets/index.html")||url.startsWith(ORIGIN+"/assets/controls.html")){emit("ready",ble.configuration());if(ble.channelReady()){try{JSONObject state=ble.configuration();state.put("address",state.optString("lastAddress"));emit("channelReady",state);}catch(Exception ignored){}}if(lastProtocolState!=null)emit("protocolState",lastProtocolState);io.execute(()->files.list());}}
        });
        web.loadUrl(ORIGIN+"/assets/index.html");
        if(Build.VERSION.SDK_INT>=33)BackApi33.register(this,this::handleBack);
    }
    private void handleBleEvent(String type,JSONObject data){
        if(protocol!=null){
            if(type.equals("channelReady")){protocol.channelReady();recorder.channelReady(data.optString("address"));}
            else if(type.equals("disconnected")){linkGeneration++;writes.clear();protocol.disconnected();recorder.disconnected();scoreSession="";if(scores!=null)scores.disconnected();if(keymap!=null)keymap.disconnected();if(loops!=null)loops.disconnected();}
            else if(type.equals("txDone"))writes.completed();
            else if(type.equals("rx")){try{protocol.receive(TangFrameCodec.fromHex(data.optString("hex")));}catch(Exception e){protocol.transportError(e.getMessage());}}
            else if(type.equals("error")){writes.clear();protocol.transportError(data.optString("message"));recorder.transportError(data.optString("message"));}
        }
        emit(type,data);
    }
    private static WebResourceResponse denied(){return new WebResourceResponse("text/plain","UTF-8",403,"Blocked",null,new ByteArrayInputStream(new byte[0]));}
    private static String mime(String file){if(file.endsWith(".html"))return "text/html";if(file.endsWith(".css"))return "text/css";if(file.endsWith(".js"))return "application/javascript";if(file.endsWith(".svg"))return "image/svg+xml";if(file.endsWith(".png"))return "image/png";if(file.endsWith(".json"))return "application/json";return "application/octet-stream";}
    void emit(String type,JSONObject data){if(type.equals("protocolState"))lastProtocolState=data;ui.post(()->{if(destroyed||web==null)return;try{JSONObject event=new JSONObject();event.put("type",type);event.put("data",data);web.evaluateJavascript("window.TangNativeEvent && window.TangNativeEvent("+event+")",null);if(type.equals("protocolState")&&data.optBoolean("ready")&&scores!=null&&!data.optString("session").equals(scoreSession)){scoreSession=data.optString("session");scores.sessionReady();if(keymap!=null)keymap.sessionReady();if(loops!=null)loops.sessionReady();}}catch(Exception ignored){}});}
    private void publishScore(){if(scores==null)return;try{emit("scoreState",new JSONObject().put("supported",scores.supported()).put("busy",scores.busy()).put("uploading",scores.uploading()).put("valid",scores.valid()).put("active",scores.active()).put("waiting",scores.waiting()).put("completed",scores.completed()).put("progress",scores.progress()).put("message",scores.message()).put("elapsedUs",scores.elapsedUs()).put("targetKeys",scores.targetKeys()).put("current",scores.current()).put("total",scores.total()).put("limit",scores.limit()));}catch(Exception e){error(e.getMessage());}}
    private void publishKeymap(){if(keymap==null)return;try{org.json.JSONArray values=new org.json.JSONArray();int[] mapping=keymap.mapping();if(mapping!=null)for(int value:mapping)values.put(value);emit("keymapState",new JSONObject().put("supported",keymap.supported()).put("busy",keymap.busy()).put("revision",keymap.revision()).put("mapping",values).put("message",keymap.message()));}catch(Exception e){error(e.getMessage());}}
    private void publishLoops(){if(loops==null)return;try{
        JSONObject d=new JSONObject().put("supported",loops.supported()).put("pending",loops.pending()).put("message",loops.message());byte[] b=loops.state();d.put("known",b!=null);
        if(b!=null){String[] names={"running","recording","armed","stopRequested","finalizing","preparing"};for(int i=0;i<names.length;i++)d.put(names[i],(b[1]&(1<<i))!=0);
            d.put("fault",b[2]&255).put("recordTrack",b[3]&255).put("lengthSamples",TangFrameCodec.get(b,4,4)).put("position",TangFrameCodec.get(b,8,4)).put("countRemaining",TangFrameCodec.get(b,12,4));
            d.put("revision",TangFrameCodec.get(b,24,4)).put("verifiedSamples",TangFrameCodec.get(b,28,4)).put("bpm",TangFrameCodec.get(b,32,2)).put("bars",b[34]&255).put("countIn",b[35]&255);
            org.json.JSONArray tracks=new org.json.JSONArray();for(int i=0;i<4;i++)tracks.put(new JSONObject().put("valid",(b[16]&(1<<i))!=0).put("muted",(b[17]&(1<<i))!=0).put("solo",(b[18]&(1<<i))!=0).put("undo",(b[19]&(1<<i))!=0).put("volume",b[20+i]&255));d.put("tracks",tracks);
        }emit("loopState",d);
    }catch(Exception e){error(e.getMessage());}}
    private void error(String message){try{emit("error",new JSONObject().put("message",message));}catch(Exception ignored){}}
    private void requestScan(){
        String[] required=Build.VERSION.SDK_INT>=31?new String[]{Manifest.permission.BLUETOOTH_SCAN,Manifest.permission.BLUETOOTH_CONNECT}:new String[]{Manifest.permission.ACCESS_FINE_LOCATION};
        for(String permission:required)if(checkSelfPermission(permission)!=PackageManager.PERMISSION_GRANTED){scanAfterPermission=true;requestPermissions(required,BLE_PERMISSIONS);return;}
        if(!ble.available()){error("本设备不支持蓝牙 BLE");return;}
        try{if(!ble.enabled()){scanAfterPermission=true;startActivityForResult(new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE),ENABLE_BLUETOOTH);return;}ble.scan();}catch(SecurityException e){error("请在系统设置中授予附近设备／蓝牙权限");}
    }
    @Override public void onRequestPermissionsResult(int request,String[] permissions,int[] results){super.onRequestPermissionsResult(request,permissions,results);if(request==BLE_PERMISSIONS){boolean granted=results.length>0;for(int r:results)granted&=r==PackageManager.PERMISSION_GRANTED;if(granted&&scanAfterPermission){scanAfterPermission=false;requestScan();}else{scanAfterPermission=false;error("蓝牙扫描权限未授予，可以在系统设置中重新开启");}}}
    @Override protected void onActivityResult(int request,int result,Intent intent){
        super.onActivityResult(request,result,intent);
        if(request==PICK_POCKET){if(pocketChooser!=null){pocketChooser.onReceiveValue(result==RESULT_OK&&intent!=null&&intent.getData()!=null?new Uri[]{intent.getData()}:null);pocketChooser=null;}return;}
        if(request==ENABLE_BLUETOOTH){if(result==RESULT_OK){scanAfterPermission=false;requestScan();}else error("蓝牙未开启");return;}
        if(request==PICK_MIDI){if(result==RESULT_OK&&intent!=null&&intent.getData()!=null){Uri uri=intent.getData();String token=importToken;io.execute(()->files.importDocument(uri,token));}else emit("fileCancelled",new JSONObject());}
        if(request==CREATE_FILE){if(result==RESULT_OK&&intent!=null&&intent.getData()!=null){Uri uri=intent.getData();byte[] contents=exportContent;String message=exportMessage;exportContent=null;io.execute(()->files.export(uri,contents,message));}else{exportContent=null;emit("exportCancelled",new JSONObject());}}
    }
    public final class NativeBridge {
        @JavascriptInterface public void browseScores(){ui.post(()->scoreBrowser.open(MainActivity.this,url->{if(!destroyed&&web!=null)web.evaluateJavascript("window.TangLibrary && TangLibrary.downloadUrl("+JSONObject.quote(url)+")",null);}));}
        @JavascriptInterface public void downloadPocketScore(String url,String token){io.execute(()->pocket.download(url,token));}
        @JavascriptInterface public void cancelPocketDownload(String token){pocket.cancel(token);}
        @JavascriptInterface public void listPocketRecordings(){io.execute(()->pocket.list());}
        @JavascriptInterface public void stopPocketAudio(){ui.post(MainActivity.this::stopPocketPlayer);}
        @JavascriptInterface public void playPocketRecording(String name){io.execute(()->{try{pocket.verified(name);java.io.File f=pocket.checked(name);ui.post(()->{try{stopPocketPlayer();pocketPlayer=new android.media.MediaPlayer();pocketPlayer.setDataSource(f.getPath());pocketPlayer.setOnCompletionListener(p->stopPocketPlayer());pocketPlayer.prepare();pocketPlayer.start();emit("pocketAudio",new JSONObject().put("playing",true).put("name",name).put("message","正在试听已保存的录音"));}catch(Exception e){stopPocketPlayer();error(e.getMessage());}});}catch(Exception e){error(e.getMessage());}});}
        @JavascriptInterface public void exportPocketRecording(String name){io.execute(()->{try{byte[] bytes=pocket.verified(name);ui.post(()->chooseExport(name,"audio/wav",bytes,"WAV 已保存到所选位置"));}catch(Exception e){error(e.getMessage());}});}
        @JavascriptInterface public void openPianoRecorder(){ui.post(()->{web.evaluateJavascript("window.TangApp && TangApp.nav('recordings')",null);recorder.publish();});}
        @JavascriptInterface public void recorderAction(String action,int slot){ui.post(()->{try{recorder.action(action,slot);}catch(Exception e){error(e.getMessage());}});}
        @JavascriptInterface public void recorderStatus(){ui.post(()->recorder.publish());}
        @JavascriptInterface public void uploadScore(String json){ui.post(()->{try{
            if(json.length()>500000)throw new IllegalArgumentException("曲谱数据过大");
            JSONObject data=new JSONObject(json);org.json.JSONArray notes=data.getJSONArray("notes");java.util.List<ScoreObject.Note> parsed=new java.util.ArrayList<>();
            for(int i=0;i<notes.length();i++){JSONObject n=notes.getJSONObject(i);parsed.add(new ScoreObject.Note(integer(n,"startUs"),integer(n,"durationUs"),Math.toIntExact(integer(n,"pitch")),Math.toIntExact(integer(n,"velocity"))));}
            scores.upload(new ScoreObject(parsed,integer(data,"durationUs"),protocol.maxScoreNotes()));
        }catch(Exception e){error(e.getMessage());}});}
        @JavascriptInterface public void scoreAction(String action){ui.post(()->{switch(action){case "refresh":scores.refresh();break;case "cancel":scores.cancel();break;case "timed":scores.start(false);break;case "wait":scores.start(true);break;case "stop":scores.stop();break;}publishScore();});}
        @JavascriptInterface public void scoreStatus(){ui.post(MainActivity.this::publishScore);}
        @JavascriptInterface public void keymapStatus(){ui.post(MainActivity.this::publishKeymap);}
        @JavascriptInterface public void loopStatus(){ui.post(MainActivity.this::publishLoops);}
        @JavascriptInterface public void loopAction(String json){ui.post(()->{try{
            JSONObject d=new JSONObject(json);String action=d.getString("action");
            if(action.equals("configure"))loops.configure(Math.toIntExact(integer(d,"bpm")),Math.toIntExact(integer(d,"bars")),Math.toIntExact(integer(d,"countIn")),integer(d,"revision"));
            else if(action.equals("mix"))loops.mix(Math.toIntExact(integer(d,"track")),d.getBoolean("muted"),d.getBoolean("solo"),Math.toIntExact(integer(d,"volume")),integer(d,"revision"));
            else loops.action(action,d.has("track")?Math.toIntExact(integer(d,"track")):0);
        }catch(Exception e){error(e.getMessage());}});}
        @JavascriptInterface public void readKeymap(){ui.post(()->keymap.read());}
        @JavascriptInterface public void setKeymap(String json){ui.post(()->{try{JSONObject d=new JSONObject(json);org.json.JSONArray a=d.getJSONArray("mapping");int[] map=new int[a.length()];for(int i=0;i<map.length;i++){Object v=a.get(i);if(!(v instanceof Number)||((Number)v).doubleValue()!=Math.rint(((Number)v).doubleValue()))throw new IllegalArgumentException("音高必须为整数");map[i]=Math.toIntExact(((Number)v).longValue());}keymap.apply(integer(d,"expectedRevision"),map);}catch(Exception e){error(e.getMessage());}});}
        @JavascriptInterface public void selectMidi(String token){ui.post(()->{importToken=token;Intent pick=new Intent(Intent.ACTION_OPEN_DOCUMENT);pick.setType("*/*");pick.addCategory(Intent.CATEGORY_OPENABLE);pick.putExtra(Intent.EXTRA_MIME_TYPES,new String[]{"audio/midi","audio/x-midi","audio/mid","application/octet-stream"});try{startActivityForResult(pick,PICK_MIDI);}catch(Exception e){emit("fileCancelled",new JSONObject());error("无法打开文件选择器");}});}
        @JavascriptInterface public void downloadMidi(String url,String token,String hash,String title){io.execute(()->files.download(url,token,hash,title));}
        @JavascriptInterface public void cancelMidi(String token){files.cancel(token);io.execute(()->files.discard(token));}
        @JavascriptInterface public void commitMidi(String token,String metadata){io.execute(()->files.commit(token,metadata));}
        @JavascriptInterface public void listMidi(){io.execute(()->files.list());}
        @JavascriptInterface public void openCachedMidi(String id,String token){io.execute(()->files.open(id,token));}
        @JavascriptInterface public void removeCachedMidi(String id){io.execute(()->files.remove(id));}
        @JavascriptInterface public void scanBle(){ui.post(MainActivity.this::requestScan);}
        @JavascriptInterface public void stopScan(){ui.post(()->ble.stopScan());}
        @JavascriptInterface public void connectBle(String address){ui.post(()->ble.connect(address));}
        @JavascriptInterface public void disconnectBle(){ui.post(()->ble.disconnect());}
        @JavascriptInterface public void sendHex(String hex){ui.post(()->{if(protocol.sessionActive()){error("自动协议会话运行中，请使用PING和参数入口");return;}ble.send(hex);});}
        @JavascriptInterface public void protocolReconnect(){ui.post(()->{if(ble.channelReady())protocol.channelReady();else error("请先连接BLE通道");});}
        @JavascriptInterface public void protocolPing(){protocol.ping();}
        @JavascriptInterface public void readParameters(){protocol.readParameters();}
        @JavascriptInterface public void setParameters(String json){try{JSONObject request=new JSONObject(json);long revision=request.getLong("expectedRevision");JSONObject values=request.getJSONObject("values");Map<Integer,Integer> changes=new LinkedHashMap<>();java.util.Iterator<String> keys=values.keys();while(keys.hasNext()){String key=keys.next();Object raw=values.get(key);if(!(raw instanceof Number)||((Number)raw).doubleValue()!=((Number)raw).intValue())throw new IllegalArgumentException("参数必须是整数");changes.put(Integer.parseInt(key),((Number)raw).intValue());}protocol.setParameters(revision,changes);}catch(Exception e){error("参数格式错误："+e.getMessage());}}
        @JavascriptInterface public void configureBle(String service,String tx,String rx){ui.post(()->ble.configure(service,tx,rx));}
        @JavascriptInterface public void saveJson(String name,String json){ui.post(()->{if(json==null||json.length()>2_000_000){error("导出数据过大");return;}chooseExport(name,"application/json",json.getBytes(StandardCharsets.UTF_8),"乐句事件 JSON 已保存");});}
        @JavascriptInterface public void exportMidi(String id,String name){io.execute(()->{try{byte[] bytes=files.exportBytes(id);ui.post(()->chooseExport(name,"audio/midi",bytes,"MIDI 文件已保存"));}catch(Exception e){error(e.getMessage());}});}

    }
    private void chooseExport(String name,String mimeType,byte[] bytes,String message){
        if(exportContent!=null){error("请先完成当前文件保存");return;}
        exportContent=bytes;exportMessage=message;exportName=name.replaceAll("[\\\\/:*?\"<>|]","_");
        Intent create=new Intent(Intent.ACTION_CREATE_DOCUMENT);create.setType(mimeType);create.addCategory(Intent.CATEGORY_OPENABLE);create.putExtra(Intent.EXTRA_TITLE,exportName);
        try{startActivityForResult(create,CREATE_FILE);}catch(Exception e){exportContent=null;error("无法打开保存文件窗口");}
    }
    private void handleBack(){if(web!=null&&web.getUrl()!=null&&web.getUrl().contains("/controls.html")){web.loadUrl(ORIGIN+"/assets/index.html#device");return;}if(web==null){finish();return;}web.evaluateJavascript("window.TangBack ? window.TangBack() : false",handled->{if(!"true".equals(handled))finish();});}
    // API 33+ uses the registered platform callback; this override serves Android 8–12.
    @SuppressLint("GestureBackNavigation")
    @Override public void onBackPressed(){handleBack();}
    @android.annotation.TargetApi(33)
    private static final class BackApi33 {
        static void register(Activity activity,Runnable handler){activity.getOnBackInvokedDispatcher().registerOnBackInvokedCallback(android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT,handler::run);}
    }
    @Override protected void onResume(){super.onResume();if(pocket!=null)io.execute(()->pocket.list());}
    private void stopPocketPlayer(){if(pocketPlayer!=null){pocketPlayer.release();pocketPlayer=null;try{emit("pocketAudio",new JSONObject().put("playing",false));}catch(Exception ignored){}}}
    private static long integer(JSONObject obj,String key)throws org.json.JSONException{Object value=obj.get(key);if(!(value instanceof Number))throw new IllegalArgumentException("曲谱字段必须为整数："+key);double n=((Number)value).doubleValue();if(!Double.isFinite(n)||n!=Math.rint(n)||Math.abs(n)>9007199254740991d)throw new IllegalArgumentException("曲谱字段无效："+key);return ((Number)value).longValue();}
    @Override protected void onStop(){super.onStop();ble.stopScan();stopPocketPlayer();}
    @Override protected void onDestroy(){destroyed=true;scoreBrowser.close();ui.removeCallbacks(scoreTimer);stopPocketPlayer();if(pocketChooser!=null){pocketChooser.onReceiveValue(null);pocketChooser=null;}if(recorder!=null)recorder.close();if(protocol!=null)protocol.close();writes.clear();ble.close();io.shutdown();if(web!=null){web.removeJavascriptInterface("TangAndroid");web.destroy();web=null;}super.onDestroy();}
}
