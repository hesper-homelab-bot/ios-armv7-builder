const http=require("http");
const s=http.createServer((req,res)=>{res.end("hi-ipad")});
s.listen(18080,"127.0.0.1",()=>{
  const r=http.get("http://127.0.0.1:18080/",(res2)=>{
    let d="";
    res2.on("data",(c)=>d+=c);
    res2.on("end",()=>{
      console.log("http roundtrip:",d,res2.statusCode);
      s.close(); process.exit(0);
    });
  });
});
