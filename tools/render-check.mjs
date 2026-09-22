// CN-17: execute the renderers. Parsing catches syntax; the top-level check catches
// startup throws; this catches what a renderer does when actually RUN - a ReferenceError
// in a branch, a TypeError on a Supabase builder (rpc(...).catch), an undefined helper.
// It is a smoke test: it asserts "does not throw", not correctness.
// usage: node tools/render-check.mjs index.html /tmp/ft_render.mjs
import fs from "node:fs";
const src=fs.readFileSync(process.argv[2],"utf8");
const m=/<script type="module">([\s\S]*?)<\/script>/.exec(src);
if(!m){ console.error("no module script"); process.exit(2); }
let code=m[1];
const noop=()=>{};
// ---- permissive DOM proxy (iterable, so [...x] and new Set(x) work) ----
const mk=()=>new Proxy(function(){}, {
  get(t,p){ if(p==="then") return undefined; if(p===Symbol.toPrimitive) return ()=>""; if(p===Symbol.iterator) return function*(){};
            if(p==="length") return 0; if(p==="classList") return {add:noop,remove:noop,toggle:noop,contains:()=>false};
            if(p==="style") return new Proxy({},{get:()=>"",set:()=>true}); if(p==="dataset") return {};
            if(p==="querySelectorAll") return ()=>[]; if(p==="querySelector") return ()=>mk(); if(p==="getContext") return ()=>mk();
            if(p==="getItem") return ()=>null; if(p==="matches") return ()=>false; if(p==="getBoundingClientRect") return ()=>({width:100,height:100,left:0,top:0});
            if(p==="children") return []; if(p==="parentElement") return mk(); if(p==="value"||p==="textContent"||p==="innerHTML") return "";
            return mk(); },
  set(){ return true; }, apply(){ return mk(); }, construct(){ return mk(); }, has(){ return true; }
});
// ---- Supabase-like builder: thenable, chainable, NO .catch (that is the point) ----
const result={data:[],error:null,count:0};
const builder=()=>new Proxy({}, { get(t,p){
  if(p==="then") return (res,rej)=>Promise.resolve(result).then(res,rej);
  if(p==="catch"||p==="finally") return undefined;
  if(p===Symbol.toPrimitive) return ()=>"";
  return ()=>builder(); } });
const storeStub=new Proxy({}, { get(t,p){
  if(p==="_sb") return { from:()=>builder(), rpc:()=>builder(), auth:{getUser:()=>Promise.resolve({data:{user:{id:"u1"}}})}, storage:{from:()=>({createSignedUrl:()=>Promise.resolve({data:{signedUrl:"blob:x"}})})} };
  if(p==="auth") return new Proxy({ currentUser:()=>Promise.resolve({id:"u1"}), updateProfile:()=>Promise.resolve({}), myProfile:()=>Promise.resolve(null), onAuthStateChange:()=>({data:{subscription:{unsubscribe:noop}}}) },{ get:(o,k)=>k in o?o[k]:(()=>Promise.resolve(mk())) });
  // store.<name> may be a namespace (store.logs.list()) or a function (store.coaches(), store.videoMeta(paths)) - be both
  return new Proxy(function(){}, { get:(o,k)=>(k==="then"?undefined:(()=>Promise.resolve(mk()))), apply:()=>Promise.resolve(mk()) });
} });
globalThis.window=globalThis; globalThis.document=mk(); Object.defineProperty(globalThis,"navigator",{value:{userAgent:"node",vibrate:noop,mediaDevices:{},geolocation:{getCurrentPosition:noop},serviceWorker:{register:()=>Promise.resolve(),getRegistration:()=>Promise.resolve(null),ready:Promise.resolve({pushManager:{getSubscription:()=>Promise.resolve(null)}})},clipboard:{writeText:()=>Promise.resolve()}},configurable:true});
globalThis.localStorage={getItem:()=>null,setItem:noop,removeItem:noop}; globalThis.history={pushState:noop,replaceState:noop,state:null};
globalThis.location={hash:"",search:"",href:"",pathname:"/",origin:"https://x"}; globalThis.store=storeStub; globalThis.supabase=mk();
globalThis.matchMedia=()=>({matches:false,addEventListener:noop,addListener:noop});
globalThis.requestAnimationFrame=noop; globalThis.speechSynthesis={speak:noop,cancel:noop}; globalThis.SpeechSynthesisUtterance=function(){};
globalThis.MediaRecorder=function(){}; globalThis.URL=globalThis.URL||{createObjectURL:noop,revokeObjectURL:noop};
globalThis.addEventListener=noop; globalThis.removeEventListener=noop; globalThis.setInterval=()=>0;
globalThis.MutationObserver=function(){this.observe=noop}; globalThis.ResizeObserver=function(){this.observe=noop}; globalThis.IntersectionObserver=function(){this.observe=noop};
globalThis.fetch=()=>Promise.resolve({ok:true,status:200,json:()=>Promise.resolve({}),headers:{get:()=>""}});
globalThis.Notification={permission:"default",requestPermission:()=>Promise.resolve("denied")};
const realSetTimeout=setTimeout; globalThis.setTimeout=()=>0;
code=code.replace(/^\s*import\s+([^;]+?)\s+from\s+"https?:[^"]+"\s*;?/gm,(all,spec)=>{
  const names=[]; const m1=/\{([^}]*)\}/.exec(spec); if(m1){ for(const part of m1[1].split(",")){ const nm=part.trim().split(/\s+as\s+/).pop().trim(); if(nm) names.push(nm); } }
  const def=spec.replace(/\{[^}]*\}/,"").replace(/,/g,"").trim(); if(def && !/^\*/.test(def)) names.push(def);
  return "const "+names.map(n=>n+"=globalThis.__mk()").join(",")+";"; });
globalThis.__mk=mk;
const names=[...new Set([...code.matchAll(/^\s*(?:async\s+)?function\s+(render\w+)\s*\(/gm)].map(x=>x[1]))];
code+=`\nglobalThis.__ft={ set(me,eng){ ME=me; try{ currentEng=eng; currentEngOther={id:"u2",display_name:"Other"}; traineeEngs=[eng]; }catch(e){} }, fns:{} };\n`+names.map(n=>`try{ globalThis.__ft.fns.${n}=${n}; }catch(e){}`).join("\n")+"\n";
fs.writeFileSync(process.argv[3], code);
await import("file://"+process.argv[3]);
const ft=globalThis.__ft;
const profiles={
  trainee:{id:"u1",role:"trainee",display_name:"Test Trainee",week_streak_count:3,push_prefs:{},is_admin:false},
  coach:{id:"u1",role:"coach",display_name:"Test Coach",week_streak_count:0,push_prefs:{},is_admin:true}
};
const SKIP=new Set(["renderBuilderItems","renderIvEditor","renderGoals"]);   // need an open editor / retired screen
let failures=0, ran=0;
const wait=(p)=>Promise.race([p, new Promise(res=>realSetTimeout(()=>res("timeout"),1500))]);
// renderers that log-and-swallow still surface here: watch console.error for the throw signatures
const origErr=console.error; let softFails=[]; console.error=(...a)=>{ const s=a.map(x=>x&&x.message||String(x)).join(" "); if(/is not a function|is not defined|Cannot read propert|is not iterable/.test(s)) softFails.push(s.slice(0,160)); };
for(const role of ["trainee","coach"]){
  ft.set(profiles[role],{id:"e1",coach_id:role==="coach"?"u1":"u2",trainee_id:role==="trainee"?"u1":"u2",status:"active",goal_title:"Test goal",started_at:"2026-09-01T00:00:00Z",workouts_per_week_cap:3,level:1});
  for(const name of names){
    if(SKIP.has(name)) continue;
    const fn=ft.fns[name]; if(typeof fn!=="function") continue;
    ran++;
    try{
      const r=fn(mk(),mk(),mk(),mk());
      if(r && typeof r.then==="function"){ await wait(r); }
    }catch(e){
      const msg=String(e && e.message || e);
      if(/is not a function|is not defined|Cannot read propert|is not iterable|Assignment to constant|before initialization/.test(msg)){
        failures++; console.log(`  FAIL  ${name} (${role}): ${msg}`);
      }
    }
  }
}
console.error=origErr;
for(const s of [...new Set(softFails)]){ failures++; console.log(`  FAIL  (caught inside a renderer) ${s}`); }
console.log(failures? `RENDER CHECK: ${failures} failure(s) in ${ran} calls` : `RENDER CHECK OK: ${ran} renderer calls, no throws`);
process.exit(failures?1:0);
