const http = require('http');
const https = require('https');
const tls = require('tls');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const ROOT = __dirname;
const RSC_DIR = path.join(ROOT, 'rsc');
const PORT = process.env.PORT || 3000;

// Reuse TLS connections to the origin for proxied API calls.
const proxyAgent = new https.Agent({ keepAlive: true, maxSockets: 16 });

function rscName(route) {
  const safe = route.replace(/^\/+/, '').replace(/\//g, '__') || 'index';
  return safe + '.rsc';
}

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ico': 'image/x-icon',
  '.txt': 'text/plain; charset=utf-8',
  '.xml': 'application/xml; charset=utf-8',
};

const COMPRESSIBLE = new Set(['.html', '.js', '.css', '.json', '.svg', '.txt', '.xml']);

function safePath(root, pathname) {
  const decoded = decodeURIComponent(pathname);
  const resolved = path.resolve(root, '.' + decoded);
  if (resolved !== root && !resolved.startsWith(root + path.sep)) return null;
  return resolved;
}

function sendFile(res, filePath, req) {
  const ext = path.extname(filePath).toLowerCase();
  const type = MIME[ext] || 'application/octet-stream';
  const stat = fs.statSync(filePath);
  const acceptEncoding = (req.headers['accept-encoding'] || '');
  let encoding = null;
  if (COMPRESSIBLE.has(ext)) {
    if (acceptEncoding.includes('gzip')) encoding = 'gzip';
    else if (acceptEncoding.includes('deflate')) encoding = 'deflate';
  }
  // Caching: hashed _next assets are immutable; others revalidate.
  const immutable = filePath.includes(path.sep + '_next' + path.sep);
  const cacheControl = immutable
    ? 'public, max-age=31536000, immutable'
    : 'public, max-age=0, must-revalidate';

  const headers = {
    'Content-Type': type,
    'Cache-Control': cacheControl,
    'Content-Length': stat.size,
  };
  if (encoding) {
    delete headers['Content-Length'];
    res.writeHead(200, Object.assign(headers, { 'Content-Encoding': encoding, 'Vary': 'Accept-Encoding' }));
    const stream = fs.createReadStream(filePath);
    const comp = encoding === 'gzip' ? zlib.createGzip() : zlib.createDeflate();
    stream.pipe(comp).pipe(res);
  } else {
    res.writeHead(200, headers);
    fs.createReadStream(filePath).pipe(res);
  }
}

const server = http.createServer((req, res) => {
  let url;
  try {
    url = new URL(req.url, 'http://localhost');
  } catch (e) {
    res.statusCode = 400;
    res.end('bad request');
    return;
  }
  const pathname = url.pathname;
  const isRsc = url.searchParams.has('_rsc');

  // Proxy API requests to the origin so the game can load live data.
  if (pathname === '/api' || pathname.startsWith('/api/')) {
    const target = 'https://krillion.io' + req.url;
    const proxyReq = https.request(target, {
      method: req.method,
      agent: proxyAgent,
      headers: Object.assign({}, req.headers, { host: 'krillion.io' }),
      timeout: 30000,
    }, (proxyRes) => {
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res);
    });
    proxyReq.on('timeout', () => { proxyReq.destroy(); });
    proxyReq.on('error', (e) => {
      if (!res.headersSent) {
        res.statusCode = 502;
        res.end('proxy error: ' + e.message);
      }
    });
    req.on('error', () => proxyReq.destroy());
    req.pipe(proxyReq);
    return;
  }

  if (isRsc) {
    const name = rscName(pathname);
    const filePath = path.join(RSC_DIR, name);
    if (fs.existsSync(filePath)) {
      res.setHeader('Content-Type', 'text/x-component; charset=utf-8');
      res.setHeader('Cache-Control', 'public, max-age=0, must-revalidate');
      fs.createReadStream(filePath).pipe(res);
      return;
    }
    res.statusCode = 404;
    res.end('not found');
    return;
  }

  const filePath = safePath(ROOT, pathname);
  if (!filePath) {
    res.statusCode = 403;
    res.end('forbidden');
    return;
  }
  let resolved = filePath;
  try {
    const st = fs.statSync(resolved);
    if (st.isDirectory()) resolved = path.join(resolved, 'index.html');
  } catch (e) {
    const alt = path.join(filePath, 'index.html');
    if (fs.existsSync(alt)) resolved = alt;
  }
  if (!fs.existsSync(resolved)) {
    res.statusCode = 404;
    res.end('not found');
    return;
  }
  try {
    sendFile(res, resolved, req);
  } catch (e) {
    if (!res.headersSent) {
      res.statusCode = 500;
      res.end('server error');
    }
  }
});

// Proxy WebSocket upgrades (party mode) to the origin.
server.on('upgrade', (req, socket, head) => {
  const target = 'krillion.io';
  const tlsSocket = tls.connect(443, target, { servername: target }, () => {
    let reqLine = req.method + ' ' + req.url + ' HTTP/1.1\r\n';
    for (const [k, v] of Object.entries(req.headers)) {
      if (k.toLowerCase() === 'host') reqLine += 'Host: ' + target + '\r\n';
      else reqLine += k + ': ' + v + '\r\n';
    }
    reqLine += '\r\n';
    tlsSocket.write(reqLine);
    if (head && head.length) tlsSocket.write(head);
    tlsSocket.pipe(socket);
    socket.pipe(tlsSocket);
  });
  tlsSocket.setTimeout(30000, () => tlsSocket.destroy());
  tlsSocket.on('error', () => socket.destroy());
  socket.on('error', () => tlsSocket.destroy());
});

server.listen(PORT, () => {
  console.log('Krillion mirror running at http://localhost:' + PORT);
});
