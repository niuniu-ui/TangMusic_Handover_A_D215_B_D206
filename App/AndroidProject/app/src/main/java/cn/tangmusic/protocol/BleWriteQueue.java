package cn.tangmusic.protocol;

import java.util.ArrayDeque;

/** Serialize complete application packets; a GATT callback belongs to one sender. */
public final class BleWriteQueue {
    public enum Owner { CONTROL, RECORDER, DEBUG }
    public interface Sink { void send(byte[] bytes); }
    public interface Completion { void done(Owner owner); }
    private static final class Packet {
        final Owner owner; final byte[] bytes;
        Packet(Owner owner,byte[] bytes){this.owner=owner;this.bytes=bytes.clone();}
    }
    private final ArrayDeque<Packet> pending=new ArrayDeque<>();
    private final Sink sink;private final Completion completion;private Packet active;
    public BleWriteQueue(Sink sink,Completion completion){this.sink=sink;this.completion=completion;}
    public void send(Owner owner,byte[] bytes){
        if(pending.size()>=16)throw new IllegalStateException("蓝牙请求队列繁忙，请稍后重试");
        pending.add(new Packet(owner,bytes));drain();
    }
    private void drain(){if(active==null&&!pending.isEmpty()){active=pending.remove();sink.send(active.bytes.clone());}}
    public void completed(){if(active==null)return;Owner owner=active.owner;active=null;completion.done(owner);drain();}
    public void clear(){pending.clear();active=null;}
}
