#!/bin/sh
export PATH=/var/mobile/tools/node/bin:$PATH
cd /var/mobile/scratch/node
echo "=== ITEM4a http server + curl client ==="
node -e '
const http = require("http");
http.createServer((req,res)=>{res.end("hello from node "+process.arch)})
    .listen(8787, "127.0.0.1", ()=>console.log("listening"));
' &
SRV=$!
sleep 2
curl -s http://127.0.0.1:8787/ ; echo " <- curl"
/var/mobile/tools/lsof -nP -i :8787 2>/dev/null | head -3
kill $SRV 2>/dev/null
echo "=== ITEM4b plain http outbound ==="
node -e 'require("http").get("http://nodejs.org/", r=>{console.log("outbound status", r.statusCode); r.resume(); r.on("end",()=>process.exit(0))}).on("error", e=>{console.log("ERR", e.message); process.exit(1)})'
echo "EXIT4B=$?"
echo "=== ITEM4c dns ==="
node -e 'require("dns").lookup("nodejs.org",(e,a)=>{console.log("dns", a); process.exit(0)})'
