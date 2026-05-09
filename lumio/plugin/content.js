/**
 * content.js — 内容脚本
 * 注入每个页面，响应 popup 的消息请求，返回页面元数据。
 */

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type !== 'GET_PAGE_INFO') return;

  try {
    // 优先取 og:title / og:description，其次降级到 document.title
    const ogTitle = document.querySelector('meta[property="og:title"]')?.content;
    const ogDesc  = document.querySelector('meta[property="og:description"]')?.content;
    const ogImage = document.querySelector('meta[property="og:image"]')?.content;
    const siteName = document.querySelector('meta[property="og:site_name"]')?.content
                  || document.querySelector('meta[name="application-name"]')?.content;

    // 正文摘录（取前 500 字，供后续 AI 摘要用）
    const bodyText = (() => {
      const article = document.querySelector('article, [role="main"], .article, #article, .post-content');
      const el = article || document.body;
      return el.innerText.replace(/\s+/g, ' ').trim().slice(0, 500);
    })();

    // 估算阅读时间（中文 300 字/分钟）
    const wordCount = document.body.innerText.replace(/\s+/g, '').length;
    const readMin   = Math.max(1, Math.round(wordCount / 300));

    sendResponse({
      title:    ogTitle || document.title || '',
      desc:     ogDesc  || '',
      image:    ogImage || '',
      source:   siteName || new URL(location.href).hostname,
      bodyText,
      readMin,
      url:      location.href,
    });
  } catch (e) {
    sendResponse({ title: document.title || '', url: location.href });
  }

  return true; // 保持消息通道开启（异步 sendResponse）
});
