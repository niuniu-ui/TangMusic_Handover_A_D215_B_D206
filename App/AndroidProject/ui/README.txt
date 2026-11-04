Tang Music 手机功能界面 · Pocket 风格 · 0.7.0-studio-unified/700

当前状态（2026-10-26）：用户已要求完整编译。Java/浏览器本地检查通过，0.7.0 APK 已打包，V2/V3 签名验证通过；尚未安装到手机或进行新版 BLE 实测。手机此前安装版本为 0.6.2。
APK：bluetooth_hardware_test_20261018/releases/TangMusic-0.7.0-studio-unified-debug.apk。
构建记录：bluetooth_hardware_test_20261018/reports/apk-build.json。
随后 FPGA 共用混音优化增加 fault=4（混音超时），客户端提示源码已更新并做 JVM 回归；此提示尚未重新打包进上述 APK。

index.html：曲库、乐器、调音、录音四个主页面。
instrument-style.css：统一视觉，包含四轨及键位编辑布局。
instrument-ui.js：调音展示、共用连接弹窗、内嵌录音/回传、手机 WAV 播放与导出。
score-ui.js：实际上传确认进度、设备能力、FPGA 时间/等待按键引导。
performance-ui.js：32 键排列、手机草稿、四轨 PCM 音频操作和实际状态。无 Pad 控制。

原生共用入口：../app/src/main/java/cn/tangmusic/app/MainActivity.java
录音控制器：../app/src/main/java/cn/tangmusic/app/RecorderClient.java
MainActivity 只创建一个 BleTransport；BleWriteQueue 按完整数据包串行发送并分发写入完成。
PianoRecorderActivity 保留作历史参考，已移除 Manifest 入口；主页面不会启动它或为录音断开连接。
协议客户端：ScoreUploadClient、KeymapClient、AudioLoopClient；保留 TmcpClient 的会话、校验和版本冲突处理。

界面资源同步（不编译）：python bluetooth_hardware_test_20261018/tools/package_instrument_ui.py
此脚本将上述五个文件同步到 assets。其它曲库、MIDI、BLE 与基础脚本仍以 assets/web 内的文件为源。
重新打包：python bluetooth_hardware_test_20261018/tools/build_test_apk.py
输出新文件名 TangMusic-0.7.0-studio-unified-debug.apk，不覆盖既有 0.6.2 APK。

录音兼容 BD01/BD02 单槽及 Studio v3 双槽；普通调音/录音不依赖新四轨固件。
曲谱、键位映射和四轨须匹配 C303 功能能力，旧固件会禁用相关操作。
主工程及完整功能说明：all/TangMusic_Studio_138C/手机与四轨音频说明.txt。
本地测试入口：tools/check_native_sources.py、check_unified_workflow.py、check_connection_recovery.py、check_performance_web.cjs、check_app_web.cjs。
这些是源代码/浏览器/设备模型测试，不代表已通过新版 APK 手机 BLE 或 C303 耳机实测。
