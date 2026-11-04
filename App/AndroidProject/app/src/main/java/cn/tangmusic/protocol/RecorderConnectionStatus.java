package cn.tangmusic.protocol;

/** A valid board status, not a BLE connection, establishes recorder readiness. */
public final class RecorderConnectionStatus {
    private enum Phase { OFFLINE, SCANNING, CONNECTING, VERIFYING, READY, FAILED }
    private Phase phase=Phase.OFFLINE;
    private String address="",reason="";
    public void connecting(){phase=Phase.CONNECTING;address="";reason="";}
    public void scanning(){phase=Phase.SCANNING;reason="";}
    public void verifying(String value){phase=Phase.VERIFYING;address=value;reason="";}
    public void verified(){phase=Phase.READY;reason="";}
    public void failed(String value){phase=Phase.FAILED;reason=value==null?"设备响应异常":value;}
    public void disconnected(){phase=Phase.OFFLINE;address="";reason="";}
    public boolean ready(){return phase==Phase.READY;}
    public String text(){
        switch(phase){
            case SCANNING:return "正在扫描 E104…";
            case CONNECTING:return "正在建立蓝牙连接…";
            case VERIFYING:return "蓝牙已连接，正在核对录音功能…";
            case READY:return "录音设备已就绪 · "+address;
            case FAILED:return "设备通信未就绪 · "+reason;
            default:return "蓝牙未连接 · 已接收的录音进度保留";
        }
    }
}
