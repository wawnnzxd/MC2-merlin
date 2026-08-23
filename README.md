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

软件中心 → 离线安装 → 上传 `packages/*.tar.gz`;或 SSH:
```sh
tar -xzf MC2_*.tar.gz -C /tmp && sh /tmp/merlinclash/install.sh
```

## 1.2.2 上游变更摘要(2026-08-23 评估)

- 内核升到 mihomo v1.19.28
- **删掉整套「定时脚本记录代理组状态」**(`clash_node_mark.sh` + `autosermark` cron + usb2jffs 判断),统一用内核 `store-selected`
- ASP 同步删「节点恢复日志」面板和 `recordbycron` 开关
- routing-mark `524288 → 256`(已确认与本机 fullcone 的 `0x2333` 不冲突)
- 9 个规则文件更新(GoogleCN / GoogleFCM / UnBan / rule_mc*)
- CSS 上游未动(与我们的 `.orig` 备份逐字节相同)⇒ 皮肤补丁零冲突
