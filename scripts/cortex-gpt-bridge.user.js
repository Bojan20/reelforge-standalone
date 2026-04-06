// ==UserScript==
// @name         CORTEX GPT Browser Bridge
// @namespace    https://fluxforge.studio
// @version      1.0.0
// @description  Neural bridge between CORTEX (Corti) and ChatGPT Browser. WebSocket connection to localhost:9742.
// @author       VanVinkl Studio
// @match        https://chatgpt.com/*
// @match        https://chat.openai.com/*
// @grant        none
// @run-at       document-idle
// ==/UserScript==

(function () {
    'use strict';

    // ═══════════════════════════════════════════════════════════════════════════
    // CONFIG
    // ═══════════════════════════════════════════════════════════════════════════

    const WS_URL = 'ws://127.0.0.1:9742';
    const RECONNECT_INTERVAL = 3000;     // ms between reconnect attempts
    const RESPONSE_POLL_INTERVAL = 500;  // ms between DOM checks for response
    const MAX_RESPONSE_WAIT = 120000;    // max ms to wait for ChatGPT response
    const VERSION = '1.0.0';

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    let ws = null;
    let reconnectTimer = null;
    let processing = false;     // Currently waiting for ChatGPT to respond
    let currentRequestId = null;

    // ═══════════════════════════════════════════════════════════════════════════
    // UI BADGE — visual indicator on the page
    // ═══════════════════════════════════════════════════════════════════════════

    function createBadge() {
        const badge = document.createElement('div');
        badge.id = 'cortex-bridge-badge';
        badge.style.cssText = `
            position: fixed;
            bottom: 12px;
            right: 12px;
            z-index: 99999;
            padding: 6px 12px;
            border-radius: 20px;
            font-family: monospace;
            font-size: 11px;
            font-weight: bold;
            cursor: pointer;
            transition: all 0.3s ease;
            box-shadow: 0 2px 8px rgba(0,0,0,0.3);
        `;
        badge.title = 'CORTEX GPT Browser Bridge';
        document.body.appendChild(badge);
        return badge;
    }

    function updateBadge(status) {
        let badge = document.getElementById('cortex-bridge-badge');
        if (!badge) badge = createBadge();

        const states = {
            connected: { bg: '#10b981', text: 'white', label: 'CORTEX CONNECTED' },
            disconnected: { bg: '#ef4444', text: 'white', label: 'CORTEX OFFLINE' },
            processing: { bg: '#f59e0b', text: 'black', label: 'CORTEX THINKING...' },
            error: { bg: '#dc2626', text: 'white', label: 'CORTEX ERROR' },
        };

        const s = states[status] || states.disconnected;
        badge.style.backgroundColor = s.bg;
        badge.style.color = s.text;
        badge.textContent = s.label;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // WEBSOCKET CONNECTION
    // ═══════════════════════════════════════════════════════════════════════════

    function connect() {
        if (ws && ws.readyState === WebSocket.OPEN) return;

        try {
            ws = new WebSocket(WS_URL);
        } catch (e) {
            console.log('[CORTEX Bridge] WebSocket creation failed:', e);
            scheduleReconnect();
            return;
        }

        ws.onopen = () => {
            console.log('[CORTEX Bridge] Connected to CORTEX');
            updateBadge('connected');

            // Clear reconnect timer
            if (reconnectTimer) {
                clearTimeout(reconnectTimer);
                reconnectTimer = null;
            }

            // Send identification
            ws.send(JSON.stringify({
                type: 'connected',
                user_agent: navigator.userAgent,
                model: detectModel(),
            }));
        };

        ws.onmessage = (event) => {
            try {
                const msg = JSON.parse(event.data);
                handleCommand(msg);
            } catch (e) {
                console.error('[CORTEX Bridge] Invalid message:', e, event.data);
            }
        };

        ws.onclose = () => {
            console.log('[CORTEX Bridge] Disconnected from CORTEX');
            updateBadge('disconnected');
            ws = null;
            scheduleReconnect();
        };

        ws.onerror = (e) => {
            console.log('[CORTEX Bridge] WebSocket error (CORTEX server probably not running)');
            updateBadge('disconnected');
        };
    }

    function scheduleReconnect() {
        if (reconnectTimer) return;
        reconnectTimer = setTimeout(() => {
            reconnectTimer = null;
            connect();
        }, RECONNECT_INTERVAL);
    }

    function send(msg) {
        if (ws && ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify(msg));
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COMMAND HANDLER
    // ═══════════════════════════════════════════════════════════════════════════

    function handleCommand(msg) {
        switch (msg.type) {
            case 'query':
                handleQuery(msg);
                break;
            case 'ping':
                send({ type: 'pong', ts: msg.ts });
                break;
            case 'new_chat':
                handleNewChat();
                break;
            default:
                console.log('[CORTEX Bridge] Unknown command:', msg.type);
        }
    }

    async function handleQuery(msg) {
        const { id, content, intent, urgency } = msg;

        console.log(`[CORTEX Bridge] Query received — id=${id}, intent=${intent}, urgency=${urgency}`);

        if (processing) {
            console.log('[CORTEX Bridge] Already processing, sending busy');
            send({ type: 'busy', id });
            return;
        }

        processing = true;
        currentRequestId = id;
        updateBadge('processing');

        try {
            // Step 1: Type the message into ChatGPT
            const typed = await typeMessage(content);
            if (!typed) {
                throw new Error('Failed to type message into ChatGPT input');
            }

            // Step 2: Click send
            const sent = await clickSend();
            if (!sent) {
                throw new Error('Failed to click send button');
            }

            // Step 3: Wait for response
            const response = await waitForResponse();

            // Step 4: Send response back to CORTEX
            send({
                type: 'response',
                id,
                content: response,
                streaming: false,
            });

            console.log(`[CORTEX Bridge] Response sent — id=${id}, length=${response.length}`);
        } catch (e) {
            console.error('[CORTEX Bridge] Error processing query:', e);
            send({
                type: 'error',
                id,
                message: e.message,
                code: 'dom_error',
            });
        } finally {
            processing = false;
            currentRequestId = null;
            updateBadge(ws && ws.readyState === WebSocket.OPEN ? 'connected' : 'disconnected');
        }
    }

    function handleNewChat() {
        // Try to click "New chat" button
        const newChatBtn = document.querySelector('nav a[href="/"]') ||
            document.querySelector('button[data-testid="create-new-chat-button"]') ||
            document.querySelector('[aria-label="New chat"]');

        if (newChatBtn) {
            newChatBtn.click();
            console.log('[CORTEX Bridge] New chat started');
            send({ type: 'chat_cleared' });
        } else {
            // Fallback: navigate to root
            window.location.href = 'https://chatgpt.com/';
            send({ type: 'chat_cleared' });
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DOM INTERACTION — typing and reading ChatGPT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Type a message into the ChatGPT input field.
     * Uses the contenteditable div or textarea depending on ChatGPT's current UI.
     */
    async function typeMessage(text) {
        // ChatGPT uses a contenteditable div with id="prompt-textarea"
        // or a <textarea> in older versions
        const input = document.getElementById('prompt-textarea') ||
            document.querySelector('textarea[data-id="root"]') ||
            document.querySelector('[contenteditable="true"]');

        if (!input) {
            console.error('[CORTEX Bridge] Cannot find ChatGPT input field');
            return false;
        }

        // Focus the input
        input.focus();

        if (input.tagName === 'TEXTAREA') {
            // Old textarea approach
            const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
                window.HTMLTextAreaElement.prototype, 'value'
            ).set;
            nativeInputValueSetter.call(input, text);
            input.dispatchEvent(new Event('input', { bubbles: true }));
        } else {
            // Contenteditable div (current ChatGPT UI)
            // Clear existing content
            input.innerHTML = '';

            // Create a paragraph with the text
            const p = document.createElement('p');
            p.textContent = text;
            input.appendChild(p);

            // Dispatch input event to trigger React state update
            input.dispatchEvent(new Event('input', { bubbles: true }));

            // Also try setting innerText and dispatching
            // (ChatGPT React sometimes needs this)
            await sleep(100);
            input.dispatchEvent(new Event('input', { bubbles: true }));
        }

        // Wait for UI to update
        await sleep(200);
        return true;
    }

    /**
     * Click the send button.
     */
    async function clickSend() {
        // Wait a bit for the send button to become enabled
        await sleep(300);

        // Try multiple selectors for the send button
        const sendBtn =
            document.querySelector('[data-testid="send-button"]') ||
            document.querySelector('button[aria-label="Send prompt"]') ||
            document.querySelector('form button[type="submit"]') ||
            document.querySelector('button.absolute.bottom-1\\.5') ||
            findSendButton();

        if (!sendBtn) {
            console.error('[CORTEX Bridge] Cannot find send button');
            return false;
        }

        // Check if button is disabled
        if (sendBtn.disabled) {
            console.log('[CORTEX Bridge] Send button disabled, waiting...');
            await sleep(500);
            if (sendBtn.disabled) {
                console.error('[CORTEX Bridge] Send button still disabled');
                return false;
            }
        }

        sendBtn.click();
        console.log('[CORTEX Bridge] Send button clicked');

        // Wait for the message to be sent (input clears)
        await sleep(500);
        return true;
    }

    /**
     * Fallback: find send button by looking for SVG arrow icon.
     */
    function findSendButton() {
        const buttons = document.querySelectorAll('button');
        for (const btn of buttons) {
            // Look for the send button (usually has an arrow SVG or "Send" text)
            if (btn.querySelector('svg path[d*="M15.192"]') || // Arrow path
                btn.querySelector('svg polyline[points*="22 2"]') ||
                btn.textContent.trim() === 'Send' ||
                btn.getAttribute('aria-label')?.includes('Send')) {
                return btn;
            }
        }
        return null;
    }

    /**
     * Wait for ChatGPT to finish responding.
     * Returns the text of the last assistant message.
     */
    async function waitForResponse() {
        const startTime = Date.now();

        // Count existing assistant messages before our query
        const initialCount = getAssistantMessages().length;

        // Wait for a new message to appear
        while (Date.now() - startTime < MAX_RESPONSE_WAIT) {
            await sleep(RESPONSE_POLL_INTERVAL);

            const messages = getAssistantMessages();

            // Check if a new message appeared
            if (messages.length > initialCount) {
                const lastMsg = messages[messages.length - 1];

                // Check if ChatGPT is still generating (stop button visible)
                if (isStillGenerating()) {
                    continue; // Wait for completion
                }

                // Double-check: wait a bit and verify no more content is being added
                const contentBefore = lastMsg.textContent;
                await sleep(800);
                const contentAfter = lastMsg.textContent;

                if (contentBefore === contentAfter && !isStillGenerating()) {
                    // Response is complete
                    return extractMessageContent(lastMsg);
                }
                // Still changing, keep waiting
            }
        }

        throw new Error(`Response timeout after ${MAX_RESPONSE_WAIT / 1000}s`);
    }

    /**
     * Get all assistant message elements.
     */
    function getAssistantMessages() {
        // ChatGPT renders assistant messages in elements with data-message-author-role="assistant"
        const byRole = document.querySelectorAll('[data-message-author-role="assistant"]');
        if (byRole.length > 0) return Array.from(byRole);

        // Fallback: look for message containers with specific class patterns
        const messageGroups = document.querySelectorAll('.group\\/conversation-turn');
        const assistantMsgs = [];
        for (const group of messageGroups) {
            // Assistant messages typically have a different background or no user icon
            if (!group.querySelector('[data-message-author-role="user"]')) {
                assistantMsgs.push(group);
            }
        }
        return assistantMsgs;
    }

    /**
     * Check if ChatGPT is still generating a response.
     */
    function isStillGenerating() {
        // Look for the stop/regenerate button which indicates generation in progress
        const stopBtn = document.querySelector('[data-testid="stop-button"]') ||
            document.querySelector('button[aria-label="Stop generating"]') ||
            document.querySelector('button.stop-button');

        return !!stopBtn;
    }

    /**
     * Extract clean text content from an assistant message element.
     */
    function extractMessageContent(element) {
        // Try to get the markdown-rendered content
        const markdownEl = element.querySelector('.markdown') ||
            element.querySelector('[class*="markdown"]') ||
            element.querySelector('.prose');

        if (markdownEl) {
            return markdownEl.innerText.trim();
        }

        // Fallback: get all text
        return element.innerText.trim();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Detect the current ChatGPT model (if visible in the UI).
     */
    function detectModel() {
        // Look for model selector/indicator
        const modelEl = document.querySelector('[data-testid="model-selector"]') ||
            document.querySelector('button[class*="model"]') ||
            document.querySelector('.model-selector');

        if (modelEl) {
            return modelEl.textContent.trim();
        }

        // Check page title or URL for model hints
        const title = document.title;
        if (title.includes('4o')) return 'GPT-4o';
        if (title.includes('4')) return 'GPT-4';

        return null;
    }

    function sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    /**
     * Periodic status report to CORTEX.
     */
    function sendStatusReport() {
        if (!ws || ws.readyState !== WebSocket.OPEN) return;

        send({
            type: 'status',
            ready: !!document.getElementById('prompt-textarea') ||
                !!document.querySelector('[contenteditable="true"]'),
            model: detectModel(),
            message_count: getAssistantMessages().length,
        });
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INIT
    // ═══════════════════════════════════════════════════════════════════════════

    console.log(`[CORTEX Bridge] v${VERSION} — initializing...`);
    updateBadge('disconnected');

    // Connect to CORTEX WebSocket server
    connect();

    // Periodic status reports
    setInterval(sendStatusReport, 30000);

    // Periodic reconnect check
    setInterval(() => {
        if (!ws || ws.readyState !== WebSocket.OPEN) {
            connect();
        }
    }, RECONNECT_INTERVAL);

    console.log(`[CORTEX Bridge] v${VERSION} — ready. Connecting to ${WS_URL}...`);
})();
