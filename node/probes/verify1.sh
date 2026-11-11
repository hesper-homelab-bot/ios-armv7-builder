#!/bin/sh
export PATH=/var/mobile/tools/node/bin:$PATH
mkdir -p /var/mobile/scratch/node
cd /var/mobile/scratch/node
echo "=== ITEM1 wrapper/engine separation ==="
head -c 4 /var/mobile/tools/node/bin/node; echo " (want #!/b)"
head -c 4 /var/mobile/tools/node/bin/node.real | od -An -tx1 | head -1
ldid -e /var/mobile/tools/node/bin/node.real >/dev/null 2>&1 && echo "signature present"
echo "=== ITEM2a jitless in v8 options ==="
node --jitless --v8-options 2>/dev/null | grep -A1 "jitless" | head -3
echo "=== ITEM2c hot loop survives ==="
node -e 'function f(x){return x*2} let s=0; for(let i=0;i<1e6;i++) s=f(i); console.log("survived", s)'
echo "=== ITEM3 modules ==="
node -e 'const fs=require("fs"); console.log(typeof fs.readFileSync)'
node -e 'const c=require("crypto"); console.log(c.createHash("sha256").update("abc").digest("hex"))'
node -e 'console.log(require("os").arch(), require("path").join("a","b"))'
printf 'import fs from "node:fs"; console.log("esm ok", typeof fs.readFileSync)' > t.mjs
node t.mjs
echo "=== ITEM5 buffers+timers ==="
node -e 'console.log(Buffer.from("aGk=","base64").toString())'
node -e 'console.log(Buffer.alloc(4).length, Buffer.from([1,2,3]).toString("hex"))'
node -e 'let n=0; const t=setInterval(()=>{ if(++n===3){clearInterval(t); console.log("ticks",n)} },100)'
node -e 'setTimeout(()=>console.log("timed out"), 50)'
node -e 'const fs=require("fs"); fs.writeFileSync("/var/mobile/scratch/node/w.txt","x"); fs.readFile("/var/mobile/scratch/node/w.txt",(e,d)=>console.log("async",d.toString()))'
node -e 'require("crypto").pbkdf2("p","s",1000,32,"sha256",(e,k)=>console.log("pbkdf2",k.length))'
echo "=== ITEM6 cpu/mem ==="
node -e 'const c=require("os").cpus(); console.log(c.length, c[0].model, c[0].speed)'
node -e 'console.log(require("os").totalmem(), require("os").freemem(), require("os").endianness())'
echo "=== ALL-DONE ==="
