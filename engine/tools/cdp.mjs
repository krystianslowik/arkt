#!/usr/bin/env node
// Evaluates a JavaScript expression (or navigates) in a DevTools target.
//
// Usage:
//   node cdp.mjs [--port 9333] [--user-gesture] [--navigate] <match> '<expression or url>'
//
// <match> is a substring of the target URL, or type:<target type>
// (page, service_worker, background_page). The first matching target from
// http://127.0.0.1:<port>/json/list is used.
//
// --user-gesture  evaluates with userGesture: true, so the call counts as a
//                 user activation (popup blocker, fullscreen, pickers).
// --navigate      sends Page.navigate {url} instead of Runtime.evaluate
//                 (a browser-initiated navigation, e.g. chrome://crash).
//
// Prints JSON.stringify(result) and exits 0; on any CDP error or page
// exception prints the error text to stderr and exits 1. No dependencies:
// uses Node's global fetch and WebSocket.

const USAGE =
  "usage: node cdp.mjs [--port 9333] [--user-gesture] [--navigate] <match> '<expression or url>'";
const TIMEOUT_MS = 15000;

function fail(message) {
  process.stderr.write(`cdp: ${message}\n`);
  process.exit(1);
}

function parseArgs(argv) {
  const opts = { port: 9333, userGesture: false, navigate: false };
  const rest = [];
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--port") {
      opts.port = Number(argv[++i]);
      if (!Number.isInteger(opts.port)) fail(`bad --port\n${USAGE}`);
    } else if (arg === "--user-gesture") {
      opts.userGesture = true;
    } else if (arg === "--navigate") {
      opts.navigate = true;
    } else {
      rest.push(arg);
    }
  }
  if (rest.length !== 2) fail(USAGE);
  [opts.match, opts.payload] = rest;
  return opts;
}

function matches(target, match) {
  if (match.startsWith("type:")) return target.type === match.slice(5);
  return target.url.includes(match);
}

async function findTarget(port, match) {
  let list;
  try {
    const res = await fetch(`http://127.0.0.1:${port}/json/list`);
    list = await res.json();
  } catch (e) {
    fail(`cannot read /json/list on port ${port}: ${e.message}`);
  }
  const target = list.find((t) => t.webSocketDebuggerUrl && matches(t, match));
  if (!target) {
    const known = list.map((t) => `  ${t.type} ${t.url}`).join("\n");
    fail(`no target matches "${match}"; targets:\n${known}`);
  }
  return target;
}

function send(wsUrl, method, params) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    const timer = setTimeout(() => {
      ws.close();
      reject(new Error(`timeout after ${TIMEOUT_MS} ms waiting for ${method}`));
    }, TIMEOUT_MS);
    ws.onopen = () => ws.send(JSON.stringify({ id: 1, method, params }));
    ws.onerror = (event) => {
      clearTimeout(timer);
      reject(new Error(event.message || "WebSocket error"));
    };
    ws.onmessage = (event) => {
      const msg = JSON.parse(event.data);
      if (msg.id !== 1) return;
      clearTimeout(timer);
      ws.close();
      resolve(msg);
    };
  });
}

const opts = parseArgs(process.argv.slice(2));
const target = await findTarget(opts.port, opts.match);

let msg;
try {
  if (opts.navigate) {
    msg = await send(target.webSocketDebuggerUrl, "Page.navigate", {
      url: opts.payload,
    });
  } else {
    const params = {
      expression: opts.payload,
      awaitPromise: true,
      returnByValue: true,
    };
    if (opts.userGesture) params.userGesture = true;
    msg = await send(target.webSocketDebuggerUrl, "Runtime.evaluate", params);
  }
} catch (e) {
  fail(e.message);
}

if (msg.error) fail(`${msg.error.message}${msg.error.data ? `: ${msg.error.data}` : ""}`);
if (opts.navigate) {
  if (msg.result.errorText) fail(msg.result.errorText);
  process.stdout.write(`${JSON.stringify(msg.result)}\n`);
} else {
  const { result, exceptionDetails } = msg.result;
  if (exceptionDetails) {
    fail(exceptionDetails.exception?.description ?? exceptionDetails.text);
  }
  process.stdout.write(`${JSON.stringify(result.value)}\n`);
}
