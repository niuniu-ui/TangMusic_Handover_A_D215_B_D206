package cn.tangmusic.app;

import android.content.Context;
import android.util.Base64;
import org.json.*;
import java.io.*;
import java.net.*;
import java.nio.file.Files;
import java.util.*;
import java.util.zip.CRC32;
import java.util.regex.*;

/** Native access for Pocket's JSON import and previously verified recorder files. */
final class PocketFiles {
    interface Events {void emit(String type,JSONObject value);}
    private final File recordings;private final Events events;
    private volatile HttpURLConnection connection;private volatile String active="";
    private final Set<String> cancelled=java.util.concurrent.ConcurrentHashMap.newKeySet();
    PocketFiles(Context context,Events events){recordings=new File(context.getFilesDir(),"piano-recordings");this.events=events;}
    void cancel(String token){cancelled.add(token);if(token.equals(active)&&connection!=null)connection.disconnect();}
    void download(String input,String token){active=token;try{
        URL url=new URL(input);byte[] bytes=null;long deadline=System.nanoTime()+20_000_000_000L;
        for(int hop=0;hop<=4;hop++){
            if(cancelled.contains(token))throw new IOException("已取消下载");
            if(!"https".equalsIgnoreCase(url.getProtocol())||url.getUserInfo()!=null)throw new IOException("请使用不含账号密码的 HTTPS 链接");
            HttpURLConnection c=(HttpURLConnection)url.openConnection();connection=c;c.setInstanceFollowRedirects(false);c.setConnectTimeout(8000);c.setReadTimeout(8000);
            try{int status=c.getResponseCode();if(status>=300&&status<400){String next=c.getHeaderField("Location");if(next==null)throw new IOException("下载跳转无效");url=new URL(url,next);continue;}if(status!=200)throw new IOException("下载失败，HTTP "+status);
                if(c.getContentLengthLong()>262144)throw new IOException("曲谱超过 256 KB 上限");
                ByteArrayOutputStream out=new ByteArrayOutputStream();try(InputStream in=c.getInputStream()){byte[] buffer=new byte[4096];int n;while((n=in.read(buffer))!=-1){if(cancelled.contains(token))throw new IOException("已取消下载");if(System.nanoTime()>deadline)throw new IOException("下载超时");if(out.size()+n>262144)throw new IOException("曲谱超过 256 KB 上限");out.write(buffer,0,n);}}bytes=out.toByteArray();break;
            }finally{c.disconnect();connection=null;}
        }
        if(bytes==null)throw new IOException("下载跳转次数过多");events.emit("pocketScore",new JSONObject().put("token",token).put("base64",Base64.encodeToString(bytes,Base64.NO_WRAP)));
    }catch(Exception e){try{events.emit("pocketScore",new JSONObject().put("token",token).put("error",e.getMessage()));}catch(Exception ignored){}}
    finally{active="";connection=null;cancelled.remove(token);}}
    File checked(String name)throws IOException{
        if(name==null||!name.matches("piano-[0-9]+-[0-9]+-[0-9]+-[0-9a-f]{1,8}-390625-8\\.wav"))throw new IOException("录音文件名无效");
        File f=new File(recordings,name);if(!f.getCanonicalFile().getParentFile().equals(recordings.getCanonicalFile())||!f.isFile()||f.length()>16*1024*1024)throw new IOException("录音文件不存在或过大");return f;
    }
    byte[] verified(String name)throws IOException{
        File file=checked(name);byte[] bytes=Files.readAllBytes(file.toPath());String[] parts=name.split("-");long samples,expected;
        try{samples=Long.parseLong(parts[3]);expected=Long.parseLong(parts[4],16);}catch(NumberFormatException e){throw new IOException("录音文件名无效",e);}
        if(samples<=0||samples>8*1024*1024||bytes.length<44||bytes.length!=44+samples*2||get(bytes,0,4)!=0x46464952L||get(bytes,8,4)!=0x45564157L||get(bytes,20,2)!=1||get(bytes,22,2)!=1||get(bytes,24,4)!=48828||get(bytes,34,2)!=16||get(bytes,40,4)!=samples*2)throw new IOException("录音文件格式不匹配");
        CRC32 crc=new CRC32();crc.update(bytes,44,bytes.length-44);if(crc.getValue()!=expected)throw new IOException("录音文件校验失败");return bytes;
    }
    private static long get(byte[] b,int p,int n){long v=0;for(int i=0;i<n;i++)v|=(b[p+i]&255L)<<(8*i);return v;}
    void list(){try{JSONArray items=new JSONArray();File[] files=recordings.listFiles((d,n)->n.endsWith(".wav"));if(files!=null){Arrays.sort(files,Comparator.comparingLong(File::lastModified).reversed());for(File f:files){try{byte[] bytes=verified(f.getName());long samples=Long.parseLong(f.getName().split("-")[3]);String date=new java.text.SimpleDateFormat("MM-dd HH:mm",Locale.CHINA).format(new Date(f.lastModified()));items.put(new JSONObject().put("name",f.getName()).put("title","钢琴演奏 · "+date).put("seconds",samples*8.0/390625).put("bytes",bytes.length));}catch(IOException ignored){}}}events.emit("pocketRecordings",new JSONObject().put("items",items));}catch(Exception ignored){}}
}
