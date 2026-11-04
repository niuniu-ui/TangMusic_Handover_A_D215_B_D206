随包开发工具

append_piano_labels_d206.py、emit_rom.py、reference/d205_font_250_baseline.json 为当前D206字库生成入口。
默认使用冻结的字形数据，Python 3.10及以上即可；不需要安装测试软件、Pillow或系统字体。
运行前请复制工程；执行 python tools/append_piano_labels_d206.py 会重写字库HEX、ROM和标签VH。
generate_game_songs.py 为本地八首练习的共享节拍表生成入口，运行会重写src/studio_game_songs.vh。
上述脚本会自行生成说明JSON到reports，仅为开发记录。

普通综合、布局布线不需要运行这些生成器。修改产生的新源码必须重新综合和布局布线。
旧D203一次性贴图覆盖脚本不作为当前生成入口。历史设计底图位于Documentation/DesignReference，最终以当前src/assets为准。
