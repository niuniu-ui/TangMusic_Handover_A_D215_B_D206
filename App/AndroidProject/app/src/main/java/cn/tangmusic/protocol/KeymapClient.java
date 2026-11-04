package cn.tangmusic.protocol;

import java.util.concurrent.Executor;
import java.util.function.Consumer;

public final class KeymapClient {
    private final TmcpClient link;private final Runnable changed;private final Executor callbacks;
    private long revision;private int[] map;private int generation;private boolean busy;private String message="尚未读取板端键位";
    public KeymapClient(TmcpClient link,Runnable changed,Executor callbacks){this.link=link;this.changed=changed;this.callbacks=callbacks;}
    public boolean supported(){return (link.features()&16)!=0;}
    public boolean busy(){return busy;}public long revision(){return revision;}public int[] mapping(){return map==null?null:map.clone();}public String message(){return message;}
    public static void validate(int[] values){
        if(values.length!=32)throw new IllegalArgumentException("需要完整的 32 键映射");long seen=0;
        for(int n:values){if(n<53||n>84||(seen&(1L<<(n-53)))!=0)throw new IllegalArgumentException("MIDI 53–84 必须各出现一次，不能重复或缺失");seen|=1L<<(n-53);}
    }
    private void accept(byte[] b){if(b.length!=36)throw new IllegalArgumentException("板端键位信息长度错误");int[] values=new int[32];for(int i=0;i<32;i++)values[i]=b[4+i]&255;validate(values);revision=TangFrameCodec.get(b,0,4);map=values;message="已读取板端映射 · 版本 "+revision;}
    private void request(int cmd,byte[] payload,Consumer<byte[]> success){int epoch=generation;busy=true;changed.run();link.command(cmd,payload,b->callbacks.execute(()->{if(epoch!=generation)return;busy=false;try{success.accept(b);}catch(Exception e){message=e.getMessage();}changed.run();}),error->callbacks.execute(()->{if(epoch!=generation)return;busy=false;message=error+"；请重新读取后核对，未自动重发修改";changed.run();}));}
    public void sessionReady(){generation++;busy=false;map=null;if(supported())read();else{message="当前固件不支持实体键位映射";changed.run();}}
    public void disconnected(){generation++;busy=false;map=null;message="连接已断开，设备映射需要重新读取";changed.run();}
    public void read(){if(!supported()||!link.ready()||busy)return;request(0x110,new byte[0],this::accept);}
    public void apply(long expectedRevision,int[] values){
        validate(values);if(!supported()||!link.ready()||busy||map==null)throw new IllegalArgumentException("请先连接并读取设备键位");
        if(expectedRevision<0||expectedRevision>0xfffffffeL)throw new IllegalArgumentException("映射版本无效");
        byte[] b=new byte[36];TangFrameCodec.put(b,0,expectedRevision,4);for(int i=0;i<32;i++)b[4+i]=(byte)values[i];
        request(0x111,b,reply->{accept(reply);message="设备已确认应用，重启板卡后恢复默认映射";});
    }
}
