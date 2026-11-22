var O=Object.defineProperty,M=(e,n)=>{let t={};for(var a in e)O(t,a,{get:e[a],enumerable:!0});return n||O(t,Symbol.toStringTag,{value:"Module"}),t};var c=M({addDataSourcesListener:()=>B,addDimensionsListener:()=>Q,addDrilldownListener:()=>re,addErrorListener:()=>ae,addModeListener:()=>X,addOptionsListener:()=>H,addThemeListener:()=>Z,addTokensListener:()=>te,clearError:()=>le,getDataSources:()=>q,getDimensions:()=>W,getError:()=>oe,getMode:()=>Y,getOptions:()=>G,getTheme:()=>ee,getTokens:()=>ne,setError:()=>se,setOptions:()=>J,triggerDrilldown:()=>ie}),U=new Proxy({},{get(){throw new Error("DashboardExtensionAPI is not available. Make sure to run this code inside a Splunk Dashboard Extension iframe.")}}),F,i=(F=globalThis.DashboardExtensionAPI)!=null?F:U,B=i.addDataSourcesListener,q=i.getDataSources,H=i.addOptionsListener,G=i.getOptions,J=i.setOptions,Q=i.addDimensionsListener,W=i.getDimensions,X=i.addModeListener,Y=i.getMode,Z=i.addThemeListener,ee=i.getTheme,te=i.addTokensListener,ne=i.getTokens,re=i.addDrilldownListener,ie=i.triggerDrilldown,ae=i.addErrorListener,oe=i.getError,se=i.setError,le=i.clearError;(function(){var e=document.createElement("style");e.setAttribute("data-viz",""),e.textContent=`html,
body,
#root {
  margin: 0;
  width: 100%;
  height: 100%;
  overflow: hidden;
  background: transparent !important;
}
.viz-container {
  width: 100%;
  height: 100%;
  position: relative;
  padding: 4px 8px 6px 6px;
  box-sizing: border-box;
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
  font-family:
    "Splunk Platform Sans",
    "Splunk Sans",
    sans-serif;
  background: transparent !important;
  overflow: hidden;
  cursor: pointer;
}
.viz-container:hover .kpi-value {
  filter: brightness(1.12);
}
.viz-container--empty {
  align-items: flex-start;
  justify-content: center;
}
.kpi-value {
  font-size: clamp(2.1rem, 22vw, 3.4rem);
  font-weight: 800;
  letter-spacing: -0.04em;
  line-height: 0.95;
  color: var(--kpi-accent, #f5d76e);
  text-shadow:
    0 1px 2px rgba(0, 0, 0, 0.95),
    0 2px 8px rgba(0, 0, 0, 0.85),
    0 0 16px color-mix(in srgb, var(--kpi-accent, #f5d76e) 50%, transparent);
}
.kpi-label {
  margin-top: 4px;
  font-size: clamp(0.8rem, 7vw, 1.05rem);
  font-weight: 700;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: #ffffff;
  text-shadow: 0 1px 8px rgba(0, 0, 0, 0.95);
}
.kpi-meta {
  display: flex;
  align-items: flex-end;
  gap: 8px;
  margin-top: 4px;
}
.kpi-spark {
  display: block;
  width: 80px;
  height: 20px;
  flex: 0 0 80px;
}
.kpi-trend {
  font-size: 0.9rem;
  font-weight: 800;
  letter-spacing: 0.04em;
  text-shadow: 0 1px 8px rgba(0, 0, 0, 0.95);
}
.kpi-status {
  color: #d7e2ec;
  text-shadow: 0 1px 8px rgba(0, 0, 0, 0.85);
  max-width: 240px;
}
@media (prefers-reduced-motion: reduce) {
  .kpi-value,
  .kpi-spark-line {
    animation: none;
  }
}
`,document.head.appendChild(e)})();var $={light:{text:"#1a1a1a",muted:"#5c6773",accent:"#4e9cf5"},dark:{text:"#f3f7fb",muted:"#d7e2ec",accent:"#f5d76e"}};document.documentElement.style.background="transparent";document.body.style.background="transparent";var _=document.getElementById("root")||document.body;_.style.background="transparent";var r=document.createElement("div");r.className="viz-container";r.setAttribute("role","link");r.tabIndex=0;_.appendChild(r);var o={data:null,loading:!1,options:{},width:0,height:0,theme:"dark",lastLabel:"",lastValue:null};function de(e){var n,t;return String((t=(n=e==null?void 0:e.name)!=null?n:e)!=null?t:"").toLowerCase()}function k(e,n){return(e||[]).findIndex(t=>de(t)===n)}function v(e,n){var t;return n<0||!((t=e==null?void 0:e[n])!=null&&t.length)?null:e[n][0]}function pe(e,n){return n<0||!(e!=null&&e[n])?[]:e[n].map(t=>Number(t)).filter(t=>Number.isFinite(t))}function ce(e){return e==null||e===""?[]:Array.isArray(e)?e.map(Number).filter(Number.isFinite):String(e).split(/[,\s]+/).map(Number).filter(Number.isFinite)}function w(e){return Number.isFinite(e)?e.toLocaleString(void 0,{maximumFractionDigits:2}):"\u2014"}function j(){for(;r.firstChild;)r.removeChild(r.firstChild)}function A(e,n){j(),r.classList.add("viz-container--empty");let t=document.createElement("div");t.className=n,t.textContent=e,r.appendChild(t)}function me(e,n){if(e.length<2)return;let t=80,a=20,m=Math.min(...e),x=Math.max(...e)-m||1,u=e.map((L,g)=>{let l=g/(e.length-1)*t,h=a-(L-m)/x*(a-2)-1;return`${l.toFixed(1)},${h.toFixed(1)}`}),d=document.createElementNS("http://www.w3.org/2000/svg","svg");d.setAttribute("class","kpi-spark"),d.setAttribute("viewBox",`0 0 ${t} ${a}`),d.setAttribute("aria-hidden","true");let s=document.createElementNS("http://www.w3.org/2000/svg","polyline");return s.setAttribute("class","kpi-spark-line"),s.setAttribute("fill","none"),s.setAttribute("stroke",n),s.setAttribute("stroke-width","2"),s.setAttribute("stroke-linecap","round"),s.setAttribute("stroke-linejoin","round"),s.setAttribute("points",u.join(" ")),d.appendChild(s),d}function y(){var S,z,C,I,T;let e=(S=$[o.theme])!=null?S:$.dark,n=(z=o.options.accentColor)!=null?z:e.accent,t=(C=o.options.showTrend)!=null?C:!0;if(r.style.background="transparent",r.style.color=e.text,r.style.setProperty("--kpi-accent",n),r.style.setProperty("--kpi-muted",e.muted),o.loading){A("\u2026","kpi-status"),r.setAttribute("aria-label","KPI tile loading");return}let a=o.data,m=(a==null?void 0:a.fields)||[],p=(a==null?void 0:a.columns)||[];if(!p.length||!((I=p[0])!=null&&I.length)){A("","kpi-status"),r.setAttribute("aria-label","KPI tile with no data");return}let x=k(m,"label"),u=k(m,"value");if(x<0||u<0){A("Need label, value","kpi-status"),r.setAttribute("aria-label","KPI tile missing required search columns");return}let d=String((T=v(p,x))!=null?T:""),s=Number(v(p,u)),L=k(m,"delta"),g=v(p,L),l=g==null||g===""?null:Number(g),h=k(m,"spark"),K=h>=0?ce(v(p,h)):pe(p,u);j(),r.classList.remove("viz-container--empty");let E=document.createElement("div");E.className="kpi-value",E.textContent=w(s),r.appendChild(E);let D=document.createElement("div");D.className="kpi-label",D.textContent=d,r.appendChild(D);let f=document.createElement("div");f.className="kpi-meta";let N=me(K,n);if(N&&f.appendChild(N),t&&Number.isFinite(l)&&l!==0){let b=document.createElement("div"),P=l>0;b.className="kpi-trend",b.style.color=P?"#7ee787":"#ff8b81",b.textContent=`${P?"\u25B2":"\u25BC"} ${w(Math.abs(l))}`,f.appendChild(b)}f.childNodes.length&&r.appendChild(f);let R=t&&Number.isFinite(l)&&l!==0?`, trend ${l>0?"up":"down"} ${w(Math.abs(l))}`:"";r.setAttribute("aria-label",`KPI ${d}: ${w(s)}${R}. Open Observability dashboard`),o.lastLabel=d,o.lastValue=Number.isFinite(s)?s:null}function V(){return{name:o.lastLabel,value:o.lastValue}}c.addDrilldownListener({node:r,action:"customUrl",payloadCallback:V});r.addEventListener("keydown",e=>{e.key!=="Enter"&&e.key!==" "||(e.preventDefault(),c.triggerDrilldown({action:"customUrl",payload:V(),originalEvent:e}))});c.addDataSourcesListener(({dataSources:e,loading:n})=>{var t,a;o.loading=n,o.data=(a=(t=e==null?void 0:e.primary)==null?void 0:t.data)!=null?a:null,y()},{invokeImmediately:!0});c.addOptionsListener(({options:e})=>{o.options=e||{},y()});c.addDimensionsListener(({width:e,height:n})=>{o.width=e,o.height=n,y()},{invokeImmediately:!0});c.addThemeListener(({theme:e})=>{o.theme=e,y()},{invokeImmediately:!0});
