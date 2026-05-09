/**
 * background.js — Service Worker
 * 处理安装事件和跨页面消息转发。
 */

chrome.runtime.onInstalled.addListener(({ reason }) => {
  if (reason === 'install') {
    console.log('[Lumio] Extension installed.');
    // TODO: 可在此处打开欢迎页
    // chrome.tabs.create({ url: 'https://lumio.app/welcome' });
  }
});

// 转发来自 popup 的消息给 content script（处理 activeTab 限制）
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === 'FORWARD_TO_TAB') {
    chrome.tabs.query({ active: true, currentWindow: true }, ([tab]) => {
      if (!tab) { sendResponse(null); return; }
      chrome.tabs.sendMessage(tab.id, msg.payload, (res) => {
        sendResponse(res || null);
      });
    });
    return true;
  }
});
