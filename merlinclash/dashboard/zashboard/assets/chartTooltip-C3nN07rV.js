import{a as e}from"./rolldown-runtime-B0Z9INg1.js";import{qt as t}from"./settings-DNj_5Pi6.js";import{y as n}from"./vendor-core-CoQEAOb7.js";import{n as r,t as i}from"./chartTypes-DJ1sn9vT.js";var a=e(n(),1),o=e=>String(e).replaceAll(`&`,`&amp;`).replaceAll(`<`,`&lt;`).replaceAll(`>`,`&gt;`).replaceAll(`"`,`&quot;`).replaceAll(`'`,`&#39;`),s=({color:e,label:t,detail:n})=>`
  <div class="flex items-center my-2 gap-1">
    <div class="w-4 h-4 rounded-full" style="background-color: ${o(e)}"></div>
    ${o(t)}
    ${o(n)}
  </div>`,c=(e,{binary:n,suffix:r=``})=>l(e,e=>`${t(e,{binary:n})}${r}`),l=(e,t)=>{if(r(e.data))return``;let[n,o]=i(e.data);return s({color:e.color,label:e.seriesName,detail:`(${(0,a.default)(n).format(`HH:mm:ss`)}): ${t(o)}`})};export{l as i,o as n,c as r,s as t};