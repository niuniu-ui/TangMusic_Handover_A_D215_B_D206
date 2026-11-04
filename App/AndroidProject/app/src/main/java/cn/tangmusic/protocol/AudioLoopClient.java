package cn.tangmusic.protocol;

import java.util.concurrent.Executor;
import java.util.function.Consumer;

/** Real DDR3 PCM loops. No note-event or phone-audio fallback. */
public final class AudioLoopClient {
    private final TmcpClient link;private final Runnable changed;private final Executor callbacks;
    private byte[] state;private int generation;private boolean pending,polling;private Runnable deferred;private long lastPoll;
    private String message="连接后读取四轨音频状态";
    public AudioLoopClient(TmcpClient link,Runnable changed,Executor callbacks){this.link=link;this.changed=changed;this.callbacks=callbacks;}
    public boolean supported(){return (link.features()&128)!=0;}
    public boolean pending(){return deferred!=null||(pending&&!polling);}public byte[] state(){return state==null?null:state.clone();}public String message(){return message;}
    private void request(int command,byte[] payload,Consumer<byte[]> success){
        int epoch=generation;pending=true;polling=command==0x400;changed.run();
        link.command(command,payload,b->callbacks.execute(()->{if(epoch!=generation)return;pending=false;polling=false;try{success.accept(b);Runnable action=deferred;deferred=null;if(action!=null)action.run();}catch(Exception e){deferred=null;message=e.getMessage();}changed.run();}),e->callbacks.execute(()->{if(epoch!=generation)return;pending=false;polling=false;deferred=null;message=e+"；请刷新状态后核对";changed.run();}));
    }
    public void sessionReady(){generation++;pending=false;polling=false;deferred=null;state=null;if(supported())refresh();else{message="当前固件不支持四轨 DDR3 音频；等待统一编译和烧录";changed.run();}}
    public void disconnected(){generation++;pending=false;polling=false;deferred=null;state=null;message="蓝牙已断开；板端循环可能仍在运行，重连后读取状态";changed.run();}
    public void refresh(){if(!supported()||!link.ready()||pending)return;request(0x400,new byte[0],b->{
        if(b.length!=40||b[0]!=1||(b[16]&255)>15||(b[17]&255)>15||(b[18]&255)>15)throw new IllegalArgumentException("四轨状态格式错误");
        for(int i=20;i<24;i++)if((b[i]&255)>128)throw new IllegalArgumentException("轨道音量越界");
        state=b.clone();int fault=b[2]&255;
        message=fault!=0?"循环已停止："+(fault==1?"DDR3 读取未及时完成":fault==2?"DDR3 校验或访问失败，请重启板卡":fault==3?"录音写入缓冲溢出":fault==4?"混音处理未及时完成":"设备故障（"+fault+"）"):
            (b[1]&32)!=0?"正在预读轨道":(b[1]&2)!=0?"正在录入实际声音":(b[1]&16)!=0?"循环已开始，正在核验最后一块录音":(b[1]&4)!=0?"已准备录音，等待下一轮或预备拍":(b[1]&1)!=0?"四轨音频循环中":"循环已停止";
    });}
    public void tick(long now){if(supported()&&link.ready()&&!pending&&now-lastPoll>=1000){lastPoll=now;refresh();}}
    private void ready(){if(!supported()||!link.ready()||pending()||state==null)throw new IllegalArgumentException("请先连接并读取四轨状态");}
    private void mutate(int command,byte[] payload){ready();if(polling){byte[] copy=payload.clone();deferred=()->mutate(command,copy);changed.run();return;}request(command,payload,b->{if(b.length!=0)throw new IllegalArgumentException("四轨确认长度错误");message="设备已确认，正在读取状态";refresh();});}
    public static long samples(int bpm,int bars){if(bpm<40||bpm>240||(bars!=1&&bars!=2&&bars!=4))throw new IllegalArgumentException("速度为 40–240 BPM，小节数为 1、2 或 4");return Math.round((11718750.0*bars/bpm)/64)*64;}
    public void configure(int bpm,int bars,int countIn,long revision){
        long n=samples(bpm,bars);if(countIn!=0&&countIn!=4)throw new IllegalArgumentException("预备拍为 0 或 4 拍");
        byte[] p=new byte[12];put(p,0,n,4);put(p,4,bpm,2);p[6]=(byte)bars;p[7]=(byte)countIn;put(p,8,revision,4);mutate(0x401,p);
    }
    public void mix(int track,boolean mute,boolean solo,int volume,long revision){
        track(track);if(volume<0||volume>128)throw new IllegalArgumentException("轨道音量越界");
        byte[] p=new byte[8];put(p,0,revision,4);p[4]=(byte)track;p[5]=(byte)(mute?1:0);p[6]=(byte)(solo?1:0);p[7]=(byte)volume;mutate(0x405,p);
    }
    public void action(String action,int track){switch(action){
        case "refresh":refresh();break;
        case "record":track(track);mutate(0x402,new byte[]{(byte)track});break;
        case "play":mutate(0x403,new byte[0]);break;
        case "stop":mutate(0x404,new byte[]{0});break;
        case "abort":mutate(0x404,new byte[]{1});break;
        case "clear":if(track!=255)track(track);mutate(0x406,new byte[]{(byte)track});break;
        case "undo":track(track);mutate(0x407,new byte[]{(byte)track});break;
        default:throw new IllegalArgumentException("未知循环操作");
    }}
    private static void track(int n){if(n<0||n>3)throw new IllegalArgumentException("轨道编号越界");}
    private static void put(byte[] p,int at,long v,int n){if(v<0||(n==4&&v>0xffffffffL))throw new IllegalArgumentException("参数越界");TangFrameCodec.put(p,at,v,n);}
}
