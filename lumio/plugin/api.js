/**
 * api.js — 网络接口层（当前为 Stub 实现）
 *
 * 所有方法都有对应的 TODO 注释，后续接入真实后端时替换即可。
 * Stub 方法会直接返回模拟数据，不发起任何网络请求。
 */

const API_BASE = 'https://api.lumio.app/v1'; // TODO: 替换为真实域名

/** 通用请求封装（留口子，stub 模式下不调用） */
async function request(method, path, body, token) {
  // TODO: 实现真实 HTTP 请求
  // const headers = { 'Content-Type': 'application/json' };
  // if (token) headers['Authorization'] = `Bearer ${token}`;
  // const res = await fetch(`${API_BASE}${path}`, {
  //   method, headers, body: body ? JSON.stringify(body) : undefined,
  // });
  // if (!res.ok) throw new Error(`API ${method} ${path} → ${res.status}`);
  // return res.json();
  throw new Error('API not implemented yet');
}

const API = {

  /* ── Auth ── */

  /**
   * 微信扫码登录
   * @param {string} wxCode  前端获取到的微信 OAuth code
   * @returns {{ id, nickname, avatar, token }}
   *
   * TODO: POST /auth/wx-login  { code: wxCode }
   */
  async login(wxCode) {
    // Stub: 返回模拟用户，不调用网络
    return {
      id:       'user_stub_001',
      nickname: '拾光用户',
      avatar:   null,
      token:    'stub_token_' + Date.now(),
    };
  },

  /**
   * 登出
   * TODO: POST /auth/logout
   */
  async logout(token) {
    // Stub: 无操作
  },

  /* ── Items ── */

  /**
   * 上传单个收藏条目
   * TODO: POST /items  { ...item }
   */
  async createItem(item, token) {
    // Stub: 返回服务端分配的 id（模拟）
    return { ...item, serverId: 'srv_' + Date.now() };
  },

  /**
   * 拉取用户全量收藏（用于多端同步）
   * TODO: GET /items
   */
  async fetchItems(token) {
    // Stub: 返回空列表
    return [];
  },

  /**
   * 删除收藏
   * TODO: DELETE /items/:id
   */
  async deleteItem(serverId, token) {
    // Stub: 无操作
  },

  /* ── AI ── */

  /**
   * 生成摘要和标签
   * @param {{ url, title, bodyText }} pageInfo
   * @returns {{ summary: string, tags: string[] } | null}
   *
   * TODO: POST /ai/summarize  { url, title, bodyText }
   */
  async summarize(pageInfo) {
    // Stub: 返回 null，调用方使用本地占位摘要
    return null;
  },
};
