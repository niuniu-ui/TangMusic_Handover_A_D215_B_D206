TangMusic 双板项目交接包 2026-11-03

确认的工程版本：A D215、B D206；手机App 0.7.3-library。
先读Documentation中的技术交接手册，再按相应章节接线、构建和烧录。

FPGA/A_D215 和 FPGA/B_D206：完整工程源码、生成后的IP/ROM、界面资源、引脚/时序约束、构建TCL和GUI配置。
Firmware/A_D215 和 Firmware/B_D206：当前交付目录中已有的.fs，保留原文件名；高云Programmer可直接使用，无需转bin。
App：清理后的完整Android工程和现有安装APK，不带SDK、IDE安装包或测试软件。
Documentation：Word技术手册、引脚/协议CSV、工程报告、版本证据、最终RTL示例预览及历史设计底图。
MANIFEST_SHA256.txt：随包每个文件的哈希；SOURCE_ORIGINS.json：版本来源和归档记录。

A D215的.fs与既有Flash写入校验/重载成功记录哈希一致。B D206的.fs为用户后来生成的现有文件，本次未代烧录或实板回读。
两板当前PnR报告均仍有setup违例，不能把“生成fs/曾运行”写成“时序收敛”。具体数值和后续接手事项见手册。
本次是交接整理，不修改乐器HDL、界面资源、接线、App代码，不运行综合/PnR或烧录。
