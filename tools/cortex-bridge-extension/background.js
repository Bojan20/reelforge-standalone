// CORTEX Bridge — Background Service Worker
//
// Manages WebSocket connection to CORTEX daemon (Rust WsServer on port 9742).
// Routes messages between content script (ChatGPT tab) and CORTEX.
//
// PROTOCOL (must match rf-gpt-bridge/src/protocol.rs):
//   CORTEX → Extension: BrowserCommand (tagged JSON with "type" field)
//     - { type: "query", id, content, intent, urgency }
//     - { type: "ping", ts }
//     - { type: "new_chat" }
//   Extension → CORTEX: BrowserEvent (tagged JSON with "type" field)
//     - { type: "response", id, content, streaming }
//     - { type: "connected", user_agent, model }
//     - { type: "pong", ts }
//     - { type: "error", id, message, code }
//     - { type: "busy", id }
//     - { type: "chat_cleared" }
//     - { type: "status", ready, model, message_count }

const CORTEX_WS_URL = 'ws://127.0.0.1:9742';
const RECONNECT_INTERVAL_MS = 3000;

let ws = null;
let reconnectTimer = null;
let contentPort = null;
let state = 'disconnected'; // disconnected | connecting | connected
let stats = { messagesSent: 0, messagesReceived: 0, reconnects: 0 };

// ═══════════════════════════════════════════════════════════════════════════════
// WEBSOCKET CONNECTION TO CORTEX
// ═══════════════════════════════════════════════════════════════════════════════

function connectToCortex() {
  if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
    return;
  }

  state = 'connecting';
  broadcastState();

  try {
    ws = new WebSocket(CORTEX_WS_URL);
  } catch (e) {
    console.error('[CORTEX Bridge] WebSocket creation failed:', e);
    state = 'disconnected';
    broadcastState();
    scheduleReconnect();
    return;
  }

  ws.onopen = () => {
    console.log('[CORTEX Bridge] Connected to CORTEX daemon at', CORTEX_WS_URL);
    state = 'connected';
    stats.reconnects++;
    broadcastState();

    // Send BrowserEvent::Connected
    wsSend({
      type: 'connected',
      user_agent: 'CORTEX Chrome Extension v1.0',
      model: null // Will be detected from ChatGPT page
    });
  };

  ws.onmessage = (event) => {
    stats.messagesReceived++;
    let msg;
    try {
      msg = JSON.parse(event.data);
    } catch (e) {
      console.error('[CORTEX Bridge] Invalid JSON from CORTEX:', event.data);
      return;
    }

    console.log('[CORTEX Bridge] ← CORTEX:', msg.type);
    handleCortexCommand(msg);
  };

  ws.onclose = (event) => {
    console.log('[CORTEX Bridge] Disconnected:', event.code, event.reason);
    state = 'disconnected';
    broadcastState();
    scheduleReconnect();
  };

  ws.onerror = () => {
    console.error('[CORTEX Bridge] WebSocket error');
  };
}

function wsSend(msg) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(msg));
    stats.messagesSent++;
    return true;
  }
  return false;
}

function scheduleReconnect() {
  clearTimeout(reconnectTimer);
  reconnectTimer = setTimeout(connectToCortex, RECONNECT_INTERVAL_MS);
}

// ═══════════════════════════════════════════════════════════════════════════════
// HANDLE COMMANDS FROM CORTEX (BrowserCommand enum)
// ═══════════════════════════════════════════════════════════════════════════════

function handleCortexCommand(cmd) {
  switch (cmd.type) {
    case 'query':
      // BrowserCommand::Query { id, content, intent, urgency }
      // Forward to content script to inject into ChatGPT
      forwardToContent({
        type: 'inject_and_send',
        id: cmd.id,
        content: cmd.content,
        intent: cmd.intent,
        urgency: cmd.urgency
      });
      break;

    case 'ping':
      // BrowserCommand::Ping { ts }
      // Respond with BrowserEvent::Pong { ts }
      wsSend({ type: 'pong', ts: cmd.ts });
      break;

    case 'new_chat':
      // BrowserCommand::NewChat
      forwardToContent({ type: 'new_chat' });
      break;

    default:
      console.warn('[CORTEX Bridge] Unknown command from CORTEX:', cmd.type);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONTENT SCRIPT COMMUNICATION
// ═══════════════════════════════════════════════════════════════════════════════

chrome.runtime.onConnect.addListener((port) => {
  if (port.name !== 'cortex-bridge') return;

  console.log('[CORTEX Bridge] Content script connected');
  contentPort = port;

  port.onMessage.addListener((msg) => {
    handleContentMessage(msg);
  });

  port.onDisconnect.addListener(() => {
    console.log('[CORTEX Bridge] Content script disconnected');
    contentPort = null;
  });

  // Tell CORTEX that ChatGPT is ready
  wsSend({
    type: 'status',
    ready: true,
    model: null,
    message_count: 0
  });
});

function forwardToContent(msg) {
  if (contentPort) {
    contentPort.postMessage(msg);
    return true;
  }
  console.warn('[CORTEX Bridge] No content script — ChatGPT tab not open');
  // Send error back to CORTEX
  if (msg.id) {
    wsSend({
      type: 'error',
      id: msg.id,
      message: 'ChatGPT tab is not open or extension not injected',
      code: 'no_tab'
    });
  }
  return false;
}

function handleContentMessage(msg) {
  // Content script results → convert to BrowserEvent and send to CORTEX
  switch (msg.type) {
    case 'response':
      // BrowserEvent::Response { id, content, streaming }
      wsSend({
        type: 'response',
        id: msg.id,
        content: msg.content,
        streaming: msg.streaming || false
      });
      break;

    case 'error':
      // BrowserEvent::Error { id, message, code }
      wsSend({
        type: 'error',
        id: msg.id || null,
        message: msg.message,
        code: msg.code || 'content_error'
      });
      break;

    case 'busy':
      // BrowserEvent::Busy { id }
      wsSend({ type: 'busy', id: msg.id });
      break;

    case 'chat_cleared':
      // BrowserEvent::ChatCleared
      wsSend({ type: 'chat_cleared' });
      break;

    case 'status':
      // BrowserEvent::Status
      wsSend({
        type: 'status',
        ready: msg.ready,
        model: msg.model || null,
        message_count: msg.message_count || 0
      });
      break;

    default:
      // Forward as-is
      wsSend(msg);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STATE BROADCASTING (for popup UI)
// ═══════════════════════════════════════════════════════════════════════════════

function broadcastState() {
  chrome.runtime.sendMessage({
    type: 'state_update',
    state,
    stats,
    hasContentScript: !!contentPort
  }).catch(() => {});
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === 'get_state') {
    sendResponse({ state, stats, hasContentScript: !!contentPort });
    return true;
  }
  if (msg.type === 'reconnect') {
    connectToCortex();
    sendResponse({ ok: true });
    return true;
  }
});

// ═══════════════════════════════════════════════════════════════════════════════
// STARTUP
// ═══════════════════════════════════════════════════════════════════════════════

connectToCortex();
console.log('[CORTEX Bridge] Background service worker started');
