# MC2-merlin

Magic Catling 2(merlinclash)的自用定制版。**基底跟随上游,改动以 patch 形式单独维护**,上游更新时重打即可。

## 相对上游的改动

| # | 改动 | 文件 |
|---|---|---|
| 01 | 去在线公告/广告(`notice_show()` 注释,断掉对 raw.githubusercontent.com 的跨域拉取) | `webs/Module_merlinclash.asp` |
| 01 | **皮肤固定梅林风格**(`<body skin='ASUSWRT'>`,不跟随固件 `sc_skin`;想跟随改回 `<% nvram_get("sc_skin"); %>`) | 同上 |
| 02 | 重构版 CSS(27.6KB,令牌驱动;ROG/TUF/TS 强调色仍保留在 `[skin=…]` 选择器里) | `res/merlinclash.css` |
| 03 | **zashboard 面板换自家 fork**(上游每次更新都会覆盖回老版,本仓库固化) | `dashboard/zashboard/` |

## 版本号约定

`<上游版本>.<修订>`,如 `1.2.2.1` = 上游 1.2.2 + 本仓库第 1 次修订。
⚠️ **不能用 `1.2.2-merlin.1` 这种带横线的格式**:上游 `install.sh` 第 56 行把 version 剥字母/去尾段/删点后做
**整数比较**(`-lt 100`),带横线会变成 `122-1` 直接报错。四段纯数字 → `1221`,安全。

## 上游更新流程

```sh
# 1. 拿新版 MC2_x.y.z_ARM64.tar.gz,解压到 merlinclash/(整个替换)
# 2. 重打补丁
cd MC2-merlin && for p in patches/*.patch; do patch -p1 < "$p"; done
# 3. 面板:按 patches/03-zashboard-fork.md 拉 fork 的 dist.zip 替换
# 4. 改 merlinclash/version 为 x.y.z.1,打包
COPYFILE_DISABLE=1 tar --no-xattrs -czf packages/MC2_x.y.z.1_ARM64.tar.gz merlinclash
```
patch 冲突 = 上游动了我们改的地方,手工合一下再 `diff -u` 重生成。

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
