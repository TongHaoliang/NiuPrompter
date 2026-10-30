# 开发约定

先读README.md和docs/DEVELOPMENT.md。保留iPhone横屏优先的独立侧栏界面与iPad布局；共享识别/匹配核心。不要把promptSegmentID与currentSegmentID合并。提前切句、防回跳、旧会话隔离和脱稿回找是核心行为。

修改行为后运行swift run --disable-sandbox TeleprompterChecks；运行bash scripts/check-boundaries.sh。UI改动还需iOS构建与对应横竖屏截图检查。模拟数据不代表真人识别验收通过。不要擅自加入云端识别、账号、录音保存或稿件云同步。

Xcode工程用scripts/generate-ios-project.sh生成，不提交个人签名配置、证书、设备UDID或构建产物。生成配置修改后，在干净目录验证。
