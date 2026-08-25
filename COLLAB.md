# 协作约定

这个仓库同时被**两条线**改动,而且两边都是同一个人的 Claude 会话,
git 里的 author 完全相同(`Claude Code <admin@beiyingma.com>`)—— **没法靠作者区分谁改的**。
本文件是两边共用的协议,免得互相踩。

| 线 | 工作目录 | 负责 | 目标机 |
|---|---|---|---|
| **koolshare 线** | `路由器插件/MC2-merlin/` | `install_koolshare.sh`、老版 UI(`Module_merlinclash.asp` + `merlinclash.css`)、自更新链路 | GT-BE96,koolcenter 官改固件 |
| **AI 路由器线** | `路由器插件/GT-BE19000AI/` | `install_merlin.sh`、新版 UI(`Module_mc2.asp` + `mc2.js/css`)、koolshare-shim | GT-BE19000AI,原版梅林 + shim |
| **共用** | — | `merlinclash/scripts/*`(MC2 本体)、`clash_selfupdate.sh`、`version`、`build.sh`、本文件 | 两边 |

改共用区之前先看一眼对面有没有依赖;改对面的专属区之前,**先开 issue 说一声**,别直接动手。

## 沟通渠道 = GitHub Issues

<https://github.com/wawnnzxd/MC2-merlin/issues>

两边都有 `gh` 且已认证,直接用:

```bash
gh issue list --repo wawnnzxd/MC2-merlin --state open
```

- **发现对方的改动有问题 / 有优化建议** → 开 issue,标题带 `[koolshare→AI]` 或 `[AI→koolshare]` 前缀,
  说清楚:哪个文件哪一行、什么情况下会出问题、建议怎么改。
- **要改共用区、可能影响对方** → 先开 issue 说明,改完在 issue 里回一句然后 close。
- **纯自己那条线的事** → 不用开 issue,直接改。

选 issue 不选别的(聊天记录、本地文件)的原因:跨会话持久、有时间线、用户也看得到能仲裁,
而且 context 被压缩后 `gh issue list` 还能把上下文捞回来。

## 提交信息带上是哪条线

author 分不出来,所以在 commit message 末尾加一行 trailer:

```
Line: koolshare
```
或
```
Line: AI
```

```bash
git commit -F msg.txt --trailer "Line=koolshare"
```

查历史时:`git log --format='%h %(trailer:key=Line,valueonly) %s'`

## 发版

`version` 是**共用**的,四段纯数字(`install.sh` 会剥字母后整数比较,带字母会坏)。
两边都会 `gh release create`,**发版前先 `git pull`**,别把对面的版本号覆盖回去。

自更新只认 **完整包**(`MC2_<版本>_ARM64.tar.gz`)。曾经发过 slim 增量包,已撤销 ——
装完包是残的、以后还得再下一次,是把成本推后而不是省下来。别再加回来。

## 不变量(改之前先跑 `sh check.sh`)

`check.sh` 把两边踩过坑换来的修复固化成断言。它跑得很快,发版前跑一次:

```bash
sh check.sh
```

其中最要紧的一条,单独说明:

### 🟥 绝对不要往 `merlinclash_` 命名空间写外部内容

18 个 MC2 脚本(含 `clash_config.sh:9`,开机自启和总开关都走它)执行
`eval $(dbus export merlinclash_)`,而 koolshare 固件的 `dbus export` 输出的是
**零转义**的 `export KEY="值"`。真机实测:

```
dbus set zz_x='v$(id -u)w'
eval $(dbus export zz_)     →  sh: eval: line 1: id: not found   ← 真的执行了
```

2026-08-23 曾把 GitHub Release 正文原样写进 `merlinclash_selfupdate_note` ——
发布说明里一个反引号就是下次开机的 root 执行。该键已删除,所有进 dbus 的外部值
统一过 `sane()`(只留 `[A-Za-z0-9._:-]`)。

**AI 线注意**:`koolshare-shim` 自己实现的 `dbus` **有**转义 `$` 和反引号,所以梅林那侧
这条通道是堵上的 —— 但它堵上的原因就是 shim 里那几行转义。**别把它当成"多余的复杂度"优化掉。**
