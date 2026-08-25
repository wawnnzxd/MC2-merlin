<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="X-UA-Compatible" content="IE=Edge" />
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<meta http-equiv="Pragma" content="no-cache" />
<meta http-equiv="Expires" content="-1" />
<title>Magic Catling</title>
<link rel="stylesheet" type="text/css" href="index_style.css" />
<link rel="stylesheet" type="text/css" href="form_style.css" />
<link rel="stylesheet" type="text/css" href="/user/res/kslite.css" />
<link rel="stylesheet" type="text/css" href="/user/res/mc2.css" />
<script type="text/javascript" src="/js/jquery.js"></script>
<script type="text/javascript" src="/state.js"></script>
<script type="text/javascript">
	// ⚠️ 不调 show_menu()。它是 ASUS 老式框架的入口,会往 #mainMenu / #tabMenu
	//    那套 DOM 写 innerHTML,而本页是自己画的、没有那些元素 →
	//    TypeError: Cannot set properties of null → init 中断 →
	//    body 停在 index_style.css 给的 visibility:hidden → 整页空白。
	//
	//    上游那份 Module_merlinclash.asp 正是走老框架的,所以它的 #tabMenu
	//    在新版 SPA 里被填成了 "Sysinfo",八个面板只有第一个能显示 ——
	//    这也是重写的直接原因之一。
	function init() {
		document.body.style.visibility = "visible";
		reportHeight();
	}
	// ⚠️ 只量 body,**绝不能碰 documentElement.scrollHeight** —— html 撑满 iframe,
	//    那个值恒等于 iframe 当前高度,拿它上报就是正反馈:上报 H → iframe 变 H →
	//    下次量到还是 H → 再上报,高度只增不减。实测内容 519px 时 iframe 已被撑到
	//    5957px,底下全是空白(2026-08-25 修)。
	function reportHeight() {
		try {
			var h = document.body ? document.body.scrollHeight : 0;
			if (h > 0) parent.postMessage({ type: "resize", height: h }, "*");
		} catch (e) {}
	}
	window.addEventListener("resize", reportHeight);
</script>
</head>

<body onload="init();">
<div class="kslite mc2">

	<!-- ══ 状态条:常驻,不随 tab 切换 ══════════════════════
	     改任何设置前最该确认的就是「内核在不在跑」,所以它固定在顶部,
	     而不是像原版那样埋在第一个面板里。 -->
	<div class="kslite-card">
		<div class="mc2-hero">
			<div class="mc2-hero__state">
				<span class="mc2-dot" id="mcDot"></span>
				<div>
					<div class="mc2-hero__label" id="mcState">读取中…</div>
					<div class="mc2-hero__core" id="mcCore">—</div>
				</div>
			</div>
			<div class="mc2-hero__ops">
				<select class="mc2-select" id="mcYaml" style="flex:0 1 190px"></select>
				<button type="button" class="kslite-btn kslite-btn--ghost" id="mcPanel" disabled>管理面板</button>
				<button type="button" class="kslite-btn kslite-btn--ghost" id="mcRestart" disabled>重启</button>
				<button type="button" class="mc2-toggle" id="mcToggle" disabled
				        aria-label="总开关"></button>
			</div>
		</div>

		<div class="mc2-runtime">
			<div class="mc2-run"><span class="mc2-run__k">内核进程</span><span class="mc2-run__v" id="mcPid">—</span></div>
			<div class="mc2-run"><span class="mc2-run__k">启动时间</span><span class="mc2-run__v" id="mcUp">—</span></div>
			<div class="mc2-run"><span class="mc2-run__k">当前配置</span><span class="mc2-run__v" id="mcCfg">—</span></div>
			<div class="mc2-run"><span class="mc2-run__k">插件版本</span><span class="mc2-run__v" id="mcVer">—</span></div>
		</div>
	</div>

	<!-- ══ Tab ══════════════════════════════════════════ -->
	<div class="mc2-tabs" role="tablist">
		<button type="button" class="mc2-tab is-active" data-tab="sub"   role="tab">订阅管理</button>
		<button type="button" class="mc2-tab"           data-tab="dns"   role="tab">DNS 设置</button>
		<button type="button" class="mc2-tab"           data-tab="rule"  role="tab">自定规则</button>
		<button type="button" class="mc2-tab"           data-tab="acl"   role="tab">访问控制</button>
		<button type="button" class="mc2-tab"           data-tab="adv"   role="tab">高级设置</button>
		<button type="button" class="mc2-tab"           data-tab="extra" role="tab">附加功能</button>
		<button type="button" class="mc2-tab"           data-tab="log"   role="tab">日志记录</button>
		<button type="button" class="mc2-tab"           data-tab="conf"  role="tab">当前配置</button>
	</div>

	<!-- 操作反馈:放在 tab 条下面而不是某个面板里 —— 保存/更新在哪个 tab 都会发生,
	     反馈得在哪个 tab 都看得见。 -->
	<div class="kslite-log" id="mcLog" style="margin:0 0 10px"></div>

	<!-- ══ 订阅管理 ══════════════════════════════════════ -->
	<div class="mc2-panel is-active" data-panel="sub">
		<div class="kslite-card">
			<div class="kslite-card__hd">订阅地址</div>
			<p class="kslite-hint">
				更新后会重新生成配置文件,需要重启内核才生效。
			</p>
			<div class="mc2-row">
				<div class="mc2-row__k">订阅链接
					<span class="mc2-row__hint">一行一条,可合并多个</span>
				</div>
				<div class="mc2-row__v">
					<textarea class="mc2-input mc2-input--mono" id="mcSubLinks" rows="2"
					          placeholder="https://example.com/link/xxxxx?clash=1"></textarea>
				</div>
			</div>
			<div class="mc2-row">
				<div class="mc2-row__k">自动更新</div>
				<div class="mc2-row__v">
					<!-- ⚠️ value 是**秒数**,不是序号 —— 上游 clash_subscribe.sh 直接拿它当
					     cron 间隔用(实测 dbus 里存的是 259200 = 3 天)。填 0/1/2/3
					     会被当成「0～3 秒」,订阅每秒都在重拉。 -->
					<select class="mc2-select" id="mcSubCycle" style="flex:0 1 160px">
						<option value="0">不自动更新</option>
						<option value="43200">每 12 小时</option>
						<option value="86400">每天</option>
						<option value="259200">每 3 天</option>
						<option value="604800">每周</option>
					</select>
				</div>
			</div>
			<div style="display:flex;gap:9px;margin-top:14px;flex-wrap:wrap">
				<button type="button" class="kslite-btn" id="mcSubUpdate">立即更新订阅</button>
				<button type="button" class="kslite-btn kslite-btn--ghost" id="mcSubSave">保存设置</button>
			</div>
		</div>

		<div class="kslite-card">
			<div class="kslite-card__hd">节点处理</div>
			<p class="kslite-hint">
				订阅转换时对节点做的处理,改完要点「立即更新订阅」才应用。
			</p>
			<div class="mc2-grid">
				<div class="mc2-row">
					<div class="mc2-row__k">节点重命名
						<span class="mc2-row__hint">按地区归类并统一命名</span>
					</div>
					<div class="mc2-row__v">
						<button type="button" class="mc2-toggle" id="mcSubRename" aria-label="节点重命名"></button>
					</div>
				</div>
				<div class="mc2-row">
					<div class="mc2-row__k">地区旗帜
						<span class="mc2-row__hint">节点名前加国旗 emoji</span>
					</div>
					<div class="mc2-row__v">
						<button type="button" class="mc2-toggle" id="mcSubEmoji" aria-label="地区旗帜"></button>
					</div>
				</div>
				<div class="mc2-row">
					<div class="mc2-row__k">UDP 转发
						<span class="mc2-row__hint">游戏语音需要,机场不支持时开了也没用</span>
					</div>
					<div class="mc2-row__v">
						<button type="button" class="mc2-toggle" id="mcSubUdp" aria-label="UDP 转发"></button>
					</div>
				</div>
				<div class="mc2-row">
					<div class="mc2-row__k">跳过证书验证
						<span class="mc2-row__hint">自签证书的节点才需要</span>
					</div>
					<div class="mc2-row__v">
						<button type="button" class="mc2-toggle" id="mcSubScv" aria-label="跳过证书验证"></button>
					</div>
				</div>
				<div class="mc2-row">
					<div class="mc2-row__k">TCP Fast Open
						<span class="mc2-row__hint">降低建连延迟</span>
					</div>
					<div class="mc2-row__v">
						<button type="button" class="mc2-toggle" id="mcSubTfo" aria-label="TCP Fast Open"></button>
					</div>
				</div>
			</div>
		</div>

		<div class="kslite-card">
			<div class="kslite-card__hd">本地上传</div>
			<div class="kslite-drop" id="mcDrop">
				<div class="kslite-drop__title">把配置文件拖到这里</div>
				<div class="kslite-drop__sub">已有现成 .yaml 时用这个,不走订阅转换</div>
				<button type="button" class="kslite-btn" id="mcPick">选择文件</button>
				<input type="file" class="kslite-file" id="mcFile" accept=".yaml,.yml" />
			</div>
		</div>
	</div>

	<!-- ══ DNS 设置(二期)═══════════════════════════════ -->
	<div class="mc2-panel" data-panel="dns">
		<div class="kslite-card">
			<div class="kslite-card__hd">DNS 方案</div>
			<p class="kslite-hint">
				改动保存后要<strong>重启内核</strong>才生效。DNS 是全网解析的必经之路,拿不准就别动。
			</p>
			<div class="mc2-row">
				<div class="mc2-row__k">解析方案</div>
				<div class="mc2-row__v">
					<div class="mc2-seg" id="mcDnsType">
						<button type="button" class="mc2-seg__opt" data-val="rh">Redir-Host</button>
						<button type="button" class="mc2-seg__opt" data-val="fi">Fake-ip</button>
					</div>
				</div>
			</div>
			<div class="mc2-row" id="mcFakeipRow" style="display:none">
				<div class="mc2-row__k">黑名单解析服务器
					<span class="mc2-row__hint">Fake-ip 黑名单里的域名交给它解析</span>
				</div>
				<div class="mc2-row__v">
					<input type="text" class="mc2-input mc2-input--mono" id="mcFakeipSrv"
					       style="flex:0 1 220px" placeholder="223.5.5.5" />
				</div>
			</div>
			<div class="mc2-grid">
				<div class="mc2-row">
					<div class="mc2-row__k">DNS 劫持
						<span class="mc2-row__hint">把局域网 DNS 请求截给内核</span>
					</div>
					<div class="mc2-row__v"><button type="button" class="mc2-toggle mc2-dirty" id="mcDnsHijack" aria-label="DNS 劫持"></button></div>
				</div>
				<div class="mc2-row">
					<div class="mc2-row__k">路由自身 DNS 走 Clash
						<span class="mc2-row__hint">路由器自己发起的解析也进内核</span>
					</div>
					<div class="mc2-row__v"><button type="button" class="mc2-toggle mc2-dirty" id="mcDnsProxy" aria-label="路由自身 DNS 走 Clash"></button></div>
				</div>
				<div class="mc2-row">
					<div class="mc2-row__k">清除路由自定义 DNS
						<span class="mc2-row__hint">启动时清掉 WAN 口手填的 DNS</span>
					</div>
					<div class="mc2-row__v"><button type="button" class="mc2-toggle mc2-dirty" id="mcDnsClear" aria-label="清除路由自定义 DNS"></button></div>
				</div>
				<div class="mc2-row">
					<div class="mc2-row__k">Sniffer 域名嗅探
						<span class="mc2-row__hint">从流量里嗅出真实域名再分流</span>
					</div>
					<div class="mc2-row__v"><button type="button" class="mc2-toggle mc2-dirty" id="mcDnsSniffer" aria-label="Sniffer 域名嗅探"></button></div>
				</div>
			</div>
			<div style="display:flex;gap:9px;margin-top:12px">
				<button type="button" class="kslite-btn" id="mcDnsSave">保存 DNS 设置</button>
			</div>
		</div>

		<div class="kslite-card">
			<div class="kslite-card__hd">高级编辑</div>
			<p class="kslite-hint">
				直接编辑配置片段(YAML)。保存即写入,<strong>重启内核生效</strong>;写错格式内核会起不来,启动日志里能看到原因。
			</p>
			<div style="display:flex;gap:9px;flex-wrap:wrap">
				<button type="button" class="kslite-btn kslite-btn--ghost mc2-edit" data-edit="dns_rh">Redir-Host</button>
				<button type="button" class="kslite-btn kslite-btn--ghost mc2-edit" data-edit="dns_fi">Fake-IP</button>
				<button type="button" class="kslite-btn kslite-btn--ghost mc2-edit" data-edit="hosts">自定义 Hosts</button>
				<button type="button" class="kslite-btn kslite-btn--ghost mc2-edit" data-edit="sniffer">Sniffer 配置</button>
			</div>
		</div>
	</div>

	<!-- ══ 自定规则(二期)═══════════════════════════════ -->
	<div class="mc2-panel" data-panel="rule">
		<div class="kslite-card">
			<div class="kslite-card__hd">IPtables 前置分流</div>
			<p class="kslite-hint">
				在流量进内核<strong>之前</strong>用 iptables 分掉 —— 比内核规则更快,改动要重启内核生效。
			</p>
			<div class="mc2-row">
				<div class="mc2-row__k">大陆 IP 不经过内核
					<span class="mc2-row__hint">chnroute 表里的目标直接放行,降低内核负担</span>
				</div>
				<div class="mc2-row__v">
					<button type="button" class="mc2-toggle" id="mcChnroute" aria-label="大陆 IP 不经过内核"></button>
				</div>
			</div>
			<div class="mc2-row">
				<div class="mc2-row__k">自定义分流
					<span class="mc2-row__hint">IP / 域名,一行一条,可带掩码</span>
				</div>
				<div class="mc2-row__v">
					<button type="button" class="kslite-btn kslite-btn--ghost mc2-edit" data-edit="ipt_black">强制绕行</button>
					<button type="button" class="kslite-btn kslite-btn--ghost mc2-edit" data-edit="ipt_white">强制转发</button>
				</div>
			</div>
		</div>

		<div class="kslite-card">
			<div class="kslite-card__hd">自定 Clash 规则</div>
			<p class="kslite-hint">
				插到订阅规则<strong>前面</strong>、优先匹配。简易模式用下面的表格,专业模式直接写 Clash rules 语法。
			</p>
			<div class="mc2-row">
				<div class="mc2-row__k">规则模式</div>
				<div class="mc2-row__v">
					<div class="mc2-seg" id="mcAclPlan">
						<button type="button" class="mc2-seg__opt" data-val="easy">简易</button>
						<button type="button" class="mc2-seg__opt" data-val="pro">专业</button>
					</div>
					<button type="button" class="kslite-btn kslite-btn--ghost mc2-edit" data-edit="acl" id="mcAclProBtn">编辑规则(专业)</button>
				</div>
			</div>
			<!-- 简易模式的规则表格:type/content/节点组 三元组,存 dbus 编号键,
			     clash_saveacls.sh 重排落盘。类型和节点组下拉都来自内核导出
			     (/_temp/proxytype.txt + proxygroups.txt),内核没启动过就没有 —— 那时给提示。 -->
			<div id="mcAclEasy">
				<div class="mc2-tablewrap">
					<table class="mc2-table">
						<thead><tr><th style="width:25%">类型</th><th>内容</th><th style="width:23%">出口(节点组)</th><th style="width:52px"></th></tr></thead>
						<tbody id="mcAclRows"></tbody>
						<tbody>
							<tr>
								<td><select class="mc2-select" id="mcAclType"></select></td>
								<td><input class="mc2-input mc2-table__mono" id="mcAclContent" placeholder="example.com / 1.2.3.0/24" /></td>
								<td><select class="mc2-select" id="mcAclGroup"></select></td>
								<td><button type="button" class="kslite-btn" id="mcAclAdd" style="padding:5px 11px">加</button></td>
							</tr>
						</tbody>
					</table>
				</div>
				<p class="mc2-row__hint" id="mcAclNote" style="margin-top:6px"></p>
			</div>
		</div>
	</div>

	<!-- ══ 访问控制(三期)═══════════════════════════════ -->
	<div class="mc2-panel" data-panel="acl">
		<div class="kslite-card">
			<div class="kslite-card__hd">设备绕行名单</div>
			<p class="kslite-hint">
				名单里的设备<strong>不走代理</strong>(或强制走),按 IP / MAC 匹配。改完<strong>重启内核</strong>生效。
			</p>
			<div class="mc2-row">
				<div class="mc2-row__k">匹配方法</div>
				<div class="mc2-row__v">
					<div class="mc2-seg" id="mcNokMethod">
						<button type="button" class="mc2-seg__opt" data-val="0">IP + MAC</button>
						<button type="button" class="mc2-seg__opt" data-val="1">仅 IP</button>
						<button type="button" class="mc2-seg__opt" data-val="2">仅 MAC</button>
					</div>
				</div>
			</div>
			<div class="mc2-tablewrap">
				<table class="mc2-table">
					<thead><tr>
						<th style="width:15%">别名</th><th style="width:20%">IP</th><th style="width:22%">MAC</th>
						<th style="width:14%">端口</th><th style="width:16%">策略</th><th style="width:52px"></th>
					</tr></thead>
					<tbody id="mcNokRows"></tbody>
					<tbody>
						<tr>
							<td><input class="mc2-input" id="mcNokName" placeholder="电视" /></td>
							<td><input class="mc2-input mc2-table__mono" id="mcNokIp" placeholder="192.168.50.20" /></td>
							<td><input class="mc2-input mc2-table__mono" id="mcNokMac" placeholder="可留空" /></td>
							<td>
								<select class="mc2-select" id="mcNokPort">
									<option value="all">全部端口</option>
									<option value="80,443">仅 80,443</option>
								</select>
							</td>
							<td>
								<select class="mc2-select" id="mcNokMode">
									<option value="0">不走代理</option>
									<option value="1">强制走代理</option>
								</select>
							</td>
							<td><button type="button" class="kslite-btn" id="mcNokAdd" style="padding:5px 11px">加</button></td>
						</tr>
					</tbody>
				</table>
			</div>
		</div>
	</div>

	<!-- ══ 高级设置(三期)═══════════════════════════════ -->
	<div class="mc2-panel" data-panel="adv">
		<div class="kslite-card">
			<div class="kslite-card__hd">插件行为</div>
			<div class="mc2-grid">
				<div class="mc2-row">
					<div class="mc2-row__k">实时进程守护
						<span class="mc2-row__hint">依赖 koolshare 固件的 perp,本机(原版梅林)没有 —— 已锁定关闭</span>
					</div>
					<div class="mc2-row__v"><button type="button" class="mc2-toggle" id="mcAdvWatchdog" disabled aria-label="实时进程守护"></button></div>
				</div>
				<div class="mc2-row">
					<div class="mc2-row__k">队列请求
						<span class="mc2-row__hint">页面操作排队发,弱路由防拥塞</span>
					</div>
					<div class="mc2-row__v"><button type="button" class="mc2-toggle" id="mcAdvQueue" aria-label="队列请求"></button></div>
				</div>
				<div class="mc2-row">
					<div class="mc2-row__k">开机自启推迟
						<span class="mc2-row__hint">等网络就绪再启动,秒</span>
					</div>
					<div class="mc2-row__v">
						<button type="button" class="mc2-toggle" id="mcAdvDelaySw" aria-label="开机自启推迟"></button>
						<input class="mc2-input mc2-table__mono" id="mcAdvDelayVal" style="flex:0 1 76px" />
					</div>
				</div>
				<div class="mc2-row">
					<div class="mc2-row__k">启动日志重试
						<span class="mc2-row__hint">检查内核起没起来的重试次数</span>
					</div>
					<div class="mc2-row__v">
						<button type="button" class="mc2-toggle" id="mcAdvLogSw" aria-label="启动日志重试"></button>
						<input class="mc2-input mc2-table__mono" id="mcAdvLogVal" style="flex:0 1 76px" />
					</div>
				</div>
			</div>
		</div>

		<div class="kslite-card">
			<div class="kslite-card__hd">内核参数</div>
			<div class="mc2-grid">
				<div class="mc2-row">
					<div class="mc2-row__k">TCP 并发连接
						<span class="mc2-row__hint">对同域名多 IP 并发试连,取最快</span>
					</div>
					<div class="mc2-row__v"><button type="button" class="mc2-toggle" id="mcAdvTcp" aria-label="TCP 并发连接"></button></div>
				</div>
				<div class="mc2-row">
					<div class="mc2-row__k">http/socks 混合端口
						<span class="mc2-row__hint">给局域网设备手动挂代理用</span>
					</div>
					<div class="mc2-row__v"><button type="button" class="mc2-toggle" id="mcAdvMix" aria-label="http/socks 混合端口"></button></div>
				</div>
				<div class="mc2-row">
					<div class="mc2-row__k">节点测速间隔
						<span class="mc2-row__hint">秒;开了才用自定义值</span>
					</div>
					<div class="mc2-row__v">
						<button type="button" class="mc2-toggle" id="mcAdvIntSw" aria-label="节点测速间隔"></button>
						<select class="mc2-select" id="mcAdvIntVal" style="flex:0 1 96px">
							<option>60</option><option>120</option><option>180</option><option>240</option>
							<option>300</option><option>360</option><option>420</option><option>480</option>
							<option>540</option><option>600</option>
						</select>
					</div>
				</div>
				<div class="mc2-row">
					<div class="mc2-row__k">切换容差
						<span class="mc2-row__hint">毫秒;新节点快出这个值才切换</span>
					</div>
					<div class="mc2-row__v">
						<button type="button" class="mc2-toggle" id="mcAdvTolSw" aria-label="切换容差"></button>
						<select class="mc2-select" id="mcAdvTolVal" style="flex:0 1 96px">
							<option>100</option><option>200</option><option>300</option><option>500</option><option>1000</option>
						</select>
					</div>
				</div>
				<div class="mc2-row">
					<div class="mc2-row__k">管理面板密码</div>
					<div class="mc2-row__v">
						<input class="mc2-input mc2-table__mono" id="mcAdvDashPw" style="flex:0 1 160px" />
					</div>
				</div>
			</div>
		</div>

		<div class="kslite-card">
			<div class="kslite-card__hd">代理方式</div>
			<div class="mc2-row">
				<div class="mc2-row__k">透明代理模式
					<span class="mc2-row__hint">UDP 走 TPROXY;与 AiProtection 网络神盾冲突</span>
				</div>
				<div class="mc2-row__v">
					<div class="mc2-seg" id="mcAdvTproxy">
						<button type="button" class="mc2-seg__opt" data-val="closed">关闭</button>
						<button type="button" class="mc2-seg__opt" data-val="tcp">仅 TCP</button>
						<button type="button" class="mc2-seg__opt" data-val="udp">仅 UDP</button>
						<button type="button" class="mc2-seg__opt" data-val="tcpudp">TCP + UDP</button>
					</div>
				</div>
			</div>
			<div class="mc2-grid">
				<div class="mc2-row">
					<div class="mc2-row__k">关闭透明代理
						<span class="mc2-row__hint">只跑内核不接管流量(调试用)</span>
					</div>
					<div class="mc2-row__v"><button type="button" class="mc2-toggle" id="mcAdvCloseProxy" aria-label="关闭透明代理"></button></div>
				</div>
				<div class="mc2-row">
					<div class="mc2-row__k">代理访客 / IoT 网络</div>
					<div class="mc2-row__v"><button type="button" class="mc2-toggle" id="mcAdvIot" aria-label="代理访客 / IoT 网络"></button></div>
				</div>
				<div class="mc2-row">
					<div class="mc2-row__k">代理路由自身流量</div>
					<div class="mc2-row__v"><button type="button" class="mc2-toggle" id="mcAdvSelf" aria-label="代理路由自身流量"></button></div>
				</div>
				<!-- ⚠️ 只读。上游 UI 这里是个可编辑输入框、绑 merlinclash_ipt_routingmark_val,
				     但那是**死键** —— 25 个脚本里没有任何代码读它(只在 clash_base.sh
				     的键名注释表里出现过一次)。真正生效的是 clash_config.sh 第 17 行
				     硬编码的 mcrm="256",它同时写进 clash 的 routing-mark 和 iptables 的
				     --mark 匹配,两处引用同一个变量所以天然自洽。
				     ⚠️⚠️ 这两个值一旦不一致,clash 自己发出的流量会被 iptables 重定向
				     回 clash,形成无限环路 —— 路由器直接死机(用户实际踩过)。
				     所以这里如实显示 256 并锁死,不给一个"改了没用"的输入框。 -->
				<div class="mc2-row">
					<div class="mc2-row__k">路由流量标记值
						<span class="mc2-row__hint">脚本内硬编码,与 iptables 匹配值绑定,不可改</span>
					</div>
					<div class="mc2-row__v">
						<span class="mc2-run__v" id="mcAdvMark" style="opacity:.7">256</span>
					</div>
				</div>
			</div>
			<div style="display:flex;gap:9px;margin-top:12px">
				<button type="button" class="kslite-btn" id="mcAdvSave">保存高级设置</button>
			</div>
		</div>
	</div>
	<!-- ══ 附加功能(四期)═══════════════════════════════ -->
	<div class="mc2-panel" data-panel="extra">
		<div class="kslite-card">
			<div class="kslite-card__hd">数据库更新</div>
			<p class="kslite-hint">
				Geo 库决定「哪些域名/IP 算国内」,大陆白名单给 iptables 前置分流用。更新走外网,机场慢时要等。
			</p>
			<div class="mc2-row">
				<div class="mc2-row__k">GeoIP 库</div>
				<div class="mc2-row__v">
					<select class="mc2-select" id="mcGeoIp" style="flex:0 1 210px">
						<option value="lite">Lite(200K)</option>
						<option value="full">Full(20M)</option>
						<option value="head">跟随基础配置</option>
					</select>
				</div>
			</div>
			<div class="mc2-row">
				<div class="mc2-row__k">GeoSite 库</div>
				<div class="mc2-row__v">
					<select class="mc2-select" id="mcGeoSite" style="flex:0 1 210px">
						<option value="default">Default(800K)</option>
						<option value="lite">Lite(200K)</option>
						<option value="full">Full(5M)</option>
						<option value="head">跟随基础配置</option>
					</select>
					<button type="button" class="kslite-btn" id="mcGeoUpdate">设置并更新</button>
					<span class="mc2-row__hint" id="mcGeoDate"></span>
				</div>
			</div>
			<div class="mc2-row">
				<div class="mc2-row__k">大陆 IP 白名单
					<span class="mc2-row__hint">chnroute,「大陆 IP 不经过内核」用它</span>
				</div>
				<div class="mc2-row__v">
					<button type="button" class="kslite-btn kslite-btn--ghost" id="mcChnUpdate">更新</button>
					<span class="mc2-row__hint" id="mcChnDate"></span>
				</div>
			</div>
			<p class="mc2-row__hint" style="margin-top:8px">
				内核本体由插件包管理(升级 = 重打包整体更新),不提供页面上传 —— 这是本定制版的维护约定。
			</p>
		</div>

		<div class="kslite-card">
			<div class="kslite-card__hd">备份与恢复</div>
			<p class="kslite-hint">
				勾选要打包的内容,下载成 <code>mc_backup.tar.gz</code>;恢复后需重启内核。
			</p>
			<div class="mc2-grid" id="mcBakBoxes">
				<div class="mc2-row"><div class="mc2-row__k">插件设置</div><div class="mc2-row__v"><button type="button" class="mc2-toggle is-on" data-bak="merlinclash_bak_set" aria-label="插件设置"></button></div></div>
				<div class="mc2-row"><div class="mc2-row__k">访问控制名单</div><div class="mc2-row__v"><button type="button" class="mc2-toggle is-on" data-bak="merlinclash_bak_acl" aria-label="访问控制名单"></button></div></div>
				<div class="mc2-row"><div class="mc2-row__k">配置文件</div><div class="mc2-row__v"><button type="button" class="mc2-toggle is-on" data-bak="merlinclash_bak_yaml" aria-label="配置文件"></button></div></div>
				<div class="mc2-row"><div class="mc2-row__k">自定义规则</div><div class="mc2-row__v"><button type="button" class="mc2-toggle is-on" data-bak="merlinclash_bak_rule" aria-label="自定义规则"></button></div></div>
				<div class="mc2-row"><div class="mc2-row__k">DNS 配置</div><div class="mc2-row__v"><button type="button" class="mc2-toggle is-on" data-bak="merlinclash_bak_dns" aria-label="DNS 配置"></button></div></div>
				<div class="mc2-row"><div class="mc2-row__k">规则数据库</div><div class="mc2-row__v"><button type="button" class="mc2-toggle is-on" data-bak="merlinclash_bak_db" aria-label="规则数据库"></button></div></div>
			</div>
			<div style="display:flex;gap:9px;margin-top:12px;align-items:center;flex-wrap:wrap">
				<button type="button" class="kslite-btn" id="mcBakDown">下载备份</button>
				<button type="button" class="kslite-btn kslite-btn--ghost" id="mcBakPick">恢复备份…</button>
				<input type="file" class="kslite-file" id="mcBakFile" accept=".gz" />
			</div>
		</div>

		<div class="kslite-card">
			<div class="kslite-card__hd">定时重启</div>
			<p class="kslite-hint">
				保存后<strong>重启内核</strong>生效(cron 任务在内核启动流程里写入)。
			</p>
			<div class="mc2-row">
				<div class="mc2-row__k">重启计划</div>
				<div class="mc2-row__v">
					<select class="mc2-select" id="mcRstMode" style="flex:0 1 120px">
						<option value="1">关闭</option>
						<option value="5">每隔</option>
						<option value="2">每天</option>
						<option value="3">每周</option>
						<option value="4">每月</option>
					</select>
					<span id="mcRstFields" style="display:flex;gap:7px;align-items:center;flex-wrap:wrap">
						<input class="mc2-input mc2-table__mono" id="mcRstEvery" style="flex:0 1 64px" title="间隔分钟" />
						<span class="mc2-row__hint" id="mcRstEveryU">分钟</span>
						<select class="mc2-select" id="mcRstDay" style="flex:0 1 76px" title="几号"></select>
						<select class="mc2-select" id="mcRstWeek" style="flex:0 1 88px" title="周几">
							<option value="0">周日</option><option value="1">周一</option><option value="2">周二</option>
							<option value="3">周三</option><option value="4">周四</option><option value="5">周五</option>
							<option value="6">周六</option>
						</select>
						<select class="mc2-select" id="mcRstHour" style="flex:0 1 72px" title="时"></select>
						<span class="mc2-row__hint">:</span>
						<select class="mc2-select" id="mcRstMin" style="flex:0 1 72px" title="分"></select>
					</span>
					<button type="button" class="kslite-btn kslite-btn--ghost" id="mcRstSave">保存</button>
				</div>
			</div>
		</div>
	</div>

	<!-- ══ 日志记录(四期)═══════════════════════════════ -->
	<div class="mc2-panel" data-panel="log">
		<div class="kslite-card">
			<div class="kslite-card__hd">日志</div>
			<div style="display:flex;gap:9px;margin-bottom:10px;flex-wrap:wrap">
				<div class="mc2-seg" id="mcLogSrc">
					<button type="button" class="mc2-seg__opt is-active" data-val="op">操作日志</button>
					<button type="button" class="mc2-seg__opt" data-val="core">内核日志</button>
				</div>
				<button type="button" class="kslite-btn kslite-btn--ghost" id="mcLogRefresh">刷新</button>
			</div>
			<textarea class="mc2-editor__ta" id="mcLogView" readonly spellcheck="false"
			          style="min-height:420px"></textarea>
		</div>
	</div>

	<!-- ══ 当前配置(四期)═══════════════════════════════ -->
	<div class="mc2-panel" data-panel="conf">
		<div class="kslite-card">
			<div class="kslite-card__hd">当前配置预览</div>
			<p class="kslite-hint">
				内核<strong>正在使用</strong>的完整配置(启动时快照)。只读 —— 要改去「DNS 设置」和「订阅管理」。
			</p>
			<div style="display:flex;gap:9px;margin-bottom:10px">
				<button type="button" class="kslite-btn kslite-btn--ghost" id="mcConfRefresh">刷新</button>
			</div>
			<textarea class="mc2-editor__ta" id="mcConfView" readonly spellcheck="false"
			          style="min-height:460px"></textarea>
		</div>
	</div>

	<!-- 共享的内联编辑器:JS 把它搬到触发按钮所在的卡片尾部展开。
	     整页只有这一个实例 —— 同时只可能编辑一段,多实例只会多出状态同步的活。 -->
	<div class="kslite-card mc2-editor" id="mcEditor">
		<div class="kslite-card__hd" id="mcEditorTitle">编辑</div>
		<textarea class="mc2-editor__ta" id="mcEditorText" spellcheck="false"></textarea>
		<div class="mc2-editor__bar">
			<span class="mc2-editor__hint" id="mcEditorHint"></span>
			<button type="button" class="kslite-btn kslite-btn--ghost" id="mcEditorCancel">取消</button>
			<button type="button" class="kslite-btn" id="mcEditorSave">保存</button>
		</div>
	</div>

</div>
<script type="text/javascript" src="/user/res/mc2.js"></script>
</body>
</html>
