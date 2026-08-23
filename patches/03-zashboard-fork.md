# 03 — zashboard 面板换成自家 fork

不以 diff 形式存(395 个文件 9MB,diff 无意义)。记来源与重放方法:

- 来源:https://github.com/wawnnzxd/zashboard/releases —— 取 latest 的 `dist.zip`
- 当前固化版本:**v3.19.0-c.5**(2026-08-20)
- 重放:`gh release download <tag> --repo wawnnzxd/zashboard --pattern dist.zip`
  解压后把 `dist/` 内容整个替换 `merlinclash/dashboard/zashboard/`
- 为什么:MC2 上游 1.2.2 自带的 zashboard 是老架构(单文件打包,无 EarthGlobe/BackendSettings 等拆分页),
  功能落后于 fork。**每次上游更新都会把面板覆盖回老版**,本仓库固化 fork 版,安装即正确。
- 配置里 `external-ui-url` 仍指向 fork 的 releases,面板内「更新」按钮可在线拉最新。
