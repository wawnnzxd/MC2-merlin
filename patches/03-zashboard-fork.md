# 03 — zashboard 面板换成自家 fork

不以 diff 形式存(395 个文件 9MB,diff 无意义)。记来源与重放方法:

- 来源:https://github.com/wawnnzxd/zashboard/releases —— 取 latest 的 `dist.zip`
- 当前固化版本:**v3.22.0-c.1**(2026-08-24 发布,2026-08-25 装到 BE19000AI)
- ⚠️ **别装上游 Zephyruso/zashboard** —— 2026-08-25 误装过一次。判据很直观:
  **fork 版页面 `<title>` 是 `Desire`,上游版是 `zashboard`**,浏览器标签页一眼可辨。
  另外两版目录结构不同:上游 dist 是**平铺**(index.html 在根),
  MC2 要的是 `dashboard/zashboard/` 子目录结构(external-ui 指向那里),
  平铺直接解压会让 `/ui/zashboard/` 404。
- 重放:`gh release download <tag> --repo wawnnzxd/zashboard --pattern dist.zip`
  解压后把 `dist/` 内容整个替换 `merlinclash/dashboard/zashboard/`
- 为什么:MC2 上游 1.2.2 自带的 zashboard 是老架构(单文件打包,无 EarthGlobe/BackendSettings 等拆分页),
  功能落后于 fork。**每次上游更新都会把面板覆盖回老版**,本仓库固化 fork 版,安装即正确。
- 配置里 `external-ui-url` 仍指向 fork 的 releases,面板内「更新」按钮可在线拉最新。
