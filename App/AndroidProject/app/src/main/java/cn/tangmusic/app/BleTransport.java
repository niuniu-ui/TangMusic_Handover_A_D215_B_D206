package cn.tangmusic.app;

import android.annotation.SuppressLint;
import android.bluetooth.*;
import android.bluetooth.le.*;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.*;

@SuppressLint("MissingPermission")
final class BleTransport {
    interface Events { void emit(String type,JSONObject data); }
    private final Context context;
    private final Events events;
    private final Handler ui=new Handler(Looper.getMainLooper());
    private final BluetoothAdapter adapter;
    private final SharedPreferences prefs;
    private final boolean recordingLink;
    private java.util.function.Consumer<byte[]> binaryReceiver;
    private boolean discoveryStarted;
    private BluetoothLeScanner scanner;
    private BluetoothGatt gatt;
    private final Runnable mtuFallback=()->{if(gatt!=null&&!discoveryStarted)discover(gatt);};
    private BluetoothGattCharacteristic tx,rx;
    private boolean scanning,ready,writing;
    private long receivedBytes;
    private byte[] message;
    private int position,chunkSize;
    private final Map<String,JSONObject> scanBatch=new LinkedHashMap<>();
    private boolean batchPending;
    private final Runnable flushScan=()->{batchPending=false;if(!scanning){scanBatch.clear();return;}JSONArray items=new JSONArray();for(JSONObject item:scanBatch.values())items.put(item);scanBatch.clear();if(items.length()>0)emit("devicesFound","items",items);};
    private final Runnable scanTimeout=()->stopScan();
    private final Runnable writeTimeout=()->{if(writing){fail("蓝牙写入超时，请重新连接后再发送");disconnect();}};
    private final Runnable connectionTimeout=()->{if(gatt!=null&&!ready){fail("连接或发现服务超时，请检查 UUID 与模块状态");disconnect();}};
    BleTransport(Context context,Events events){this(context,events,false);}
    BleTransport(Context context,Events events,boolean recordingLink){this.context=context;this.events=events;this.recordingLink=recordingLink;BluetoothManager manager=(BluetoothManager)context.getSystemService(Context.BLUETOOTH_SERVICE);adapter=manager==null?null:manager.getAdapter();prefs=context.getSharedPreferences("ble",Context.MODE_PRIVATE);}
    void binaryReceiver(java.util.function.Consumer<byte[]> receiver){binaryReceiver=receiver;}
    void transferPriority(boolean active){if(gatt!=null)try{gatt.requestConnectionPriority(active?BluetoothGatt.CONNECTION_PRIORITY_HIGH:BluetoothGatt.CONNECTION_PRIORITY_BALANCED);}catch(Exception ignored){}}
    private void discover(BluetoothGatt current){if(current!=gatt||discoveryStarted)return;discoveryStarted=true;ui.removeCallbacks(mtuFallback);if(!current.discoverServices()){fail("无法发现蓝牙服务");disconnect();}}
    private void emit(String type,Object...pairs){try{JSONObject data=new JSONObject();for(int i=0;i<pairs.length;i+=2)data.put((String)pairs[i],pairs[i+1]);if(type.equals("connecting")||type.equals("connected")||type.equals("channelReady")||type.equals("txDone")||type.equals("disconnected")||type.equals("error"))android.util.Log.i("TangBle",(recordingLink?"recorder ":"control ")+type+" "+data+" rxBytes="+receivedBytes);events.emit(type,data);}catch(Exception ignored){}}
    private void fail(String message){emit("error","message",message);}
    boolean channelReady(){return ready;}
    boolean available(){return adapter!=null;}
    boolean enabled(){return adapter!=null&&adapter.isEnabled();}
    JSONObject configuration(){JSONObject data=new JSONObject();try{data.put("service",prefs.getString("service","FFF0"));data.put("tx",prefs.getString("tx","FFF2"));data.put("rx",prefs.getString("rx","FFF1"));data.put("lastAddress",prefs.getString("lastAddress",""));}catch(Exception ignored){}return data;}
    private static UUID uuid(String input){String value=input.trim();if(value.matches("(?i)[0-9a-f]{4}"))value="0000"+value+"-0000-1000-8000-00805f9b34fb";else if(value.matches("(?i)[0-9a-f]{8}"))value+="-0000-1000-8000-00805f9b34fb";if(!value.matches("(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"))throw new IllegalArgumentException("UUID 格式无效");return UUID.fromString(value);}
    void configure(String service,String write,String notify){try{uuid(service);uuid(write);uuid(notify);disconnect();prefs.edit().putString("service",service.trim()).putString("tx",write.trim()).putString("rx",notify.trim()).apply();events.emit("configuration",configuration());}catch(Exception e){fail("请输入正确的 16 位、32 位或完整 UUID");}}
    void scan(){try{if(!enabled()){fail("请先开启蓝牙");return;}stopScan();scanner=adapter.getBluetoothLeScanner();if(scanner==null){fail("无法启动 BLE 扫描");return;}scanning=true;emit("scanStarted");scanner.startScan(null,new ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(),scanCallback);ui.postDelayed(scanTimeout,10000);}catch(Exception e){stopScan();fail("蓝牙扫描失败："+e.getMessage());}}
    void stopScan(){ui.removeCallbacks(scanTimeout);ui.removeCallbacks(flushScan);if(scanning)flushScan.run();batchPending=false;scanBatch.clear();if(scanning){scanning=false;try{if(scanner!=null)scanner.stopScan(scanCallback);}catch(Exception ignored){}emit("scanStopped");}}
    private final ScanCallback scanCallback=new ScanCallback(){
        @Override public void onScanResult(int kind,ScanResult result){ui.post(()->{if(!scanning)return;try{
            BluetoothDevice device=result.getDevice();String address=device.getAddress();
            String name=result.getScanRecord()==null?null:result.getScanRecord().getDeviceName();if(name==null||name.trim().isEmpty())name=device.getName();
            name=BleNames.clean(name,address);
            if(!BleNames.instrument(name,address,prefs.getString("lastAddress","")))return;
            scanBatch.put(address,new JSONObject().put("address",address).put("name",name).put("instrument",true).put("rssi",result.getRssi()));
            if(!batchPending){batchPending=true;ui.postDelayed(flushScan,250);}
        }catch(Exception ignored){}});}
        @Override public void onBatchScanResults(List<ScanResult> results){for(ScanResult result:results)onScanResult(ScanSettings.CALLBACK_TYPE_ALL_MATCHES,result);}
        @Override public void onScanFailed(int errorCode){ui.post(()->{stopScan();fail("扫描失败，系统代码 "+errorCode+"；请稍后重试");});}
    };
    void connect(String address){try{if(adapter==null||!BluetoothAdapter.checkBluetoothAddress(address)){fail("蓝牙设备地址无效");return;}stopScan();disconnect();emit("connecting","address",address);gatt=adapter.getRemoteDevice(address).connectGatt(context,false,callback,BluetoothDevice.TRANSPORT_LE);if(gatt==null){fail("无法建立蓝牙连接");return;}ui.postDelayed(connectionTimeout,15000);}catch(Exception e){fail("连接失败："+e.getMessage());disconnect();}}
    void disconnect(){ui.removeCallbacks(connectionTimeout);ui.removeCallbacks(writeTimeout);ui.removeCallbacks(mtuFallback);discoveryStarted=false;ready=false;writing=false;receivedBytes=0;message=null;tx=null;rx=null;BluetoothGatt old=gatt;gatt=null;if(old!=null){try{old.disconnect();old.close();}catch(Exception ignored){}emit("disconnected");}}
    void close(){stopScan();disconnect();}
    private final BluetoothGattCallback callback=new BluetoothGattCallback(){
        @Override public void onConnectionStateChange(BluetoothGatt current,int status,int state){ui.post(()->{if(current!=gatt)return;if(status!=BluetoothGatt.GATT_SUCCESS||state==BluetoothProfile.STATE_DISCONNECTED){if(status!=BluetoothGatt.GATT_SUCCESS)fail("蓝牙连接中断，状态码 "+status);disconnect();return;}if(state==BluetoothProfile.STATE_CONNECTED){emit("connected","address",current.getDevice().getAddress());if(recordingLink&&current.requestMtu(247))ui.postDelayed(mtuFallback,2000);else discover(current);}});}
        @Override public void onMtuChanged(BluetoothGatt current,int mtu,int status){ui.post(()->{if(current!=gatt)return;emit("mtu","value",mtu,"status",status);discover(current);});}
        @Override public void onServicesDiscovered(BluetoothGatt current,int status){ui.post(()->{if(current!=gatt)return;if(status!=BluetoothGatt.GATT_SUCCESS){fail("蓝牙服务发现失败");disconnect();return;}try{
            JSONArray services=new JSONArray();for(BluetoothGattService service:current.getServices()){JSONObject item=new JSONObject().put("uuid",service.getUuid());JSONArray chars=new JSONArray();for(BluetoothGattCharacteristic characteristic:service.getCharacteristics())chars.put(new JSONObject().put("uuid",characteristic.getUuid()).put("properties",characteristic.getProperties()));item.put("characteristics",chars);services.put(item);}emit("services","items",services);
            JSONObject config=configuration();BluetoothGattService service=current.getService(uuid(config.getString("service")));if(service==null)throw new IllegalStateException("未找到配置的服务 UUID");tx=service.getCharacteristic(uuid(config.getString("tx")));rx=service.getCharacteristic(uuid(config.getString("rx")));if(tx==null||rx==null)throw new IllegalStateException("未找到配置的发送或接收特征");if((tx.getProperties()&(BluetoothGattCharacteristic.PROPERTY_WRITE|BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE))==0)throw new IllegalStateException("发送特征不可写");
            int mode=rx.getProperties();byte[] value;if((mode&BluetoothGattCharacteristic.PROPERTY_NOTIFY)!=0)value=BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE;else if((mode&BluetoothGattCharacteristic.PROPERTY_INDICATE)!=0)value=BluetoothGattDescriptor.ENABLE_INDICATION_VALUE;else throw new IllegalStateException("接收特征不支持通知或指示");
            BluetoothGattDescriptor cccd=rx.getDescriptor(uuid("2902"));if(cccd==null||!current.setCharacteristicNotification(rx,true))throw new IllegalStateException("无法开启接收通知");cccd.setValue(value);if(!current.writeDescriptor(cccd))throw new IllegalStateException("无法配置通知描述符");
        }catch(Exception e){fail(e.getMessage()+"，请按实际服务列表修改 UUID 后重连");disconnect();}});}
        @Override public void onDescriptorWrite(BluetoothGatt current,BluetoothGattDescriptor descriptor,int status){ui.post(()->{if(current!=gatt)return;if(status!=BluetoothGatt.GATT_SUCCESS){fail("开启蓝牙通知失败，代码 "+status);disconnect();return;}ready=true;ui.removeCallbacks(connectionTimeout);prefs.edit().putString("lastAddress",current.getDevice().getAddress()).apply();emit("channelReady","address",current.getDevice().getAddress());});}
        @Override public void onCharacteristicChanged(BluetoothGatt current,BluetoothGattCharacteristic characteristic){byte[] data=characteristic.getValue();receive(current,data==null?new byte[0]:data.clone());}
        @Override public void onCharacteristicChanged(BluetoothGatt current,BluetoothGattCharacteristic characteristic,byte[] value){receive(current,value.clone());}
        @Override public void onCharacteristicWrite(BluetoothGatt current,BluetoothGattCharacteristic characteristic,int status){ui.post(()->{if(current!=gatt||!writing)return;ui.removeCallbacks(writeTimeout);if(status!=BluetoothGatt.GATT_SUCCESS){fail("蓝牙写入失败，代码 "+status);disconnect();return;}position+=chunkSize;if(position>=message.length){int bytes=message.length;message=null;writing=false;emit("txDone","bytes",bytes);}else writeNext();});}
    };
    private void receive(BluetoothGatt current,byte[] bytes){ui.post(()->{if(current==gatt){long old=receivedBytes;receivedBytes+=bytes.length;if(old==0||receivedBytes/8192!=old/8192)android.util.Log.i("TangBle",(recordingLink?"recorder ":"control ")+"RX chunk="+bytes.length+" total="+receivedBytes);if(binaryReceiver!=null)binaryReceiver.accept(bytes);else emit("rx","hex",hex(bytes),"bytes",bytes.length);}});}
    private static String hex(byte[] data){StringBuilder result=new StringBuilder();for(byte b:data){if(result.length()>0)result.append(' ');result.append(String.format(Locale.ROOT,"%02X",b&255));}return result.toString();}
    void send(String input){try{if(!ready||gatt==null||tx==null)throw new IllegalStateException("蓝牙通道尚未就绪");if(writing)throw new IllegalStateException("上次数据仍在发送，请稍后重试");String clean=input.replaceAll("\\s","");if(clean.isEmpty()||clean.length()>8192||(clean.length()%2)!=0||!clean.matches("(?i)[0-9a-f]+"))throw new IllegalArgumentException("发送数据必须为完整 HEX，最多 4096 字节");message=new byte[clean.length()/2];for(int i=0;i<message.length;i++)message[i]=(byte)Integer.parseInt(clean.substring(i*2,i*2+2),16);writing=true;position=0;emit("txStarted","bytes",message.length,"hex",hex(message));writeNext();}catch(Exception e){fail(e.getMessage());}}
    private void writeNext(){try{chunkSize=Math.min(20,message.length-position);byte[] chunk=Arrays.copyOfRange(message,position,position+chunkSize);tx.setWriteType((tx.getProperties()&BluetoothGattCharacteristic.PROPERTY_WRITE)!=0?BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT:BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE);tx.setValue(chunk);if(!gatt.writeCharacteristic(tx))throw new IllegalStateException("蓝牙繁忙，写入未提交");ui.postDelayed(writeTimeout,8000);}catch(Exception e){fail("发送失败："+e.getMessage());disconnect();}}
}
