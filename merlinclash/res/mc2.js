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
	var el = {}, busy = false, db = {};

	/* ---------------- 通信 ---------------- */
	function nonce(p) { return p + (p.indexOf("?") < 0 ? "?" : "&") + "_=" + Date.now(); }

	function getJSON(p) {
		return fetch(nonce(p), { cache: "no-store" }).then(function (r) { return r.json(); });
	}

	// fields 里的键值会被后端写进 dbus —— 上游脚本全靠读 dbus 拿参数,
	// 所以「保存设置」本质就是带 fields 发一次请求。
	//
	// ⚠️ 必须检查 response.error 并抛出。handler 在脚本不存在等情况下回
	//    HTTP 200 + {"error":"..."},光看 HTTP 状态码是发现不了的 ——
	//    踩过:dummy_script.sh 缺失时所有"保存"静默失败,dbus 纹丝不动,
	//    页面却一路显示"已保存"。假成功比失败更害人,它让人不再排查。
	function post(method, params, fields) {
		return fetch("/_api/", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({
				id: Math.floor(Math.random() * 1e8),
				method: method,
				params: params || [],
				fields: fields || {}
			})
		}).then(function (r) { return r.json(); })
		.then(function (j) {
			if (j && j.error) throw new Error(j.error);
			return j;
		});
	}

	function fit() { if (typeof window.reportHeight === "function") window.reportHeight(); }

	// 即改即存的统一出口:写一组 dbus 键,成功提示、失败也提示。
	// 单独收一个函数是因为这类调用散在各处,逐个补 .catch 迟早漏一个。
	function saveKV(fields, okMsg) {
		return post("dummy_script.sh", [], fields)
			.then(function () { okMsg && log(okMsg); })
			.catch(function (e) { log("保存失败:" + e.message); });
	}

	function log(t) {
		el.log.classList.add("is-show");
		el.log.textContent = t;
		el.log.scrollTop = el.log.scrollHeight;
		fit();
	}

	// handler 对不存在的文件回 200 + 空串(不是 404),所以这里不会拿到 undefined
	// ⚠️ baseline 机制防"旧日志假完成":点按钮后 handler 拉起脚本要几百毫秒,
	//    而首轮轮询几十毫秒就到 —— 读到的是**上一次操作的旧日志**,尾部残留的
	//    结束标记会被当成"已完成",轮询秒退,用户看到的全是旧内容
	//    (2026-08-25 用户点「设置并更新」看到的却是重启日志)。
	//    规则:首轮内容存为 baseline;若首轮就带标记,视为旧日志 —— 只显示、
	//    不收尾,等内容发生变化(脚本清空/开写)后,再按正常标记判定完成。
	function pollLog(file, onDone) {
		var stop = false, waited = 0, baseline = null, baselineStale = false;
		var MAX = 180000;      // 3 分钟兜底:标记万一没出现也要收尾,不能空转到天荒地老
		(function tick() {
			if (stop) return;
			fetch(nonce("/_temp/" + file), { cache: "no-store" })
				.then(function (r) { return r.text(); })
				.then(function (t) {
					var done = false, clean = t;
					DONE_MARKS.forEach(function (m) {
						if (clean.indexOf(m) >= 0) { done = true; clean = clean.split(m).join(""); }
					});
					if (baseline === null) { baseline = t; baselineStale = done; }
					if (baselineStale) {
						if (t === baseline) { done = false; clean = "等待任务启动 …"; }
						else baselineStale = false;    // 内容变了 = 新任务开写,恢复正常判定
					}
					log(clean.replace(/\s+$/, ""));
					if (done) { stop = true; onDone && onDone(); return; }
					waited += 700;
					if (waited >= MAX) { stop = true; onDone && onDone(); return; }
					setTimeout(tick, 700);
				})
				.catch(function () { waited += 1200; if (waited < MAX) setTimeout(tick, 1200); else { stop = true; onDone && onDone(); } });
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
		el.core.textContent = db.merlinclash_core_version || db.merlinclash_version || "—";

		el.pid.textContent = pid || "未运行";
		el.up.textContent  = fmtStart(db.merlinclash_binary_startime);
		el.cfg.textContent = db.merlinclash_set_yamlsel_start || "—";
		el.ver.textContent = db.merlinclash_version || "—";

		setToggle(el.toggle, enable);
		el.toggle.disabled = false;
		el.panel.disabled = !running;
		el.restart.disabled = !enable;
		fit();
	}

	function loadStatus() {
		// 先让后端把运行态刷进 dbus,再按前缀整批读回来
		return post("mc2_status.sh", [])
			.then(function () { return getJSON("/_api/merlinclash_"); })
			.then(function (j) {
				db = (j && j.result && j.result[0]) || {};
				paintStatus();
				paintSub();
				paintDns();
				paintRule();
				paintAclTable();
				paintNok();
				paintAdv();
				paintExtra();
				fillYamlList();
				// 简易/专业互斥显示,跟随当前模式
				var plan = db.merlinclash_acl_plan === "pro" ? "pro" : "easy";
				el.aclEasy.style.display = plan === "easy" ? "" : "none";
				el.aclProBtn.style.display = plan === "pro" ? "" : "none";
			})
			.catch(function (e) {
				el.state.textContent = "读取状态失败";
				el.core.textContent = e.message;
			});
	}

	// 可选配置文件:上游把列表存在 merlinclash_select_yaml* 里,
	// 拿不到就至少把「当前正在用的那个」放进去,别给个空下拉框。
	function fillYamlList() {
		var cur = db.merlinclash_set_yamlsel_start || "";
		var names = [];
		Object.keys(db).forEach(function (k) {
			if (/^merlinclash_yamlname/.test(k) && db[k]) names.push(db[k]);
		});
		if (cur && names.indexOf(cur) < 0) names.unshift(cur);
		if (!names.length && cur) names = [cur];
		el.yaml.innerHTML = names.map(function (n) {
			return '<option value="' + esc(n) + '"' + (n === cur ? " selected" : "") + ">" + esc(n) + "</option>";
		}).join("");
	}

	function toggleMC() {
		if (busy) return;
		busy = true;
		el.toggle.disabled = true;
		var next = isOn(el.toggle) ? "0" : "1";
		log(next === "1" ? "正在启动 Magic Catling …\n" : "正在停止 …\n");

		// 启停要几十秒(检查配置、起内核、建 30+ 条 iptables 链)。
		// 期间每 3 秒刷一次状态条,让「内核起来了没、接管了没」实时可见 ——
		// 只在最后刷一次的话,这几十秒里页面看着像卡住了。
		var ticking = setInterval(function () { refreshStatusOnly(); }, 3000);
		var stopTick = function () { clearInterval(ticking); };

		// 总开关本身就是 dbus 里的 merlinclash_enable,写进去再触发 start
		post("clash_config.sh", ["start"], { merlinclash_enable: next })
			.then(function () {
				pollLog("merlinclash_log.txt", function () {
					stopTick(); busy = false; loadStatus();
				});
			})
			.catch(function (e) {
				stopTick(); log("出错:" + e.message); busy = false; el.toggle.disabled = false;
			});
	}

	// 重启 = 停内核→清规则→按当前配置全量重启(clash_config.sh 的 restart 分支)。
	// 改完 DNS/订阅/规则后要它生效,或者代理行为不对想"重来一遍",点这个最省事。
	function restartMC() {
		if (busy) return;
		if (!confirm("重启 Magic Catling?约需半分钟,期间代理会短暂中断。")) return;
		busy = true;
		el.restart.disabled = true;
		el.toggle.disabled = true;
		log("正在重启 Magic Catling …\n");
		var ticking = setInterval(function () { refreshStatusOnly(); }, 3000);
		post("clash_config.sh", ["restart"])
			.then(function () {
				pollLog("merlinclash_log.txt", function () {
					clearInterval(ticking); busy = false; loadStatus();
				});
			})
			.catch(function (e) {
				clearInterval(ticking); log("重启失败:" + e.message);
				busy = false; el.restart.disabled = false; el.toggle.disabled = false;
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
	var SUB_TOGGLES = [
		["subRename", "merlinclash_sub_rename"],
		["subEmoji",  "merlinclash_sub_emoji"],
		["subUdp",    "merlinclash_sub_udp"],
		["subScv",    "merlinclash_sub_scv"],
		["subTfo",    "merlinclash_sub_tfo"]
	];

	function paintSub() {
		// ⚠️ dbus 里存的是 base64(上游 UI 也是这么存的),显示前必须解码 ——
		//    直接塞进 textarea 用户看到的是一坨密文,改也改不对(2026-08-25 踩到)。
		el.subLinks.value = b64d(db.merlinclash_sub_links || "");
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
		var f = {
			// 存回 dbus 要重新编码,和上游格式保持一致
			merlinclash_sub_links: b64e(el.subLinks.value.trim()),
			merlinclash_sub_updatecycle: el.subCycle.value
		};
		SUB_TOGGLES.forEach(function (p) { f[p[1]] = isOn(el[p[0]]) ? "1" : "0"; });
		return f;
	}

	function saveSub() {
		if (busy) return;
		busy = true;
		log("保存订阅设置 …\n");
		// dummy_script.sh 是上游用来「只写 dbus、不执行动作」的空脚本
		post("dummy_script.sh", [], collectSub())
			.then(function () { busy = false; log("已保存。改动会在下次更新订阅时应用。"); loadStatus(); })
			.catch(function (e) { busy = false; log("保存失败:" + e.message); });
	}

	function updateSub() {
		if (busy) return;
		if (!el.subLinks.value.trim()) { log("先填订阅链接。"); return; }
		busy = true;
		log("正在拉取订阅并转换配置,机场响应慢时需要等一会 …\n");
		// 先把当前表单写进 dbus,再让 clash_subscribe.sh 按这些参数干活
		post("clash_subscribe.sh", ["update"], collectSub())
			.then(function () {
				pollLog("merlinclash_log.txt", function () { busy = false; loadStatus(); });
			})
			.catch(function (e) { busy = false; log("更新失败:" + e.message); });
	}

	function uploadYaml(file) {
		if (!/\.(ya?ml)$/i.test(file.name)) { log("只接受 .yaml 配置,当前选的是:" + file.name); return; }
		busy = true;
		log("上传 " + file.name + " (" + (file.size / 1024).toFixed(1) + " KB) …\n");
		var fd = new FormData();
		fd.append("file", file, file.name);
		fetch("/_upload", { method: "POST", body: fd })
			.then(function (r) { return r.json(); })
			.then(function (j) {
				if (!j || j.result !== "ok") throw new Error("上传失败:" + JSON.stringify(j));
				return post("clash_subscribe.sh", ["upload"], { merlinclash_sub_upload_filename: file.name });
			})
			.then(function () { pollLog("merlinclash_log.txt", function () { busy = false; loadStatus(); }); })
			.catch(function (e) { log("出错:" + e.message); busy = false; });
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
		if (busy) return;
		busy = true;
		log("保存 DNS 设置 …\n");
		post("dummy_script.sh", [], {
			merlinclash_dns_type:          segVal(el.dnsType) || "rh",
			merlinclash_dns_fakeip_server: el.fakeipSrv.value.trim() || "223.5.5.5",
			merlinclash_dns_dnshijack_sw:  isOn(el.dnsHijack)  ? "1" : "0",
			merlinclash_dns_proxydns_sw:   isOn(el.dnsProxy)   ? "1" : "0",
			merlinclash_dns_cleardns_sw:   isOn(el.dnsClear)   ? "1" : "0",
			merlinclash_dns_sniffer_sw:    isOn(el.dnsSniffer) ? "1" : "0"
		}).then(function () {
			busy = false;
			log("已保存。重启内核后生效 —— DNS 属于全网解析路径,建议在没人用网的时候重启。");
			loadStatus();
		}).catch(function (e) { busy = false; log("保存失败:" + e.message); });
	}

	/* ---------------- 自定规则(二期)---------------- */
	function paintRule() {
		setToggle(el.chnroute, db.merlinclash_set_chnroute_sw === "1");
		segSet(el.aclPlan, db.merlinclash_acl_plan === "pro" ? "pro" : "easy");
	}

	/* ---------------- 内联编辑器 ----------------
	 * 复刻上游 common_text_editor 的协议:
	 *   读:POST clash_getbasicyaml.sh(把配置段导出到 /tmp/upload/*.txt)
	 *       → GET /_temp/<文件>。handler 是**异步**起脚本的,导出可能还没写完,
	 *       所以拿到空内容时重试两次。
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

	function editorOpen(key, anchorBtn) {
		var cfg = EDITS[key];
		if (!cfg) return;
		editCur = key;
		el.editorTitle.textContent = cfg.title;
		el.editorHint.textContent = cfg.hint;
		el.editorText.value = "读取中…";
		// 把编辑器搬到触发按钮所在卡片的后面展开 —— 编辑哪段,编辑器就出现在哪段下面
		var card = anchorBtn.closest(".kslite-card");
		card.parentNode.insertBefore(el.editor, card.nextSibling);
		el.editor.classList.add("is-open");
		fit();

		post("clash_getbasicyaml.sh", []).then(function () {
			var tries = 0;
			(function read() {
				tries++;
				fetch(nonce("/_temp/" + cfg.file), { cache: "no-store" })
					.then(function (r) { return r.text(); })
					.then(function (t) {
						// 导出是异步的,空内容可能是"还没写完"——重试两次再认
						if (!t && tries < 3) return void setTimeout(read, 900);
						el.editorText.value = t || "";
						fit();
					})
					.catch(function () { if (tries < 3) setTimeout(read, 1200); });
			})();
		});
	}

	function editorClose() {
		el.editor.classList.remove("is-open");
		editCur = null;
		fit();
	}

	function editorSave() {
		var cfg = EDITS[editCur];
		if (!cfg || busy) return;
		var content = el.editorText.value;
		if (cfg.noCN && /[一-龥]/.test(content)) {
			el.editorHint.textContent = "内容里有中文 —— iptables 规则不接受,请检查后再保存。";
			return;
		}
		busy = true;
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
				busy = false;
				editorClose();
				log("已保存。重启内核后生效。");
			})
			.catch(function (e) { busy = false; el.editorHint.textContent = "保存失败:" + e.message; });
	}

	/* ---------------- ACL 规则表格(三期,简易模式)----------------
	 * 存储:merlinclash_acl_{type,content,lianjie}_<N>,值 = Base64(encodeURIComponent(v))。
	 * clash_saveacls.sh save 会遍历 dbus(置空的自动跳过)→ 重写
	 * rule_custom/<配置>_custom_rule.yaml → 再按文件顺序重新编号写回 dbus,
	 * 所以「删除」= 该行三键置空 + save,重排它管,前端不用维护连续编号。
	 * 类型/节点组下拉来自内核导出(clash_getproxygroup.sh → /_temp/proxytype.txt
	 * + proxygroups.txt)—— 内核没起过就没有,这时说清楚而不是给空下拉。
	 */
	function b64e(v) { return btoa(encodeURIComponent(v)); }
	function b64d(v) {
		try { return decodeURIComponent(atob(v)); } catch (e) { return v || ""; }
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
				'<td class="mc2-table__mono">' + esc(b64d(db["merlinclash_acl_type_" + n])) + '</td>' +
				'<td class="mc2-table__mono">' + esc(b64d(db["merlinclash_acl_content_" + n])) + '</td>' +
				'<td>' + esc(b64d(db["merlinclash_acl_lianjie_" + n])) + '</td>' +
				'<td><button type="button" class="mc2-x" data-acldel="' + n + '" title="删除">×</button></td>' +
			'</tr>';
		}).join("") : '<tr class="is-empty"><td colspan="4">还没有规则 —— 用下面一行添加</td></tr>';
		fit();
	}

	function loadAclOptions() {
		// 触发内核导出,再读两个下拉的数据
		return post("clash_getproxygroup.sh", []).then(function () {
			var tries = 0;
			(function read() {
				tries++;
				Promise.all([
					fetch(nonce("/_temp/proxytype.txt"), { cache: "no-store" }).then(function (r) { return r.text(); }),
					fetch(nonce("/_temp/proxygroups.txt"), { cache: "no-store" }).then(function (r) { return r.text(); })
				]).then(function (rs) {
					var types = rs[0].split("\n").filter(Boolean);
					var groups = rs[1].split("\n").filter(Boolean);
					if (!types.length && tries < 3) return void setTimeout(read, 900);
					if (!types.length) {
						el.aclNote.textContent = "类型 / 节点组列表拿不到 —— 内核至少要成功启动过一次,列表才会生成。";
						return;
					}
					el.aclType.innerHTML = types.map(function (t) { return "<option>" + esc(t) + "</option>"; }).join("");
					el.aclGroup.innerHTML = groups.map(function (g) { return "<option>" + esc(g) + "</option>"; }).join("");
					// 内核没跑时后端导出的是占位文案「请启动插件」——
					// 下拉里孤零零一项没头没尾,补一句人话说清前因后果
					el.aclNote.textContent = /请启动/.test(types[0] || "")
						? "类型和出口列表来自运行中的配置 —— 先启动 Magic Catling,再回这里加规则。"
						: "";
				});
			})();
		});
	}

	function aclAdd() {
		var t = el.aclType.value, c = el.aclContent.value.trim(), g = el.aclGroup.value;
		if (!t || !c || !g) { log("类型、内容、出口都要填。"); return; }
		var n = (aclRows().pop() || 0) + 1, f = {};
		f["merlinclash_acl_type_" + n] = b64e(t);
		f["merlinclash_acl_content_" + n] = b64e(c);
		f["merlinclash_acl_lianjie_" + n] = b64e(g);
		busy = true;
		post("clash_saveacls.sh", ["save"], f).then(function () {
			busy = false; el.aclContent.value = "";
			log("规则已添加,重启内核后生效。");
			loadStatus();
		}).catch(function (e) { busy = false; log("添加失败:" + e.message); });
	}

	function aclDel(n) {
		var f = {};
		["type", "content", "lianjie"].forEach(function (p) { f["merlinclash_acl_" + p + "_" + n] = ""; });
		busy = true;
		post("clash_saveacls.sh", ["save"], f).then(function () {
			busy = false;
			log("规则已删除,重启内核后生效。");
			loadStatus();
		}).catch(function (e) { busy = false; log("删除失败:" + e.message); });
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

	function paintNok() {
		segSet(el.nokMethod, db.merlinclash_nokpacl_method || "0");
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

	function nokAdd() {
		var ip = el.nokIp.value.trim(), name = el.nokName.value.trim();
		if (!ip || !name) { log("别名和 IP 都要填。"); return; }
		var n = (nokRows().pop() || 0) + 1, f = {};
		f["merlinclash_nokpacl_name_" + n] = name;
		f["merlinclash_nokpacl_ip_" + n] = ip;
		f["merlinclash_nokpacl_mac_" + n] = el.nokMac.value.trim() || " ";
		f["merlinclash_nokpacl_port_" + n] = el.nokPort.value;
		f["merlinclash_nokpacl_mode_" + n] = el.nokMode.value;
		saveKV(f).then(function () {
			el.nokIp.value = ""; el.nokName.value = ""; el.nokMac.value = "";
			log("已加入名单,重启内核后生效。");
			loadStatus();
		});
	}

	function nokDel(n) {
		var f = {};
		["name", "ip", "mac", "port", "mode"].forEach(function (p) { f["merlinclash_nokpacl_" + p + "_" + n] = ""; });
		saveKV(f).then(function () {
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
		setToggle(el.advQueue,  db.merlinclash_set_queue_sw === "1");
		setToggle(el.advDelaySw, db.merlinclash_set_startdelay_sw === "1");
		el.advDelayVal.value = db.merlinclash_set_startdelay_val || "120";
		setToggle(el.advLogSw, db.merlinclash_set_logcheck_sw === "1");
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

	function saveAdv() {
		if (busy) return;
		var tp = segVal(el.advTproxy) || "udp";
		// 上游在切非 closed 模式时弹的那个警告,内容是真的 —— TPROXY 与网络神盾冲突
		busy = true;
		log("保存高级设置 …\n");
		post("dummy_script.sh", [], {
			merlinclash_set_queue_sw:      isOn(el.advQueue) ? "1" : "0",
			merlinclash_set_startdelay_sw: isOn(el.advDelaySw) ? "1" : "0",
			merlinclash_set_startdelay_val: el.advDelayVal.value.trim() || "120",
			merlinclash_set_logcheck_sw:   isOn(el.advLogSw) ? "1" : "0",
			merlinclash_set_logcheck_val:  el.advLogVal.value.trim() || "40",
			merlinclash_set_tcpcon_sw:     isOn(el.advTcp) ? "1" : "0",
			merlinclash_set_mixport_sw:    isOn(el.advMix) ? "1" : "0",
			merlinclash_set_interval_sw:   isOn(el.advIntSw) ? "1" : "0",
			merlinclash_set_interval_val:  el.advIntVal.value,
			merlinclash_set_tolerance_sw:  isOn(el.advTolSw) ? "1" : "0",
			merlinclash_set_tolerance_val: el.advTolVal.value,
			merlinclash_set_dashboard_password: el.advDashPw.value.trim() || "clash",
			merlinclash_ipt_tproxy_type:   tp,
			merlinclash_ipt_closeproxy_sw: isOn(el.advCloseProxy) ? "1" : "0",
			merlinclash_ipt_proxyiot_sw:   isOn(el.advIot) ? "1" : "0",
			merlinclash_ipt_proxyrouter_sw: isOn(el.advSelf) ? "1" : "0",
			merlinclash_set_watchdog_sw:   "0"      // 恒 0,见 paintAdv 的注释
		}).then(function () {
			busy = false;
			log("已保存。重启内核后生效。" + (tp !== "closed" ? "\n提醒:TPROXY 模式与 AiProtection 网络神盾冲突,确认它是关闭的。" : ""));
			loadStatus();
		}).catch(function (e) { busy = false; log("保存失败:" + e.message); });
	}

	/* ---------------- 附加功能(四期)---------------- */
	function nowStamp() {
		var d = new Date(), p = function (n) { return (n < 10 ? "0" : "") + n; };
		return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()) +
			" " + p(d.getHours()) + ":" + p(d.getMinutes());
	}

	function paintExtra() {
		el.geoIp.value = db.merlinclash_set_geoip_type || "full";
		el.geoSite.value = db.merlinclash_set_geosite_type || "full";
		el.geoDate.textContent = db.merlinclash_db_geo_updatetime ? "上次:" + db.merlinclash_db_geo_updatetime : "";
		el.chnDate.textContent = db.merlinclash_db_chnroute_updatetime ? "上次:" + db.merlinclash_db_chnroute_updatetime : "";

		el.rstMode.value = db.merlinclash_select_clash_restart || "1";
		el.rstEvery.value = db.merlinclash_select_clash_restart_minute_2 || "30";
		el.rstDay.value = db.merlinclash_select_clash_restart_day || "1";
		el.rstWeek.value = db.merlinclash_select_clash_restart_week || "1";
		el.rstHour.value = db.merlinclash_select_clash_restart_hour || "4";
		el.rstMin.value = db.merlinclash_select_clash_restart_minute || "0";
		rstFieldsShow();
	}

	// 按计划模式只露相关字段:「每隔」只要分钟数,「每天」只要时:分……
	// 五种模式共用一排字段、全摆出来的话,一半输入框跟当前模式无关,填了也没用。
	function rstFieldsShow() {
		var m = el.rstMode.value;
		el.rstEvery.style.display = el.rstEveryU.style.display = (m === "5" ? "" : "none");
		el.rstDay.style.display  = (m === "4" ? "" : "none");
		el.rstWeek.style.display = (m === "3" ? "" : "none");
		var timed = (m === "2" || m === "3" || m === "4");
		el.rstHour.style.display = el.rstMin.style.display = (timed ? "" : "none");
		el.rstHour.nextElementSibling.style.display = (timed ? "" : "none");   // 冒号
		fit();
	}

	function geoUpdate() {
		if (busy) return;
		if (!confirm("更新 Geo 数据库?要下载十几 MB,机场慢时需要等。")) return;
		busy = true;
		log("正在更新 Geo 数据库 …\n");
		// ⚠️ params 必须是 ["5"] —— 脚本的分发是 `case $2 in 5)`,数字暗号,
		//    不是语义化的 "update"。传空/传错 → case 不匹配 → rc=0 空转退出,
		//    表面毫无异常:fields 照写、日志不动、Geo 文件纹丝不动
		//    (2026-08-25 踩到:用户点「设置并更新」只看到旧日志)。
		//    上游 push_data(script, action, ...) 的 action 就是这个数字。
		post("clash_update_ipdb.sh", ["5"], {
			merlinclash_action: "update",
			merlinclash_set_geoip_type: el.geoIp.value,
			merlinclash_set_geosite_type: el.geoSite.value,
			merlinclash_db_geo_updatetime: nowStamp()
		}).then(function () {
			pollLog("merlinclash_log.txt", function () {
				// 上游脚本会把软链覆盖成实体(大文件落回 jffs),更新完自动归位 ksdata
				post("mc2_fixlink.sh", []).catch(function(){}).then(function () {
					busy = false; loadStatus();
				});
			});
		}).catch(function (e) { busy = false; log("更新失败:" + e.message); });
	}

	function chnUpdate() {
		if (busy) return;
		if (!confirm("更新大陆 IP 白名单?")) return;
		busy = true;
		log("正在更新大陆 IP 白名单 …\n");
		// 同上:chnroute 的数字暗号是 25(case $2 in 25)
		post("clash_update_chnroute.sh", ["25"], {
			merlinclash_action: "update",
			merlinclash_db_chnroute_updatetime: nowStamp()
		}).then(function () {
			pollLog("merlinclash_log.txt", function () { busy = false; loadStatus(); });
		}).catch(function (e) { busy = false; log("更新失败:" + e.message); });
	}

	function bakFields() {
		var f = {};
		Array.prototype.forEach.call(el.bakBoxes.querySelectorAll("[data-bak]"), function (b) {
			f[b.getAttribute("data-bak")] = isOn(b) ? "1" : "0";
		});
		return f;
	}

	function bakDown() {
		if (busy) return;
		busy = true;
		log("正在打包备份 …\n");
		post("clash_backup.sh", ["backup"], bakFields()).then(function () {
			// 打包是异步的,等两秒再取文件;真大的备份两秒不够,但拿到的会是
			// 半截 tar —— 上游也这样。稳妥起见等 pollLog 出结束标记后再下载。
			pollLog("merlinclash_log.txt", function () {
				busy = false;
				var a = document.createElement("a");
				a.href = "/_temp/mc_backup.tar.gz";
				a.download = "mc_backup.tar.gz";
				document.body.appendChild(a); a.click(); document.body.removeChild(a);
				log("备份已生成,浏览器开始下载。");
			});
		}).catch(function (e) { busy = false; log("备份失败:" + e.message); });
	}

	function bakRestore(file) {
		if (!/\.gz$/i.test(file.name)) { log("备份文件应是 .tar.gz"); return; }
		if (!confirm("用「" + file.name + "」覆盖当前配置?恢复后需重启内核。")) return;
		busy = true;
		log("上传备份 " + file.name + " …\n");
		var fd = new FormData();
		fd.append("file", file, "mc_backup.tar.gz");   // 恢复脚本按固定名找文件
		fetch("/_upload", { method: "POST", body: fd })
			.then(function (r) { return r.json(); })
			.then(function (j) {
				if (!j || j.result !== "ok") throw new Error("上传失败:" + JSON.stringify(j));
				return post("clash_backup.sh", ["restore"], {});
			})
			.then(function () {
				pollLog("merlinclash_log.txt", function () { busy = false; loadStatus(); });
			})
			.catch(function (e) { busy = false; log("恢复失败:" + e.message); });
	}

	function rstSave() {
		saveKV({
			merlinclash_select_clash_restart: el.rstMode.value,
			merlinclash_select_clash_restart_minute_2: el.rstEvery.value.trim() || "30",
			merlinclash_select_clash_restart_day: el.rstDay.value,
			merlinclash_select_clash_restart_week: el.rstWeek.value,
			merlinclash_select_clash_restart_hour: el.rstHour.value,
			merlinclash_select_clash_restart_minute: el.rstMin.value
		}, "定时重启已保存,重启内核后 cron 生效。");
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
		}).then(function (r) { return r.text(); }).then(function (t) {
			t = t.replace(/BBABBBBC|XU6J03M6/g, "").replace(/\s+$/, "");
			el.logView.value = t || (src === "op" ? "还没有操作日志。" : "还没有内核日志 —— 内核至少要启动过一次。");
			el.logView.scrollTop = el.logView.scrollHeight;
			fit();
		}).catch(function (e) { el.logView.value = "读取失败:" + e.message; });
	}

	function loadConfView() {
		fetch(nonce("/_temp/view.txt"), { cache: "no-store" })
			.then(function (r) { return r.text(); })
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
				// 懒加载:进 tab 才拉数据,别每次开页面全量跑一遍
				if (name === "rule" && el.aclType && !el.aclType.options.length) loadAclOptions();
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
			subRename: "mcSubRename", subEmoji: "mcSubEmoji", subUdp: "mcSubUdp",
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
			advWatchdog: "mcAdvWatchdog", advQueue: "mcAdvQueue",
			advDelaySw: "mcAdvDelaySw", advDelayVal: "mcAdvDelayVal",
			advLogSw: "mcAdvLogSw", advLogVal: "mcAdvLogVal",
			advTcp: "mcAdvTcp", advMix: "mcAdvMix",
			advIntSw: "mcAdvIntSw", advIntVal: "mcAdvIntVal",
			advTolSw: "mcAdvTolSw", advTolVal: "mcAdvTolVal",
			advDashPw: "mcAdvDashPw", advTproxy: "mcAdvTproxy",
			advCloseProxy: "mcAdvCloseProxy", advIot: "mcAdvIot",
			advSelf: "mcAdvSelf", advMark: "mcAdvMark", advSave: "mcAdvSave",
			geoIp: "mcGeoIp", geoSite: "mcGeoSite", geoUpdate: "mcGeoUpdate", geoDate: "mcGeoDate",
			chnUpdate: "mcChnUpdate", chnDate: "mcChnDate",
			bakBoxes: "mcBakBoxes", bakDown: "mcBakDown", bakPick: "mcBakPick", bakFile: "mcBakFile",
			rstMode: "mcRstMode", rstEvery: "mcRstEvery", rstEveryU: "mcRstEveryU",
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
			saveKV({
				merlinclash_set_yamlsel_start: this.value,
				merlinclash_set_yamlsel_startchange: "1"
			}, "配置已切换,需要重启内核才生效。");
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
		[el.advQueue, el.advDelaySw, el.advLogSw, el.advTcp, el.advMix,
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

		loadStatus();
	}

	if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
	else init();
})();
