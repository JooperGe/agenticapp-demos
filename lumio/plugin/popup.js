/**
 * popup.js — 主逻辑
 * 视图：login → main / list / search
 */

/* ══════════════════════ 工具函数 ══════════════════════ */

/** 格式化时间戳为友好字符串 */
function formatTime(ts) {
  const now = Date.now();
  const diff = now - ts;
  if (diff < 60000)  return '刚刚';
  if (diff < 3600000) return `${Math.floor(diff / 60000)} 分钟前`;
  const d = new Date(ts);
  const today = new Date();
  const yesterday = new Date(today); yesterday.setDate(today.getDate() - 1);
  if (d.toDateString() === today.toDateString())
    return `今天 ${d.getHours()}:${String(d.getMinutes()).padStart(2,'0')}`;
  if (d.toDateString() === yesterday.toDateString())
    return `昨天 ${d.getHours()}:${String(d.getMinutes()).padStart(2,'0')}`;
  return `${d.getMonth()+1}/${d.getDate()} ${d.getHours()}:${String(d.getMinutes()).padStart(2,'0')}`;
}

/** 本地生成占位 AI 摘要 + 标签（后端接入后替换） */
function localSummary(title, source) {
  const topics = [
    ['AI 前沿', 'tag-amber'], ['产品设计', 'tag-blue'], ['技术深度', 'tag-green'],
    ['商业洞察', 'tag-purple'], ['创业思考', 'tag-pink'], ['效率工具', 'tag-blue'],
    ['职场成长', 'tag-amber'], ['人文科普', 'tag-green'],
  ];
  // 从标题关键词粗略推断话题
  const kw = title.toLowerCase();
  let picked = [topics[Math.floor(Math.random() * topics.length)]];
  if (/ai|gpt|llm|模型|机器学习|神经网络/.test(kw)) picked = [['AI 前沿', 'tag-amber'], ['技术深度', 'tag-green']];
  else if (/产品|设计|ux|ui|交互/.test(kw)) picked = [['产品设计', 'tag-blue']];
  else if (/创业|融资|商业|增长/.test(kw)) picked = [['商业洞察', 'tag-purple'], ['创业思考', 'tag-pink']];
  else if (/程序|代码|架构|开发|工程/.test(kw)) picked = [['技术深度', 'tag-green']];

  const summaries = [
    `本文探讨了「${title.slice(0, 16)}…」的核心要点，覆盖背景、挑战与实践建议，值得反复回看。`,
    `作者从多个维度剖析了相关问题，提炼出 3 个关键洞察，对从业者有较强的参考价值。`,
    `这篇文章系统梳理了该领域的发展脉络，并给出了可操作的实践路径。`,
  ];
  return {
    summary: summaries[Math.floor(Math.random() * summaries.length)],
    tags: picked,
  };
}

/** 构建标签 HTML */
function tagsHTML(tags) {
  return tags.map(([label, cls]) =>
    `<span class="tag ${cls}">${label}</span>`
  ).join('');
}

/** 从 URL 获取 favicon */
function faviconURL(url) {
  try {
    const origin = new URL(url).origin;
    return `https://www.google.com/s2/favicons?domain=${origin}&sz=32`;
  } catch { return ''; }
}

/* ══════════════════════ 视图管理 ══════════════════════ */

const VIEWS = ['login', 'main', 'list', 'search'];

function showView(name) {
  VIEWS.forEach(v => {
    document.getElementById(`view-${v}`).classList.toggle('hidden', v !== name);
  });
  if (name === 'list')   initListView();
  if (name === 'search') initSearchView();
  if (name === 'main')   initMainView();
}

/* ══════════════════════ 登录流程 ══════════════════════ */

let loginTimer = null;

function startLoginFlow() {
  const countdownWrap = document.getElementById('countdown-wrap');
  const countdownText = document.getElementById('countdown-text');
  const qrSuccess     = document.getElementById('qr-success');

  // 2s 后显示倒计时
  setTimeout(() => {
    countdownWrap.classList.remove('hidden');
    let sec = 3;
    countdownText.textContent = `模拟扫码中… ${sec}s 后自动登录`;
    const tick = setInterval(() => {
      sec--;
      if (sec > 0) {
        countdownText.textContent = `模拟扫码中… ${sec}s 后自动登录`;
      } else {
        clearInterval(tick);
        // 显示成功遮罩
        qrSuccess.classList.remove('hidden');
        countdownWrap.classList.add('hidden');
        // 1s 后完成登录
        setTimeout(async () => {
          const user = await API.login('mock_wx_code');
          await Storage.setUser(user);
          showView('main');
        }, 900);
      }
    }, 1000);
  }, 800);
}

/* ══════════════════════ 主视图（添加页面） ══════════════════════ */

let currentPageInfo = null;

async function initMainView() {
  const loading  = document.getElementById('page-loading');
  const infoEl   = document.getElementById('page-info');
  const addBtn   = document.getElementById('btn-add');
  const feedback = document.getElementById('add-feedback');

  loading.classList.remove('hidden');
  infoEl.classList.add('hidden');
  feedback.classList.add('hidden');
  addBtn.disabled = false;
  addBtn.textContent = ''; // reset
  addBtn.innerHTML = `<svg viewBox="0 0 24 24" fill="none" width="18" height="18"><path d="M19 21l-7-5-7 5V5a2 2 0 012-2h10a2 2 0 012 2z" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg> 添加到拾光`;

  try {
    // 获取当前标签页
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab) throw new Error('no tab');

    // 尝试通过 content.js 获取页面详情
    let pageInfo = null;
    try {
      pageInfo = await new Promise((resolve, reject) => {
        chrome.tabs.sendMessage(tab.id, { type: 'GET_PAGE_INFO' }, (res) => {
          if (chrome.runtime.lastError || !res) reject();
          else resolve(res);
        });
      });
    } catch {
      // content.js 未注入（如 about:blank、chrome:// 等）
      pageInfo = { title: tab.title || '', url: tab.url || '', source: '', readMin: 0 };
    }

    currentPageInfo = pageInfo;

    // 渲染
    document.getElementById('page-favicon').src  = faviconURL(pageInfo.url);
    document.getElementById('page-source').textContent  = pageInfo.source || new URL(pageInfo.url).hostname;
    document.getElementById('page-readtime').textContent = pageInfo.readMin ? `${pageInfo.readMin} 分钟阅读` : '';
    document.getElementById('page-title').textContent    = pageInfo.title;

    // AI 摘要（Stub）
    let aiResult = null;
    try { aiResult = await API.summarize(pageInfo); } catch {}
    const { summary, tags } = aiResult || localSummary(pageInfo.title, pageInfo.source);
    document.getElementById('ai-summary-text').textContent = summary;
    document.getElementById('ai-tags').innerHTML = tagsHTML(tags);
    currentPageInfo._tags   = tags.map(([l]) => l);
    currentPageInfo._summary = summary;

    loading.classList.add('hidden');
    infoEl.classList.remove('hidden');

    // 检查是否已收藏
    const items = await Storage.getItems();
    const already = items.find(i => i.url === pageInfo.url);
    if (already) {
      addBtn.disabled = true;
      addBtn.innerHTML = `<svg viewBox="0 0 24 24" fill="none" width="18" height="18"><path d="M19 21l-7-5-7 5V5a2 2 0 012-2h10a2 2 0 012 2z" fill="rgba(255,255,255,.5)" stroke="rgba(255,255,255,.5)" stroke-width="2" stroke-linecap="round"/></svg> 已在收藏夹中`;
    }
  } catch (e) {
    loading.textContent = '无法获取页面信息';
  }
}

async function handleAddPage() {
  if (!currentPageInfo) return;
  const addBtn   = document.getElementById('btn-add');
  const feedback = document.getElementById('add-feedback');

  addBtn.disabled = true;
  addBtn.innerHTML = `<div class="spinner" style="width:16px;height:16px;border-width:2px"></div> 保存中…`;

  const result = await Storage.addItem({
    url:     currentPageInfo.url,
    title:   currentPageInfo.title,
    favicon: faviconURL(currentPageInfo.url),
    summary: currentPageInfo._summary || '',
    tags:    currentPageInfo._tags || [],
    source:  currentPageInfo.source || '',
  });

  if (result.duplicate) {
    feedback.textContent = '已在收藏夹中，无需重复添加';
    feedback.className = 'add-feedback warning';
  } else {
    feedback.textContent = '已成功添加到拾光 ✓';
    feedback.className = 'add-feedback success';
    addBtn.innerHTML = `<svg viewBox="0 0 24 24" fill="none" width="18" height="18"><path d="M19 21l-7-5-7 5V5a2 2 0 012-2h10a2 2 0 012 2z" fill="rgba(255,255,255,.5)" stroke="rgba(255,255,255,.5)" stroke-width="2" stroke-linecap="round"/></svg> 已在收藏夹中`;
    // TODO: API.createItem(result.item, user.token)
  }

  feedback.classList.remove('hidden');
}

/* ══════════════════════ 列表视图 ══════════════════════ */

let activeTag = '全部';

async function initListView() {
  await renderTagTabs();
  await renderList();
}

async function renderTagTabs() {
  const tags    = await Storage.getAllTags();
  const tabsEl  = document.getElementById('tag-tabs');
  tabsEl.innerHTML = tags.map(t =>
    `<button class="tab-pill${t === activeTag ? ' active' : ''}" data-tag="${t}">${t}</button>`
  ).join('');
  tabsEl.querySelectorAll('.tab-pill').forEach(btn => {
    btn.addEventListener('click', async () => {
      activeTag = btn.dataset.tag;
      await renderTagTabs();
      await renderList();
    });
  });
}

async function renderList(filter) {
  const items = filter !== undefined
    ? await Storage.searchItems(filter)
    : await Storage.filterByTag(activeTag);

  const countEl = document.getElementById('list-count');
  if (countEl) countEl.textContent = `共 ${(await Storage.getItems()).length} 篇`;

  const container = document.getElementById('list-items');
  container.innerHTML = '';

  if (!items.length) {
    container.innerHTML = `<div class="list-empty">
      <svg viewBox="0 0 24 24" fill="none" width="40" height="40"><path d="M19 21l-7-5-7 5V5a2 2 0 012-2h10a2 2 0 012 2z" stroke="#D6D3D1" stroke-width="1.5"/></svg>
      <p>${filter ? '没有找到相关收藏' : '还没有收藏，去添加第一篇吧'}</p>
    </div>`;
    return;
  }

  // 按日期分组
  const groups = {};
  items.forEach(item => {
    const label = formatDateGroup(item.savedAt);
    if (!groups[label]) groups[label] = [];
    groups[label].push(item);
  });

  Object.entries(groups).forEach(([label, groupItems]) => {
    const labelEl = document.createElement('div');
    labelEl.className = 'date-label';
    labelEl.textContent = label;
    container.appendChild(labelEl);

    groupItems.forEach(item => {
      container.appendChild(buildItemCard(item));
    });
  });
}

function formatDateGroup(ts) {
  const d = new Date(ts);
  const today = new Date();
  const yesterday = new Date(today); yesterday.setDate(today.getDate() - 1);
  if (d.toDateString() === today.toDateString())     return '今天';
  if (d.toDateString() === yesterday.toDateString()) return '昨天';
  const diff = Math.floor((Date.now() - ts) / 86400000);
  if (diff < 7) return `${diff} 天前`;
  return `${d.getFullYear()}/${d.getMonth()+1}/${d.getDate()}`;
}

function buildItemCard(item) {
  const card = document.createElement('div');
  card.className = 'item-card';

  const tagHtml = (item.tags || []).slice(0, 2).map(t => {
    const cls = ['tag-amber','tag-blue','tag-green','tag-purple','tag-pink'][
      Math.abs([...t].reduce((s,c)=>s+c.charCodeAt(0),0)) % 5
    ];
    return `<span class="tag ${cls}">${t}</span>`;
  }).join('');

  card.innerHTML = `
    <img class="item-favicon" src="${item.favicon || ''}" alt="" onerror="this.style.display='none'"/>
    <div class="item-body">
      <div class="item-title">${escHtml(item.title)}</div>
      <div class="item-meta">
        ${tagHtml}
        <span class="item-time">${formatTime(item.savedAt)}</span>
      </div>
    </div>
    <button class="item-del" data-id="${item.id}" title="删除">
      <svg viewBox="0 0 24 24" fill="none"><path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
    </button>
  `;

  // 点击卡片打开页面
  card.addEventListener('click', e => {
    if (e.target.closest('.item-del')) return;
    chrome.tabs.create({ url: item.url });
  });

  // 删除
  card.querySelector('.item-del').addEventListener('click', async (e) => {
    e.stopPropagation();
    await Storage.removeItem(item.id);
    // TODO: API.deleteItem(item.serverId, user.token)
    card.style.transition = 'opacity .2s';
    card.style.opacity = '0';
    setTimeout(() => {
      card.remove();
      renderTagTabs(); // 更新 tab 计数
    }, 200);
  });

  return card;
}

function escHtml(str) {
  return str.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

/* ══════════════════════ 搜索视图 ══════════════════════ */

async function initSearchView() {
  const input = document.getElementById('search-input');
  input.value = '';
  document.getElementById('search-results').innerHTML = `
    <div class="search-empty">
      <svg viewBox="0 0 24 24" fill="none" width="40" height="40"><circle cx="11" cy="11" r="7" stroke="#D6D3D1" stroke-width="1.5"/><path d="M20 20l-3-3" stroke="#D6D3D1" stroke-width="1.5" stroke-linecap="round"/></svg>
      <p>输入关键词搜索你的收藏</p>
    </div>`;
  setTimeout(() => input.focus(), 80);
}

async function handleSearch(query) {
  const container = document.getElementById('search-results');
  if (!query.trim()) {
    container.innerHTML = `<div class="search-empty">
      <svg viewBox="0 0 24 24" fill="none" width="40" height="40"><circle cx="11" cy="11" r="7" stroke="#D6D3D1" stroke-width="1.5"/><path d="M20 20l-3-3" stroke="#D6D3D1" stroke-width="1.5" stroke-linecap="round"/></svg>
      <p>输入关键词搜索你的收藏</p>
    </div>`;
    return;
  }
  const items = await Storage.searchItems(query);
  container.innerHTML = '';
  if (!items.length) {
    container.innerHTML = `<div class="search-empty">
      <svg viewBox="0 0 24 24" fill="none" width="40" height="40"><circle cx="11" cy="11" r="7" stroke="#D6D3D1" stroke-width="1.5"/><path d="M20 20l-3-3" stroke="#D6D3D1" stroke-width="1.5" stroke-linecap="round"/></svg>
      <p>没有找到"${escHtml(query)}"相关的收藏</p>
    </div>`;
    return;
  }
  items.forEach(item => container.appendChild(buildItemCard(item)));
}

/* ══════════════════════ 事件绑定 ══════════════════════ */

function bindEvents() {
  // 底部导航（所有视图）
  document.querySelectorAll('.nav-item[data-view]').forEach(btn => {
    btn.addEventListener('click', () => showView(btn.dataset.view));
  });

  // 登录视图 — 模拟扫码
  startLoginFlow();

  // 主视图 — 添加按钮
  document.getElementById('btn-add').addEventListener('click', handleAddPage);

  // 主视图 — 跳转搜索
  document.getElementById('btn-goto-search').addEventListener('click', () => showView('search'));

  // 主视图 — 退出登录
  document.getElementById('btn-logout').addEventListener('click', async () => {
    if (!confirm('确认退出登录？')) return;
    await Storage.clearUser();
    showView('login');
    startLoginFlow();
  });

  // 列表视图 — 返回
  document.getElementById('btn-list-back').addEventListener('click', () => showView('main'));

  // 列表视图 — 搜索框
  const listSearch = document.getElementById('list-search-input');
  const listClear  = document.getElementById('list-search-clear');
  listSearch.addEventListener('input', async () => {
    const q = listSearch.value;
    listClear.classList.toggle('hidden', !q);
    await renderList(q || undefined);
  });
  listClear.addEventListener('click', async () => {
    listSearch.value = '';
    listClear.classList.add('hidden');
    await renderList();
  });

  // 搜索视图 — 返回
  document.getElementById('btn-search-back').addEventListener('click', () => showView('main'));

  // 搜索视图 — 输入
  let searchDebounce = null;
  document.getElementById('search-input').addEventListener('input', (e) => {
    clearTimeout(searchDebounce);
    searchDebounce = setTimeout(() => handleSearch(e.target.value), 200);
  });
}

/* ══════════════════════ 初始化 ══════════════════════ */

async function init() {
  bindEvents();
  const loggedIn = await Storage.isLoggedIn();
  if (loggedIn) {
    showView('main');
  } else {
    showView('login');
  }
}

document.addEventListener('DOMContentLoaded', init);
