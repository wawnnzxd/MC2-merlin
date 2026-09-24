/* mc2.js —— Magic Catling 界面逻辑(GT-BE19000AI 重写版)
 *
 * ★ 后端一个字节都不改。这里复刻的是上游 Module_merlinclash.asp 里 push_data()
 *   用的那套协议,对接的还是原来那 16 个 clash_*.sh:
 *
 *     POST /_api/   {id, method:"clash_xxx.sh", params:["动作"], fields:{dbus键值}}
 *                   → 响应 {result:<同一个 id>};fields 由 handler 写进 dbus
 *     GET  /_api/<前缀>          → {result:[{键:值,...}]}   按前缀读 dbus
 *     GET  /_temp/<文件>         → 纯文本,轮询日志
 *     POST /_upload              → multipart,落 /tmp/upload/
 *
 *   所有请求走相对路径,由 ks-shim.js 在 XHR/fetch 层改道到 :8080。
 *
 * 2026-09-23 审计修复后的两处例外(都不改上游脚本):
 *   · 「大陆 IP 白名单 → 更新」调我们自己的 mc2_chnupdate.sh(交给 N98chnupdate,约定 C6);
 *     它不在、且这台没见过 N98 的更新记录时,确认后才退回上游 clash_update_chnroute.sh(见 chnMissing);
 *   · 内核版本、全部代理组直接问内核的 RESTful API(:9990 /version、/group,mihomoApi)——
 *     上游 dbus 里的版本记录是陈旧的,clash_getproxygroup.sh 只导出 select 组。
 *   「删除 = 字段置空」依赖 /_api/ 的约定:fields 里空串的键由 handler 执行 dbus remove(约定 C1)。
 *   ⚠️ 本文件在 GT-BE19000AI/mc2-merlin/plugin/res/ 和 MC2-merlin/merlinclash/res/ 各一份,
 *      必须逐字节相同(以 plugin 这份为准,改完 cp 过去再 md5 对拍)。
 */
(function () {
	"use strict";

	// ⚠️ MC2 用的是 BBABBBBC,**不是** koolshare 通用的 XU6J03M6 ——
	//    实测 9 个 clash_*.sh 全写 BBABBBBC,一个都没用 XU6J03M6。
	//    我一开始按通用标记写,结果 pollLog 永远等不到结束信号:
	//    日志能实时刷出来,但 onDone 从不触发 → loadStatus() 不执行 →
	//    操作明明成功了,状态条还停在旧值,得手动刷新页面才看到
	//    (2026-08-25 用户反馈「连接成功了并没有实时更新状态」)。
	//    而且轮询会一直空转下去,不会自己停。
	//    两个都认,将来若混用别的脚本也不会再踩。
	var DONE_MARKS = ["BBABBBBC", "XU6J03M6"];
	// ★ 2026-09-23 审计修复 mc2ui-20:busy 只表示「长任务」(启停/重启/订阅/上传/Geo/chnroute/备份恢复),
	//   saving 统计进行中的「短保存」(只写 dbus 或落一个小文件)。以前两者共用一个布尔:
	//   短保存结束时无条件 busy=false,正在跑的启停/重启就被「放开」了,总开关和重启又能点,
	//   再点一次就是两个 apply_mc 并发拆规则。
	var el = {}, busy = false, saving = 0, db = {};
	// ★ 2026-09-23 审计修复 mc2ui-19:表单「已改未存」标记(按组)。loadStatus() 只重绘没有草稿的组,
	//   以前每次操作结束都全量回填,别的 tab 里还没保存的改动会被悄悄还原。
	var dirty = {};
	// ★ 2026-09-23 审计修复 mc2ui-05:规则 tab 的类型/出口下拉是否需要重新拉取
	//   (内核没跑时拿到的是占位符;启停/重启/换配置后节点组也可能变)。
	var aclStale = true;

	/* ---------------- 通信 ---------------- */
	function nonce(p) { return p + (p.indexOf("?") < 0 ? "?" : "&") + "_=" + Date.now(); }

	// ★ 2026-09-23 审计修复(A 包 ksapid 鉴权三档 / 请求体限长的配套,跨包请求 A-X3):
	//   ksapid 拒绝请求时把原因说成人话,而不是「Unexpected token …」或一个裸状态码。
	//   · 401 —— 切到 enforce 档后,没带 WebUI 登录 cookie:{"error":"ksapid auth: no-cookie (login to WebUI first)"};
	//   · 413 —— /_api/ 请求体超过 128KB:{"error":"api body max 128KB"}(/_upload 是 256MB);
	//   · 403 —— Host / Origin 不对。⚠️ ksapid 回 403 时故意不带 Access-Control-Allow-Origin,而 /_api/ 等
	//     经 ks-shim 改道到 :8080 属于跨源请求 ⇒ 浏览器直接拦下,页面拿到的只是 fetch 的网络错误(TypeError),
	//     读不到 403 本身。所以网络错误也按「连不上 ksapid / 被 403 拒绝」给出排查方向(netErr)。
	//   默认 log 档不拦截,行为与以前一致。以前 r.json() 碰到非 JSON 响应只报解析错,状态码一个字不提。
	var API_MAX = 131072;   // 与 ksapid-handler.sh 里 /_api/ 的请求体上限一致(CLEN > 131072 → 413)
	var HTTP_HINT = {
		401: "没通过 ksapid 的登录校验 —— 请先登录路由器 WebUI(登录过期就重新登录),再刷新本页重试",
		403: "被 ksapid 拒绝(Host / Origin 不对)—— 请直接用路由器地址(LAN IP 或 asusrouter.com)打开 WebUI,别经反代 / 其它域名",
		413: "提交的内容太大,超过了 ksapid 的上限"
	};
	// 拼一个带状态码的错误。j.error 原样保留在消息里 —— chnRun 靠它认出「no script」。
	function httpErr(status, j, t) {
		var why = (j && j.error) ? j.error : String(t || "").replace(/\s+/g, " ").slice(0, 120);
		var raw = "HTTP " + status + (why ? ":" + why : "");
		var e = new Error(HTTP_HINT[status] ? HTTP_HINT[status] + "。(" + raw + ")" : raw);
		e.status = status;
		return e;
	}
	function netErr(e) {
		if (e && e.name === "TypeError") {
			throw new Error("连不上 ksapid(:8080),或请求被它以 403 拒绝(Host / Origin 不对时不回跨域头,浏览器只报网络错误)。" +
				"请用路由器地址打开 WebUI、确认 ksapid 在运行后刷新重试。(" + e.message + ")");
		}
		throw e;
	}
	// 读 ksapid 的 JSON 响应:非 2xx → httpErr;2xx 但带 error(脚本不存在等)→ 照旧抛 error 原文。
	function readJSON(r) {
		return r.text().then(function (t) {
			var j = null;
			try { j = JSON.parse(t); } catch (e) { /* 非 JSON:下面按状态码 / 原文报 */ }
			if (!r.ok) throw httpErr(r.status, j, t);
			if (!j || typeof j !== "object") throw new Error("后端回的不是 JSON:" + String(t).slice(0, 80));
			if (j.error) throw new Error(j.error);
			return j;
		});
	}
	// /_temp/ 文本:非 2xx 当读取失败(否则 401 的错误 JSON 会被当成文件内容填进编辑框)
	function readText(r) {
		if (r.ok) return r.text();
		return r.text().then(function (t) {
			var j = null;
			try { j = JSON.parse(t); } catch (e) { /* 非 JSON */ }
			throw httpErr(r.status, j, t);
		});
	}
	function utf8Len(s) {
		if (window.TextEncoder) return new TextEncoder().encode(s).length;
		return unescape(encodeURIComponent(s)).length;
	}

	function getJSON(p) {
		return fetch(nonce(p), { cache: "no-store" }).then(readJSON, netErr);
	}

	// fields 里的键值会被后端写进 dbus —— 上游脚本全靠读 dbus 拿参数,
	// 所以「保存设置」本质就是带 fields 发一次请求。
	//
	// ⚠️ 必须检查 response.error 并抛出。handler 在脚本不存在等情况下回
	//    {"error":"..."}(以前是 HTTP 200,现在是 404),光看 HTTP 状态码是发现不了的 ——
	//    踩过:dummy_script.sh 缺失时所有"保存"静默失败,dbus 纹丝不动,
	//    页面却一路显示"已保存"。假成功比失败更害人,它让人不再排查。
	// ★ 2026-09-23(A-X3):超过 128KB 的请求体前端直接拦下、不发 —— handler 回 413 时并不读完请求体就关连接,
	//   浏览器还在上传,常常只拿到连接被重置(网络错误),看不到 413 的说明。
	function post(method, params, fields) {
		var body = JSON.stringify({
			id: Math.floor(Math.random() * 1e8),
			method: method,
			params: params || [],
			fields: fields || {}
		});
		var n = utf8Len(body);
		if (n > API_MAX) {
			var e = new Error("要提交的内容 " + (n / 1024).toFixed(1) + " KB,超过 ksapid 的 128KB 上限,没有发送" +
				"(编辑器内容要先 URL 转义再 base64,体积约是原文的 2 倍,中文约 4 倍 —— 请删减内容再保存)。");
			e.status = 413;
			return Promise.reject(e);
		}
		return fetch("/_api/", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: body
		}).then(readJSON, netErr);
	}

	// 订阅链接框按内容撑高(CSS field-sizing 不支持时的兜底;值是程序填的,input 事件不触发,所以放在 fit 里一起做)
	function fitArea(ta) {
		if (!ta || (window.CSS && CSS.supports && CSS.supports("field-sizing", "content"))) return;
		ta.style.height = "auto";
		ta.style.height = (ta.scrollHeight + 2) + "px";
	}
	function fit() {
		fitArea(document.getElementById("mcSubLinks"));
		if (typeof window.reportHeight === "function") window.reportHeight();
	}

	// ★ 2026-09-24 用户要求布局不许留一大片空白:auto-fit 网格按「放得下几列排几列」,项目数和列数对不上时
	//   末行只剩一两个、右边空一大片(4 个插件排成 3+1、4 个开关排成 3+1)。
	//   这里在「按最小列宽放得下的列数」以内,挑末行空位最少的列数(一样少取列多的;不少于一半、不少于 2 列);
	//   宽度变了(含 MC2 切 tab 时网格从隐藏变可见)、子项增减了都重算。CSS 里的 auto-fit 仍是没 JS 时的兜底。
	function balanceGrid(g, minW) {
		if (!g.clientWidth) return;
		var gap = parseFloat(getComputedStyle(g).columnGap) || 0, n = 0, i;
		for (i = 0; i < g.children.length; i++) if (getComputedStyle(g.children[i]).display !== "none") n++;
		if (!n) return;
		var c = Math.max(1, Math.min(n, Math.floor((g.clientWidth + gap) / (minW + gap))));
		var best = c, bestE = (c - n % c) % c, k, e;
		for (k = c - 1; k >= Math.max(2, Math.ceil(c / 2)); k--) { e = (k - n % k) % k; if (e < bestE) { best = k; bestE = e; } }
		var v = "repeat(" + best + ", minmax(0, 1fr))";
		if (g.getAttribute("data-cols") !== String(best)) { g.style.gridTemplateColumns = v; g.setAttribute("data-cols", best); }
	}
	function autoBalance(sel, minW) {
		Array.prototype.forEach.call(document.querySelectorAll(sel), function (g) {
			var run = function () { balanceGrid(g, minW); };
			run();
			if (window.ResizeObserver) new ResizeObserver(run).observe(g);
			if (window.MutationObserver) new MutationObserver(run).observe(g, { childList: true });
		});
	}

	// 即改即存的统一出口:写一组 dbus 键,成功提示、失败也提示。
	// 单独收一个函数是因为这类调用散在各处,逐个补 .catch 迟早漏一个。
	// ★ 2026-09-23 审计修复 mc2ui-20:长任务进行中拒绝写入(以前完全不看 busy,apply_mc 正在
	//   按 dbus 重建规则时照样并发写键),并把界面上已经切换的即存控件还原回 dbus 当前值。
	//   返回的 Promise 解析为 true(已保存)/ false(被拒或失败),调用方据此决定要不要清输入框。
	function saveKV(fields, okMsg) {
		if (busy) {
			log("启停 / 重启等任务正在进行,请等它结束再改。");
			repaintInstant();
			return Promise.resolve(false);
		}
		saving++; lockOps();
		return post("dummy_script.sh", [], fields)
			.then(function () {
				// 本地 db 同步记上(空串 = 删键,同 /_api/ 约定),保存被拒时 repaintInstant 才还原得对
				Object.keys(fields).forEach(function (k) {
					if (fields[k] === "") delete db[k]; else db[k] = String(fields[k]);
				});
				saving--; lockOps(); okMsg && log(okMsg); return true;
			})
			.catch(function (e) { saving--; lockOps(); log("保存失败:" + e.message); return false; });
	}

	// ★ 2026-09-23 审计修复 mc2ui-20:两类入口的守卫。静默 return 会让人以为按钮坏了,一律说明原因。
	function longGuard() {
		if (busy || saving > 0) { log("有任务正在进行,请等它结束再操作。"); return true; }
		return false;
	}
	function shortGuard() {
		if (busy) { log("启停 / 重启等任务正在进行,请等它结束再保存。"); return true; }
		return false;
	}
	// 总开关 / 重启的可点状态只由 busy、saving、enable 决定;不重绘别的东西
	function lockOps() {
		if (!el.toggle) return;
		el.toggle.disabled  = busy || saving > 0;
		el.restart.disabled = busy || saving > 0 || db.merlinclash_enable !== "1";
	}
	// 即存控件(chnroute / 规则模式 / 匹配方法 / 配置下拉)按 db 当前值还原 —— 保存被拒时用
	function repaintInstant() {
		paintRule();
		segSet(el.nokMethod, nokMethodVal());
		fillYamlList();
	}

	function log(t) {
		el.log.classList.add("is-show");
		el.log.textContent = t;
		el.log.scrollTop = el.log.scrollHeight;
		fit();
	}

	// handler 对不存在的文件回 200 + 空串(不是 404),所以这里不会拿到 undefined
	// ⚠️ baseline 机制防"旧日志假完成":上一次操作的旧日志尾部残留着结束标记,
	//    不加区分就会被当成"已完成",轮询秒退,用户看到的全是旧内容
	//    (2026-08-25 用户点「设置并更新」看到的却是重启日志)。
	// ★ 2026-09-23 审计修复 mc2ui-11 / ksapid-12:基线改成**发 POST 之前**拍的快照(pre)。
	//    旧做法把 POST 返回后首轮读到的内容当基线、首轮带标记就当旧日志 —— 可 handler 要等脚本
	//    调了 http_response(或干脆等脚本跑完)才回包,秒结束 / 秒失败的任务首轮读到的恰恰是
	//    **本次**完整的最终日志,于是被当成旧日志:「等待任务启动 …」盖住真实结果(常常是报错),
	//    界面锁 3 分钟。现在的规则:
	//    · 内容 === 快照              → 本次任务还没写日志,继续等(45 秒一点没动就收尾并说明);
	//    · 内容以快照开头(追加型脚本)→ 只在新增部分里找结束标记、也只显示新增部分,
	//                                   残留的旧 BBABBBBC 不会再被当成本次完成;
	//    · 其它(脚本先清空再写)      → 按整份内容判定。
	//    快照拿不到(pre 不是字符串)时退回旧的「首轮当基线」逻辑,兼容。
	//    onDone(text, finished):text = 本次日志正文(已去标记);finished = 见到了结束标记(超时为 false)。
	function markIn(t) {
		return DONE_MARKS.some(function (m) { return t.indexOf(m) >= 0; });
	}
	function snapLog(file) {
		return fetch(nonce("/_temp/" + file), { cache: "no-store" })
			.then(function (r) { return r.text(); })
			.catch(function () { return null; });
	}
	// 统一写法:先拍快照 → 再发请求(starter 返回 POST 的 Promise)→ 带快照轮询 merlinclash_log.txt。
	// POST 失败照常 reject,交给调用方的 .catch 复位 busy。
	// maxMs 可选:脚本自己的硬上限比默认 3 分钟长时传进来(大陆 IP 白名单约 5 分钟),免得前端先放弃。
	function runLogged(starter, onDone, maxMs) {
		var LOGF = "merlinclash_log.txt";
		return snapLog(LOGF).then(function (pre) {
			return starter().then(function () { pollLog(LOGF, onDone, pre, maxMs); });
		});
	}
	function pollLog(file, onDone, pre, maxMs) {
		var stop = false, waited = 0, idle = 0, last = "";
		var hasPre = typeof pre === "string";
		var baseline = hasPre ? pre : null, baselineStale = hasPre;
		var cutBase = hasPre ? pre : null;   // 追加型脚本的「旧内容」前缀:只在它之后找标记
		var MAX = maxMs > 0 ? maxMs : 180000;   // 默认 3 分钟兜底:标记万一没出现也要收尾,不能空转到天荒地老
		var IDLE_MAX = 45000;  // 快照之后 45 秒日志一个字没变 = 任务没跑起来(或者不写这个日志)
		function finish(ok) { stop = true; onDone && onDone(last, ok); }
		(function tick() {
			if (stop) return;
			fetch(nonce("/_temp/" + file), { cache: "no-store" })
				.then(readText)      // 2026-09-23(A-X3):401 等非 2xx 不当成日志内容
				.then(function (t) {
					if (baseline === null) {       // 兼容路径:没有快照,首轮当基线
						baseline = t; baselineStale = markIn(t);
						if (baselineStale) cutBase = t;
					}
					if (baselineStale && t === baseline) {
						log("等待任务启动 …");
						waited += 700; idle += 700;
						if (hasPre && idle >= IDLE_MAX) {
							log("日志 " + (IDLE_MAX / 1000) + " 秒没有任何变化 —— 任务可能没有执行。请到「日志记录」看看,或稍后刷新页面。");
							return finish(false);
						}
						if (waited >= MAX) return finish(false);
						return void setTimeout(tick, 700);
					}
					baselineStale = false;    // 内容变了 = 新任务开写,恢复正常判定
					// 追加型脚本(不清日志、直接往后写):只看快照之后新增的部分
					var body = (cutBase && t.length > cutBase.length && t.indexOf(cutBase) === 0)
						? t.slice(cutBase.length) : t;
					var done = false, clean = body;
					DONE_MARKS.forEach(function (m) {
						if (clean.indexOf(m) >= 0) { done = true; clean = clean.split(m).join(""); }
					});
					last = clean.replace(/\s+$/, "");
					log(last);
					if (done) return finish(true);
					waited += 700;
					if (waited >= MAX) return finish(false);
					setTimeout(tick, 700);
				})
				.catch(function (e) {
					if (e && e.status) log((last ? last + "\n\n" : "") + "⚠️ 读日志失败:" + e.message + "\n任务可能还在后台跑,继续重试 …");
					waited += 1200; if (waited < MAX) setTimeout(tick, 1200); else finish(false);
				});
		})();
	}

	function esc(s) {
		return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
			return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
		});
	}

	/* ---------------- 开关部件 ---------------- */
	function setToggle(node, on) { if (node) node.classList.toggle("is-on", !!on); }
	function isOn(node) { return node && node.classList.contains("is-on"); }

	/* ---------------- 状态 ---------------- */
	// ⚠️ 上游存启动时间时漏了引号:
	//       a_tmp=$(echo_date2)                       # 【2026年08月25日 12:07:29】
	//       dbus set merlinclash_binary_startime=$a_tmp
	//   没引号 → shell 按空格分词 → dbus 只收到第一段,时分秒那半截丢了。
	//   真 koolshare 上也一样,是上游的 bug。我们不改后端,这里做显示层兜底:
	//   把包裹用的【】去掉,拿到什么显示什么,至少日期是准的。
	function fmtStart(v) {
		if (!v) return "—";
		return String(v).replace(/[【】]/g, "").trim() || "—";
	}

	function paintStatus() {
		var enable  = db.merlinclash_enable === "1";
		// ⚠️ 用 mc2_status.sh 写的 mc2_pid / mc2_ready,**不是** merlinclash_pid ——
		//    那个键根本不存在(我一开始想当然假设的)。上游没有任何机器可读的
		//    进程状态接口:clash_status.sh 只写 chnroute_num,
		//    clash_proc_status.sh 输出的是给弹窗看的人类可读文本。
		//    结果是内核明明跑着,状态条却一直说「内核未就绪」(2026-08-25 踩到)。
		var pid     = db.merlinclash_mc2_pid || "";
		var running = enable && db.merlinclash_mc2_ready === "1";

		el.dot.className = "mc2-dot " + (running ? "is-on" : (enable ? "" : "is-off"));
		el.state.textContent = running
			? ("运行中" + (parseInt(db.merlinclash_mc2_chains, 10) > 0 ? "" : "(未接管流量)"))
			: (enable ? (pid ? "内核已启动,端口未就绪" : "已启用,内核未运行") : "已停止");
		el.core.textContent = coreText();
		refreshCoreVer(running ? pid : "");

		el.pid.textContent = pid || "未运行";
		el.up.textContent  = fmtStart(db.merlinclash_binary_startime);
		el.cfg.textContent = db.merlinclash_set_yamlsel_start || "—";
		el.ver.textContent = db.merlinclash_version || "—";

		setToggle(el.toggle, enable);
		// ⚠️ busy 期间(启停/重启正在跑)必须保持禁用。
		//    以前这里无条件 false —— 3 秒一次的状态轮询会在操作途中把开关和
		//    「重启」变回可点,用户点了却被 busy 静默吃掉,看着像界面卡死。
		//    2026-09-23 起短保存进行中(saving>0)也一并禁用,见 lockOps。
		lockOps();
		el.panel.disabled   = !running;
		fit();
	}

	// ★ 2026-09-23 审计修复 mc2ui-24:内核版本以「运行中的内核自报」为准。
	//   merlinclash_core_version 是 install.sh 装机时写的快照,merlinclash_binary_ver 只在 apply_mc 时刷新;
	//   用户点「在线更新 alpha 内核」只重启内核,两个键都不动(09-11 就被旧版本号带偏过一次)。
	//   内核在跑时直接问 mihomo 的 GET /version(按 PID 缓存,换了进程才再问);问不到(没跑 / 端口不通 /
	//   https 页面混合内容被拦)才退回 dbus 记录值,并明确标成「记录值」。
	//   以前的兜底 merlinclash_version 是**插件**版本,放在内核版本的位置上是错的,去掉。
	var coreVer = { pid: "", ver: "", pending: false, failPid: "", fails: 0 };
	function coreText() {
		if (coreVer.ver && coreVer.pid && coreVer.pid === (db.merlinclash_mc2_pid || "")) return coreVer.ver;
		var rec = db.merlinclash_binary_ver || db.merlinclash_core_version || "";
		return rec ? rec + "(记录值)" : "—";
	}
	function refreshCoreVer(pid) {
		if (!pid || coreVer.pending || coreVer.pid === pid) return;
		if (coreVer.failPid === pid && coreVer.fails >= 3) return;   // 同一个进程连问 3 次都不通就别再问了
		coreVer.pending = true;
		mihomoApi("/version").then(function (j) {
			coreVer.pending = false;
			if (!j || !j.version) throw new Error("no version");
			coreVer.pid = pid;
			coreVer.ver = (j.meta ? "Mihomo " : "") + j.version;
			el.core.textContent = coreText();
		}).catch(function () {
			coreVer.pending = false;
			if (coreVer.failPid !== pid) { coreVer.failPid = pid; coreVer.fails = 0; }
			coreVer.fails++;
		});
	}

	// 直接问内核自己的 RESTful API(external-controller:端口默认 9990,密码 = 管理面板密码)。
	// mihomo 默认 CORS 放行任意来源,浏览器可以直连;credentials 显式 omit —— 带凭据的跨源请求
	// 要求对方回 Allow-Credentials,mihomo 不回,会被浏览器拦掉。3 秒超时,问不到就当拿不到。
	function mihomoApi(path) {
		var port = db.merlinclash_dashboard_port || "9990";
		var url = location.protocol + "//" + location.hostname + ":" + port + path;
		var secs = [db.merlinclash_set_dashboard_password || "clash"];
		if (secs[0] !== "clash") secs.push("clash");   // 刚改了面板密码还没重启内核时,运行中的仍是旧值
		function one(i) {
			var ctl = window.AbortController ? new AbortController() : null;
			var tm = ctl ? setTimeout(function () { ctl.abort(); }, 3000) : null;
			var init = { cache: "no-store", credentials: "omit", headers: { Authorization: "Bearer " + secs[i] } };
			if (ctl) init.signal = ctl.signal;
			return fetch(url, init).then(function (r) {
				clearTimeout(tm);
				if (r.status === 401 && i + 1 < secs.length) return one(i + 1);
				if (!r.ok) throw new Error("HTTP " + r.status);
				return r.json();
			}, function (e) { clearTimeout(tm); throw e; });
		}
		return one(0);
	}

	// ★ 2026-09-23 审计修复 mc2ui-19:force=true(首次加载 / 恢复备份后)才全量回填并清空草稿标记;
	//   平时只重绘状态条、服务端表格、即存控件,以及**没有草稿**的表单组 ——
	//   启停几十秒里去别的 tab 改的开关、A tab 改了没存又去 B tab 保存,都不会再被悄悄还原。
	function loadStatus(force) {
		// 先让后端把运行态刷进 dbus,再按前缀整批读回来
		return post("mc2_status.sh", [])
			.then(function () { return getJSON("/_api/merlinclash_"); })
			.then(function (j) {
				db = (j && j.result && j.result[0]) || {};
				if (force) dirty = {};
				paintStatus();
				if (!dirty.sub) paintSub();
				if (!dirty.dns) paintDns();
				paintRule();
				paintAclTable();
				paintNok();
				if (!dirty.adv) paintAdv();
				paintExtra();
				fillYamlList();
				// 简易/专业互斥显示已并进 paintRule(见那里的注释)
			})
			.catch(function (e) {
				el.state.textContent = "读取状态失败";
				el.core.textContent = e.message;
			});
	}

	// 可选配置文件列表。
	// ★ 2026-09-23 审计修复 mc2ui-29:列表来自 /tmp/upload/yamls.txt(软链到 yaml_bak/yamls.txt,
	//   由订阅 / 上传 / 恢复 / clash_getbasicyaml.sh 维护,上游旧页面读的也是它)。
	//   以前从 dbus 的 merlinclash_yamlname* 键收集 —— 上游没有任何脚本写这种键,下拉里永远只有
	//   当前那一个,「切换配置」这个功能实际不存在。
	//   拿不到就至少把「当前正在用的那个」放进去,别给个空下拉框。
	var yamlNames = [];
	function parseYamls(t) {
		return String(t || "").split(/\r?\n/).map(function (s) { return s.trim(); }).filter(function (s) {
			// 隐藏文件、以及 V93sslinksguard 旧版放在 yaml_bak 第一层的 sslinks_*_latest 备份
			// (它也是 .yaml,会被 find 列进来,选中它内核必起不来)一律不算配置
			return s && s.charAt(0) !== "." && !/^sslinks_.*_latest$/.test(s);
		});
	}
	function refreshYamlList() {
		function read() {
			return fetch(nonce("/_temp/yamls.txt"), { cache: "no-store" })
				.then(readText).then(parseYamls);      // 2026-09-23(A-X3):401 的错误 JSON 别当成配置名
		}
		return read().then(function (names) {
			if (names.length) return names;
			// 重启后 /tmp/upload 里的软链没了:让 clash_getbasicyaml.sh 重建一次再读
			return post("clash_getbasicyaml.sh", []).then(read);
		}).then(function (names) {
			yamlNames = names;
			fillYamlList();
		}).catch(function () {});
	}
	function fillYamlList() {
		// 用户正在下拉里选的时候别重绘,否则列表会在手底下跳掉
		if (document.activeElement === el.yaml) return;
		var cur = db.merlinclash_set_yamlsel_start || "";
		var names = yamlNames.slice();
		if (cur && names.indexOf(cur) < 0) names.unshift(cur);
		el.yaml.innerHTML = names.map(function (n) {
			return '<option value="' + esc(n) + '"' + (n === cur ? " selected" : "") + ">" + esc(n) + "</option>";
		}).join("");
	}

	// 长任务结束后的统一收尾:内核状态和节点组可能都变了,规则 tab 的下拉标记为过期;
	// 用户此刻正停在规则 tab 上就当场重拉(mc2ui-05)。
	function afterCoreChange() {
		aclStale = true;
		var cur = document.querySelector('.mc2-tab.is-active');
		if (cur && cur.getAttribute("data-tab") === "rule") loadAclOptions();
	}

	function toggleMC() {
		if (longGuard()) return;
		busy = true;
		lockOps();
		var next = isOn(el.toggle) ? "0" : "1";
		log(next === "1" ? "正在启动 Magic Catling …\n" : "正在停止 …\n");

		// 启停要几十秒(检查配置、起内核、建 30+ 条 iptables 链)。
		// 期间每 3 秒刷一次状态条,让「内核起来了没、接管了没」实时可见 ——
		// 只在最后刷一次的话,这几十秒里页面看着像卡住了。
		var ticking = setInterval(function () { refreshStatusOnly(); }, 3000);
		var stopTick = function () { clearInterval(ticking); };

		// 总开关本身就是 dbus 里的 merlinclash_enable,写进去再触发 start。
		// ★ 2026-09-23(mc2ui-15 纵深防御):开启时顺带把 watchdog_sw 钉成 0 —— 本机没有 perp,
		//   它若被(旧备份恢复等途径)写成 1,startClashNormalOrPerp 会去 perpctl,内核起不来。
		var f = next === "1" ? { merlinclash_enable: "1", merlinclash_set_watchdog_sw: "0" } : { merlinclash_enable: "0" };
		runLogged(function () { return post("clash_config.sh", ["start"], f); }, function () {
			stopTick(); busy = false; loadStatus().then(afterCoreChange);
		}).catch(function (e) {
			stopTick(); log("出错:" + e.message); busy = false; lockOps();
		});
	}

	// 重启 = 停内核→清规则→按当前配置全量重启。
	// 改完 DNS/订阅/规则后要它生效,或者代理行为不对想"重来一遍",点这个最省事。
	// ★ 2026-09-23 审计修复 ksapid-12 / mc2ui-03:走 clash_config.sh 的 **start 分支 + enable=1**
	//   (和上游旧页面「重启&保存」、clash_restart_update.sh 一致),不再走 restart 分支。
	//   restart 分支是给 clash_subscribe / selfupdate 这些**内部**调用准备的:不清日志、不回
	//   http_response、不加锁、成功时不写 BBABBBBC —— POST 挂到脚本结束(最长 30 秒),pollLog 要么
	//   空等 3 分钟,要么被残留的旧标记提前判完成,再点一次就是两个 apply_mc 无锁并发。
	//   start 分支在 enable=1 时同样是全量 apply_mc,并且先清日志、立刻回包、set_lock、结束写标记。
	//   重启按钮只在 enable=1 时可点,带上 enable=1 不改变语义。
	function restartMC() {
		if (longGuard()) return;
		if (!confirm("重启 Magic Catling?约需半分钟,期间代理会短暂中断。")) return;
		busy = true;
		lockOps();
		log("正在重启 Magic Catling …\n");
		var ticking = setInterval(function () { refreshStatusOnly(); }, 3000);
		runLogged(function () {
			return post("clash_config.sh", ["start"], { merlinclash_enable: "1", merlinclash_set_watchdog_sw: "0" });
		}, function () {
			clearInterval(ticking); busy = false; loadStatus().then(afterCoreChange);
		}).catch(function (e) {
			clearInterval(ticking); log("重启失败:" + e.message);
			busy = false; lockOps();
		});
	}

	// 只刷状态条,不重绘整个表单 —— 启停轮询时用。
	// 用 loadStatus() 会把订阅框、开关这些一起重绘,用户正在看的内容会跳。
	function refreshStatusOnly() {
		// ★ 2026-09-02:标签页不可见时不轮询。这一步后端要跑 mc2_status.sh + 读 199 个 dbus 键,
		//   页面开着不看时也每 3 秒打一次纯属白烧路由器 CPU(审计实测一次 2.35s,占一颗核 78%)。
		if (document.hidden) return Promise.resolve();
		return post("mc2_status.sh", [])
			.then(function () { return getJSON("/_api/merlinclash_"); })
			.then(function (j) {
				var d = (j && j.result && j.result[0]) || {};
				Object.keys(d).forEach(function (k) { db[k] = d[k]; });
				paintStatus();
			})
			.catch(function () {});
	}

	/* ---------------- 订阅 ---------------- */
	// ★ 2026-09-23 审计修复 mc2ui-13:删掉「节点重命名」这个假开关。它绑的 merlinclash_sub_rename
	//   在上游是**订阅生成的配置文件名**(AP_ + Online = AP_Online,旧页面标注「配置文件名称」),
	//   不是布尔开关;上游也没有「按地区归类统一命名」这个功能。以前一点保存就把 Online 改写成 0/1。
	var SUB_TOGGLES = [
		["subEmoji",  "merlinclash_sub_emoji"],
		["subUdp",    "merlinclash_sub_udp"],
		["subScv",    "merlinclash_sub_scv"],
		["subTfo",    "merlinclash_sub_tfo"]
	];

	// ★ 2026-09-23 审计修复 mc2ui-12:订阅链接的编码必须和上游一致 —— 上游存 Base64.encode(原文)
	//   (UTF-8 base64,不套 encodeURIComponent),后端 decode_url_link 只做 base64 解码。
	//   以前用 ACL 那套 b64e(= btoa(encodeURIComponent)),后端解出来是 https%3A%2F%2F…,
	//   旧页面「订阅」直接失败。多条链接上游用「|」分隔,textarea 里一行一条,存的时候合并。
	var subOrig = "";      // 回填时的原文;没改就不回写这个键,顺带不去碰它的编码
	// ★ 2026-09-23(mc2ui-12 复审):dbus 里现存的是旧版新界面的双重编码值时置 true。
	//   只把它「显示对」不够 —— 旧版页面的「订阅」照样解出 https%3A%2F%2F… 而失败。
	//   这时 subOrig 置成哨兵,保存必回写;页面打开时还会自动改正一次(fixLegacySub)。
	var subLegacy = false;
	var SUB_LEGACY = "\u0000legacy";
	function subEnc(v) { return btoa(unescape(encodeURIComponent(v))); }
	function subDec(v, info) {
		if (!v || !String(v).trim()) return "";
		var s;
		try { s = decodeURIComponent(escape(atob(v))); } catch (e) { return ""; }
		// 兼容旧版新界面存过的双重编码值:整串是 %XX 形式时,多解一层
		if (/^[a-z]+%3A%2F%2F/i.test(s)) {
			try { s = decodeURIComponent(s); if (info) info.legacy = true; } catch (e2) {}
		}
		return s.split("|").map(function (x) { return x.trim(); }).join("\n");
	}
	// 按上游格式(UTF-8 base64,多条用「|」合并)编码 textarea 里的内容
	function subLinksField() {
		var links = el.subLinks.value.split(/\r?\n/).map(function (x) { return x.trim(); })
			.filter(Boolean).join("|");
		return links ? subEnc(links) : "";
	}
	// 打开页面时把双重编码值改回上游格式:内容不变(解码后原样重编码),只修编码,
	// 省掉「用户得先碰一下输入框再保存」这一步。有草稿 / 有任务在跑时不动,留给手动保存(哨兵保证会回写)。
	function fixLegacySub() {
		if (!subLegacy || dirty.sub || busy || saving > 0) return;
		var v = subLinksField();
		if (!v) return;
		saving++; lockOps();
		post("dummy_script.sh", [], { merlinclash_sub_links: v }).then(function () {
			saving--; lockOps();
			db.merlinclash_sub_links = v;
			subLegacy = false;
			subOrig = el.subLinks.value;
			log("已把订阅链接改回上游编码格式(旧版新界面曾存成双重编码,旧版页面「订阅」会因此失败;链接内容没变)。");
		}).catch(function () { saving--; lockOps(); });
	}

	function paintSub() {
		// ⚠️ dbus 里存的是 base64(上游 UI 也是这么存的),显示前必须解码 ——
		//    直接塞进 textarea 用户看到的是一坨密文,改也改不对(2026-08-25 踩到)。
		var info = {};
		el.subLinks.value = subDec(db.merlinclash_sub_links || "", info);
		subLegacy = !!info.legacy;
		subOrig = subLegacy ? SUB_LEGACY : el.subLinks.value;
		SUB_TOGGLES.forEach(function (p) { setToggle(el[p[0]], db[p[1]] === "1"); });

		// 周期是秒数。dbus 里可能是我们没列出的值(用户在旧版页面填过别的),
		// 那样直接赋值会选不中、下拉框显示空白 —— 看着像"没读到配置"。
		// 补一个当前值的选项进去,如实显示。
		var cyc = db.merlinclash_sub_updatecycle || "0";
		if (!el.subCycle.querySelector('option[value="' + cyc + '"]')) {
			var o = document.createElement("option");
			o.value = cyc;
			var h = Math.round(parseInt(cyc, 10) / 3600);
			o.textContent = isFinite(h) && h > 0 ? "每 " + h + " 小时(自定义)" : cyc;
			el.subCycle.appendChild(o);
		}
		el.subCycle.value = cyc;
	}

	function collectSub() {
		var f = { merlinclash_sub_updatecycle: el.subCycle.value };
		// 存回 dbus 要重新编码,和上游格式保持一致(见 subEnc)。没改过就不带这个键
		// (现存值是旧双重编码时 subOrig 是哨兵,一定回写)。
		if (el.subLinks.value !== subOrig) f.merlinclash_sub_links = subLinksField();
		SUB_TOGGLES.forEach(function (p) { f[p[1]] = isOn(el[p[0]]) ? "1" : "0"; });
		return f;
	}

	function saveSub() {
		if (shortGuard()) return;
		saving++; lockOps();
		log("保存订阅设置 …\n");
		// dummy_script.sh 是上游用来「只写 dbus、不执行动作」的空脚本
		post("dummy_script.sh", [], collectSub())
			.then(function () {
				saving--; dirty.sub = false; lockOps();
				log("已保存。这些参数在「订阅」新配置时使用(旧版 Magic Catling 页面的「订阅」按钮);" +
					"对「更新当前配置」和已有配置的定时更新无效 —— 那两者按配置自己记录的地址和周期走。");
				loadStatus();
			})
			.catch(function (e) { saving--; lockOps(); log("保存失败:" + e.message); });
	}

	// ★ 2026-09-23 审计修复 mc2ui-09:按钮改为「更新当前配置」,如实对接上游的 update 分支。
	//   update → run_update 只做一件事:按 merlinclash_set_yamlsel_edit 找 yaml_bak/<名>.dlinks,
	//   从里面记录的地址重新下载这份配置;它**不读**输入框里的链接、节点处理开关和更新周期。
	//   以前这里要求先填链接、把整张表单写进 dbus,却从不写 yamlsel_edit(只有旧页面写)——
	//   edit 为空就报「订阅字典文件丢失」,edit 残留旧值就拉错配置。现在显式把 edit 指到当前配置。
	//   当前配置正在运行(enable=1)时,上游会在更新成功后自动重启内核 —— 先说清楚。
	function updateSub() {
		if (longGuard()) return;
		var cur = db.merlinclash_set_yamlsel_start || "";
		if (!cur) { log("还没有当前配置,没法更新。"); return; }
		if (!confirm("按「" + cur + "」记录的原地址(yaml_bak/" + cur + ".dlinks)重新拉取这份配置?" +
			(db.merlinclash_enable === "1" ? "\n\n更新成功后会自动重启内核,代理会短暂中断。" : "") +
			"\n下载或格式校验失败时,上游会删掉这份配置的 provider 缓存目录(装了 V93sslinksguard 的机器 5 分钟内自动种回)。")) return;
		busy = true;
		lockOps();
		log("正在按原地址重新拉取「" + cur + "」,远端慢时需要等一会 …\n");
		runLogged(function () {
			return post("clash_subscribe.sh", ["update"], { merlinclash_set_yamlsel_edit: cur });
		}, function () {
			busy = false; refreshYamlList(); loadStatus().then(afterCoreChange);
		}).catch(function (e) { busy = false; lockOps(); log("更新失败:" + e.message); });
	}

	// ★ 2026-09-23 审计修复 mc2ui-33:补回上游的文件名校验,并按后端的真实能力规范化。
	//   后端 clash_subscribe.sh 只会处理「字母数字_- + 单个点 + 小写 .yaml」:cp 没加引号(空格必挂)、
	//   find -name "*.yaml" 区分大小写(.yml / .YAML 找不到)、配置名取第一个点之前(多个点会登记错名)。
	//   .yml / 大写扩展名统一改成 xxx.yaml 再上传(multipart 的 filename 决定落盘名),其它非法名直接拦下。
	function uploadYaml(file) {
		if (longGuard()) return;
		var m = /^([A-Za-z0-9_-]{1,32})\.ya?ml$/i.exec(file.name);
		if (!m) {
			log("文件名只能是 字母 / 数字 / 下划线 / 横杠 + .yaml(不能有空格、中文或多个点,最长 32 个字符),当前是:" + file.name);
			return;
		}
		var fname = m[1] + ".yaml";
		if (yamlNames.indexOf(m[1]) >= 0 || m[1] === db.merlinclash_set_yamlsel_start) {
			// ★ 2026-09-23(mc2ui-33 复审):同名上传的风险不止「覆盖」—— 文件格式校验不过时,上游
			//   yaml_prepare 的失败分支会 rm -rf yaml_bak/<名>/(clash_subscribe.sh 失败分支),
			//   连这份配置的 provider 缓存(SSLINK 节点)一起删掉。和「更新当前配置」的确认框说法一致。
			if (!confirm("已有同名配置「" + m[1] + "」,上传会覆盖它(yaml_bak 第②层 + yaml_use),继续?" +
				"\n\n注意:文件格式校验不过时,上游会删掉这份配置的 provider 缓存目录 yaml_bak/" + m[1] + "/" +
				"(装了 V93sslinksguard 的机器 5 分钟内自动种回)。")) return;
		}
		busy = true;
		lockOps();
		log("上传 " + fname + " (" + (file.size / 1024).toFixed(1) + " KB) …\n");
		var fd = new FormData();
		fd.append("file", file, fname);
		runLogged(function () {
			return fetch("/_upload", { method: "POST", body: fd })
				.then(readJSON, netErr)          // 2026-09-23(A-X3):401 / 413 / 507 等说清楚原因
				.then(function (j) {
					if (!j || j.result !== "ok") throw new Error("上传失败:" + JSON.stringify(j));
					return post("clash_subscribe.sh", ["upload"], { merlinclash_sub_upload_filename: fname });
				});
		}, function () { busy = false; refreshYamlList(); loadStatus(); })
			.catch(function (e) { log("出错:" + e.message); busy = false; lockOps(); });
	}

	/* ---------------- DNS 设置(二期)---------------- */
	function segVal(seg) {
		var a = seg.querySelector(".mc2-seg__opt.is-active");
		return a ? a.getAttribute("data-val") : "";
	}
	function segSet(seg, val) {
		Array.prototype.forEach.call(seg.querySelectorAll(".mc2-seg__opt"), function (o) {
			o.classList.toggle("is-active", o.getAttribute("data-val") === val);
		});
	}
	function bindSeg(seg, onChange) {
		seg.addEventListener("click", function (ev) {
			var b = ev.target.closest(".mc2-seg__opt");
			if (!b) return;
			segSet(seg, b.getAttribute("data-val"));
			onChange && onChange(b.getAttribute("data-val"));
		});
	}

	function paintDns() {
		segSet(el.dnsType, db.merlinclash_dns_type === "fi" ? "fi" : "rh");
		el.fakeipRow.style.display = db.merlinclash_dns_type === "fi" ? "" : "none";
		el.fakeipSrv.value = db.merlinclash_dns_fakeip_server || "";
		setToggle(el.dnsHijack,  db.merlinclash_dns_dnshijack_sw === "1");
		setToggle(el.dnsProxy,   db.merlinclash_dns_proxydns_sw === "1");
		setToggle(el.dnsClear,   db.merlinclash_dns_cleardns_sw === "1");
		setToggle(el.dnsSniffer, db.merlinclash_dns_sniffer_sw === "1");
	}

	function saveDns() {
		if (shortGuard()) return;
		saving++; lockOps();
		log("保存 DNS 设置 …\n");
		post("dummy_script.sh", [], {
			merlinclash_dns_type:          segVal(el.dnsType) || "rh",
			merlinclash_dns_fakeip_server: el.fakeipSrv.value.trim() || "223.5.5.5",
			merlinclash_dns_dnshijack_sw:  isOn(el.dnsHijack)  ? "1" : "0",
			merlinclash_dns_proxydns_sw:   isOn(el.dnsProxy)   ? "1" : "0",
			merlinclash_dns_cleardns_sw:   isOn(el.dnsClear)   ? "1" : "0",
			merlinclash_dns_sniffer_sw:    isOn(el.dnsSniffer) ? "1" : "0"
		}).then(function () {
			saving--; dirty.dns = false; lockOps();
			log("已保存。重启内核后生效 —— DNS 属于全网解析路径,建议在没人用网的时候重启。");
			loadStatus();
		}).catch(function (e) { saving--; lockOps(); log("保存失败:" + e.message); });
	}

	/* ---------------- 自定规则(二期)---------------- */
	function paintRule() {
		setToggle(el.chnroute, db.merlinclash_set_chnroute_sw === "1");
		var plan = db.merlinclash_acl_plan === "pro" ? "pro" : "easy";
		segSet(el.aclPlan, plan);
		// 简易/专业互斥显示,跟随当前模式。
		// ★ 2026-09-23 审计修复 mc2ui-20(复审):这段原来只在 loadStatus 末尾。长任务中切规则模式,
		//   saveKV 拒绝后 repaintInstant → paintRule 只把分段控件改回去,下面的表格 / 专业按钮
		//   还停在切换后的样子(分段显示「简易」,露出的却是专业按钮)。放进 paintRule 两处都对。
		el.aclEasy.style.display = plan === "easy" ? "" : "none";
		el.aclProBtn.style.display = plan === "pro" ? "" : "none";
		fit();
	}

	/* ---------------- 内联编辑器 ----------------
	 * 复刻上游 common_text_editor 的协议:
	 *   读:POST clash_getbasicyaml.sh(把配置段软链到 /tmp/upload/*.txt)
	 *       → GET /_temp/<文件>。handler 会等脚本调 http_response(脚本最后一行)或跑完才回包,
	 *       所以 POST 返回时软链已经建好;读到空串基本就是文件真的为空 / 不存在
	 *       (强制绕行、强制转发、自定义规则没写过时就是这样)。只留一次短重试兜底。
	 *       (2026-09-23 更正:旧注释说 handler 是异步起脚本、要重试两次,那是早期版本的行为。)
	 *   存:内容 → encodeURIComponent → Base64 → 按 5000 字符分片写进
	 *       merlinclash_yamledit_content_<N>(dbus 单键有长度上限,这是上游的
	 *       既定协议,别改)→ POST clash_yamlfilechange.sh 按 tag 落盘。
	 */
	var EDITS = {
		dns_rh:    { title: "Redir-Host 配置",  tag: "redirhost", file: "clash_redirhost.txt",        hint: "YAML 片段,缩进即语法" },
		dns_fi:    { title: "Fake-IP 配置",     tag: "fakeip",    file: "clash_fakeip.txt",           hint: "YAML 片段,缩进即语法" },
		hosts:     { title: "自定义 Hosts",     tag: "hosts",     file: "clash_hosts.txt",            hint: "YAML 片段" },
		sniffer:   { title: "Sniffer 配置",     tag: "sniffer",   file: "clash_sniffercontent.txt",   hint: "YAML 片段" },
		acl:       { title: "自定义规则",       tag: "acl",       file: "clash_rule.txt",             hint: "Clash rules 语法,一行一条" },
		ipt_black: { title: "强制绕行规则",     tag: "iptblack",  file: "clash_ipsetproxyarround.txt", hint: "IP / 域名,一行一条,不能有中文", noCN: true },
		ipt_white: { title: "强制转发规则",     tag: "iptwhite",  file: "clash_ipsetproxy.txt",       hint: "IP / 域名,一行一条,不能有中文", noCN: true }
	};
	var editCur = null;
	// ★ 读取是否成功。没读到就绝不允许保存 —— 否则 textarea 里那句占位符
	//   「读取中…」会被当成配置内容写进去,把用户原有的规则全冲掉。
	var editLoaded = false;
	// ★ 2026-09-23 审计修复 mc2ui-18:每次打开编辑器发一个序号,读取链的每个回调先核对序号,
	//   不是最新一次打开发起的就直接丢弃。以前快速切段时,前一段晚到的读取结果会写进新打开
	//   那一段的编辑框(标题已是新段、editLoaded 也是 true),保存就写进了错误的配置文件。
	var editSeq = 0;

	function editorOpen(key, anchorBtn) {
		var cfg = EDITS[key];
		if (!cfg) return;
		var seq = ++editSeq;
		editCur = key;
		editLoaded = false;                 // 每次打开都重置,不能沿用上一次的成功状态
		el.editorTitle.textContent = cfg.title;
		el.editorHint.textContent = cfg.hint;
		el.editorText.value = "读取中…";
		el.editorText.readOnly = true;      // 读到之前不许输入 —— 晚到的内容会冲掉刚打的字
		// 把编辑器搬到触发按钮所在卡片的后面展开 —— 编辑哪段,编辑器就出现在哪段下面
		var card = anchorBtn.closest(".kslite-card");
		card.parentNode.insertBefore(el.editor, card.nextSibling);
		el.editor.classList.add("is-open");
		fit();

		function fail(msg) {
			if (seq !== editSeq) return;
			// ⚠️ 必须明确告知并禁用保存。
			//    以前这里什么都不做,textarea 一直显示「读取中…」,
			//    看着只是慢 —— 用户点保存就把这五个字写进配置文件了。
			editLoaded = false;
			el.editorText.value = "";
			el.editorHint.textContent = msg + " 已禁用保存以免覆盖原有内容 —— 请关闭后重试。";
		}
		post("clash_getbasicyaml.sh", []).then(function () {
			if (seq !== editSeq) return;
			var tries = 0;
			(function read() {
				if (seq !== editSeq) return;
				tries++;
				fetch(nonce("/_temp/" + cfg.file), { cache: "no-store" })
					.then(readText)       // 2026-09-23(A-X3):401 等非 2xx 不能当文件内容填进来(保存就覆盖了)
					.then(function (t) {
						if (seq !== editSeq) return;          // 已经切到别的段 / 关掉了:丢弃
						if (!t && tries < 2) return void setTimeout(read, 600);
						el.editorText.value = t || "";
						el.editorText.readOnly = false;
						editLoaded = true;   // 真读到了(空内容也算),这时才允许保存
						fit();
					})
					.catch(function (e) {
						if (seq !== editSeq) return;
						if (e && e.status) return fail("读取失败:" + e.message);   // ksapid 明确拒绝,重试也一样
						if (tries < 3) return void setTimeout(read, 1200);
						fail("读取失败(后端没响应)。");
					});
			})();
		}).catch(function (e) { fail("读取失败:" + e.message + "。"); });
	}

	function editorClose() {
		editSeq++;                          // 作废还没回来的读取
		el.editorText.readOnly = false;
		el.editor.classList.remove("is-open");
		editCur = null;
		fit();
	}

	function editorSave() {
		var cfg = EDITS[editCur];
		if (!cfg) return;
		if (shortGuard()) return;
		if (saving > 0) { el.editorHint.textContent = "上一次保存还没完成,稍等再点。"; return; }
		// ★ 没成功读到原内容就不许保存。否则会拿占位符/空白覆盖掉真实配置。
		if (!editLoaded) {
			el.editorHint.textContent =
				"还没读到原内容,不能保存 —— 直接写入会覆盖掉现有配置。请关闭后重试。";
			return;
		}
		var content = el.editorText.value;
		if (cfg.noCN && /[一-龥]/.test(content)) {
			el.editorHint.textContent = "内容里有中文 —— iptables 规则不接受,请检查后再保存。";
			return;
		}
		saving++; lockOps();
		var fields = { merlinclash_yamledit_tag: cfg.tag };
		if (content !== "") {
			// btoa 只吃 Latin-1,先 encodeURIComponent 把多字节转成 %XX 纯 ASCII(上游同款)
			var s = btoa(encodeURIComponent(content)), n = 5000, i = 0;
			for (; i < s.length / n; i++) fields["merlinclash_yamledit_content_" + i] = s.slice(n * i, n * (i + 1));
			fields.merlinclash_yamledit_content_count = i;
		} else {
			fields.merlinclash_yamledit_content_0 = " ";
			fields.merlinclash_yamledit_content_count = 1;
		}
		log("保存「" + cfg.title + "」…\n");
		post("clash_yamlfilechange.sh", [], fields)
			.then(function () {
				saving--; lockOps();
				editorClose();
				log("已保存。重启内核后生效。");
			})
			.catch(function (e) { saving--; lockOps(); el.editorHint.textContent = "保存失败:" + e.message; });
	}

	/* ---------------- ACL 规则表格(三期,简易模式)----------------
	 * 存储:merlinclash_acl_{type,content,lianjie}_<N>,值 = Base64(encodeURIComponent(v))。
	 * clash_saveacls.sh save 遍历 dbus 里还在的编号 → 重写 rule_custom/<配置>_custom_rule.yaml,
	 * 下次 apply_mc 的 check_rule 再按文件顺序重新编号写回 dbus,前端不用维护连续编号。
	 * 「删除」= 该行三键置空 + save。
	 * ⚠️ 2026-09-23 更正(审计 mc2ui-01 / kscore-01):「置空」能删掉,靠的是 /_api/ 的约定 ——
	 *    fields 里值为空串的键 = dbus remove(koolshare 原版语义,由 ksapid 兼容层实现)。
	 *    dbus CLI 本身 `set k=` 会**留下**空键,get_list 照样列出它,save_yaml 就往规则文件里
	 *    写一行「,,」→ 下次启动插入「,,,」规则、内核解析失败、MC2 自己关掉。
	 *    所以别绕过 /_api/ 去直接 dbus set 空值来删规则。
	 * 类型/节点组下拉来自内核导出(clash_getproxygroup.sh → /_temp/proxytype.txt
	 * + proxygroups.txt)—— 内核没起过就没有,这时说清楚而不是给空下拉。
	 */
	function b64e(v) { return btoa(encodeURIComponent(v)); }
	// ★ 2026-09-23 审计修复 mc2ui-25:表格显示专用的解码。每次 apply_mc,后端 push_dbus 会用
	//   urlencode(空格 → +)+ URL-safe base64(+ → -、/ → _、去掉 =)重写全部 acl 键,
	//   标准 atob 碰到 - / _ 就抛异常(显示原始 base64),+ 也还原不成空格(「Microsoft+Edge」)。
	//   前端 b64e 用 encodeURIComponent,字面的 + 会被编成 %2B,所以解出来的 + 只可能来自空格。
	function aclB64d(v) {
		if (!v) return "";
		try {
			var s = String(v).replace(/-/g, "+").replace(/_/g, "/");
			while (s.length % 4) s += "=";
			return decodeURIComponent(atob(s).replace(/\+/g, " "));
		} catch (e) { return String(v); }
	}

	function aclRows() {
		var rows = [];
		Object.keys(db).forEach(function (k) {
			var m = k.match(/^merlinclash_acl_type_(\d+)$/);
			if (m && db[k]) rows.push(parseInt(m[1], 10));
		});
		return rows.sort(function (a, b) { return a - b; });
	}

	function paintAclTable() {
		var rows = aclRows();
		el.aclRows.innerHTML = rows.length ? rows.map(function (n) {
			return '<tr>' +
				'<td class="mc2-table__mono">' + esc(aclB64d(db["merlinclash_acl_type_" + n])) + '</td>' +
				'<td class="mc2-table__mono">' + esc(aclB64d(db["merlinclash_acl_content_" + n])) + '</td>' +
				'<td>' + esc(aclB64d(db["merlinclash_acl_lianjie_" + n])) + '</td>' +
				'<td><button type="button" class="mc2-x" data-acldel="' + n + '" title="删除">×</button></td>' +
			'</tr>';
		}).join("") : '<tr class="is-empty"><td colspan="4">还没有规则 —— 用下面一行添加</td></tr>';
		fit();
	}

	// ★ 2026-09-23 审计修复 mc2ui-05:内核没跑时后端导出的是占位文案「请启动插件」。以前把它当正常
	//   选项填进下拉、「加」照样能点 —— 能存下一条「请启动插件,xxx,请启动插件」,下次启动内核解析
	//   失败、MC2 自己关掉;而且懒加载只看下拉是不是空的,占位符也算一项,启动内核后回来也不再拉,
	//   只能整页刷新。现在:占位符 → 两个下拉和「加」一律禁用;aclStale 决定进 tab 时要不要重拉。
	// ★ 2026-09-23 审计修复 mc2ui-39:出口下拉补上 fallback / url-test / load-balance 组。
	//   clash_getproxygroup.sh 只 grep "Selector"(上游脚本,不改),香港故障切换、美国故障切换、
	//   苹果服务这些「钉死出口」用的组都选不到。这里再直接问一次内核的 GET /group(全部代理组),
	//   合并进来;问不到就只用脚本导出的那份,并在提示里说明。
	function aclLock(msg) {
		el.aclType.innerHTML = el.aclGroup.innerHTML = '<option value="">(内核未运行)</option>';
		el.aclType.disabled = el.aclGroup.disabled = el.aclAdd.disabled = true;
		el.aclNote.textContent = msg;
		fit();
	}
	function fillAclSelects(types, groups) {
		// 重新填充时保留用户已经选好的项(还在列表里的话)
		var pt = el.aclType.value, pg = el.aclGroup.value;
		el.aclType.innerHTML = types.map(function (t) { return "<option>" + esc(t) + "</option>"; }).join("");
		el.aclGroup.innerHTML = groups.map(function (g) { return "<option>" + esc(g) + "</option>"; }).join("");
		if (pt && types.indexOf(pt) >= 0) el.aclType.value = pt;
		if (pg && groups.indexOf(pg) >= 0) el.aclGroup.value = pg;
		el.aclType.disabled = el.aclGroup.disabled = el.aclAdd.disabled = false;
		fit();
	}
	function mihomoGroupNames() {
		return mihomoApi("/group").then(function (j) {
			var p = (j && j.proxies) || [];
			var list = Array.isArray(p) ? p : Object.keys(p).map(function (k) { return p[k]; });
			var order = [], names = [];
			list.forEach(function (g) {
				if (!g || !g.name) return;
				// GLOBAL 的成员表按配置文件顺序排列(代理在前、组在后),拿它给组排序,和配置里看到的一致
				if (g.name === "GLOBAL") { order = g.all || []; return; }
				names.push(g.name);
			});
			return names.sort(function (a, b) {
				var ia = order.indexOf(a), ib = order.indexOf(b);
				if (ia < 0) ia = 1e9;
				if (ib < 0) ib = 1e9;
				return ia - ib || (a < b ? -1 : a > b ? 1 : 0);
			});
		});
	}
	function mergeGroups(txt, api) {
		if (!api.length) return txt;
		var out = [];
		function add(n) { if (n && out.indexOf(n) < 0) out.push(n); }
		add("DIRECT"); add("REJECT");
		api.forEach(add);
		txt.forEach(add);          // 脚本导出里有、内核没报的(不该发生)也别丢
		return out;
	}

	function loadAclOptions() {
		aclStale = false;          // 本次开始拉取;拿不到 / 占位符时再置回 true
		// 触发内核导出,再读两个下拉的数据
		return post("clash_getproxygroup.sh", []).then(function () {
			var tries = 0;
			(function read() {
				tries++;
				Promise.all([
					fetch(nonce("/_temp/proxytype.txt"), { cache: "no-store" }).then(readText),
					fetch(nonce("/_temp/proxygroups.txt"), { cache: "no-store" }).then(readText)
				]).catch(function (e) {
					// ⚠️ 以前这里没有 catch:fetch 一 reject,整条链静默断掉,
					//    两个下拉框和提示语全是空的,页面上没有任何线索。
					// 2026-09-23(A-X3):ksapid 明确拒绝(401 等)就直接说原因,重试也一样
					if (e && e.status) { aclStale = true; el.aclNote.textContent = "读取类型 / 节点组失败:" + e.message; return null; }
					if (tries < 3) { setTimeout(read, 900); return null; }
					aclStale = true;
					el.aclNote.textContent =
						"读取类型 / 节点组失败(后端没响应)。稍后切回本页会自动重试。";
					return null;
				}).then(function (rs) {
					if (!rs) return;          // 上面已处理(重试中或已报错)
					var types = rs[0].split("\n").map(function (x) { return x.trim(); }).filter(Boolean);
					var groups = rs[1].split("\n").map(function (x) { return x.trim(); }).filter(Boolean);
					if (!types.length && tries < 3) return void setTimeout(read, 900);
					if (!types.length) {
						aclStale = true;
						aclLock("类型 / 节点组列表拿不到 —— 内核至少要成功启动过一次,列表才会生成。");
						return;
					}
					// 内核没跑时后端导出的是占位文案「请启动插件」:绝不能当成选项(见函数头注释)
					if (/请启动/.test(types[0]) || /请启动/.test(groups[0] || "")) {
						aclStale = true;
						aclLock("内核没在运行,类型和出口列表拿不到 —— 先打开总开关启动 Magic Catling,完成后这里会自动刷新。");
						return;
					}
					return mihomoGroupNames().catch(function () { return []; }).then(function (extra) {
						fillAclSelects(types, mergeGroups(groups, extra));
						el.aclNote.textContent = extra.length ? "" :
							"出口下拉只含 select 类型的组 —— 没能直连内核(9990 端口)取到 fallback / url-test 组,需要的话用专业模式手写。";
					});
				});
			})();
		}).catch(function (e) {
			aclStale = true;
			el.aclNote.textContent = "读取类型 / 节点组失败:" + e.message;
		});
	}

	function aclAdd() {
		if (shortGuard()) return;
		if (saving > 0) { log("上一条还在保存,稍等再加。"); return; }
		var t = el.aclType.value, c = el.aclContent.value.trim(), g = el.aclGroup.value;
		// ★ mc2ui-05:占位符 / 列表失效时绝不提交(存下去下次启动内核必挂)
		if (el.aclAdd.disabled || /请启动/.test(t + g)) {
			log("内核没在运行,类型 / 出口列表无效 —— 先启动 Magic Catling 再加规则。");
			return;
		}
		if (!t || !c || !g) { log("类型、内容、出口都要填。"); return; }
		var n = (aclRows().pop() || 0) + 1, f = {};
		f["merlinclash_acl_type_" + n] = b64e(t);
		f["merlinclash_acl_content_" + n] = b64e(c);
		f["merlinclash_acl_lianjie_" + n] = b64e(g);
		saving++; lockOps();
		post("clash_saveacls.sh", ["save"], f).then(function () {
			saving--; lockOps(); el.aclContent.value = "";
			// 先在本地记上,免得 loadStatus 回来之前再点「加」算出同一个编号、把这条覆盖掉
			Object.keys(f).forEach(function (k) { db[k] = f[k]; });
			paintAclTable();
			log("规则已添加,重启内核后生效。");
			loadStatus();
		}).catch(function (e) { saving--; lockOps(); log("添加失败:" + e.message); });
	}

	function aclDel(n) {
		if (shortGuard()) return;
		if (saving > 0) { log("上一条还在保存,稍等再删。"); return; }
		var f = {};
		// 值为空串 = 删键(/_api/ 的约定,见本节头注释)
		["type", "content", "lianjie"].forEach(function (p) { f["merlinclash_acl_" + p + "_" + n] = ""; });
		saving++; lockOps();
		post("clash_saveacls.sh", ["save"], f).then(function () {
			saving--; lockOps();
			Object.keys(f).forEach(function (k) { delete db[k]; });
			paintAclTable();
			log("规则已删除,重启内核后生效。");
			loadStatus();
		}).catch(function (e) { saving--; lockOps(); log("删除失败:" + e.message); });
	}

	/* ---------------- 访问控制(三期,设备绕行)----------------
	 * 键:merlinclash_nokpacl_{name,ip,mac,port,mode}_<N>,**明文**(与 ACL 不同,
	 * 上游就是这么存的);method 是全局匹配方法。都走 dummy_script.sh 直写 dbus。
	 */
	function nokRows() {
		var rows = [];
		Object.keys(db).forEach(function (k) {
			var m = k.match(/^merlinclash_nokpacl_ip_(\d+)$/);
			if (m && db[k]) rows.push(parseInt(m[1], 10));
		});
		return rows.sort(function (a, b) { return a - b; });
	}

	// ★ 2026-09-23 审计修复 mc2ui-08:匹配方法的取值是 **1 / 2 / 3**(1=IP+MAC、2=仅 IP、3=仅 MAC),
	//   和后端 get_method_name / load_nat、上游旧页面、defaults.conf(method=1)一致。
	//   以前页面按 0 / 1 / 2 编号,整体错一位:线上的 1 显示成「仅 IP」,点「仅 MAC」存的是 2
	//   (后端按仅 IP 处理),「仅 MAC」永远选不到。空值和旧页面存下的 0 在后端的实际行为
	//   等同 1(三个分支都不命中,IP、MAC 两套集合都建),所以按「IP + MAC」显示,如实。
	function nokMethodVal() {
		var nm = db.merlinclash_nokpacl_method;
		return (nm === "2" || nm === "3") ? nm : "1";
	}

	function paintNok() {
		segSet(el.nokMethod, nokMethodVal());
		var rows = nokRows();
		el.nokRows.innerHTML = rows.length ? rows.map(function (n) {
			var mode = db["merlinclash_nokpacl_mode_" + n] === "1" ? "强制走代理" : "不走代理";
			var port = db["merlinclash_nokpacl_port_" + n] || "all";
			return '<tr>' +
				'<td>' + esc(db["merlinclash_nokpacl_name_" + n]) + '</td>' +
				'<td class="mc2-table__mono">' + esc(db["merlinclash_nokpacl_ip_" + n]) + '</td>' +
				'<td class="mc2-table__mono">' + esc((db["merlinclash_nokpacl_mac_" + n] || "").trim()) + '</td>' +
				'<td class="mc2-table__mono">' + esc(port === "all" ? "全部" : port) + '</td>' +
				'<td>' + mode + '</td>' +
				'<td><button type="button" class="mc2-x" data-nokdel="' + n + '" title="删除">×</button></td>' +
			'</tr>';
		}).join("") : '<tr class="is-empty"><td colspan="6">名单为空 —— 用下面一行添加设备</td></tr>';
		fit();
	}

	// ★ 2026-09-23 审计修复 mc2ui-21:IP / MAC 做格式校验。后端把它们拼进 ipset 文件再
	//   `ipset -! restore 2>/dev/null`:一行语法错,整个集合(刚 flush 过)一条都加载不进去,
	//   错误输出还被丢掉 —— 名单里的设备全部静默失效。
	function nokAdd() {
		if (saving > 0) { log("上一条还在保存,稍等再加。"); return; }
		var ip = el.nokIp.value.trim(), name = el.nokName.value.trim();
		if (!ip || !name) { log("别名和 IP 都要填。"); return; }
		var m = ip.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?:\/(\d{1,2}))?$/);
		if (!m || [m[1], m[2], m[3], m[4]].some(function (o) { return +o > 255; }) ||
			(m[5] !== undefined && (+m[5] < 1 || +m[5] > 32))) {
			log("IP 格式不对:只收 IPv4 或 IPv4/掩码(1-32),如 192.168.0.20 或 192.168.0.0/24。");
			return;
		}
		var mac = el.nokMac.value.trim().replace(/-/g, ":").toLowerCase();
		if (mac && !/^([0-9a-f]{2}:){5}[0-9a-f]{2}$/.test(mac)) {
			log("MAC 格式不对:形如 aa:bb:cc:dd:ee:ff(横杠分隔也行),或者留空。");
			return;
		}
		var n = (nokRows().pop() || 0) + 1, f = {};
		f["merlinclash_nokpacl_name_" + n] = name;
		f["merlinclash_nokpacl_ip_" + n] = ip;
		f["merlinclash_nokpacl_mac_" + n] = mac || " ";
		f["merlinclash_nokpacl_port_" + n] = el.nokPort.value;
		f["merlinclash_nokpacl_mode_" + n] = el.nokMode.value;
		saveKV(f).then(function (ok) {
			if (!ok) return;           // 被拒 / 失败:输入框留着,改了再点
			el.nokIp.value = ""; el.nokName.value = ""; el.nokMac.value = "";
			paintNok();                // saveKV 已把 f 记进本地 db:先画出来,也防连点撞编号
			log("已加入名单,重启内核后生效。");
			loadStatus();
		});
	}

	function nokDel(n) {
		if (saving > 0) { log("上一条还在保存,稍等再删。"); return; }
		var f = {};
		// 值为空串 = 删键(/_api/ 的约定)
		["name", "ip", "mac", "port", "mode"].forEach(function (p) { f["merlinclash_nokpacl_" + p + "_" + n] = ""; });
		saveKV(f).then(function (ok) {
			if (!ok) return;
			paintNok();
			log("已移出名单,重启内核后生效。");
			loadStatus();
		});
	}

	/* ---------------- 高级设置(三期)---------------- */
	function paintAdv() {
		// watchdog 恒显示关且禁点:上游靠 koolshare 的 perp 守护,本机没有。
		// install.sh 已强制 watchdog_sw=0 —— 这里如实显示、不给打开的机会,
		// 开了内核压根起不来(startClashNormalOrPerp 会去 perpctl)。
		setToggle(el.advWatchdog, false);
		// ★ 2026-09-23 审计修复 mc2ui-31:「队列请求」(queue_sw)和「启动日志重试」开关(logcheck_sw)
		//   在当前架构里没有任何代码读 —— 前者只影响旧版页面自己的请求排队,后者上游脚本根本不看
		//   (start_clash 无条件用 logcheck_val,<20 按 40)。两个开关从页面上拿掉,dbus 键保持原值不动。
		setToggle(el.advDelaySw, db.merlinclash_set_startdelay_sw === "1");
		el.advDelayVal.value = db.merlinclash_set_startdelay_val || "120";
		el.advLogVal.value = db.merlinclash_set_logcheck_val || "40";

		setToggle(el.advTcp, db.merlinclash_set_tcpcon_sw === "1");
		setToggle(el.advMix, db.merlinclash_set_mixport_sw === "1");
		setToggle(el.advIntSw, db.merlinclash_set_interval_sw === "1");
		el.advIntVal.value = db.merlinclash_set_interval_val || "300";
		setToggle(el.advTolSw, db.merlinclash_set_tolerance_sw === "1");
		el.advTolVal.value = db.merlinclash_set_tolerance_val || "100";
		el.advDashPw.value = db.merlinclash_set_dashboard_password || "";

		segSet(el.advTproxy, db.merlinclash_ipt_tproxy_type || "udp");
		setToggle(el.advCloseProxy, db.merlinclash_ipt_closeproxy_sw === "1");
		setToggle(el.advIot, db.merlinclash_ipt_proxyiot_sw === "1");
		setToggle(el.advSelf, db.merlinclash_ipt_proxyrouter_sw === "1");
		// 路由标记值是只读展示(见 asp 里的注释):真正生效的是 clash_config.sh
		// 硬编码的 mcrm="256",dbus 里那个 routingmark_val 是没人读的死键。
		// 这里不回填 dbus 值 —— 回填 255 会和实际生效的 256 对不上,更误导。
	}

	// 数字框:只收整数,范围外 / 非数字一律回落默认值。上游脚本拿它直接做算术和 sleep,
	// 「abc」「30次」这种值会让 start_clash 的重试循环算错、MC2 自己关掉。
	function intIn(v, lo, hi, def) {
		v = String(v || "").trim();
		if (!/^\d+$/.test(v)) return def;
		var n = parseInt(v, 10);
		return (n >= lo && n <= hi) ? String(n) : def;
	}

	function saveAdv() {
		if (shortGuard()) return;
		var tp = segVal(el.advTproxy) || "udp";
		// ★ 2026-09-23 审计修复 mc2ui-38:面板密码补回上游的「只收字母数字」,改动时提醒同步。
		//   它会被原样拼进 yq 表达式(.secret = "…"),含引号 / 反斜杠时 yq 失败、secret 实际没改,
		//   日志却说改了;而 aiboard 上的 netlog 采集等外部调用方默认用 clash,改了会静默 401。
		var pw = el.advDashPw.value.trim() || "clash";
		if (!/^[A-Za-z0-9]{1,32}$/.test(pw)) { log("面板密码只能是字母和数字(最长 32 位)。"); return; }
		// ★ 2026-09-23(跨包通报 I-X2):提示语按 netlog 的真实症状写。采集器读容器环境变量 MIHOMO_SECRET
		//   (默认 clash),不会自己跟着变;没同步时 NetWatch 实时页顶上出现红色「采集停摆」告警卡。
		//   路由器侧 V92longrun / V99bootcheck / unban_fix.sh 都从 dbus 读密码,会自动跟上。
		var pwChanged = pw !== (db.merlinclash_set_dashboard_password || "clash");
		if (pwChanged &&
			!confirm("面板密码要改成「" + pw + "」?重启内核后生效。\n\n" +
				"必须手动同步:aiboard 上 netlog 采集容器的 MIHOMO_SECRET(默认 clash;重建 netlog 容器时加 " +
				"-e MIHOMO_SECRET=" + pw + ")。不同步的话,NetWatch 实时页会出现红色「采集停摆 · 采集器连不上 mihomo:" +
				"HTTP Error 401」告警卡,连接记录停止更新。\n\n" +
				"路由器上的 V92longrun / V99bootcheck / unban_fix.sh 从 dbus 读密码,会自动跟上;" +
				"Mac 上的 tools/sslinks-refresh.sh 旧版写死 Bearer clash,用之前确认它已改成读 dbus。")) return;
		var logVal = intIn(el.advLogVal.value, 20, 999, "40");
		var delayVal = intIn(el.advDelayVal.value, 0, 600, "120");
		// 上游在切非 closed 模式时弹的那个警告,内容是真的 —— TPROXY 与网络神盾冲突
		saving++; lockOps();
		log("保存高级设置 …\n");
		post("dummy_script.sh", [], {
			merlinclash_set_startdelay_sw: isOn(el.advDelaySw) ? "1" : "0",
			merlinclash_set_startdelay_val: delayVal,
			merlinclash_set_logcheck_val:  logVal,
			merlinclash_set_tcpcon_sw:     isOn(el.advTcp) ? "1" : "0",
			merlinclash_set_mixport_sw:    isOn(el.advMix) ? "1" : "0",
			merlinclash_set_interval_sw:   isOn(el.advIntSw) ? "1" : "0",
			merlinclash_set_interval_val:  el.advIntVal.value,
			merlinclash_set_tolerance_sw:  isOn(el.advTolSw) ? "1" : "0",
			merlinclash_set_tolerance_val: el.advTolVal.value,
			merlinclash_set_dashboard_password: pw,
			merlinclash_ipt_tproxy_type:   tp,
			merlinclash_ipt_closeproxy_sw: isOn(el.advCloseProxy) ? "1" : "0",
			merlinclash_ipt_proxyiot_sw:   isOn(el.advIot) ? "1" : "0",
			merlinclash_ipt_proxyrouter_sw: isOn(el.advSelf) ? "1" : "0",
			merlinclash_set_watchdog_sw:   "0"      // 恒 0,见 paintAdv 的注释
		}).then(function () {
			saving--; dirty.adv = false; lockOps();
			log("已保存。重启内核后生效。" + (tp !== "closed" ? "\n提醒:TPROXY 模式与 AiProtection 网络神盾冲突,确认它是关闭的。" : "") +
				(pwChanged ? "\n提醒:面板密码改了 —— 记得同步 aiboard netlog 容器的 MIHOMO_SECRET(重建 netlog 容器时加 -e MIHOMO_SECRET=…)。" : ""));
			loadStatus();
		}).catch(function (e) { saving--; lockOps(); log("保存失败:" + e.message); });
	}

	/* ---------------- 附加功能(四期)---------------- */
	function nowStamp() {
		var d = new Date(), p = function (n) { return (n < 10 ? "0" : "") + n; };
		return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()) +
			" " + p(d.getHours()) + ":" + p(d.getMinutes());
	}
	// ★ 2026-09-23(mc2ui-30):「上次更新」优先取日志里**路由器自己**的时间戳
	//   (echo_date 写的【2026年09月23日 14:00:00】),取不到才用浏览器时间。
	function stampFrom(t) {
		var m, last = null, re = /【(\d{4})年(\d{2})月(\d{2})日\s+(\d{2}):(\d{2})/g;
		while ((m = re.exec(t || ""))) last = m;
		return last ? (last[1] + "-" + last[2] + "-" + last[3] + " " + last[4] + ":" + last[5]) : nowStamp();
	}

	// ★ 2026-09-23 审计修复 mc2ui-14:「每隔」只能从上游认的 11 个值里选(2~30 按分钟,1/3/6/12 按小时)。
	//   以前是自由输入框、单位写死「分钟」:填 60 这类值,apply_mc 先删旧任务、却一条新任务都不建
	//   (页面照样说已保存);填 6 以为是 6 分钟,实际每 6 小时。
	var RST_EVERY = ["2", "5", "10", "15", "20", "25", "30", "1", "3", "6", "12"];
	function setRstEvery(v) {
		Array.prototype.forEach.call(el.rstEvery.querySelectorAll("option[data-bad]"), function (o) { o.remove(); });
		if (RST_EVERY.indexOf(v) < 0) {
			// dbus 里是旧页面 / 旧版本存下的无效值:如实显示,并提示重选(不偷偷改成别的值)
			var o = document.createElement("option");
			o.value = v; o.setAttribute("data-bad", "1");
			o.textContent = v + "(无效,请重选)";
			el.rstEvery.appendChild(o);
		}
		el.rstEvery.value = v;
	}

	function paintExtra() {
		el.geoDate.textContent = db.merlinclash_db_geo_updatetime ? "上次:" + db.merlinclash_db_geo_updatetime : "";
		el.chnDate.textContent = db.merlinclash_db_chnroute_updatetime ? "上次:" + db.merlinclash_db_chnroute_updatetime : "";
		if (!dirty.geo) {
			el.geoIp.value = db.merlinclash_set_geoip_type || "full";
			el.geoSite.value = db.merlinclash_set_geosite_type || "full";
		}
		// ★ 2026-09-23 审计修复 mc2ui-15:备份 / 恢复勾选回显 dbus 里存的值(以前写死全开)。
		//   键不存在按「开」,与 defaults.conf 一致。
		if (!dirty.bak) {
			Array.prototype.forEach.call(el.bakBoxes.querySelectorAll("[data-bak]"), function (b) {
				setToggle(b, db[b.getAttribute("data-bak")] !== "0");
			});
		}
		if (!dirty.rst) {
			el.rstMode.value = db.merlinclash_select_clash_restart || "1";
			setRstEvery(db.merlinclash_select_clash_restart_minute_2 || "30");
			el.rstDay.value = db.merlinclash_select_clash_restart_day || "1";
			el.rstWeek.value = db.merlinclash_select_clash_restart_week || "1";
			el.rstHour.value = db.merlinclash_select_clash_restart_hour || "4";
			el.rstMin.value = db.merlinclash_select_clash_restart_minute || "0";
			rstFieldsShow();
		}
	}

	// 按计划模式只露相关字段:「每隔」只要间隔,「每天」只要时:分……
	// 五种模式共用一排字段、全摆出来的话,一半输入框跟当前模式无关,填了也没用。
	function rstFieldsShow() {
		var m = el.rstMode.value;
		el.rstEvery.style.display = (m === "5" ? "" : "none");
		el.rstDay.style.display  = (m === "4" ? "" : "none");
		el.rstWeek.style.display = (m === "3" ? "" : "none");
		var timed = (m === "2" || m === "3" || m === "4");
		el.rstHour.style.display = el.rstMin.style.display = (timed ? "" : "none");
		el.rstHour.nextElementSibling.style.display = (timed ? "" : "none");   // 冒号
		fit();
	}

	// ★ 2026-09-23 审计修复 mc2ui-30:「上次更新」不再随请求预写。handler 先写 fields 再跑脚本,
	//   以前不管下载成没成功时间戳都先落了,下载失败也显示「已更新」;上游 core_download 失败时
	//   还会悄悄 dbus set …_type=lite,把用户选的 Full 降成 Lite。现在看日志判成败:成功才写时间,
	//   失败就明说,并把 Geo 类型改回用户的选择。
	function geoUpdate() {
		if (longGuard()) return;
		if (!confirm("更新 Geo 数据库?要下载十几 MB,机场慢时需要等。")) return;
		var wantIp = el.geoIp.value, wantSite = el.geoSite.value;
		busy = true;
		lockOps();
		dirty.geo = false;          // 表单值随这次请求写进 dbus
		log("正在更新 Geo 数据库 …\n");
		// ⚠️ params 必须是 ["5"] —— 脚本的分发是 `case $2 in 5)`,数字暗号,
		//    不是语义化的 "update"。传空/传错 → case 不匹配 → rc=0 空转退出,
		//    表面毫无异常:fields 照写、日志不动、Geo 文件纹丝不动
		//    (2026-08-25 踩到:用户点「设置并更新」只看到旧日志)。
		//    上游 push_data(script, action, ...) 的 action 就是这个数字。
		runLogged(function () {
			return post("clash_update_ipdb.sh", ["5"], {
				merlinclash_action: "update",
				merlinclash_set_geoip_type: wantIp,
				merlinclash_set_geosite_type: wantSite
			});
		}, function (t, finished) {
			// ★ 2026-09-23(mc2ui-30 复审):GeoIP 和 GeoSite 是先后两次独立下载,要按库分别判。
			//   以前日志里只要有一处「所有下载地址均失效」就整体报「更新失败、旧文件没动」、不写时间 ——
			//   GeoIP 已经换成新文件、只有 GeoSite 失败时,这句话是错的。上游失败时只把**失败那个库**的
			//   类型改成 lite,回写也只回写那一个。
			var v = geoVerdict(t);
			var fix = {}, lines = [];
			if (v.ip === "fail" && wantIp !== "lite") fix.merlinclash_set_geoip_type = wantIp;
			if (v.site === "fail" && wantSite !== "lite") fix.merlinclash_set_geosite_type = wantSite;
			if (v.ip === "ok" || v.site === "ok") fix.merlinclash_db_geo_updatetime = stampFrom(t);
			if (v.busy) lines.push("⚠️ 上游报「数据库升级已经在运行」,可能有另一次更新同时在跑。");
			[["GeoIP", v.ip, wantIp], ["GeoSite", v.site, wantSite]].forEach(function (p) {
				var st = p[1], tx;
				if (st === "ok") tx = "✅ 已更新(下次启动内核生效)";
				else if (st === "fail") tx = "❌ 下载失败或空间不足,旧文件没动" +
					(p[2] !== "lite" ? ";上游失败时会把它的类型悄悄改成 Lite,已按你的选择改回" : "");
				else if (st === "head") tx = "跟随基础配置,由内核启动时自己拉取,这次没有下载";
				else tx = finished ? "没有看到它的结果" : "还没看到结果(任务可能还在后台跑)";
				lines.push(p[0] + ":" + tx);
			});
			if (!finished) lines.unshift("⚠️ 没等到结束标记,任务可能还在后台跑 —— 稍后刷新页面看「上次」时间。");
			(Object.keys(fix).length ? post("dummy_script.sh", [], fix).catch(function () {}) : Promise.resolve())
				.then(function () {
					// 上游脚本会把软链覆盖成实体(大文件落回 jffs),更新完自动归位 ksdata
					return post("mc2_fixlink.sh", []).catch(function () {});
				})
				.then(function () {
					busy = false; lockOps();
					log(t + "\n\n" + lines.join("\n"));
					loadStatus();
				});
		}).catch(function (e) { busy = false; lockOps(); log("更新失败:" + e.message); });
	}
	// 按库解析 clash_update_ipdb.sh 的日志。上游每个库的输出是:
	//   「开始更新 GeoIP-Full ...」→「GeoIP-Full 更新成功！」
	//                             或「错误：GeoIP-Full 所有下载地址均失效！」/「错误：JFFS 空间不足！…」(不带库名,
	//                               归到最近一次「开始更新」的那个库)
	//   跟随基础配置:「GeoIP 已设为跟随基础配置…」/「GeoSite 已设为跟随基础配置…」
	// 返回 { ip, site }:"ok" | "fail" | "head" | ""(没看到),busy = 见到「已经在运行」。
	function geoVerdict(t) {
		var r = { ip: "", site: "", busy: false }, cur = "";
		function key(n) { return n === "GeoIP" ? "ip" : "site"; }
		String(t || "").split("\n").forEach(function (l) {
			var m;
			if (/已经在运行/.test(l)) { r.busy = true; return; }
			if ((m = /开始更新\s*(GeoIP|GeoSite)/.exec(l))) { cur = key(m[1]); return; }
			if ((m = /(GeoIP|GeoSite)\s*已设为跟随基础配置/.exec(l))) { r[key(m[1])] = "head"; return; }
			if ((m = /(GeoIP|GeoSite)\S*\s*更新成功/.exec(l))) { r[key(m[1])] = "ok"; return; }
			if (/所有下载地址均失效|空间不足/.test(l)) {
				m = /(GeoIP|GeoSite)/.exec(l);
				var k = m ? key(m[1]) : cur;
				if (k) r[k] = "fail";
			}
		});
		return r;
	}

	// ★ 2026-09-23 审计修复 mc2ui-34(约定 C6):改调 mc2_chnupdate.sh —— 它把更新交给 N98chnupdate 强制执行
	//   (APNIC∪17mon 并集 + 条数 / 抽查校验,通过后原子替换现网集合,并写回 res/china_ip_route.ipset)。
	//   以前调上游 clash_update_chnroute.sh 25:下 fernvenue 单一来源,并 rm 掉 N98 维护的并集文件,
	//   下次 apply 时被单源数据整份替换(腾讯云 43.x 等受让段丢失),还可能让 N98 误判成杭州布局。
	// ★ 2026-09-23(复审):结论判定改成只认「本次」的输出,见 chnVerdict。脚本硬上限约 5 分钟,轮询给到 5.5 分钟。
	// ★ 2026-09-23 审计修复(跨包核对 D-X5,第二轮逐条核过):
	//   ① 轮询上限 CHN_MAX_MS = 330 秒 ≥ mc2_chnupdate.sh 的最坏用时:N98 force 看门狗 180 秒(超时 kill -9 后
	//      N98 立即返回)+ IPv6 下载 curl --max-time 120 秒 + N98 status 几秒 ≈ 305 秒。pollLog 的 waited 只按
	//      700ms/轮累加、不含每轮请求本身的耗时,实际等得只会更久。
	//   ② fields 一律为空 —— 点击时**不写** merlinclash_db_chnroute_updatetime。走 N98 时由它校验通过后
	//      自己写「<时间> N98并集」;只有退回上游脚本且判定成功时,chnDone 才补写路由器时间。
	//      (点击就写的话,失败了「上次」也会被刷新,掩盖失败。)
	//   ③ 运行中再点(另一个标签页 / 刷新过页面):mc2_chnupdate.sh 只追加一句「…正在进行,请等它结束」、
	//      不清日志、不写 BBABBBBC;结束标记由正在跑的那次写。pollLog 按快照只看新增部分,等到的就是那次的
	//      标记,chnVerdict 判 busy(本次未执行),chnDone 说明上面是那一次的输出。
	var CHN_MAX_MS = 330000;
	function chnUpdate() {
		if (longGuard()) return;
		if (!confirm("更新大陆 IP 白名单?\n由 N98chnupdate 拉 APNIC + 17mon 取并集,校验通过后原子替换,立即生效、不用重启内核。")) return;
		chnRun("mc2_chnupdate.sh", []);
	}
	function chnRun(script, params) {
		busy = true;
		lockOps();
		log("正在更新大陆 IP 白名单 …\n");
		runLogged(function () { return post(script, params, {}); }, chnDone, CHN_MAX_MS).catch(function (e) {
			busy = false; lockOps();
			if (script === "mc2_chnupdate.sh" && /no script/i.test(e.message)) return chnMissing();
			log("更新失败:" + e.message);
		});
	}
	// mc2_chnupdate.sh 不在(它只随 migration 单独部署;MC2 卸载 / 重装会 rm scripts/mc2_*.sh 把它删掉):
	// · 见过 N98 的更新记录(「上次」带「N98并集」)= 这台由 N98 维护并集 ⇒ 不退回上游,免得单源数据把并集顶掉;
	// · 没见过 = 多半是只装了 MC2 的机器 ⇒ 问一句后改用上游脚本(这正是 mc2_chnupdate.sh 没有 N98 时自己会做的事)。
	function chnMissing() {
		if (/N98/.test(db.merlinclash_db_chnroute_updatetime || "")) {
			log("后端脚本 mc2_chnupdate.sh 不在(MC2 卸载 / 重装会删掉 scripts/mc2_*.sh,需要重新部署)。\n" +
				"这台的大陆白名单由 N98chnupdate 维护 APNIC∪17mon 并集,为了不被上游的单一来源数据顶掉,这里不改用上游脚本;" +
				"部署回来之前 N98 仍会每周日 04:30 自动更新。");
			return;
		}
		if (!confirm("这台没有 mc2_chnupdate.sh,也没见过 N98chnupdate 的更新记录。\n" +
			"改用 MC2 上游脚本更新吗?它只下载 fernvenue 单一来源,重启内核后才生效。\n\n" +
			"如果这台其实装了 N98chnupdate(例如武汉主路由),请点「取消」,重新部署 mc2_chnupdate.sh —— " +
			"上游脚本会删掉 N98 的并集文件。")) { log("已取消。请部署 mc2_chnupdate.sh 后再点「更新」。"); return; }
		chnRun("clash_update_chnroute.sh", ["25"]);
	}
	// 从本次日志里判结论。只看「当前状态:」那一行之前的内容 —— mc2_chnupdate.sh 最后会跑 `N98 status`,
	// 它打印 update.log 的最后 8 行,是**历史**记录(每行带「YYYY-MM-DD HH:MM:SS 」前缀),
	// 里面一条旧的 [FAIL] 不能算成这次失败;带这种前缀的行在别处出现也一律排除。
	//   IPv4(N98 的 stdout 行不带日期前缀):
	//     busy — 「已有一次大陆 IP 白名单更新正在进行」(mc2_chnupdate 自己的锁)/ 「[SKIP] 已有一次…」(N98 的锁:
	//            force 模式下 N98 唯一的 [SKIP] 就是它,**什么都没做**)/ 上游「…已经在运行」
	//     fail — [FAIL] 行 / 「❌ IPv4 更新失败」(看门狗 kill -9 时 [FAIL] 只进 update.log,靠这句)/ 上游【ipv4】下载失败
	//     ok   — [OK] 行 / 上游【ipv4】更新成功 / 已经是最新版本
	//   IPv6 单独判(借上游 core_update_chnroute,【ipv6】前缀),不影响 IPv4 结论。
	//   若脚本输出了约定的机读行 MC2_RESULT=OK|FAIL|BUSY(IPv4)/ MC2_RESULT6=OK|SAME|FAIL|SKIP,优先用它。
	//   n98 = 这次走的是 N98(它自己会写「上次」时间,前端不要再覆盖)。
	function chnVerdict(t) {
		t = String(t || "");
		var cut = t.search(/^[^\n]*当前状态[:：][ \t]*$/m);
		var main = (cut >= 0 ? t.slice(0, cut) : t).split("\n").filter(function (l) {
			return !/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} /.test(l);
		}).join("\n");
		var r = { main: main, v4: "", v6: "", n98: false, warn: /^\[WARN\]/m.test(main) };
		var m4 = /^MC2_RESULT=(OK|FAIL|BUSY)\b/m.exec(t), m6 = /^MC2_RESULT6=(OK|SAME|FAIL|SKIP)\b/m.exec(t);
		r.n98 = !!m4 || /N98chnupdate|^\[(OK|FAIL|SKIP|WARN)\]/m.test(main);
		// busyBy = "mc2":撞上 mc2_chnupdate.sh 自己的锁(另一个标签页 / 刷新前点的那次还在跑)——
		//   这时等到的结束标记和上面的输出都属于正在跑的那一次(D-X5 ③)
		r.busyBy = /已有一次大陆 IP 白名单更新正在进行/.test(main) ? "mc2" : "";
		if (/已有一次大陆 IP 白名单更新正在进行|大陆白名单规则更新已经在运行/.test(main)) r.v4 = "busy";
		else if (m4) r.v4 = m4[1].toLowerCase();
		else if (/^\[SKIP\][^\n]*已有一次/m.test(main)) r.v4 = "busy";
		else if (/^\[FAIL\]|❌ ?IPv4|❌[^\n]*无法更新|【ipv4】[^\n]*(下载失败|文件内容错误)/m.test(main)) r.v4 = "fail";
		else if (/^\[OK\]|【ipv4】[^\n]*(更新成功|已经是最新版本)/m.test(main)) r.v4 = "ok";
		if (m6) r.v6 = m6[1].toLowerCase();
		else if (/【ipv6】[^\n]*(下载失败|文件内容错误)/.test(main)) r.v6 = "fail";
		else if (/【ipv6】[^\n]*已经是最新版本/.test(main)) r.v6 = "same";
		else if (/【ipv6】[^\n]*更新成功/.test(main)) r.v6 = "ok";
		else if (/跳过 IPv6/.test(main)) r.v6 = "skip";
		return r;
	}
	function chnDone(t, finished) {
		var r = chnVerdict(t), lines = [];
		if (!finished) lines.push("⚠️ 没等到结束标记(任务可能还在后台跑),下面是目前能看到的结论;稍后刷新页面看「上次」时间,或到「日志记录」看详情。");
		var other = r.busyBy === "mc2";
		if (other) {
			// 去掉本次追加的那一句(和约定的 MC2_RESULT=BUSY,若有),剩下的就是正在跑的那一次的输出
			var o = chnVerdict(String(t || "").replace(/^[^\n]*已有一次大陆 IP 白名单更新正在进行[^\n]*\n?/m, "")
				.replace(/^MC2_RESULT=BUSY[^\n]*\n?/m, ""));
			lines.push("⚠️ 点的时候已有一次更新在跑,本次没有重复执行" +
				(finished ? ";已等到那一次结束,上面是它在你点击之后的输出。" : ";上面是它在你点击之后的输出。"));
			lines.push(o.v4 === "ok" ? "那一次 IPv4:✅ 已更新并立即生效(「上次」时间由它写)。"
				: o.v4 === "fail" ? "那一次 IPv4:❌ 更新失败,现网白名单和数据文件都没动(原因见上面的 [FAIL] 行)。"
				: o.v4 === "busy" ? "那一次 IPv4:也撞上了另一次更新 / 恢复,没有执行。"
				: "那一次的 IPv4 结论在你点击之前就已输出 —— 看「上次」时间,或到「日志记录」看全文。");
		}
		else if (r.v4 === "busy") lines.push("⚠️ IPv4:已有一次更新 / 恢复正在进行,本次没有重复执行 —— 等它结束后看「上次」时间。");
		else if (r.v4 === "fail") lines.push("❌ IPv4:更新失败,现网白名单和数据文件都没动(原因见上面的 [FAIL] / 下载失败 行)。");
		else if (r.v4 === "ok") lines.push(r.n98
			? "✅ IPv4:并集已更新并立即生效(不用重启内核)。" + (r.warn ? "但只拿到一个来源,见上面的 [WARN] 行。" : "")
			: "✅ IPv4:已按上游单一来源更新,重启内核后生效。");
		else if (finished) lines.push("⚠️ IPv4:没看到本次的结论行 —— 到「日志记录」看详情。");
		var v6 = other ? "IPv6(那一次):" : "IPv6:";
		if (r.v6 === "ok") lines.push(v6 + "已更新,重启内核后生效。");
		else if (r.v6 === "same") lines.push(v6 + "已是最新,无需替换。");
		else if (r.v6 === "fail") lines.push(v6 + "下载失败或文件内容不对,保持原样(不影响上面 IPv4 的结果)。");
		else if (r.v6 === "skip") lines.push(v6 + "这次跳过。");
		// 「上次」时间:走 N98 时它校验通过后自己写(「… N98并集」),前端不覆盖;只有上游路径才由前端补写
		var fix = (!r.n98 && r.v4 === "ok") ? { merlinclash_db_chnroute_updatetime: stampFrom(r.main) } : null;
		(fix ? post("dummy_script.sh", [], fix).catch(function () {}) : Promise.resolve())
			.then(function () {
				busy = false; lockOps();
				var shown = String(t || "").replace(/^MC2_RESULT6?=[^\n]*\n?/gm, "").replace(/\s+$/, "");
				log(shown + "\n\n" + lines.join("\n"));
				loadStatus();
			});
	}

	function bakFields() {
		var f = {};
		Array.prototype.forEach.call(el.bakBoxes.querySelectorAll("[data-bak]"), function (b) {
			f[b.getAttribute("data-bak")] = isOn(b) ? "1" : "0";
		});
		return f;
	}
	function bakPicked() {
		return Array.prototype.filter.call(el.bakBoxes.querySelectorAll("[data-bak]"), isOn)
			.map(function (b) { return b.getAttribute("aria-label"); });
	}

	// 备份分支先 `>` 清空日志、打完包才 http_response —— POST 返回时日志就是本次的结果。
	// 读它判成败:有「打包完成」= 成功;有 BBABBBBC = 失败(backup 分支只有失败路径写标记)。
	// 最多再等 60 秒,覆盖打包超过 handler 30 秒回包上限的情况。
	function waitBakLog() {
		return new Promise(function (resolve, reject) {
			var n = 0;
			function again(msg) {
				if (++n >= 60) return reject(new Error(msg || "等了 60 秒还没打完包"));
				setTimeout(tick, 1000);
			}
			function tick() {
				fetch(nonce("/_temp/merlinclash_log.txt"), { cache: "no-store" })
					.then(readText)
					.then(function (t) {
						var clean = t.split("BBABBBBC").join("").replace(/\s+$/, "");
						log(clean);
						if (t.indexOf("BBABBBBC") >= 0) {
							var e = new Error("见上方日志");
							e.logText = clean;
							return reject(e);
						}
						if (t.indexOf("打包完成") >= 0) return resolve(t);
						again();
					}, function (e) { again(e && e.status ? "读日志失败:" + e.message : "读日志失败"); });
			}
			tick();
		});
	}

	// ★ 2026-09-23 审计修复 ksapid-12 / mc2ui-07(与 A 包 ksapid-05 同一处):
	//   ① backup 分支成功时**不写** BBABBBBC,以前等 pollLog 的结束标记要空转 3 分钟 —— 改为读一次日志判成败;
	//   ② 以前用 <a href="/_temp/…"> 触发下载:锚点导航不经过 ks-shim(它只改道 XHR / fetch),请求落到
	//      80 端口的梅林 httpd,根本拿不到文件,界面却说「备份已生成」。现在用 fetch 取(经 shim 改道 8080),
	//      校验 gzip 文件头,再交给同源的 blob 链接下载;空包 / 取不到一律明说失败。
	//   ③ 一项都没勾就不发请求(以前会等 3 分钟,最后还提示「备份已生成」)。
	function bakDown() {
		if (longGuard()) return;
		var f = bakFields(), picked = bakPicked();
		if (!picked.length) { log("至少勾选一项再备份。"); return; }
		busy = true;
		lockOps();
		dirty.bak = false;          // 勾选随这次请求写进 dbus
		log("正在打包备份(" + picked.join("、") + ")…\n");
		var bakLog = "";
		post("clash_backup.sh", ["backup"], f)
			.then(waitBakLog)
			.then(function (t) {
				bakLog = t.replace(/\s+$/, "");
				return fetch(nonce("/_temp/mc_backup.tar.gz"), { cache: "no-store" });
			})
			.then(function (r) {
				// 2026-09-23(A-X3):非 2xx 带上 ksapid 的原因(401 未登录等)
				if (!r.ok) return readText(r).then(null, function (e) { throw new Error("取备份包失败:" + e.message); });
				return r.arrayBuffer();
			})
			.then(function (buf) {
				var b = new Uint8Array(buf);
				if (b.length < 20 || b[0] !== 0x1f || b[1] !== 0x8b) throw new Error("备份包为空或不是 gzip 格式,没有下载");
				var u = URL.createObjectURL(new Blob([buf], { type: "application/gzip" }));
				var a = document.createElement("a");
				a.href = u;
				a.download = "mc_backup_" + nowStamp().replace(/\D/g, "").replace(/^(\d{8})(\d{4})$/, "$1-$2") + ".tar.gz";
				document.body.appendChild(a); a.click(); document.body.removeChild(a);
				setTimeout(function () { URL.revokeObjectURL(u); }, 60000);
				busy = false;
				lockOps();
				log(bakLog + "\n\n备份已下载(" + (b.length < 1024 ? b.length + " 字节" : (b.length / 1024).toFixed(1) + " KB") +
					"):" + a.download);
			})
			.catch(function (e) {
				busy = false;
				lockOps();
				var lt = e.logText || bakLog;
				log((lt ? lt + "\n\n" : "") + "备份失败:" + e.message);
			});
	}

	// ★ 2026-09-23 审计修复 mc2ui-15:
	//   ① 恢复要带上页面上的勾选。以前 fields 是空的,脚本按 dbus 里**上次备份时**的勾选整体恢复,
	//      只想恢复 DNS 也会把设备名单、配置文件一起覆盖;
	//   ② 恢复流程会先 `clash_config.sh stop stop`(enable 置 0)且不再打开 —— 以前提示「需重启内核」,
	//      重启按钮却因 enable=0 是灰的。现在:恢复前开着的,恢复后自动按原状态重新启动;
	//   ③ 备份里的插件设置可能带回 watchdog_sw=1(koolshare 固件时代的备份):本机没有 perp,
	//      开着内核永远起不来。恢复后一律钉回 0。
	function bakRestore(file) {
		if (longGuard()) return;
		if (!/\.(tar\.gz|tgz|gz)$/i.test(file.name)) { log("备份文件应是 .tar.gz"); return; }
		var f = bakFields(), picked = bakPicked();
		if (!picked.length) { log("至少勾选一项再恢复。"); return; }
		var wasOn = db.merlinclash_enable === "1";
		if (!confirm("用「" + file.name + "」覆盖这些项目:" + picked.join("、") + "?\n\n恢复期间 Magic Catling 会先停止" +
			(wasOn ? ",完成后自动重新启动(代理会中断半分钟左右)。" : ";它现在是关着的,恢复后保持关闭。"))) return;
		busy = true;
		lockOps();
		dirty.bak = false;
		log("上传备份 " + file.name + " …\n");
		var fd = new FormData();
		fd.append("file", file, "mc_backup.tar.gz");   // 恢复脚本按固定名找文件
		function done() { busy = false; refreshYamlList(); loadStatus(true).then(afterCoreChange); }
		runLogged(function () {
			return fetch("/_upload", { method: "POST", body: fd })
				.then(readJSON, netErr)          // 2026-09-23(A-X3):401 / 413 / 507 等说清楚原因
				.then(function (j) {
					if (!j || j.result !== "ok") throw new Error("上传失败:" + JSON.stringify(j));
					return post("clash_backup.sh", ["restore"], f);
				});
		}, function (t) {
			var ok = /还原完成/.test(t);
			// 内核有没有被恢复流程停掉,以 dbus 里的 enable 为准(校验没过的路径在停内核之前就退出了)
			getJSON("/_api/merlinclash_enable").catch(function () { return null; }).then(function (j) {
				var en = j && j.result && j.result[0] ? j.result[0].merlinclash_enable : "";
				if (wasOn && en !== "1") {
					log(t + "\n\n" + (ok ? "恢复完成," : "恢复没有成功,") + "正在按原状态重新启动 Magic Catling …");
					return runLogged(function () {
						return post("clash_config.sh", ["start"], { merlinclash_enable: "1", merlinclash_set_watchdog_sw: "0" });
					}, function (t2) {
						// 启动会清空日志,恢复失败时把恢复日志一并留在面板上
						log((ok ? "" : t + "\n\n⚠️ 恢复没有成功(上面是恢复日志)。\n\n") + t2 + "\n\n" +
							(ok ? "恢复完成," : "") + "已按原状态重新启动 Magic Catling。");
						done();
					});
				}
				return post("dummy_script.sh", [], { merlinclash_set_watchdog_sw: "0" }).catch(function () {}).then(function () {
					log(t + "\n\n" + (ok ? "恢复完成。" + (wasOn ? "" : "Magic Catling 保持关闭,需要时打开总开关。")
						: "恢复没有成功,见上方日志。"));
					done();
				});
			}).catch(function (e) { busy = false; lockOps(); log("恢复后重新启动失败:" + e.message); loadStatus(true); });
		}).catch(function (e) { busy = false; lockOps(); log("恢复失败:" + e.message); });
	}

	function rstSave() {
		var mode = el.rstMode.value, every = el.rstEvery.value;
		if (mode === "5") {
			if (RST_EVERY.indexOf(every) < 0) { log("「每隔」的间隔无效,请从下拉里重新选一个。"); return; }
			if ((every === "2" || every === "5") &&
				!confirm("每 " + every + " 分钟完整重启一次内核(iptables、dnsmasq 一起重建),代理和 DNS 会频繁中断。确定?")) return;
		}
		saveKV({
			merlinclash_select_clash_restart: mode,
			merlinclash_select_clash_restart_minute_2: every || "30",
			merlinclash_select_clash_restart_day: el.rstDay.value,
			merlinclash_select_clash_restart_week: el.rstWeek.value,
			merlinclash_select_clash_restart_hour: el.rstHour.value,
			merlinclash_select_clash_restart_minute: el.rstMin.value
		}, "定时重启已保存,重启内核后 cron 生效。").then(function (ok) { if (ok) dirty.rst = false; });
	}

	/* ---------------- 日志 / 当前配置(四期)---------------- */
	function loadLogView() {
		var src = segVal(el.logSrc) || "op";
		var ready = src === "op"
			? Promise.resolve()
			// 内核日志在 /tmp/clash_run.log,handler 只serve /tmp/upload —— 上游做法:
			// 先让 clash_outputlog.sh 把它 cp 过来,再读
			: post("clash_outputlog.sh", []).then(function () {
				return new Promise(function (r) { setTimeout(r, 800); });
			});
		ready.then(function () {
			return fetch(nonce("/_temp/" + (src === "op" ? "merlinclash_log.txt" : "clash_run.log")), { cache: "no-store" });
		}).then(readText).then(function (t) {      // 2026-09-23(A-X3):401 等显示原因,不把错误 JSON 当日志
			t = t.replace(/BBABBBBC|XU6J03M6/g, "").replace(/\s+$/, "");
			el.logView.value = t || (src === "op" ? "还没有操作日志。" : "还没有内核日志 —— 内核至少要启动过一次。");
			el.logView.scrollTop = el.logView.scrollHeight;
			fit();
		}).catch(function (e) { el.logView.value = "读取失败:" + e.message; });
	}

	function loadConfView() {
		fetch(nonce("/_temp/view.txt"), { cache: "no-store" })
			.then(readText)
			.then(function (t) {
				el.confView.value = t || "还没有配置快照 —— 内核启动时才会生成(启动流程会把当前 yaml 拷一份出来)。";
				fit();
			})
			.catch(function (e) { el.confView.value = "读取失败:" + e.message; });
	}

	/* ---------------- Tab ---------------- */
	// 分期占位:全部面板已实装,留个空表以防回退
	var PENDING = {};

	function fillPending() {
		Object.keys(PENDING).forEach(function (k) {
			var p = document.querySelector('[data-panel="' + k + '"]');
			if (!p) return;
			var d = PENDING[k];
			p.innerHTML = '<div class="kslite-card"><div class="mc2-todo">' +
				"<strong>" + esc(d[0]) + "</strong> 正在重写,计划在<strong>" + esc(d[1]) + "</strong>完成。" +
				(d[2] ? "<br>" + esc(d[2]) : "") +
				'<br><br>这期间该功能请用旧版页面(菜单里的 <strong>Magic Catling</strong>)。' +
				"</div></div>";
		});
	}

	function bindTabs() {
		var tabs = document.querySelectorAll(".mc2-tab");
		Array.prototype.forEach.call(tabs, function (t) {
			t.addEventListener("click", function () {
				Array.prototype.forEach.call(tabs, function (x) { x.classList.remove("is-active"); });
				t.classList.add("is-active");
				var name = t.getAttribute("data-tab");
				Array.prototype.forEach.call(document.querySelectorAll(".mc2-panel"), function (p) {
					p.classList.toggle("is-active", p.getAttribute("data-panel") === name);
				});
				// 懒加载:进 tab 才拉数据,别每次开页面全量跑一遍。
				// 规则 tab 看 aclStale(mc2ui-05):以前只看「下拉是不是空的」,占位符也算一项,
				// 内核没跑时进来一次之后就再也不拉了。
				if (name === "rule" && el.aclType && (aclStale || !el.aclType.options.length)) loadAclOptions();
				if (name === "log" && el.logView && !el.logView.value) loadLogView();
				if (name === "conf" && el.confView && !el.confView.value) loadConfView();
				fit();
			});
		});
	}

	/* ---------------- 初始化 ---------------- */
	function init() {
		var ids = {
			dot: "mcDot", state: "mcState", core: "mcCore", toggle: "mcToggle",
			panel: "mcPanel", restart: "mcRestart", yaml: "mcYaml", pid: "mcPid", up: "mcUp",
			cfg: "mcCfg", ver: "mcVer", log: "mcLog",
			subLinks: "mcSubLinks", subCycle: "mcSubCycle",
			subEmoji: "mcSubEmoji", subUdp: "mcSubUdp",
			subScv: "mcSubScv", subTfo: "mcSubTfo",
			subUpdate: "mcSubUpdate", subSave: "mcSubSave",
			drop: "mcDrop", pick: "mcPick", file: "mcFile",
			dnsType: "mcDnsType", fakeipRow: "mcFakeipRow", fakeipSrv: "mcFakeipSrv",
			dnsHijack: "mcDnsHijack", dnsProxy: "mcDnsProxy", dnsClear: "mcDnsClear",
			dnsSniffer: "mcDnsSniffer", dnsSave: "mcDnsSave",
			chnroute: "mcChnroute", aclPlan: "mcAclPlan",
			editor: "mcEditor", editorTitle: "mcEditorTitle", editorText: "mcEditorText",
			editorHint: "mcEditorHint", editorSave: "mcEditorSave", editorCancel: "mcEditorCancel",
			aclEasy: "mcAclEasy", aclRows: "mcAclRows", aclType: "mcAclType",
			aclContent: "mcAclContent", aclGroup: "mcAclGroup", aclAdd: "mcAclAdd",
			aclNote: "mcAclNote", aclProBtn: "mcAclProBtn",
			nokMethod: "mcNokMethod", nokRows: "mcNokRows", nokName: "mcNokName",
			nokIp: "mcNokIp", nokMac: "mcNokMac", nokPort: "mcNokPort",
			nokMode: "mcNokMode", nokAdd: "mcNokAdd",
			advWatchdog: "mcAdvWatchdog",
			advDelaySw: "mcAdvDelaySw", advDelayVal: "mcAdvDelayVal",
			advLogVal: "mcAdvLogVal",
			advTcp: "mcAdvTcp", advMix: "mcAdvMix",
			advIntSw: "mcAdvIntSw", advIntVal: "mcAdvIntVal",
			advTolSw: "mcAdvTolSw", advTolVal: "mcAdvTolVal",
			advDashPw: "mcAdvDashPw", advTproxy: "mcAdvTproxy",
			advCloseProxy: "mcAdvCloseProxy", advIot: "mcAdvIot",
			advSelf: "mcAdvSelf", advMark: "mcAdvMark", advSave: "mcAdvSave",
			geoIp: "mcGeoIp", geoSite: "mcGeoSite", geoUpdate: "mcGeoUpdate", geoDate: "mcGeoDate",
			chnUpdate: "mcChnUpdate", chnDate: "mcChnDate",
			bakBoxes: "mcBakBoxes", bakDown: "mcBakDown", bakPick: "mcBakPick", bakFile: "mcBakFile",
			rstMode: "mcRstMode", rstEvery: "mcRstEvery",
			rstDay: "mcRstDay", rstWeek: "mcRstWeek", rstHour: "mcRstHour",
			rstMin: "mcRstMin", rstSave: "mcRstSave",
			logSrc: "mcLogSrc", logRefresh: "mcLogRefresh", logView: "mcLogView",
			confRefresh: "mcConfRefresh", confView: "mcConfView"
		};
		Object.keys(ids).forEach(function (k) { el[k] = document.getElementById(ids[k]); });
		if (!el.toggle) return;

		bindTabs();
		fillPending();

		el.toggle.addEventListener("click", toggleMC);
		el.restart.addEventListener("click", restartMC);
		el.subSave.addEventListener("click", saveSub);
		el.subUpdate.addEventListener("click", updateSub);
		SUB_TOGGLES.forEach(function (p) {
			el[p[0]].addEventListener("click", function () { this.classList.toggle("is-on"); });
		});

		// 管理面板在内核自己的端口上,**必须新标签打开**。
		// ⚠️ 不用 window.open():本页在 web wrapper 的 iframe 里,某些情况下
		//    它会被降级成「当前窗口导航」,整个路由器管理页被顶掉(ddnsgo 踩过)。
		el.panel.addEventListener("click", function () {
			var port = db.merlinclash_dashboard_port || "9990";
			// ⚠️ 不能指 :9990 根路径 —— 那是 mihomo 的 RESTful API,直接访问回
			//    {"message":"Unauthorized"}(2026-08-25 用户点出来一脸问号)。
			//    指 #/overview:已配过后端的浏览器直接进面板(用户实际在用的入口);
			//    没配过的会被 zashboard 路由守卫引导到配置页,填一次就存 localStorage。
			//    (试过 #/setup?hostname=…&secret=… URL 直配,fork 版 probe 不过,弃用。)
			var a = document.createElement("a");
			a.href = location.protocol + "//" + location.hostname + ":" + port +
				"/ui/zashboard/#/overview";
			a.target = "_blank";
			a.rel = "noopener noreferrer";
			document.body.appendChild(a); a.click(); document.body.removeChild(a);
		});

		el.yaml.addEventListener("change", function () {
			var v = this.value;
			this.blur();               // 先失焦:保存被拒时 fillYamlList 才能把下拉还原回当前配置
			saveKV({
				merlinclash_set_yamlsel_start: v,
				merlinclash_set_yamlsel_startchange: "1"
			}, "配置已切换,需要重启内核才生效。").then(function (ok) {
				if (!ok) return;
				aclStale = true;       // 自定规则跟着配置走,节点组也可能不同
				loadStatus();
			});
		});

		// ── DNS tab ──
		bindSeg(el.dnsType, function (v) {
			el.fakeipRow.style.display = v === "fi" ? "" : "none";
			fit();
		});
		el.dnsSave.addEventListener("click", saveDns);
		[el.dnsHijack, el.dnsProxy, el.dnsClear, el.dnsSniffer].forEach(function (t) {
			t.addEventListener("click", function () { this.classList.toggle("is-on"); });
		});

		// ── 规则 tab ──
		// chnroute 和 acl_plan 是即改即存(上游同款语义):它们不属于"编辑一堆再统一保存"
		// 的表单,拆开存反而少一个"改了忘保存"的坑。生效仍要重启内核。
		el.chnroute.addEventListener("click", function () {
			this.classList.toggle("is-on");
			saveKV({ merlinclash_set_chnroute_sw: isOn(el.chnroute) ? "1" : "0" }, "已保存。重启内核后生效。");
		});
		bindSeg(el.aclPlan, function (v) {
			el.aclEasy.style.display = v === "easy" ? "" : "none";
			el.aclProBtn.style.display = v === "pro" ? "" : "none";
			fit();
			saveKV({ merlinclash_acl_plan: v }, "规则模式已切为「" + (v === "pro" ? "专业" : "简易") + "」,重启内核后生效。");
		});

		// ── ACL 规则表格 ──
		el.aclAdd.addEventListener("click", aclAdd);
		el.aclRows.addEventListener("click", function (ev) {
			var n = ev.target.getAttribute && ev.target.getAttribute("data-acldel");
			if (n && confirm("删除这条规则?")) aclDel(n);
		});

		// ── 访问控制 ──
		bindSeg(el.nokMethod, function (v) {
			saveKV({ merlinclash_nokpacl_method: v }, "匹配方法已保存,重启内核后生效。");
		});
		el.nokAdd.addEventListener("click", nokAdd);
		el.nokRows.addEventListener("click", function (ev) {
			var n = ev.target.getAttribute && ev.target.getAttribute("data-nokdel");
			if (n && confirm("把这台设备移出名单?")) nokDel(n);
		});

		// ── 高级设置 ──
		el.advSave.addEventListener("click", saveAdv);
		[el.advDelaySw, el.advTcp, el.advMix,
		 el.advIntSw, el.advTolSw, el.advCloseProxy, el.advIot, el.advSelf].forEach(function (t) {
			t.addEventListener("click", function () { this.classList.toggle("is-on"); });
		});

		// ── 附加功能 ──
		// 时/分/日 下拉用脚本生成,手写 24+60+31 个 option 纯属折磨
		el.rstHour.innerHTML = Array.from({ length: 24 }, function (_, i) { return "<option>" + i + "</option>"; }).join("");
		el.rstMin.innerHTML  = Array.from({ length: 60 }, function (_, i) { return "<option>" + i + "</option>"; }).join("");
		el.rstDay.innerHTML  = Array.from({ length: 31 }, function (_, i) { return "<option value='" + (i + 1) + "'>" + (i + 1) + " 号</option>"; }).join("");
		el.geoUpdate.addEventListener("click", geoUpdate);
		el.chnUpdate.addEventListener("click", chnUpdate);
		el.bakDown.addEventListener("click", bakDown);
		el.bakPick.addEventListener("click", function () { el.bakFile.click(); });
		el.bakFile.addEventListener("change", function () {
			if (this.files[0]) bakRestore(this.files[0]);
			this.value = "";
		});
		Array.prototype.forEach.call(el.bakBoxes.querySelectorAll("[data-bak]"), function (b) {
			b.addEventListener("click", function () { this.classList.toggle("is-on"); });
		});
		el.rstMode.addEventListener("change", rstFieldsShow);
		el.rstSave.addEventListener("click", rstSave);

		// ── 日志 / 当前配置 ──
		bindSeg(el.logSrc, loadLogView);
		el.logRefresh.addEventListener("click", loadLogView);
		el.confRefresh.addEventListener("click", loadConfView);

		// ── 编辑器 ──
		Array.prototype.forEach.call(document.querySelectorAll(".mc2-edit"), function (b) {
			b.addEventListener("click", function () { editorOpen(b.getAttribute("data-edit"), b); });
		});
		el.editorSave.addEventListener("click", editorSave);
		el.editorCancel.addEventListener("click", editorClose);

		el.pick.addEventListener("click", function () { el.file.click(); });
		el.file.addEventListener("change", function () {
			if (this.files[0]) uploadYaml(this.files[0]);
			this.value = "";
		});
		["dragenter", "dragover"].forEach(function (t) {
			el.drop.addEventListener(t, function (e) { e.preventDefault(); el.drop.classList.add("is-over"); });
		});
		["dragleave", "drop"].forEach(function (t) {
			el.drop.addEventListener(t, function (e) { e.preventDefault(); el.drop.classList.remove("is-over"); });
		});
		el.drop.addEventListener("drop", function (e) {
			if (e.dataTransfer.files && e.dataTransfer.files[0]) uploadYaml(e.dataTransfer.files[0]);
		});

		// ── 草稿标记(mc2ui-19)──
		// 「改一堆再点保存」的表单组:用户动过就标脏,loadStatus 不再回填它,直到保存成功或整页强制重绘。
		// 即改即存的控件(chnroute / 规则模式 / 匹配方法 / 配置下拉)不在此列。
		function markDirty(group, nodes) {
			nodes.forEach(function (n) {
				if (!n) return;
				var evs = /^(INPUT|TEXTAREA|SELECT)$/.test(n.tagName) ? ["input", "change"] : ["click"];
				evs.forEach(function (ev) { n.addEventListener(ev, function () { dirty[group] = true; }); });
			});
		}
		markDirty("sub", [el.subLinks, el.subCycle].concat(SUB_TOGGLES.map(function (p) { return el[p[0]]; })));
		markDirty("dns", [el.dnsType, el.fakeipSrv, el.dnsHijack, el.dnsProxy, el.dnsClear, el.dnsSniffer]);
		markDirty("adv", [el.advDelaySw, el.advDelayVal, el.advLogVal, el.advTcp, el.advMix, el.advIntSw, el.advIntVal,
			el.advTolSw, el.advTolVal, el.advDashPw, el.advTproxy, el.advCloseProxy, el.advIot, el.advSelf]);
		markDirty("geo", [el.geoIp, el.geoSite]);
		markDirty("bak", Array.prototype.slice.call(el.bakBoxes.querySelectorAll("[data-bak]")));
		markDirty("rst", [el.rstMode, el.rstEvery, el.rstDay, el.rstWeek, el.rstHour, el.rstMin]);

		autoBalance(".mc2-grid", 265);     // 与 mc2.css 里 minmax(265px, 1fr) 一致
		autoBalance(".mc2-runtime", 170);  // 与 minmax(170px, 1fr) 一致
		loadStatus(true).then(fixLegacySub);
		refreshYamlList();
	}

	if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
	else init();
})();
