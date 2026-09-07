// Executes the app module's top level with a permissive DOM stub, to surface any runtime throw during startup.
import fs from "node:fs";
const src=fs.readFileSync(process.argv[2],"utf8");
const m=/<script type="module">([\s\S]*?)<\/script>/.exec(src);
if(!m){ console.error("no module script"); process.exit(2); }
const code=m[1];
const noop=()=>{};
const mk=()=>new Proxy(function(){}, {
  get(t,p){ if(p==="then") return undefined; if(p===Symbol.toPrimitive) return ()=>""; if(p==="length") return 0;
            if(p==="classList") return {add:noop,remove:noop,toggle:noop,contains:()=>false};
            if(p==="style") return new Proxy({},{get:()=>"",set:()=>true});
            if(p==="dataset") return {};
            if(p==="querySelectorAll") return ()=>[];
            if(p==="querySelector") return ()=>mk();
            if(p==="getContext") return ()=>mk();
            if(p==="getItem") return ()=>null;
            if(p==="matches") return ()=>false;
            return mk(); },
  set(){ return true; }, apply(){ return mk(); }, construct(){ return mk(); }, has(){ return true; }
});
const doc=mk();
globalThis.window=globalThis; globalThis.document=doc; Object.defineProperty(globalThis,"navigator",{value:{userAgent:"node",vibrate:noop,mediaDevices:{},geolocation:{},serviceWorker:{register:()=>Promise.resolve()}},configurable:true});
globalThis.localStorage={getItem:()=>null,setItem:noop,removeItem:noop}; globalThis.history={pushState:noop,replaceState:noop,state:null};
globalThis.location={hash:"",search:"",href:"",pathname:"/"}; globalThis.store=mk(); globalThis.supabase=mk();
globalThis.matchMedia=()=>({matches:false,addEventListener:noop,addListener:noop});
globalThis.requestAnimationFrame=noop; globalThis.speechSynthesis={speak:noop,cancel:noop}; globalThis.SpeechSynthesisUtterance=function(){};
globalThis.MediaRecorder=function(){}; globalThis.URL=globalThis.URL||{createObjectURL:noop,revokeObjectURL:noop};
globalThis.addEventListener=noop; globalThis.removeEventListener=noop; globalThis.setInterval=()=>0; globalThis.setTimeout=()=>0;
globalThis.MutationObserver=function(){this.observe=noop}; globalThis.ResizeObserver=function(){this.observe=noop}; globalThis.IntersectionObserver=function(){this.observe=noop};
globalThis.fetch=()=>new Promise(()=>{});
const stubbed=code.replace(/^\s*import\s+([^;]+?)\s+from\s+"https?:[^"]+"\s*;?/gm,(all,spec)=>{
  const names=[]; const m1=/\{([^}]*)\}/.exec(spec); if(m1){ for(const part of m1[1].split(",")){ const nm=part.trim().split(/\s+as\s+/).pop().trim(); if(nm) names.push(nm); } }
  const def=spec.replace(/\{[^}]*\}/,"").replace(/,/g,"").trim(); if(def && !/^\*/.test(def)) names.push(def);
  return "const "+names.map(n=>n+"=globalThis.__mk()").join(",")+";"; });
globalThis.__mk=mk;
fs.writeFileSync(process.argv[3], stubbed);
try{ await import("file://"+process.argv[3]); console.log("TOP-LEVEL OK: module evaluated without throwing"); }
catch(e){ console.log("TOP-LEVEL THROW:", e && e.stack ? e.stack.split("\n").slice(0,6).join("\n") : e); }
