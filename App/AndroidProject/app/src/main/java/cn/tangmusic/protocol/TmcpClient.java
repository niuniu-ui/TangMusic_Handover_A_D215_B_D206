package cn.tangmusic.protocol;

import java.security.SecureRandom;
import java.util.ArrayDeque;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.function.Consumer;

/** The same request engine runs on Android and in the desktop RTL preview. */
public final class TmcpClient implements AutoCloseable {
    public interface Transport {void write(byte[] wire);}
    public interface Listener {void state(State value);void log(String message);void result(boolean success,int status,long detail,String message);}
    public static final class State {
        public final String phase,error,sessionHex;
        public final boolean ready,busy;
        public final long revision,pingMs;
        public final int pendingCommand;
        public final Map<Integer,Integer> parameters;
        State(String phase,String error,long session,long revision,long pingMs,int pendingCommand,Map<Integer,Integer> parameters){
            this.phase=phase;this.error=error;this.sessionHex=String.format(java.util.Locale.ROOT,"%08X",session);
            this.ready="ready".equals(phase);this.busy=pendingCommand!=0;this.revision=revision;this.pingMs=pingMs;this.pendingCommand=pendingCommand;
            this.parameters=Collections.unmodifiableMap(new LinkedHashMap<>(parameters));
        }
    }
    private static final int[] IDS={1,2,3,4,16,17,18,19,32,33,34,35,48,49,50,51};
    private final Transport transport;private final Listener listener;
    private final ScheduledExecutorService timer=Executors.newSingleThreadScheduledExecutor(r->{Thread t=new Thread(r,"tmcp-request-timer");t.setDaemon(true);return t;});
    private final ArrayDeque<Operation> queue=new ArrayDeque<>();
    private TangFrameCodec.StreamDecoder decoder=new TangFrameCodec.StreamDecoder();
    private final Map<Integer,Integer> parameters=new LinkedHashMap<>();
    private String phase="offline",error="";private long session,revision,pingMs=-1,lastReply,nextHeartbeat;
    private int nextSequence=2,automaticRecoveries;private boolean channel,closed,heartbeat=true;private Pending pending;
    private long features;private int maxScoreNotes,blockBytes;
    public synchronized long features(){return features;}
    public synchronized boolean ready(){return phase.equals("ready");}
    public synchronized int maxScoreNotes(){return maxScoreNotes;}
    public synchronized int blockBytes(){return blockBytes;}
    private static long now(){return System.nanoTime()/1000000;}
    private static final class Operation {
        final int command;final byte[] payload;final Consumer<byte[]> success;final boolean startup,userWrite;Consumer<String> failure;
        Operation(int command,byte[] payload,Consumer<byte[]> success,boolean startup,boolean userWrite){this.command=command;this.payload=payload.clone();this.success=success;this.startup=startup;this.userWrite=userWrite;}
    }
    private static final class Pending {
        final Operation operation;final int sequence;final byte[] wire;long sentAt,deadline;int retries;boolean written;TangFrameCodec.Frame response;
        Pending(Operation op,int sequence,byte[] wire){this.operation=op;this.sequence=sequence;this.wire=wire;}
    }
    public TmcpClient(Transport transport,Listener listener){this.transport=transport;this.listener=listener;timer.scheduleAtFixedRate(this::tick,100,100,TimeUnit.MILLISECONDS);}
    public synchronized boolean sessionActive(){return pending!=null||phase.equals("ready")||phase.equals("hello")||phase.equals("confirming");}
    public synchronized void channelReady(){
        automaticRecoveries=0;beginSession();
    }
    private void beginSession(){
        if(closed)return;channel=true;queue.clear();pending=null;decoder=new TangFrameCodec.StreamDecoder();parameters.clear();revision=0;pingMs=-1;
        do{session=Integer.toUnsignedLong(new SecureRandom().nextInt());}while(session==0);
        nextSequence=2;phase="hello";error="";lastReply=now();publish();
        Operation hello=new Operation(TangProtocolV1.CMD_HELLO,TangFrameCodec.hello(session).payload(),body->{
            if(body.length!=46)throw new IllegalArgumentException("HELLO能力表长度错误");
            if((TangFrameCodec.get(body,4,4)&1)==0)throw new IllegalArgumentException("设备尚未开放参数控制");
            features=TangFrameCodec.get(body,4,4);blockBytes=(int)TangFrameCodec.get(body,10,2);maxScoreNotes=(int)TangFrameCodec.get(body,12,2);
            if(TangFrameCodec.get(body,40,4)!=Integer.toUnsignedLong(TangProtocolV1.PARAMETER_SCHEMA_CRC32))throw new IllegalArgumentException("参数定义版本不匹配");
            phase="confirming";queue.add(new Operation(4,cookie(),echo->{acceptPing(echo);queue.add(readOperation(true));},true,false));
        },true,false);
        queue.add(hello);drain();
    }
    public synchronized void disconnected(){failOperations("连接已断开，请重新核对设备");channel=false;pending=null;queue.clear();features=0;maxScoreNotes=0;blockBytes=0;phase="offline";error="";session=0;decoder=new TangFrameCodec.StreamDecoder();publish();}
    public synchronized void transportError(String message){if(channel&&sessionActive())fail("蓝牙传输失败："+message);}
    public synchronized void writeComplete(){
        if(pending==null)return;pending.written=true;pending.deadline=now()+3000;finishIfComplete();
    }
    public synchronized void receive(byte[] bytes){
        if(closed||!channel)return;
        for(TangFrameCodec.Frame frame:decoder.feed(bytes,now()))handleFrame(frame);
    }
    private void handleFrame(TangFrameCodec.Frame frame){
            Pending p=pending;
            if(p==null||frame.kind!=1||frame.command!=p.operation.command||frame.sequence!=p.sequence||frame.session!=session){listener.log("忽略不匹配或迟到的应答");return;}
            if(frame.major!=1){fail("设备协议版本不兼容");return;}
            p.response=frame;finishIfComplete();
    }
    public synchronized void ping(){if(requireReady())enqueue(new Operation(4,cookie(),this::acceptPing,false,false));}
    public synchronized void readParameters(){if(requireReady())enqueue(readOperation(false));}
    public synchronized void command(int command,byte[] payload,Consumer<byte[]> success,Consumer<String> failure){
        if(!phase.equals("ready")){failure.accept("请先连接乐器并完成握手");return;}
        if(payload.length>256||queue.size()>=8){failure.accept("请求队列繁忙或数据过长");return;}
        Operation op=new Operation(command,payload,success,false,false);op.failure=failure;enqueue(op);
    }
    public synchronized void setParameters(long expectedRevision,Map<Integer,Integer> changes){
        if(!requireReady())return;
        if(expectedRevision<0||expectedRevision>0xFFFFFFFEL||changes.isEmpty()||changes.size()>16){listener.result(false,4,0,"参数批次或版本无效");return;}
        byte[] body=new byte[5+changes.size()*4];TangFrameCodec.put(body,0,expectedRevision,4);body[4]=(byte)changes.size();int offset=5;
        for(Map.Entry<Integer,Integer> item:changes.entrySet()){
            int id=item.getKey(),value=item.getValue();if(!validParameter(id,value)){listener.result(false,4,id,"参数超出协议范围");return;}
            TangFrameCodec.put(body,offset,id,2);TangFrameCodec.put(body,offset+2,value,2);offset+=4;
        }
        enqueue(new Operation(0x102,body,response->{acceptParameters(response);listener.result(true,0,revision,"设备参数已确认");},false,true));
    }
    public synchronized void heartbeatEnabled(boolean enabled){heartbeat=enabled;nextHeartbeat=now()+2000;listener.log(enabled?"恢复心跳":"暂停心跳（电脑故障验证）");}
    private boolean requireReady(){if(!phase.equals("ready")){listener.result(false,5,0,"请先完成协议握手");return false;}return true;}
    private void enqueue(Operation op){if(queue.size()>=8){listener.result(false,6,0,"请求队列繁忙，请稍后重试");return;}queue.add(op);drain();}
    private byte[] cookie(){byte[] b=new byte[4];TangFrameCodec.put(b,0,now()&0xFFFFFFFFL,4);return b;}
    private Operation readOperation(boolean startup){return new Operation(0x101,new byte[0],body->{acceptParameters(body);if(startup){phase="ready";nextHeartbeat=now()+2000;error="";}},startup,false);}
    private void acceptPing(byte[] body){
        if(body.length!=4||pending==null||!java.util.Arrays.equals(body,pending.operation.payload))throw new IllegalArgumentException("PING回传内容不一致");
        pingMs=Math.max(0,now()-pending.sentAt);
    }
    private static boolean validParameter(int id,int value){
        boolean known=false;for(int candidate:IDS)known|=candidate==id;
        int max=(id==3||id==16||id==32||id==48)?1:id==4?3:127;return known&&value>=0&&value<=max;
    }
    private void acceptParameters(byte[] body){
        if(body.length!=69||body[4]!=16)throw new IllegalArgumentException("参数快照长度错误");
        Map<Integer,Integer> snapshot=new LinkedHashMap<>();int previous=-1;
        for(int i=0;i<16;i++){int id=(int)TangFrameCodec.get(body,5+i*4,2),value=(int)TangFrameCodec.get(body,7+i*4,2);if(id<=previous||!validParameter(id,value))throw new IllegalArgumentException("参数快照不符合协议");snapshot.put(id,value);previous=id;}
        revision=TangFrameCodec.get(body,0,4);if(revision==0xFFFFFFFFL)throw new IllegalArgumentException("参数版本保留值");parameters.clear();parameters.putAll(snapshot);
    }
    private void drain(){
        if(closed||pending!=null||!channel||queue.isEmpty())return;
        Operation op=queue.remove();int sequence=op.command==1?1:nextSequence++;
        if(sequence>65535){fail("序号已用尽，请重新握手");return;}
        byte[] wire=new TangFrameCodec.Frame(1,0,op.command,sequence,op.command==1?0:session,op.payload).encode();pending=new Pending(op,sequence,wire);sendPending();
    }
    private void sendPending(){
        Pending p=pending;if(p==null)return;p.written=false;p.response=null;p.sentAt=now();p.deadline=0;
        listener.log(String.format(java.util.Locale.ROOT,"TX cmd=%04X seq=%d retry=%d",p.operation.command,p.sequence,p.retries));publish();
        try{transport.write(p.wire.clone());}catch(Exception e){fail("发送失败："+e.getMessage());}
    }
    private void finishIfComplete(){
        Pending p=pending;if(p==null||!p.written||p.response==null)return;
        lastReply=now();
        try{
            byte[] body=TangFrameCodec.responsePayload(p.response);
            // Keep pending visible while the callback verifies the echoed PING cookie.
            p.operation.success.accept(body);pending=null;error="";
        }catch(TangFrameCodec.DeviceError e){
            if(e.status==8||e.status==9){recoverSession("设备会话已失效，状态码 "+e.status);return;}
            pending=null;
            if(p.operation.failure!=null){p.operation.failure.accept("板端拒绝操作，状态码 "+e.status+"，详情 "+e.detail);publish();drain();return;}
            if(p.operation.startup){fail("设备拒绝会话，状态码 "+e.status);return;}
            error=e.status==18?"设备参数已变化，请读取后再修改":"设备拒绝参数，状态码 "+e.status;
            listener.result(false,e.status,e.detail,error);
            if(p.operation.userWrite)queue.addFirst(readOperation(false));
        }catch(Exception e){if(p.operation.failure!=null)p.operation.failure.accept(e.getMessage());pending=null;fail(e.getMessage());return;}
        publish();drain();
    }
    private synchronized void tick(){
        if(closed)return;long time=now();for(TangFrameCodec.Frame frame:decoder.expire(time))handleFrame(frame);
        if(pending!=null){
            if(!pending.written&&time-pending.sentAt>=15000){fail("BLE写入超时，执行结果未知");return;}
            if(pending.written&&pending.response==null&&time>=pending.deadline){
                if(pending.retries>=3){recoverSession("设备应答超时，执行结果未知");return;}
                pending.retries++;sendPending();
            }
            return;
        }
        if(phase.equals("ready")&&time-lastReply>=10000){recoverSession("心跳超时，连接状态已失效");return;}
        if(phase.equals("ready")&&heartbeat&&queue.isEmpty()&&time>=nextHeartbeat){
            nextHeartbeat=time+2000;queue.add(new Operation(4,cookie(),this::acceptPing,false,false));queue.add(readOperation(false));drain();
        }
    }
    private void recoverSession(String reason){
        // Reprogramming/resetting the FPGA leaves BLE connected but destroys
        // its protocol session. Recreate it ONCE, and only read current state.
        // Never replay queued parameter writes into a different board session.
        if(pending!=null&&pending.operation.userWrite)listener.result(false,8,0,"通信中断，修改结果未知；重新读取后请核对参数");
        failOperations(reason);
        if(!channel||closed||automaticRecoveries>=1){fail(reason+"；请检查模块与 FPGA 串口链路后重新连接");return;}
        automaticRecoveries++;
        listener.log(reason+"；自动重新握手并读取状态（1/1）");
        beginSession();
    }
    private void failOperations(String message){
        if(pending!=null&&pending.operation.failure!=null){Consumer<String> f=pending.operation.failure;pending.operation.failure=null;f.accept(message);}
        for(Operation op:queue)if(op.failure!=null){Consumer<String> f=op.failure;op.failure=null;f.accept(message);}
    }
    private void fail(String message){failOperations(message);pending=null;queue.clear();parameters.clear();phase="error";error=message==null?"协议处理失败":message;listener.log(error);publish();}
    private void publish(){listener.state(new State(phase,error,session,revision,pingMs,pending==null?0:pending.operation.command,parameters));}
    @Override public synchronized void close(){closed=true;pending=null;queue.clear();timer.shutdownNow();}
}
