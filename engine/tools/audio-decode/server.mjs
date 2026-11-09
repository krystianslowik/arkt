// Loopback smoke page for WebAudio decodeAudioData (#806).
//
// Serves index.html and the fixtures in ./fixtures, the way a Unity web build
// fetches its audio: application/octet-stream, optionally with
// Content-Encoding br or gzip (path prefix /enc/br/ or /enc/gz/). The page
// decodes every fixture and posts the result back; the server prints it and
// exits 0 when every fixture decoded, 1 otherwise.
//
//   node engine/tools/audio-decode/server.mjs 8806 & SRV=$!
//   <engine binary> --user-data-dir=<throwaway profile> --use-mock-keychain \
//     --no-first-run --no-default-browser-check http://127.0.0.1:8806/ & PID=$!
//   wait $SRV; kill $PID
//
// A build without AAC support fails the aac.* cases with
// "EncodingError: Unable to decode audio data", the error Unity logs before
// "Loading FSB failed for audio clip".

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const fixtures = path.join(here, 'fixtures');
const port = Number(process.argv[2] ?? 8806);

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://127.0.0.1');
  if (req.method === 'POST' && url.pathname === '/result') {
    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
      res.end('ok');
      const result = JSON.parse(body);
      console.log(JSON.stringify(result, null, 1));
      const failed = Object.values(result.decode).filter((v) => !v.startsWith('ok'));
      server.close();
      process.exitCode = failed.length === 0 ? 0 : 1;
    });
    return;
  }
  if (url.pathname === '/') {
    res.setHeader('Content-Type', 'text/html');
    res.end(fs.readFileSync(path.join(here, 'index.html')));
    return;
  }
  const match = url.pathname.match(/^\/(?:enc\/(br|gz)\/)?([a-z0-9]+\.[a-z0-9]+)$/);
  const file = match && path.join(fixtures, match[2]);
  if (!file || !fs.existsSync(file)) {
    res.statusCode = 404;
    res.end();
    return;
  }
  let bytes = fs.readFileSync(file);
  if (match[1] === 'br') {
    bytes = zlib.brotliCompressSync(bytes);
    res.setHeader('Content-Encoding', 'br');
  } else if (match[1] === 'gz') {
    bytes = zlib.gzipSync(bytes);
    res.setHeader('Content-Encoding', 'gzip');
  }
  res.setHeader('Content-Type', 'application/octet-stream');
  res.end(bytes);
});

server.listen(port, '127.0.0.1');
