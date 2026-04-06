// CORTEX Bridge — Content Script
//
// Runs inside the ChatGPT tab (chatgpt.com / chat.openai.com).
// Receives commands from background script, manipulates ChatGPT DOM:
//   - Injects text into the input field
//   - Clicks send
//   - Watches for streaming completion
//   - Extracts GPT responses
//
// Sends results back as BrowserEvent types (matching rf-gpt-bridge protocol).

(() => {
  'use strict';

  // ═══════════════════════════════════════════════════════════════════════════
  // SELECTORS — ChatGPT DOM (2025/2026 ProseMirror-based UI)
  // Multiple fallbacks for resilience against DOM changes
  // ═══════════════════════════════════════════════════════════════════════════

  const SEL = {
    textarea: [
      '#prompt-textarea',
      'div[contenteditable="true"].ProseMirror',
      'div[contenteditable="true"][data-placeholder]',
      'textarea[data-id="root"]'
    ],
    sendBtn: [
      'button[data-testid="send-button"]',
      'button[aria-label*="Send"]',
      'form button[type="submit"]'
    ],
    stopBtn: [
      'button[data-testid="stop-button"]',
      'button[aria-label*="Stop"]'
    ],
    assistantMsg: ['div[data-message-author-role="assistant"]'],
    newChatBtn: [
      'nav a[href="/"]',
      'a[data-testid="create-new-chat-button"]'
    ],
    streaming: ['.result-streaming', '[class*="result-streaming"]']
  };

  function $(selectors) {
    for (const s of (typeof selectors === 'string' ? [selectors] : selectors)) {
      const el = document.querySelector(s);
      if (el) return el;
    }
    return null;
  }

  function $$(selectors) {
    for (const s of (typeof selectors === 'string' ? [selectors] : selectors)) {
      const els = document.querySelectorAll(s);
      if (els.length > 0) return Array.from(els);
    }
    return [];
  }

  const sleep = ms => new Promise(r => setTimeout(r, ms));

  // ═══════════════════════════════════════════════════════════════════════════
  // CONNECTION TO BACKGROUND
  // ═══════════════════════════════════════════════════════════════════════════

  let port = null;
  let connected = false;

  function connect() {
    try {
      port = chrome.runtime.connect({ name: 'cortex-bridge' });
      connected = true;

      port.onMessage.addListener(handleCommand);
      port.onDisconnect.addListener(() => {
        connected = false;
        setTimeout(connect, 2000);
      });

      console.log('[CORTEX] Content script connected');
    } catch (e) {
      setTimeout(connect, 3000);
    }
  }

  function send(msg) {
    if (connected && port) {
      try { port.postMessage(msg); } catch (_) { connected = false; }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMMAND HANDLER (from background, originally from CORTEX Rust)
  // ═══════════════════════════════════════════════════════════════════════════

  function handleCommand(msg) {
    switch (msg.type) {
      case 'inject_and_send':
        // BrowserCommand::Query — inject content and send to ChatGPT
        injectAndSend(msg.id, msg.content);
        break;

      case 'new_chat':
        // BrowserCommand::NewChat
        startNewChat();
        break;

      default:
        console.warn('[CORTEX] Unknown command:', msg.type);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INJECT TEXT AND SEND TO CHATGPT
  // ═══════════════════════════════════════════════════════════════════════════

  async function injectAndSend(requestId, content) {
    try {
      // Check if ChatGPT is currently busy (still generating)
      if ($(SEL.stopBtn)) {
        send({ type: 'busy', id: requestId });
        return;
      }

      const textarea = $(SEL.textarea);
      if (!textarea) {
        send({
          type: 'error', id: requestId,
          message: 'Could not find ChatGPT input field',
          code: 'textarea_not_found'
        });
        return;
      }

      textarea.focus();

      // ProseMirror contenteditable (current ChatGPT UI)
      if (textarea.contentEditable === 'true' || textarea.classList.contains('ProseMirror')) {
        textarea.innerHTML = '';
        const lines = content.split('\n');
        for (const line of lines) {
          const p = document.createElement('p');
          p.textContent = line || '\u200B';
          textarea.appendChild(p);
        }
        textarea.dispatchEvent(new Event('input', { bubbles: true }));
      }
      // Classic textarea fallback
      else if (textarea.tagName === 'TEXTAREA') {
        const setter = Object.getOwnPropertyDescriptor(
          HTMLTextAreaElement.prototype, 'value'
        ).set;
        setter.call(textarea, content);
        textarea.dispatchEvent(new Event('input', { bubbles: true }));
      }
      // Generic fallback
      else {
        textarea.textContent = content;
        textarea.dispatchEvent(new Event('input', { bubbles: true }));
      }

      // Wait for React to process and enable send button
      await sleep(200);

      const sendBtn = $(SEL.sendBtn);
      if (!sendBtn) {
        send({
          type: 'error', id: requestId,
          message: 'Could not find send button',
          code: 'send_btn_not_found'
        });
        return;
      }

      if (sendBtn.disabled) {
        await sleep(300);
        const retry = $(SEL.sendBtn);
        if (!retry || retry.disabled) {
          send({
            type: 'error', id: requestId,
            message: 'Send button remained disabled after injection',
            code: 'send_btn_disabled'
          });
          return;
        }
        retry.click();
      } else {
        sendBtn.click();
      }

      console.log('[CORTEX] Message injected and sent, waiting for response...');

      // Send streaming updates while waiting
      const responseText = await waitForResponse(requestId);

      // Send final BrowserEvent::Response
      send({
        type: 'response',
        id: requestId,
        content: responseText,
        streaming: false
      });

    } catch (e) {
      send({
        type: 'error', id: requestId,
        message: e.message,
        code: 'injection_error'
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WAIT FOR CHATGPT RESPONSE (streaming completion)
  // ═══════════════════════════════════════════════════════════════════════════

  function waitForResponse(requestId) {
    return new Promise((resolve) => {
      const TIMEOUT_MS = 300000; // 5 min max
      const STREAM_INTERVAL_MS = 1000;
      let lastText = '';

      const timeout = setTimeout(() => {
        cleanup();
        resolve(getLastAssistantText());
      }, TIMEOUT_MS);

      // Periodically send streaming updates
      const streamTimer = setInterval(() => {
        const current = getLastAssistantText();
        if (current && current !== lastText) {
          lastText = current;
          // Send streaming partial
          send({
            type: 'response',
            id: requestId,
            content: current,
            streaming: true
          });
        }
      }, STREAM_INTERVAL_MS);

      // Watch for completion: stop button disappears + no streaming class
      const observer = new MutationObserver(() => {
        const stopBtn = $(SEL.stopBtn);
        const streaming = $(SEL.streaming);

        if (!stopBtn && !streaming) {
          // Double-check after short delay (avoid flicker)
          setTimeout(() => {
            if (!$(SEL.stopBtn) && !$(SEL.streaming)) {
              cleanup();
              // Small buffer for final DOM render
              setTimeout(() => resolve(getLastAssistantText()), 300);
            }
          }, 500);
        }
      });

      observer.observe(document.body, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['class', 'data-testid']
      });

      function cleanup() {
        observer.disconnect();
        clearTimeout(timeout);
        clearInterval(streamTimer);
      }

      // Fallback: if response appears without stop button (very fast)
      setTimeout(() => {
        if (!$(SEL.stopBtn) && !$(SEL.streaming)) {
          const text = getLastAssistantText();
          if (text && text !== lastText) {
            cleanup();
            resolve(text);
          }
        }
      }, 3000);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NEW CHAT
  // ═══════════════════════════════════════════════════════════════════════════

  async function startNewChat() {
    const btn = $(SEL.newChatBtn);
    if (btn) {
      btn.click();
      await sleep(1000);
    } else {
      window.location.href = 'https://chatgpt.com/';
      await sleep(2000);
    }
    send({ type: 'chat_cleared' });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  function getLastAssistantText() {
    const msgs = $$(SEL.assistantMsg);
    if (msgs.length === 0) return '';
    return msgs[msgs.length - 1].innerText || '';
  }

  function detectModel() {
    // Try to detect which model ChatGPT is using from the UI
    // The model selector/indicator varies by ChatGPT version
    const modelBtn = document.querySelector('[data-testid="model-switcher-dropdown"]');
    if (modelBtn) return modelBtn.textContent.trim();
    // Fallback: check page title or other indicators
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VISUAL INDICATOR (small green dot in bottom-right)
  // ═══════════════════════════════════════════════════════════════════════════

  function injectIndicator() {
    if (document.getElementById('cortex-bridge-dot')) return;
    const dot = document.createElement('div');
    dot.id = 'cortex-bridge-dot';
    dot.style.cssText = `
      position: fixed; bottom: 10px; right: 10px;
      width: 12px; height: 12px; border-radius: 50%;
      background: #22c55e; border: 2px solid rgba(255,255,255,0.3);
      z-index: 99999; box-shadow: 0 0 8px rgba(34,197,94,0.5);
      cursor: pointer;
    `;
    dot.title = 'CORTEX Bridge Active';
    document.body.appendChild(dot);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PERIODIC STATUS REPORTING
  // ═══════════════════════════════════════════════════════════════════════════

  setInterval(() => {
    if (!connected) return;
    const msgs = $$(SEL.assistantMsg);
    send({
      type: 'status',
      ready: !!$(SEL.textarea),
      model: detectModel(),
      message_count: msgs.length
    });
  }, 30000); // Every 30 seconds

  // ═══════════════════════════════════════════════════════════════════════════
  // STARTUP
  // ═══════════════════════════════════════════════════════════════════════════

  console.log('[CORTEX] Content script loaded on ChatGPT');
  injectIndicator();
  connect();

})();
