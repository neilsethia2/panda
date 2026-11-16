const pill = document.getElementById('pill');
const detail = document.getElementById('detail');

function show(status) {
  if (!status || !status.connected) {
    pill.textContent = 'Not connected';
    pill.className = 'pill';
    detail.textContent = 'Open the Panda app on your Mac once, then reload this extension.';
    return;
  }
  if (!status.appRunning) {
    pill.textContent = 'Panda is not running';
    pill.className = 'pill';
    detail.textContent = 'Nothing is blocked until you open Panda from Applications.';
    return;
  }
  pill.textContent = 'Connected';
  pill.className = 'pill ok';
  detail.textContent = 'Use the panda in your menu bar to turn blocking on or off.';
}

chrome.runtime.sendMessage({ type: 'status' }, (response) => {
  if (chrome.runtime.lastError) {
    show(null);
    return;
  }
  show(response);
});
