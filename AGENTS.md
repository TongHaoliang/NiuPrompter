# 开发约定

先读README.md和docs/DEVELOPMENT.md。iPhone默认提词拍摄，纯提词在设置中；iPad保留独立纯提词布局。共享识别/匹配核心，不合并promptSegmentID与currentSegmentID。提前切句、防回跳、旧会话隔离、脱稿回找和手动点句恢复是核心行为。

拍摄由一个AVCaptureSession拥有麦克风，识别是可独立断开的消费者，暂停跟随不能中断录像。用户主动录像保存到本机，稿件库原子持久化；不擅自加入云端识别、账号、上传或云同步。删除须确认范围，不删除系统相册副本。

修改行为后运行swift run --disable-sandbox TeleprompterChecks和bash scripts/check-boundaries.sh。UI改动还需iOS构建与相关布局检查。模拟数据不代表真人识别或录像验收通过，未验证事项在开发文档中明确。

工程由scripts/generate-ios-project.sh生成，不提交个人签名配置、证书、设备标识、私人口播稿、录像或构建产物。生成配置修改后，在干净目录验证。
