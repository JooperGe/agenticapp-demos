/**
 * storage.js — 本地数据层
 * 所有读写都走 chrome.storage.local；
 * API 接入口已预留，见各方法的 TODO 注释。
 */

const KEYS = {
  USER:  'lumio_user',
  ITEMS: 'lumio_items',
};

const Storage = {

  /* ── 用户 ── */

  async getUser() {
    const res = await chrome.storage.local.get(KEYS.USER);
    return res[KEYS.USER] || null;
  },

  async setUser(user) {
    await chrome.storage.local.set({ [KEYS.USER]: user });
  },

  async clearUser() {
    await chrome.storage.local.remove(KEYS.USER);
  },

  async isLoggedIn() {
    return !!(await this.getUser());
  },

  /* ── 收藏条目 ── */

  async getItems() {
    const res = await chrome.storage.local.get(KEYS.ITEMS);
    return res[KEYS.ITEMS] || [];
  },

  /**
   * 添加新条目
   * @param {{ url, title, favicon, summary, tags, source }} item
   * @returns {{ success: boolean, duplicate?: boolean, item: object }}
   */
  async addItem(item) {
    const items = await this.getItems();
    const exists = items.find(i => i.url === item.url);
    if (exists) return { success: false, duplicate: true, item: exists };

    const newItem = {
      id:        'item_' + Date.now(),
      url:       item.url,
      title:     item.title || '（无标题）',
      favicon:   item.favicon || '',
      summary:   item.summary || '',
      tags:      item.tags || [],
      source:    item.source || '',
      savedAt:   Date.now(),
      // TODO: sync flag — set to true after API upload succeeds
      synced:    false,
    };
    items.unshift(newItem);
    await chrome.storage.local.set({ [KEYS.ITEMS]: items });
    return { success: true, item: newItem };
  },

  async removeItem(id) {
    const items = (await this.getItems()).filter(i => i.id !== id);
    await chrome.storage.local.set({ [KEYS.ITEMS]: items });
  },

  async updateItem(id, updates) {
    const items = (await this.getItems()).map(i =>
      i.id === id ? { ...i, ...updates } : i
    );
    await chrome.storage.local.set({ [KEYS.ITEMS]: items });
  },

  /** 本地全文搜索 */
  async searchItems(query) {
    const q = query.trim().toLowerCase();
    if (!q) return this.getItems();
    const items = await this.getItems();
    return items.filter(i =>
      i.title.toLowerCase().includes(q) ||
      (i.summary || '').toLowerCase().includes(q) ||
      (i.tags || []).some(t => t.toLowerCase().includes(q)) ||
      (i.source || '').toLowerCase().includes(q)
    );
  },

  /** 按话题标签筛选 */
  async filterByTag(tag) {
    const items = await this.getItems();
    if (!tag || tag === '全部') return items;
    return items.filter(i => (i.tags || []).includes(tag));
  },

  /** 获取所有出现过的标签（用于 Tab 渲染） */
  async getAllTags() {
    const items = await this.getItems();
    const set = new Set();
    items.forEach(i => (i.tags || []).forEach(t => set.add(t)));
    return ['全部', ...Array.from(set)];
  },
};
