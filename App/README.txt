TangMusic App 0.7.3 library 交接

Install/TangMusic-0.7.3-library-debug.apk 为现有安装包。AndroidProject 为清理后的完整应用工程。
包名cn.tangmusic.app.minlink，版本0.7.3-library / 703，最低Android8 API26，compileSdk/targetSdk36。
保留Gradle wrapper与源码资源；剔除旧sdk-build*、缓存、local.properties、测试和本机签名文件。
用Android Studio打开AndroidProject，配置自己的Android SDK与JDK。现有工程配置Java17、AGP9.4.1、Gradle9.6.0。
构建命令：Windows为 .\gradlew.bat :app:assembleDebug，其他系统为 sh ./gradlew :app:assembleDebug。
首次依赖解析需要可用的仓库/SDK；本次未在新电脑干净重建App，不把现有APK冒称本次重编产物。

preBuild将ui目录的五个界面文件复制到app/src/main/assets/web；维护时须修改对应ui源或同时更新两处。
ui/README.txt是原工程保留的历史说明，最终版本与能力以本文件、技术手册及代码为准。
默认BLE服务FFF0、手机写FFF2、通知FFF1；模块UART要匹配A的921600 8N1，不是U15诊断的115200。
源中旧PianoRecorderActivity不是Manifest的当前入口；MainActivity才是正式入口，控制/录音共用一条BLE链路。
安装包是debug签名；新电脑重建签名可能不同。卸载旧版前先导出已保存的MIDI/录音等数据。
