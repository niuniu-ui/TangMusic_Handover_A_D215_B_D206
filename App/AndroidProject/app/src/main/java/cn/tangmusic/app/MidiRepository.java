package cn.tangmusic.app;

import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.provider.OpenableColumns;
import android.util.Base64;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.*;

final class MidiRepository {
    interface Events {void emit(String type,JSONObject data);}
    private static final int LIMIT=2*1024*1024,MAX_FILES=50;
    private volatile java.net.HttpURLConnection activeConnection;
    private volatile String activeToken="";
    private final java.util.Set<String> cancelled=java.util.concurrent.ConcurrentHashMap.newKeySet();
    private String pendingToken=""; private byte[] pendingBytes; private JSONObject pendingMeta;
    void cancel(String token){cancelled.add(token);if(token.equals(activeToken)){HttpURLConnection c=activeConnection;if(c!=null)c.disconnect();}}
    void discard(String token){if(token.equals(pendingToken)){pendingToken="";pendingMeta=null;pendingBytes=null;}cancelled.remove(token);}
    private void check(String token)throws IOException{if(cancelled.contains(token))throw new IOException("已取消");}
    private final Context context;private final Events events;private final File directory;
    MidiRepository(Context context,Events events){this.context=context;this.events=events;directory=new File(context.getFilesDir(),"midi-library");directory.mkdirs();}
    private void error(String token,Exception e){try{events.emit("fileError",new JSONObject().put("token",token).put("message",e.getMessage()==null?"文件处理失败":e.getMessage()));}catch(Exception ignored){}}
    private static byte[] readBounded(InputStream in) throws IOException {ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] buffer=new byte[8192];int size;while((size=in.read(buffer))!=-1){if(out.size()+size>LIMIT)throw new IOException("MIDI 文件不能超过 2 MB");out.write(buffer,0,size);}return out.toByteArray();}
    private static void validate(byte[] bytes) throws IOException {if(bytes.length<14||bytes[0]!='M'||bytes[1]!='T'||bytes[2]!='h'||bytes[3]!='d')throw new IOException("文件不是标准 MIDI；MP3、WAV、PDF 不能用于音符适配");int type=((bytes[8]&255)<<8)|(bytes[9]&255);if(type>1)throw new IOException("第一版支持 MIDI 类型 0 和 1，暂不支持类型 2");if((bytes[12]&128)!=0)throw new IOException("暂不支持 SMPTE 时间制 MIDI，请先转换为 PPQ 时间制");}
    void importDocument(Uri uri,String token){try{String name="本地曲谱.mid";try(Cursor cursor=context.getContentResolver().query(uri,new String[]{OpenableColumns.DISPLAY_NAME},null,null,null)){if(cursor!=null&&cursor.moveToFirst())name=cursor.getString(0);}byte[] bytes;try(InputStream in=context.getContentResolver().openInputStream(uri)){if(in==null)throw new IOException("文件无法读取");bytes=readBounded(in);}validate(bytes);storeAndEmit(name,bytes,"local","",token,"");}catch(Exception e){error(token,e);}}
    void download(String value,String token,String expectedHash,String title){
        activeToken=token;
        try {
            check(token);long deadline=System.nanoTime()+30_000_000_000L;URL url=new URL(value);if(!"https".equalsIgnoreCase(url.getProtocol())||url.getUserInfo()!=null)throw new IOException("请使用不含账号密码的 HTTPS MIDI 文件直链");
            HttpURLConnection connection=null;byte[] data=null;
            for(int redirects=0;redirects<=4;redirects++){
                check(token);if(System.nanoTime()>deadline)throw new IOException("下载超时，请重试");connection=(HttpURLConnection)url.openConnection();activeConnection=connection;connection.setConnectTimeout(10000);connection.setReadTimeout(10000);connection.setInstanceFollowRedirects(false);connection.setRequestProperty("User-Agent","TangMusic/0.3 Android");
                try{
                    int status=connection.getResponseCode();
                    if(status>=300&&status<400){String location=connection.getHeaderField("Location");if(location==null)throw new IOException("下载地址跳转无效");url=new URL(url,location);if(!"https".equalsIgnoreCase(url.getProtocol())||url.getUserInfo()!=null)throw new IOException("下载地址必须保持 HTTPS");continue;}
                    if(status!=200)throw new IOException("下载失败，HTTP "+status);
                    int total=connection.getContentLength();if(total>LIMIT)throw new IOException("MIDI 文件不能超过 2 MB");
                    ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] chunk=new byte[8192];int read;long last=0;
                    try(InputStream in=connection.getInputStream()){while((read=in.read(chunk))!=-1){check(token);if(System.nanoTime()>deadline)throw new IOException("下载超时，请重试");if(out.size()+read>LIMIT)throw new IOException("MIDI 文件不能超过 2 MB");out.write(chunk,0,read);int percent=total>0?Math.min(99,out.size()*100/total):-1;long now=System.nanoTime();if(now-last>=100_000_000L){last=now;events.emit("downloadProgress",new JSONObject().put("token",token).put("percent",percent).put("bytes",out.size()));}}}data=out.toByteArray();break;
                }finally{connection.disconnect();activeConnection=null;}
            }
            if(data==null)throw new IOException("下载跳转次数过多");validate(data);
            String path=url.getPath();String name=path.substring(path.lastIndexOf('/')+1);if(name.isEmpty())name="在线曲谱.mid";storeAndEmit(title.isEmpty()?name:title,data,"download",value,token,expectedHash);
        }catch(Exception e){error(token,e);}finally{activeConnection=null;activeToken="";}
    }
    private void storeAndEmit(String name,byte[] data,String source,String url,String token,String expectedHash) throws Exception {
        check(token);
        byte[] hash=MessageDigest.getInstance("SHA-256").digest(data);StringBuilder id=new StringBuilder();for(byte b:hash)id.append(String.format(Locale.ROOT,"%02x",b&255));
        String key=id.toString();if(!expectedHash.isEmpty()&&!key.equalsIgnoreCase(expectedHash))throw new IOException("曲谱源文件已更新，请核对后再下载");
        JSONObject metadata=new JSONObject().put("id",key).put("name",name).put("size",data.length).put("source",source).put("url",url).put("updated",System.currentTimeMillis());
        pendingToken=token;pendingBytes=data;pendingMeta=metadata;emitFile(metadata,data,token,false);
    }
    private File checked(String id,String suffix) throws IOException {if(id==null||!id.matches("[0-9a-f]{64}"))throw new IOException("缓存标识无效");return new File(directory,id+suffix);}
    void commit(String token,String details){try{
        check(token);if(!token.equals(pendingToken)||pendingBytes==null)throw new IOException("曲谱任务已失效，请重试");
        JSONObject input=new JSONObject(details),meta=new JSONObject(pendingMeta.toString());
        double duration=input.getDouble("duration");int tracks=input.getInt("tracks");
        if(!Double.isFinite(duration)||duration<=0||tracks<=0)throw new IOException("曲谱没有可用的旋律声部");
        meta.put("duration",duration).put("tracks",tracks);
        String id=meta.getString("id");JSONObject old=new JSONObject();File previous=checked(id,".json");
        if(previous.exists())old=new JSONObject(new String(Files.readAllBytes(previous.toPath()),StandardCharsets.UTF_8));
        for(String key:new String[]{"catalogId","sourceUrl","license"}){String value=input.optString(key);if(value.length()>2048)throw new IOException("曲谱信息过长");meta.put(key,value.isEmpty()?old.optString(key):value);}
        atomic(checked(id,".mid"),pendingBytes);atomic(checked(id,".json"),meta.toString().getBytes(StandardCharsets.UTF_8));
        pendingBytes=null;pendingMeta=null;pendingToken="";trim();list();events.emit("midiCommitted",new JSONObject().put("token",token).put("meta",meta));
    }catch(Exception e){error(token,e);}finally{cancelled.remove(token);}}
    private static void atomic(File file,byte[] data)throws IOException{java.nio.file.Path temp=file.toPath().resolveSibling(file.getName()+".tmp");Files.write(temp,data);try{Files.move(temp,file.toPath(),java.nio.file.StandardCopyOption.REPLACE_EXISTING,java.nio.file.StandardCopyOption.ATOMIC_MOVE);}catch(java.nio.file.AtomicMoveNotSupportedException e){Files.move(temp,file.toPath(),java.nio.file.StandardCopyOption.REPLACE_EXISTING);}}
    void open(String id,String token){try{check(token);JSONObject meta=new JSONObject(new String(Files.readAllBytes(checked(id,".json").toPath()),StandardCharsets.UTF_8));emitFile(meta,exportBytes(id),token,true);}catch(Exception e){error(token,e);}}
    void remove(String id){try{Files.deleteIfExists(checked(id,".json").toPath());Files.deleteIfExists(checked(id,".mid").toPath());list();}catch(Exception e){error("",e);}}
    private void emitFile(JSONObject metadata,byte[] data,String token,boolean cached) throws Exception {JSONObject payload=new JSONObject(metadata.toString());payload.put("token",token).put("fromCache",cached).put("base64",Base64.encodeToString(data,Base64.NO_WRAP));events.emit("midiFile",payload);}
    byte[] exportBytes(String id)throws Exception{byte[] data=Files.readAllBytes(checked(id,".mid").toPath());validate(data);StringBuilder hash=new StringBuilder();for(byte b:MessageDigest.getInstance("SHA-256").digest(data))hash.append(String.format(Locale.ROOT,"%02x",b&255));if(!id.equals(hash.toString()))throw new IOException("本机曲谱校验失败，请重新下载");return data;}
    private List<JSONObject> entries(){List<JSONObject> items=new ArrayList<>();File[] files=directory.listFiles((dir,name)->name.endsWith(".json"));if(files!=null)for(File file:files){try{JSONObject item=new JSONObject(new String(Files.readAllBytes(file.toPath()),StandardCharsets.UTF_8));if(checked(item.getString("id"),".mid").isFile())items.add(item);}catch(Exception ignored){}}items.sort((a,b)->Long.compare(b.optLong("updated"),a.optLong("updated")));return items;}
    private void trim(){List<JSONObject> items=entries();for(int i=MAX_FILES;i<items.size();i++){String id=items.get(i).optString("id");try{Files.deleteIfExists(checked(id,".mid").toPath());Files.deleteIfExists(checked(id,".json").toPath());}catch(Exception ignored){}}}
    void list(){try{events.emit("midiLibrary",new JSONObject().put("items",new JSONArray(entries())));}catch(Exception e){error("",e);}}
    void export(Uri uri,byte[] data,String message){try{if(data==null)throw new IOException("没有待导出的数据");try(OutputStream out=context.getContentResolver().openOutputStream(uri)){if(out==null)throw new IOException("文件无法写入");out.write(data);}events.emit("exportDone",new JSONObject().put("message",message));}catch(Exception e){error("",e);}}
}
