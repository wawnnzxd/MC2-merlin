# 03 — zashboard 面板换成自家 fork

不以 diff 形式存(几百个文件 12MB,diff 无意义)。记来源与重放方法:

- 来源:https://github.com/wawnnzxd/zashboard/releases —— 取 latest 的 `dist.zip`
- 当前固化版本:**v3.24.0-c.1**(2026-09-01 发布并当日装到 BE19000AI;上一版 v3.22.0-c.1)
- ⚠️ **别装上游 Zephyruso/zashboard** —— 2026-08-25 误装过一次。判据很直观:
  **fork 版页面 `<title>` 是 `Desire`,上游版是 `zashboard`**,浏览器标签页一眼可辨。
  另外两版目录结构不同:上游 dist 是**平铺**(index.html 在根),
  MC2 要的是 `dashboard/zashboard/` 子目录结构(external-ui 指向那里),
  平铺直接解压会让 `/ui/zashboard/` 404。
- 手工重放:`gh release download <tag> --repo wawnnzxd/zashboard --pattern dist.zip`
  解压后把 `dist/` 内容整个替换 `merlinclash/dashboard/zashboard/`
- 为什么:MC2 上游 1.2.2 自带的 zashboard 是老架构(单文件打包,无 EarthGlobe/BackendSettings 等拆分页),
  功能落后于 fork。**每次上游更新都会把面板覆盖回老版**,本仓库固化 fork 版,安装即正确。

## ★★ 面板里那个「升级」按钮:提示对、动作错(2026-09-01 修)

fork 版面板的升级是**两段、各走各的**,这两段以前是错配的:

| 步骤 | 面板实际干的事 | 修之前的结果 |
|---|---|---|
| 检查更新 | `GET api.github.com/repos/**wawnnzxd**/zashboard/releases/latest` | ✅ 认 fork,会正确提示新版本号 |
| 点升级 | `POST /upgrade/ui` → **内核**按 `external-ui-url` 下载解压 | ❌ 那个 URL 指向**上游**,把 fork 覆盖成上游版 |

⇒ 症状会非常骗人:**面板明明提示的是我们 fork 的版本号,升完却变成上游版**
(`<title>` 由 `Desire` 变 `zashboard`,自家主题 `desire`/`desire-dark` 消失)。

已把 `external-ui-url` 改成 fork 的资产:

```yaml
external-ui: dashboard
external-ui-name: zashboard          # 内核据此解压到 dashboard/zashboard/
external-ui-url: https://github.com/wawnnzxd/zashboard/releases/latest/download/dist.zip
```

- ⚠️ **资产名是 `dist.zip` 不是 `dist-cdn-fonts.zip`** —— 后者是上游才有的变体;
  fork 只发 `dist.zip`(字体内嵌,路由器上不依赖外部 CDN,更稳)。
- ⚠️ **实际生效的是路由器上的 `merlinclash/yaml_basic/head.yaml`**。
  MC2 订阅时会把 `external-ui-*` 从配置里剥掉(跟 `dns`/`sniffer`/`hosts` 一样),
  所以 `merlinclash-config/AP_*.yaml` 里那份**只是母版/备忘录,改了不生效**。
  → **两处都要改**,否则白改。`yaml_bak` 里没有这几个键,不用管。
- ⚠️ `head.yaml` 是 MC2 自己的文件,**MC2 升级会覆盖它** —— 升完复查这一行。
  备份留在 `yaml_basic/head.yaml.bak-zash-20260901`。
- 内核的解压是对的:zip 里是 `dist/` 单顶层目录,内核会**自动剥掉这层**再放进
  `dashboard/zashboard/`,不会出现 `zashboard/dist/index.html` 那种嵌套。2026-09-01 实测。

### 升级流程(改完 URL 之后)

面板上直接点升级就行。命令行等价物:

```bash
curl -X POST -H 'Authorization: Bearer clash' http://192.168.0.1:9990/upgrade/ui
```

验收三件事:`<title>` 仍是 `Desire`、`assets/*.js` 里能 grep 到新版本号、
`http://192.168.0.1:9990/ui/zashboard/` 返回 200 且主 JS 能加载。
升级前先备份:`tar czf /jffs/koolshare/backup-zashboard-<版本>.tar.gz -C <dashboard目录> zashboard`。
