# MC2-merlin 会话笔记

> 记「怎么验证」和「为什么这么改」。版本历史看 Releases,用法看 README。

## 排版重做(2026-08-23,v1.2.2.5)

### 改之前先量 —— 三个探针

在插件页面的 devtools console 里跑,**改完必须复跑**,数字变了就是回归。
(路由器页面用 `http://www.asusrouter.com/Module_merlinclash.asp`,**别用 `192.168.0.1`**,
见下面「会话」一节。)

**① 标签列宽 / 数值列起点(核心对齐指标,全 8 个 tab 都要过)**
```js
(function(){var o={};[].slice.call(document.querySelectorAll('input[class*=show-btn]')).forEach(function(b){
b.click();var w={},l={};[].slice.call(document.querySelectorAll('.FormTable > tbody > tr')).forEach(function(tr){
if(!tr.offsetParent||tr.children.length!==2)return;var th=tr.querySelector('th'),td=tr.querySelector('td');if(!th||!td)return;
w[Math.round(th.getBoundingClientRect().width)]=1;l[Math.round(td.getBoundingClientRect().left)]=1;});
o[b.value]={lbl:Object.keys(w).join(','),left:Object.keys(l).join(','),scrollW:document.documentElement.scrollWidth};});
return JSON.stringify(o,null,1);})()
```
合格线:每个 tab 的 `lbl` 只有 **一个值 232**,`left` 只有 **一个值**,`scrollW` **不超过 innerWidth**。
改之前是 `lbl:"236,248"`(错位 12px)、`left:"796,808"`。

**② 行分隔线是否是一条直线**
```js
[].slice.call(document.querySelectorAll('.FormTable > tbody > tr')).map(function(tr){
var th=tr.querySelector('th'),td=tr.querySelector('td');if(!th||!td||!tr.offsetParent)return null;
return Math.round(td.getBoundingClientRect().bottom-th.getBoundingClientRect().bottom);}).filter(function(x){return x!==null;})
```
全 0 才合格。分隔线画在 `<tr>` 上就恒为 0;画在 th/td 上时曾经是 **13~347px**——
两列高度不同,同一条分隔线被画在两个 y 上。

**③ 写死像素导致的留白**
```js
[].slice.call(document.querySelectorAll('#app textarea,#app div,#app table,#app input,#app select'))
.filter(function(e){return e.offsetParent && /px$|^\d+$/.test(e.style.width||e.getAttribute('width')||'');})
.map(function(e){var r=e.getBoundingClientRect(),p=e.parentElement.getBoundingClientRect();
return {id:e.id,inline:e.style.width||e.getAttribute('width'),w:Math.round(r.width),parent:Math.round(p.width)};})
.filter(function(x){return x.parent-x.w>400;})
```
注意:**留白大不等于有问题**——一个「探测间隔」下拉框就该按内容宽,不该拉满 891px。
只有本该填满的(日志框、配置框)才算 bug。

### 关键决定

| 决定 | 为什么 |
|---|---|
| 行改用 flex 而不是 `table-layout:fixed` | 卡片头是 `colspan` 的单 td 行,fixed 算法会拿它定义列网格,后面行的 `width` 全被忽略。实测 th 反而变成 424/636。 |
| flex 规则带 `:has(> th + td:last-child)` 守卫 | **访问控制** 的 ACL 列表是切到该 tab 时 JS 才建的多列表格(初次 DOM 普查看不到)。没守卫时它被当 flex 排,撑出 105px 横向滚动条。守卫还顺带保证老浏览器无 `:has()` 时整段规则失效、退回原表格布局,不会坏。 |
| 分隔线画在 `<tr>` 上 | 见探针②。 |
| `.mc-row-main` 重写总开关行的 HTML | 上游用 `position:absolute + margin-left:70/290/300/380px` 摞五个 div,只在某一个窗口宽度下对。宽屏撕裂、窄屏文字断行成「已是最/新」。 |
| `.FormTable td span { color: inherit }` | 固件 `form_style.css` 有 `.FormTable td span{color:#FC0}`,把每个单元格里的 span 无差别染金。页面 7 种硬编码颜色统一映射到 4 个语义 token。 |

## 会话 / 调试(踩过)

- **改 CSS 不需要 `service restart_httpd`**。2026-08-23 实测:推完 CSS 不重启,`curl` 立刻拿到新内容
  → **httpd 不缓存静态文件**,缓存的是浏览器。而 restart_httpd 会**杀掉所有 WebUI 会话**。
  破缓存别用 `?t=`(带 query 的静态文件 404),用:
  ```js
  fetch('/res/merlinclash.css',{cache:'reload'}).then(r=>r.text()).then(t=>{
    var o=document.getElementById('mc_live'); if(o)o.remove();
    var s=document.createElement('style'); s.id='mc_live'; s.textContent=t; document.head.appendChild(s);});
  ```
- **`192.168.0.1` 和 `www.asusrouter.com` 是两套 cookie**。在前者登录后路由器会把页面重定向到后者,
  再导航回前者就没有会话了。**全程只用 `www.asusrouter.com`。**
- **`/_api/` 返回数字(`{"result":-403}`)= 会话过期**,不是脚本坏了。页面上的表现是
  **所有 tab 都点不开**——因为 `toggle_func()`(绑定全部 tab 的点击)写在
  `get_dbus_data()` 的 ajax success 回调里,那个请求一失败,整个初始化就跳过。
  排查顺序:先 `fetch('/_api/merlinclash')` 看是不是 -403,**别急着怀疑自己的改动**。
- **ASUS 同时只保留一个 WebUI 会话**。自动化登录会把用户自己浏览器里开着的 WebUI 踢掉,
  用户那边一刷新又把自动化踢掉,来回拉锯。长时间调试前先让用户关掉他自己的路由器页面。
