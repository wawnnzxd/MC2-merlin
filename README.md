# MC2-merlin

Magic Catling 2(merlinclash)的自用定制版。**从 1.2.2.13 起,本仓库就是主源** ——
上游降级为参考素材(值得借鉴的单点吸收进来),不再整包跟随。
兼容性保持:clash 配置文件、dbus 键、后端脚本协议(`case $2` 暗号、`BBABBBBC` 日志标记)与上游一致。

## 双固件,一份包,两套皮肤

`install.sh` 是分发器,按固件自动选:

| 固件 | 判据 | 安装分支 | UI |
|---|---|---|---|
| koolshare 官改(GT-BE96 等) | `/koolshare` 在 rootfs | `install_koolshare.sh`(上游流程+cp_smart) | 老版 ASP,koolcenter 原版皮肤 |
| 原版梅林 + koolshare-shim(GT-BE19000AI 等) | KSROOT=`/jffs/koolshare` | `install_merlin.sh`(重写) | **新版 `Module_mc2.asp`**,BE19000AI 风格 |

梅林侧只装新 UI 并清掉老 ASP 的部署与菜单;koolshare 侧反之(dispatcher 删掉误拷的新 UI 文件)。
卸载同样分发(`uninstall.sh` → `uninstall_koolshare.sh` / `uninstall_merlin.sh`)。

## 相对上游(1.2.2)的改动

| 类 | 改动 | 文件 |
|---|---|---|
| 界面 | **新版 UI 全套**(BE19000AI 风格重写,8 个 tab;含重启按钮、pollLog baseline 防旧日志假完成、`case $2` 数字暗号 5/25、post 检查 `response.error`) | `webs/Module_mc2.asp`、`res/mc2.js`、`res/mc2.css` |
| 界面 | 老 ASP 去广告 + 皮肤固定 ASUSWRT + 令牌化 CSS + 自更新入口(patch 01/02/04/05,已固化) | `webs/Module_merlinclash.asp`、`res/merlinclash.css` |
| 面板 | zashboard 换自家 fork([wawnnzxd/zashboard](https://github.com/wawnnzxd/zashboard),`<title>Desire`;上游平铺 dist 会 404,须放 `dashboard/zashboard/` 子目录) | `dashboard/zashboard/`(不进 git) |
| 后端 | `clash_config.sh` startime 引号修复(上游 bug:不加引号 dbus 只收到日期半截) | `scripts/clash_config.sh` |
| 后端 | 梅林缺失组件:`dummy_script.sh`(fields-only 保存)、`bin64/base64`(openssl 包装,busybox 没编该 applet)、`mc2_status.sh`(上游无机器可读进程状态)、`mc2_fixlink.sh`(Geo 更新后把大文件归位 ksdata 软链) | `scripts/`、`bin64/` |
| 自启 | `init.d/V150`(NTP 门控:无 RTC 电池,上电时钟=2024 纪元,等 `ntp_ready=1` 再起内核防 TLS 证书误判)+ `N150`(nat-start) | `init.d/`(仅梅林用) |
| 守护 | `merlinclash_set_watchdog_sw` 梅林侧强制 0(perp 是 koolshare 私有) | `install_merlin.sh` |

## 版本号约定

`<上游版本>.<修订>`,如 `1.2.2.1` = 上游 1.2.2 + 本仓库第 1 次修订。
⚠️ **不能用 `1.2.2-merlin.1` 这种带横线的格式**:上游 `install.sh` 第 56 行把 version 剥字母/去尾段/删点后做
**整数比较**(`-lt 100`),带横线会变成 `122-1` 直接报错。四段纯数字 → `1221`,安全。

## 上游有新版时怎么吸收

不再整包替换。流程:解包上游新版,`diff -r` 对比 `scripts/`(核心逻辑都在这),
值得要的改动**单点合入**;界面/安装脚本/面板一律以本仓库为准。
2026-08-25 对比过上游 1.2.2 包:非面板文件里上游独有的为零 —— 基底就是同一份。

⚠️ 合入脚本改动时核对三个协议耦合点(前端 mc2.js 依赖):
`case $2` 暗号(update_ipdb=5、chnroute=25、subscribe=upload/update、backup=backup/restore)、
日志结束标记 `BBABBBBC`、dbus 键名。

## 安装

安装包在 [Releases](https://github.com/wawnnzxd/MC2-merlin/releases)(**不进 git 历史**,每版 20MB 二进制会让仓库膨胀)。

软件中心 → 离线安装 → 上传 tar.gz;或 SSH:
```sh
tar -xzf MC2_*.tar.gz -C /tmp && sh /tmp/merlinclash/install.sh
# ⚠️ 重装后 merlinclash_enable 会被置 0,且手动起内核必须用 restart(start 是开机自启分支,会先 sleep 120s)
dbus set merlinclash_enable=1 && sh /koolshare/scripts/clash_config.sh restart
```

发版:
```sh
COPYFILE_DISABLE=1 tar --no-xattrs -czf packages/MC2_x.y.z.n_ARM64.tar.gz merlinclash
gh release create vx.y.z.n packages/MC2_x.y.z.n_ARM64.tar.gz --title "MC2 x.y.z.n" --notes "…"
```

## 1.2.2 上游变更摘要(2026-08-23 评估)

- 内核升到 mihomo v1.19.28
- **删掉整套「定时脚本记录代理组状态」**(`clash_node_mark.sh` + `autosermark` cron + usb2jffs 判断),统一用内核 `store-selected`
- ASP 同步删「节点恢复日志」面板和 `recordbycron` 开关
- routing-mark `524288 → 256`(已确认与本机 fullcone 的 `0x2333` 不冲突)
- 9 个规则文件更新(GoogleCN / GoogleFCM / UnBan / rule_mc*)
- CSS 上游未动(与我们的 `.orig` 备份逐字节相同)⇒ 皮肤补丁零冲突

## 自更新(v1.2.2.2 起)

插件页面「订阅配置」标签栏右侧有 **检查更新** 按钮,页面打开 3 秒后也会自动查一次
`https://api.github.com/repos/wawnnzxd/MC2-merlin/releases/latest`:

- 有新版 → 显示版本号,按钮变「立即更新」→ 点一下:下载 Release 里的 tar.gz → 校验 → 跑 install.sh →
  **自动恢复总开关 + 重启内核**(原版 install.sh 会把 `merlinclash_enable` 置 0,我们装完自己拉回来)→ 页面自动刷新。
- 后端 `scripts/clash_selfupdate.sh <id> check|install|status`;进度写在 dbus `merlinclash_selfupdate_*`,
  日志 `/tmp/upload/merlinclash_selfupdate.log`。
- **GEO 文件不会丢**:install.sh 对已存在且 >1MB 的 GeoSite/GeoIP.dat 一律「略过」。
- 仓库必须是公开的(private 的 API 需 token:`dbus set merlinclash_selfupdate_token=<PAT>`,不推荐)。

### 发版流程(给下次吸收上游新版用)
1. 上游 MC2 新包解包到 `merlinclash/`,重新套 `patches/01~04`(冲突手工合)
2. `merlinclash/version` 改成 **四段纯数字**(如 `1.2.3.1`,install.sh 会剥字母后整数比较,带字母的版本号会坏)
3. 打包 + 发 Release(tag 必须 `v` + 版本号,资产必须是 `.tar.gz`):
```bash
COPYFILE_DISABLE=1 tar --no-xattrs -czf packages/MC2_x.y.z.n_ARM64.tar.gz merlinclash
gh release create vx.y.z.n packages/MC2_x.y.z.n_ARM64.tar.gz --title "MC2 x.y.z.n" --notes "…"
```
4. 路由器上打开插件页 → 自动提示新版 → 立即更新。

### 踩过的坑
- `/_api/` 的 `method` **必须带 `.sh`**(`clash_selfupdate.sh`),写成 `clash_selfupdate` httpd 找不到脚本、前端只看到失败。
- `versioncmp A B` 在 **A 比 B 新时输出 `-1`**(反直觉),判新版用 `= "-1"`。
- 手动起内核是 `clash_config.sh restart restart`(动作在 **第 2 个参数**,`case $2 in`),只给一个参数什么都不干。

## 设计(v1.2.2.5 起)

皮肤是梅林风格(`<body skin='ASUSWRT'>` 固定,不跟随固件 `sc_skin`),视觉语言取 iOS 26 那套:
半透明材质 + 高光边 + 同心圆角 + 强 ease-out 曲线。`res/merlinclash.css` 里所有值都来自
文件顶部的 token,三条规矩:

- **间距全是 4 的倍数**,来自 `--mc-gutter` / `--mc-row-y` / `--mc-gap` 三个 token;
- **圆角走同心阶梯**:frame 22 → card 16 → control 11 → chip 8,嵌套的角才平行;
- **过渡必须写明属性**,不用 `all`;曲线只有两条(`--mc-ease` 强 ease-out、`--mc-ease-move`
  强 ease-in-out),**不用 `ease-in`**——它拖慢第一帧,而那正是眼睛盯着的一刻。

排版上做的实事(全部有量化验证,探针见 [SESSION_NOTES.md](SESSION_NOTES.md)):

| 问题 | 改法 |
|---|---|
| 标签列宽 236/248 两种,整页错位 12px | 行改 flex,`--mc-label-w` 一个 token 定死;8 个 tab 实测 232px / 数值列同一 x |
| 每行的标签下划线和数值下划线不在同一条 y(差 13~347px) | 分隔线改画在 `<tr>` 上 |
| 1600px 屏上模块只占 760px,三分之二是壁纸 | `.content` 放开 + 模块 `max-width:1240px` 居中 |
| 总开关行五个 div 用绝对定位硬编码像素堆叠,宽屏撕裂、窄屏断行 | 重写成 `.mc-row-main` flex 行 |
| 固件 CSS 把每个单元格里的 span 无差别染金 | span 继承单元格颜色,7 种硬编码色映射到 4 个语义 token |
| 按钮按下没有反馈 | 全部 `:active { transform: scale(.97) }`,130ms;hover 收进 `(hover:hover)` 门控 |
| 窄窗口把数值列挤扁 | `max-width:860px` 时标签换行到上方 |

无障碍:`prefers-reduced-motion` / `prefers-reduced-transparency` / `prefers-contrast` 三个信号各有对策
(减少动效不等于没有反馈,保留承载信息的颜色与透明度变化)。

## 更新为什么快(1.2.2.10 起)

包**始终是完整的** —— 装完就是能用的全套,不留「以后还得再下一次」的尾巴。
省开销全靠实现,不靠少发文件:

| 环节 | 上游做法 | 这里的做法 | 效果 |
|---|---|---|---|
| 下载 → 解包 | 先把 21MB 的 tar.gz 存进 `/tmp`,再解出 24MB | `curl \| tar -xz` 流式,tarball 不落地 | tmpfs 峰值 **45MB → 24MB**(`/tmp` 是 tmpfs,占的是物理内存) |
| 完整性校验 | `tar -tzf` 预检一遍,再 `tar -xzf` 解一遍 | 解包本身就是校验(管道里 `$?` 取 tar 的),外加校验解出的 version 是否等于目标版本 | 整包少 gunzip 一遍 |
| 写回 U 盘 | `rm -rf` 整个目录 → 无条件 `cp -rf` | 目录指纹一致就整个跳过;不一致则逐文件比对,只写真的变了的;`prune` 删掉源里已没有的 | 内容没变时 **~25MB 写入 → 0** |

指纹 = `md5(排序后的「文件名 + 各文件 md5」)`,存在 `/koolshare/merlinclash/.fp_<目录名>`。
源在 tmpfs(内存)读它几乎不要钱,目标在 U 盘上读它才贵 —— 所以只算源侧指纹。
实测 13MB / 409 文件的 dashboard:指纹 **0.07 秒**,逐文件比对 0.66 秒(热缓存),
安装时冷读 U 盘约 **4 秒**。

为什么在意 U 盘写入:本机这块 eVtran 没有掉电保护,已经因写入损坏过多次(见 `router-ops/`)。
每次更新白写 25MB 是纯粹的损耗。

⚠️ **`prune` 只能用于 MC2 独占的目录**(`dashboard`、`rule_configs`)。
`/koolshare/bin`、`/koolshare/scripts`、`/koolshare/res`、`/koolshare/webs` 是**所有插件共用**的,
在那里删「源里没有的文件」会删掉别的插件的东西。

### 曾经走过的弯路(别再走)
- **v1.2.2.6 发过一个 slim 增量包**(只含 scripts/webs/res,20MB → 0.12MB)。
  这是「少发文件」不是「做得更快」:装完包是残的,以后真要面板或 Geo 还得再下一次,
  只是把成本推后。已撤销,v1.2.2.6 / v1.2.2.7 上的 slim 资产也已删除。
- **v1.2.2.8 加了内容比对却毫无效果**:install.sh 的「清理旧文件」段在复制**之前**
  就 `rm -rf` 掉了整个 dashboard、rule_configs 和 bin/clash,目标被清空,比对必然全落空。
  v1.2.2.9 去掉这三处预删除、改用 rsync 语义(prune + 写前 unlink)后才真正生效。
  **教训:优化完一定要看真机日志确认它真的生效了**,别只看代码写对了没有。
