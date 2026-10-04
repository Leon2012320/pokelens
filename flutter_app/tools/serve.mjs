import http from 'node:http';
import {readFile,stat} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../build/web');
const types={'.html':'text/html; charset=utf-8','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.png':'image/png','.webp':'image/webp','.ttf':'font/ttf','.otf':'font/otf','.svg':'image/svg+xml'};
const port=Number(process.argv[2]||58123);
http.createServer(async(req,res)=>{
  try {
    const relative=decodeURIComponent(new URL(req.url,'http://localhost').pathname).replace(/^\/pokelens(?=\/)/,'');
    let file=path.resolve(root,'.'+relative);
    if(file!==root&&!file.startsWith(root+path.sep)){res.writeHead(403);return res.end();}
    try { if((await stat(file)).isDirectory())file=path.join(file,'index.html'); }
    catch { if(path.extname(file)){res.writeHead(404);return res.end('Not found');} file=path.join(root,'index.html'); }
    const data=await readFile(file);
    res.writeHead(200,{'Content-Type':types[path.extname(file)]||'application/octet-stream','Cache-Control':'no-cache'});
    res.end(data);
  }catch {res.writeHead(500);res.end('Preview unavailable');}
}).listen(port,'127.0.0.1',()=>console.log(`PokéLens preview: http://127.0.0.1:${port}/pokelens/`));
