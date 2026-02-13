const http = require('http');
const fs = require('fs');
const path = require('path');
const root = 'C:/Users/seung/dogfinder/build/web';
const mime = {
  '.html':'text/html; charset=utf-8', '.js':'application/javascript; charset=utf-8', '.css':'text/css; charset=utf-8',
  '.json':'application/json; charset=utf-8', '.png':'image/png', '.jpg':'image/jpeg', '.jpeg':'image/jpeg', '.svg':'image/svg+xml',
  '.ico':'image/x-icon', '.wasm':'application/wasm', '.txt':'text/plain; charset=utf-8', '.map':'application/json; charset=utf-8'
};
const server = http.createServer((req, res) => {
  let urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
  if (urlPath === '/') urlPath = '/index.html';
  let filePath = path.join(root, urlPath);
  if (!filePath.startsWith(path.normalize(root))) { res.statusCode = 403; return res.end('Forbidden'); }
  fs.stat(filePath, (err, stat) => {
    if (!err && stat.isDirectory()) filePath = path.join(filePath, 'index.html');
    fs.readFile(filePath, (e, data) => {
      if (e) {
        fs.readFile(path.join(root, 'index.html'), (e2, data2) => {
          if (e2) { res.statusCode = 404; return res.end('Not Found'); }
          res.setHeader('Content-Type', 'text/html; charset=utf-8');
          res.end(data2);
        });
        return;
      }
      const ext = path.extname(filePath).toLowerCase();
      res.setHeader('Content-Type', mime[ext] || 'application/octet-stream');
      res.end(data);
    });
  });
});
server.listen(8080, '127.0.0.1', () => console.log('DogFinder web server listening on http://127.0.0.1:8080'));
