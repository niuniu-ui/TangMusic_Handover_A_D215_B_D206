package cn.tangmusic.app;

/** Pure helper shared by native scan filtering and its JVM regression. */
final class BleNames {
    static boolean instrument(String name,String address,String lastAddress){
        if(address!=null&&!address.isEmpty()&&address.equalsIgnoreCase(lastAddress))return true;
        return clean(name,address).matches("(?i)(?:E104|Tang[ _-]?Music)(?:$|[-_ ].*)");
    }
    static String clean(String value,String address){
        if(value==null)return "";
        String name=value.replaceAll("[\\x00-\\x1f\\x7f\\u200b-\\u200f\\ufeff]","").trim();
        if(name.isEmpty()||name.equalsIgnoreCase(address)||name.matches("(?i)(未命名(?:\\s*BLE)?(?:\\s*设备)?|未知(?:\\s*BLE)?(?:\\s*设备)?|(?:unknown|unnamed)(?:\\s*ble)?(?:\\s*device)?|null|undefined|n/a|(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2})"))return "";
        return name;
    }
}
