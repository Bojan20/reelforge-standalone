// CORTEX Bridge — Popup UI

const statusDot = document.getElementById('statusDot');
const cortexStatus = document.getElementById('cortexStatus');
const chatgptStatus = document.getElementById('chatgptStatus');
const msgSent = document.getElementById('msgSent');
const msgRecv = document.getElementById('msgRecv');
const reconnects = document.getElementById('reconnects');
const reconnectBtn = document.getElementById('reconnectBtn');

function updateUI(data) {
  if (!data) return;

  const { state, stats, hasContentScript } = data;

  // Status dot
  statusDot.className = 'dot' + (state === 'connected' ? ' connected' : state === 'connecting' ? ' connecting' : '');

  // Text
  cortexStatus.textContent = state === 'connected' ? 'Connected' : state === 'connecting' ? 'Connecting...' : 'Disconnected';
  chatgptStatus.textContent = hasContentScript ? 'Active' : 'Not detected';
  msgSent.textContent = stats?.messagesSent || 0;
  msgRecv.textContent = stats?.messagesReceived || 0;
  reconnects.textContent = stats?.reconnects || 0;

  reconnectBtn.disabled = state === 'connecting';
}

// Get initial state
chrome.runtime.sendMessage({ type: 'get_state' }, updateUI);

// Listen for state updates
chrome.runtime.onMessage.addListener((msg) => {
  if (msg.type === 'state_update') {
    updateUI(msg);
  }
});

// Reconnect button
reconnectBtn.addEventListener('click', () => {
  chrome.runtime.sendMessage({ type: 'reconnect' });
  reconnectBtn.disabled = true;
  setTimeout(() => {
    chrome.runtime.sendMessage({ type: 'get_state' }, updateUI);
  }, 1000);
});

// Refresh every 2 seconds while popup is open
setInterval(() => {
  chrome.runtime.sendMessage({ type: 'get_state' }, updateUI);
}, 2000);
