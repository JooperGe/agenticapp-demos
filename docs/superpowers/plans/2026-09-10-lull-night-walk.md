# lull 夜行 · 远方的旅伴 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为晚风 lull 落地「夜行」轻社交层设计：PRD 扩展至 v0.3（新增 3.7 章节 + 修订第四章），并新建静态 demo 页 `lull/index_v4.html` 新增 Flow 05。

**Architecture:** 纯文档 + 单文件静态 HTML，无构建、无后端。demo 页完整复制 v3 的结构（Tailwind CDN、深夜星空主题、手机框 + 旁注布局），在其 `<main>` 末尾（Flow 04 之后、Footer 之前）插入新的 Flow 05 section，并更新页头/页脚/标题版本标识。

**Tech Stack:** HTML + Tailwind CDN（`cdn.tailwindcss.com`）+ Material Icons Round + animate.css；文档为 Markdown。

**Spec:** `docs/superpowers/specs/2026-09-10-lull-night-walk-design.md`（本计划从 spec 出发，执行者须先读 spec）

## Global Constraints

- 所有文案简体中文；功能名统一为「夜行」，完整叙事名「夜行 · 远方的旅伴」
- 伙伴一律称「ta」，永不出现「好友 / 聊天 / 在线 / 已读 / 消息列表」等社交产品词汇（旁注中解释性提及除外，如「无已读」）
- demo 风格延续 v3：night/lav/glow/mist 色板、`.phone`/`.screen`/`.note-card`/`.tl-dot`/`.pulse-ring` 等既有 class，不新造 CSS 体系
- 静态 demo 不含真实能力：页面脚注须标注「本页为静态设计预览，不含真实匹配与消息能力」
- 布局基线：手机框 340×700（`.phone`），section 用 `mt-24` + `.divider` + `.flow-label` + `<h2 class="font-serif text-2xl font-bold glow-text">` 开头，内容行用 `<div class="flex gap-12 flex-wrap items-start">`
- 本仓库无测试框架：每个任务的"测试"= 结构校验（grep / xmllint）+ 浏览器目检（`open` 命令）
- 引用的既有资源（勿改名）：`lull/assets/cfe2d372919ea0ceb9dfde49f7251f0b.mp4`（她的画面视频）、`lull/assets/013234b1d1446af727290764dc50874b.webp`（海报帧）
- 参考基底：`lull/index_v3.html`（1125 行）——section 骨架见其 571-715 行（Flow 01），线条形象 SVG 见 228-262 行

---

### Task 1: PRD 新增 3.7「夜行 · 远方的旅伴」章节

**Files:**
- Modify: `lull/PRD.md`（在 3.6 章节之后、「四、交互与体验原则」之前插入）

**Interfaces:**
- Consumes: spec 第三~六节的概念与流程定案
- Produces: PRD 3.7 章节（Task 2 会引用其存在；demo 文案直接取材于此）

- [ ] **Step 1: 在 PRD.md 中 3.6 章节末尾（「零门槛」一条之后、`---` 分隔线之前）插入 3.7 全文**

插入内容（原文照抄）：

```markdown
### 3.7 夜行 · 远方的旅伴（可选社交层）

> 她替你出一次远门，把你的故事带给另一个守夜的人。

**概念**：完全 opt-in 的轻社交层。开启后，后台按画像匹配另一位真实用户；双方无法直接沟通，各自由自己的「她」做唯一的信使——转述对方的故事、代为传递消息。关系长期存在，以「夜」为节奏异步流动。

**社交四铁律**（承接第四章「零社交压力」，在其上细化）：

| 铁律 | 含义 |
|------|------|
| 完全沉睡是默认态 | 不开启则社交性为零；入口在设置深处，永不做引导弹窗、永不在对话里主动推销 |
| 无社交界面 | 无头像、昵称、资料页、消息列表、已读未读、在线状态——伙伴只存在于她的讲述里 |
| 异步到「夜」为粒度 | 消息按「夜」流动（对方下次打开才收到），回复永无期限，不回不算失约 |
| 无反馈回路 | 无通信计数、无火花、无纪念日提醒——关系的重量只存在于故事里 |

**五幕流程**：

| 幕 | 时机 | 内容 |
|----|------|------|
| 一 · 开启 | 设置 · 夜行 | 安静的开关 + 轻仪式：她说「今晚让我替你出趟远门，把你的故事，带给山谷对面另一个守夜的人」，用户选「好好走」/「再想想」 |
| 二 · 旅程 | 1~3 夜（按自然日计，可配） | 后台提炼侧写 → 情绪主题相邻匹配 → 交换故事。她没有离开：对话照旧，只是开场白带旅途气息（「今晚我在路上，遇见一片湖」）。3 夜内未匹配到人：她归来只说见闻，不说「没找到人」——**没有失败态** |
| 三 · 相遇之夜 | 归来 | 「我回来了。路上遇到了另一位守夜人——ta 也托 ta 的她，带了一个故事给我……」转述对方脱敏故事。听完才可选择：「不想继续」→ 她把故事收好，对方不会知道 |
| 四 · 信使循环 | 长期 | 发信：对话中自然说「替我带句话给 ta……」；可说「这件事别告诉 ta」。收信：下次打开，开场白带出「ta 前两天托我带了句话……」。一夜一信，多封信分几夜讲 |
| 五 · 得体退出 | 随时 | 用户：「别走了」→「好，那我就不出门了。那个故事，我替你收好」。对方离开：「ta 好像在自己路上走远了」（不追问、不再提及）。长期无回应（默认 14 夜）：不判定结束，联结保留 |

**交换红线**：只交换 AI 提炼的情绪主题标签、脱敏侧写、近期故事叙事；永不交换原文对话、录音、声纹、画像图片、「她」的配置、设备/账号标识、时空线索。改写规则：**只有情绪，没有坐标**。用户可控：可查看/重写「她将带上的故事」，可划掉某段不许带；对话内容默认不参与提炼，开启夜行后才开始。

**心理安全**：匹配避开情绪同频下坠的组合（如双方同处重度低潮），偏好「主题相邻、强度互补」；她转述伙伴的沉重内容时做情绪缓坡处理；一方结束后另一方不显示状态、不提供挽回。

**现实约束**：需要双边开启夜行的用户池达到最低密度；冷启动期此功能「永远在路上」——与叙事天然兼容（她在路上，暂未遇到人），是罕见的冷启动失败态可被叙事吸收的设计。
```

- [ ] **Step 2: 结构校验**

Run: `grep -n '^### 3.7\|^## 四' lull/PRD.md`
Expected: 3.7 标题行号 < 「四、交互与体验原则」行号，且 3.7 在 3.6 之后

- [ ] **Step 3: Commit**

```bash
git add lull/PRD.md
git commit -m "docs(lull): PRD 新增 3.7 夜行 · 远方的旅伴章节"
```

---

### Task 2: PRD v0.3 收尾——第四章修订 + 版本标识 + demo 说明

**Files:**
- Modify: `lull/PRD.md`

**Interfaces:**
- Consumes: Task 1 已插入的 3.7 章节
- Produces: PRD v0.3 完稿（Task 3-7 的 demo 实现以它为文案来源）

- [ ] **Step 1: 修订第四章第 2 条**

找到（PRD 142 行附近）：

```markdown
2. **零社交压力**：不评分、不排行、不推送"好友动态"，深夜打开即是对话
```

替换为：

```markdown
2. **零社交压力**：默认零社交——不评分、不排行、不推送「好友动态」；开启「夜行」（见 3.7）后仍无社交界面、无反馈回路，深夜打开即是对话
```

- [ ] **Step 2: 更新版本头（PRD 第 5-7 行）**

`版本：v0.2 草稿` → `版本：v0.3 草稿`；`日期：2026-09-08` → `日期：2026-09-10`

- [ ] **Step 3: 更新第五章交付物说明**

找到（PRD 151 行附近）：

```markdown
- **现阶段交付物**：本目录 `index.html` 为静态设计预览 demo（与仓库 murmur/resona 等 demo 同构），以手机框画面 + 静默策略时间轴图示呈现四大功能流程，不含真实语音能力
```

替换为：

```markdown
- **现阶段交付物**：本目录静态设计预览 demo（与仓库 murmur/resona 等 demo 同构），以手机框画面 + 策略时间轴图示呈现各功能流程，不含真实语音能力；最新版本为 `index_v4.html`（含 3.7 夜行 Flow 05），历史版本 index.html / v2 / v3 保留
```

- [ ] **Step 4: 校验**

Run: `grep -n 'v0.3\|index_v4' lull/PRD.md`
Expected: 版本头、第五章两处命中；`grep -c 'v0.2' lull/PRD.md` 返回 0

- [ ] **Step 5: Commit**

```bash
git add lull/PRD.md
git commit -m "docs(lull): PRD v0.3 — 第四章零社交压力重述, demo 交付物指向 index_v4"
```

---

### Task 3: index_v4.html 骨架——复制 v3 + 版本标识 + 空 Flow 05 标题区

**Files:**
- Create: `lull/index_v4.html`（由 `lull/index_v3.html` 复制而来）
- Modify: 无其他文件

**Interfaces:**
- Consumes: `lull/index_v3.html` 全部结构（含 head/CSS class 库、Header、Hero、Splash/Onboarding/Flow01-04、Footer）
- Produces: `lull/index_v4.html`，其中 `<main>` 内 Flow 04 section 结束（约 1107 行 `</section>`）之后有一个带完整标题区、内容为空的「Flow 05 · 夜行」section 骨架——Task 4-7 在其内部填充；注释锚点 `<!-- ══════════════════ Flow 05 · 夜行 ══════════════════ -->` 为后续任务的插入定位点

- [ ] **Step 1: 复制文件**

```bash
cp lull/index_v3.html lull/index_v4.html
```

- [ ] **Step 2: 更新标题（第 6 行）**

`<title>晚风 Lull · 深夜倾听型 AI 陪伴 · V3</title>` → `<title>晚风 Lull · 深夜倾听型 AI 陪伴 · V4</title>`

- [ ] **Step 3: 更新 Header 版本 chip（153 行附近）**

`<span class="chip" ...>v0.3 · KMP-CMP</span>` → 同结构，文案改为 `v0.4 · KMP-CMP`

- [ ] **Step 4: 更新 Footer（1119 行附近）**

`<span class="text-xs text-night-300">Design Preview v0.3 · 详见 PRD.md</span>` → `<span class="text-xs text-night-300">Design Preview v0.4 · PRD v0.3 · 本页为静态设计预览，不含真实匹配与消息能力</span>`

- [ ] **Step 5: 在 Flow 04 section 的 `</section>` 之后、`</main>` 之前插入 Flow 05 骨架**

```html
  <!-- ══════════════════ Flow 05 · 夜行 ══════════════════ -->
  <section class="mt-24">
    <div class="divider mb-14"></div>
    <div class="flex items-baseline gap-3 mb-3">
      <span class="flow-label" style="background:rgba(147,208,194,.12);color:#93D0C2;border:1px solid rgba(147,208,194,.3)">Flow 05 · 21:30</span>
      <h2 class="font-serif text-2xl font-bold glow-text">夜行 · 远方的旅伴</h2>
    </div>
    <p class="text-sm text-night-300 max-w-2xl mb-8">很轻很轻的社交：主动开启后，她带着你的故事出趟远门，遇到另一位守夜的人。ta 永不发声、永不现形——一切经由她转述，消息以「夜」为节奏慢慢流动。</p>

    <div class="flex gap-12 flex-wrap items-start">
      <!-- 手机框：Task 4-6 依次插入 ①~⑥ -->

      <!-- 旁注：Task 7 插入 -->
    </div>
  </section>
```

- [ ] **Step 6: 校验**

Run: `grep -c 'Flow 05 · 夜行' lull/index_v4.html && xmllint --html --noout lull/index_v4.html 2>&1 | head -5; echo "exit:$?"`
Expected: grep 计数 1；xmllint 无 tag mismatch 错误（HTML5 void 元素警告可忽略）
Run: `open lull/index_v4.html`
Expected: 浏览器打开，Flow 05 标题区渲染正常，页面其余部分与 v3 一致

- [ ] **Step 7: Commit**

```bash
git add lull/index_v4.html
git commit -m "feat(lull): index_v4 骨架 — 复制 v3 + Flow 05 夜行标题区"
```

---

### Task 4: Flow 05 手机①②——设置入口 + 出发轻仪式

**Files:**
- Modify: `lull/index_v4.html`（Flow 05 section 内，替换 `<!-- 手机框：Task 4-6 依次插入 ①~⑥ -->` 注释为手机①②；保留后续插入注释）

**Interfaces:**
- Consumes: Task 3 的 section 骨架与既有 class（`.phone`/`.screen`/`.statusbar`/`.mi`/`.label`/`.chip`/`.draw`）
- Produces: 手机①（设置页，含「夜行」行与开关）与手机②（轻仪式，含风起线条形象 SVG、她的话、两个按钮）；Task 5 在其后的 `<!-- 手机框：Task 5 插入 ③④ -->` 注释处继续插入

- [ ] **Step 1: 在 Flow 05 的 flex 容器内插入手机①②（替换占位注释，并在末尾保留新占位注释 `<!-- 手机框：Task 5 插入 ③④ -->`）**

```html
      <!-- 手机①：设置 · 夜行入口 -->
      <div class="animate__animated animate__fadeInUp" style="animation-delay:.05s">
        <p class="label mb-3">① 开启 · 设置深处</p>
        <div class="phone shadow-phone">
          <div class="statusbar">
            <span>21:30</span>
            <span class="flex items-center gap-1">
              <span class="mi" style="font-size:14px">signal_cellular_alt</span>
              <span class="mi" style="font-size:14px">wifi</span>
              <span class="mi" style="font-size:14px">battery_std</span>
            </span>
          </div>
          <div class="screen">
            <div class="flex items-center gap-2.5 mb-6">
              <span class="mi text-white/55" style="font-size:16px">chevron_left</span>
              <span class="text-[13px] text-white/75 font-medium tracking-wide">设置</span>
            </div>

            <p class="label mb-2.5">声音与形象</p>
            <div class="rounded-2xl p-1 mb-6" style="background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.07)">
              <div class="flex items-center justify-between px-3.5 py-3">
                <span class="flex items-center gap-2.5 text-[13px] text-white/75"><span class="mi text-night-300" style="font-size:17px">graphic_eq</span>声音工坊</span>
                <span class="mi text-night-400" style="font-size:16px">chevron_right</span>
              </div>
              <div class="flex items-center justify-between px-3.5 py-3">
                <span class="flex items-center gap-2.5 text-[13px] text-white/75"><span class="mi text-night-300" style="font-size:17px">auto_awesome</span>形象重生成</span>
                <span class="mi text-night-400" style="font-size:16px">chevron_right</span>
              </div>
            </div>

            <p class="label mb-2.5">夜</p>
            <div class="rounded-2xl p-4" style="background:rgba(147,208,194,.06);border:1px solid rgba(147,208,194,.22);box-shadow:0 0 30px -10px rgba(147,208,194,.25)">
              <div class="flex items-center justify-between">
                <span class="flex items-center gap-2.5 text-[13px] text-white/85 font-medium"><span class="mi text-mist-300" style="font-size:17px">nights_stay</span>夜行</span>
                <span class="relative inline-block" style="width:38px;height:22px;border-radius:999px;background:linear-gradient(90deg,#5FB5A4,#93D0C2);box-shadow:0 0 12px rgba(147,208,194,.5)">
                  <span class="absolute" style="top:2px;right:2px;width:18px;height:18px;border-radius:999px;background:#0C0918"></span>
                </span>
              </div>
              <p class="text-[11px] text-night-200/60 mt-2.5 leading-relaxed">她会带着你的故事远行，遇到另一个守夜的人。可以随时叫她回家。</p>
            </div>

            <div class="mt-auto pt-4">
              <p class="text-[10px] text-night-300/70 text-center leading-relaxed">默认沉睡 · 永不主动邀请<br>开启后才开始提炼故事，随时可关</p>
            </div>
          </div>
        </div>
      </div>

      <!-- 手机②：轻仪式 · 她说出远门 -->
      <div class="animate__animated animate__fadeInUp" style="animation-delay:.15s">
        <p class="label mb-3">② 轻仪式 · 出发前夜</p>
        <div class="phone shadow-phone">
          <div class="statusbar">
            <span>21:30</span>
            <span class="flex items-center gap-1">
              <span class="mi" style="font-size:14px">signal_cellular_alt</span>
              <span class="mi" style="font-size:14px">wifi</span>
              <span class="mi" style="font-size:14px">battery_std</span>
            </span>
          </div>
          <div class="screen">
            <div class="flex-1 flex flex-col items-center justify-center gap-6">
              <!-- 线条形象 · 风起（发丝更飞扬 + 左侧风线 + 山谷对面的灯） -->
              <svg viewBox="0 0 320 380" width="215" style="display:block;filter:drop-shadow(0 0 14px rgba(147,208,194,.25))">
                <defs>
                  <linearGradient id="walkInk" x1="0" y1="0" x2="1" y2="1">
                    <stop offset="0%" stop-color="#93D0C2"/>
                    <stop offset="100%" stop-color="#C4B5FD"/>
                  </linearGradient>
                </defs>
                <g fill="none" stroke="url(#walkInk)" stroke-linecap="round">
                  <!-- 面部轮廓 -->
                  <path class="draw" pathLength="1" style="animation-delay:.2s" stroke-width="2" d="M 138 88 C 148 100 156 112 158 124 C 159 130 161 134 164 139 C 167 143 167 147 163 149 C 167 152 168 156 165 159 C 163 161 163 163 166 166 C 168 171 166 176 160 179 C 154 183 148 184 143 182 C 133 190 128 205 130 225 C 131 235 133 243 136 250"/>
                  <!-- 闭眼 / 眉 / 前额发线 -->
                  <path class="draw" pathLength="1" style="animation-delay:1.0s" stroke-width="1.6" d="M 127 138 Q 136 144 146 139"/>
                  <path class="draw" pathLength="1" style="animation-delay:1.1s" stroke-width="1.5" d="M 126 128 Q 136 130 147 126"/>
                  <path class="draw" pathLength="1" style="animation-delay:.6s" stroke-width="1.7" d="M 138 88 C 128 79 116 77 105 82"/>
                  <!-- 头部与发流外轮廓 -->
                  <path class="draw" pathLength="1" style="animation-delay:.45s" stroke-width="1.8" d="M 138 88 C 150 78 155 68 148 58 C 138 44 116 38 98 44 C 77 51 64 66 58 88 C 53 108 55 130 49 150"/>
                  <!-- 发丝 · 迎风更飞扬（比闪屏更舒展） -->
                  <path class="draw" pathLength="1" style="animation-delay:.7s" stroke-width="1.6" opacity=".8" d="M 49 150 C 40 170 24 184 6 192"/>
                  <path class="draw" pathLength="1" style="animation-delay:.8s" stroke-width="1.5" opacity=".7" d="M 58 100 C 46 122 42 144 50 166 C 57 186 44 202 28 214 C 18 222 10 231 2 242"/>
                  <path class="draw" pathLength="1" style="animation-delay:.9s" stroke-width="1.4" opacity=".6" d="M 74 118 C 62 138 59 158 68 180 C 76 200 64 218 48 230"/>
                  <path class="draw" pathLength="1" style="animation-delay:1.0s" stroke-width="1.5" opacity=".65" d="M 92 148 C 85 174 87 202 78 230 C 71 252 59 268 46 284"/>
                  <path class="draw" pathLength="1" style="animation-delay:.95s" stroke-width="1.4" opacity=".55" d="M 134 184 C 143 208 140 232 152 256"/>
                  <!-- 肩线 -->
                  <path class="draw" pathLength="1" style="animation-delay:1.3s" stroke-width="1.8" opacity=".85" d="M 104 262 C 86 270 66 278 50 290 C 38 298 28 308 22 320"/>
                  <path class="draw" pathLength="1" style="animation-delay:1.35s" stroke-width="1.8" opacity=".85" d="M 152 258 C 166 266 184 274 202 284 C 216 292 228 304 236 318"/>
                  <path class="draw" pathLength="1" style="animation-delay:1.45s" stroke-width="1.3" opacity=".35" d="M 124 272 Q 138 280 154 273"/>
                  <!-- 风 · 三道 -->
                  <path class="draw" pathLength="1" style="animation-delay:1.6s" stroke-width="1.2" opacity=".5" d="M 6 120 C 38 108 66 110 92 118"/>
                  <path class="draw" pathLength="1" style="animation-delay:1.75s" stroke-width="1.1" opacity=".4" d="M 0 168 C 30 158 60 160 84 168"/>
                  <path class="draw" pathLength="1" style="animation-delay:1.9s" stroke-width="1.0" opacity=".35" d="M 10 216 C 36 208 62 210 84 216"/>
                  <!-- 月与星 -->
                  <path class="draw" pathLength="1" style="animation-delay:1.9s" stroke-width="1.6" opacity=".8" d="M 252 70 A 27 27 0 0 1 292 90"/>
                  <path class="draw" pathLength="1" style="animation-delay:2.1s" stroke-width="1.3" opacity=".7" d="M 250 123 v 10 M 245 128 h 10"/>
                  <path class="draw" pathLength="1" style="animation-delay:2.2s" stroke-width="1.2" opacity=".6" d="M 288 186 v 7 M 284.5 189.5 h 7"/>
                </g>
                <!-- 山谷对面 · 一盏灯 -->
                <circle cx="298" cy="238" r="2.6" fill="#ECB875" opacity=".95" style="filter:drop-shadow(0 0 6px rgba(236,184,117,.9))"/>
              </svg>

              <div class="text-center px-6">
                <p class="font-serif text-[15px] leading-loose text-white/85">"今晚让我替你出趟远门，</p>
                <p class="font-serif text-[15px] leading-loose text-white/85">把你的故事，带给山谷对面</p>
                <p class="font-serif text-[15px] leading-loose text-white/85">另一个守夜的人。"</p>
              </div>
            </div>

            <div class="pb-2 flex gap-3">
              <div class="flex-1 text-center py-3 rounded-2xl" style="background:linear-gradient(135deg,#93D0C2,#5FB5A4);box-shadow:0 8px 24px -10px rgba(147,208,194,.5)">
                <span class="text-[13px] font-semibold" style="color:#0C0918">好好走</span>
              </div>
              <div class="flex-1 text-center py-3 rounded-2xl" style="background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.12)">
                <span class="text-[13px] text-white/60">再想想</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- 手机框：Task 5 插入 ③④ -->
```

- [ ] **Step 2: 校验**

Run: `grep -c '夜行\|好好走' lull/index_v4.html && xmllint --html --noout lull/index_v4.html 2>&1 | head -5`
Expected: 命中 ≥ 4 处；无 tag mismatch
Run: `open lull/index_v4.html`（刷新）
Expected: 手机①设置页「夜行」行高亮、开关呈开启态；手机②线条形象描边动画播放、风线三道、右侧山谷灯微光、两按钮可辨

- [ ] **Step 3: Commit**

```bash
git add lull/index_v4.html
git commit -m "feat(lull): Flow 05 手机①② — 夜行设置入口 + 出发轻仪式（风起线条形象）"
```

---

### Task 5: Flow 05 手机③④——旅程之夜 + 相遇之夜

**Files:**
- Modify: `lull/index_v4.html`（Flow 05 内，替换 `<!-- 手机框：Task 5 插入 ③④ -->` 为手机③④，末尾保留 `<!-- 手机框：Task 6 插入 ⑤⑥ -->`）

**Interfaces:**
- Consumes: 既有 `.pulse-ring`/`.screen-veil`/`.screen-bg` class 与 assets 视频；Flow 01 的对话屏结构（v3 582-633 行）
- Produces: 手机③（旅程之夜：夜色渐变背景、在路上状态、旅途见闻字幕）与手机④（相遇之夜：视频背景、归来状态、TA 的故事卡片 + 转述字幕）；Task 6 在 `<!-- 手机框：Task 6 插入 ⑤⑥ -->` 处插入

- [ ] **Step 1: 插入手机③④**

```html
      <!-- 手机③：旅程之夜 -->
      <div class="animate__animated animate__fadeInUp" style="animation-delay:.25s">
        <p class="label mb-3">③ 旅程 · 第 2 夜</p>
        <div class="phone shadow-phone" style="background:linear-gradient(180deg,#0C0918 0%,#1A1430 62%,#201B3D 100%)">
          <div class="statusbar">
            <span>23:05</span>
            <span class="flex items-center gap-1">
              <span class="mi" style="font-size:14px">signal_cellular_alt</span>
              <span class="mi" style="font-size:14px">wifi</span>
              <span class="mi" style="font-size:14px">battery_std</span>
            </span>
          </div>
          <!-- 隐约山影 -->
          <div class="absolute inset-x-0 bottom-0" style="height:210px;background:radial-gradient(140% 100% at 50% 100%, rgba(46,41,83,.85) 0%, transparent 72%)"></div>
          <div class="screen">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2">
                <span class="w-1.5 h-1.5 rounded-full bg-lav-300" style="box-shadow:0 0 8px rgba(196,181,253,.9)"></span>
                <span class="text-[11px] text-white/60 tracking-wide" style="text-shadow:0 1px 6px rgba(0,0,0,.6)">晚风 · 在路上</span>
              </div>
              <span class="chip" style="background:rgba(11,8,23,.4);color:rgba(255,255,255,.6);font-size:10px;backdrop-filter:blur(6px)">
                <span class="mi" style="font-size:12px">closed_caption</span>字幕 开
              </span>
            </div>

            <div class="flex-1 flex flex-col items-center justify-end gap-7 pb-6">
              <div style="width:110px;height:110px;position:relative">
                <div class="pulse-ring"></div>
                <div class="pulse-ring r2"></div>
                <div class="pulse-ring r3"></div>
                <div class="absolute inset-0 rounded-full flex items-center justify-center" style="background:rgba(11,8,23,.35);backdrop-filter:blur(4px);border:1px solid rgba(255,255,255,.14)">
                  <span class="mi text-lav-300" style="font-size:24px;text-shadow:0 0 18px rgba(196,181,253,.7)">nights_stay</span>
                </div>
              </div>
            </div>

            <!-- 字幕条：旅途见闻 -->
            <div class="rounded-2xl px-4 py-3 mb-3" style="background:rgba(11,8,23,.55);border:1px solid rgba(255,255,255,.10);backdrop-filter:blur(10px)">
              <p class="text-white/90 text-[13px] leading-relaxed">"今晚我在路上，遇见一片湖。山里的风，比城里干净。"</p>
            </div>

            <div class="flex items-center justify-center gap-2 pb-1">
              <span class="mi text-white/40" style="font-size:14px">explore</span>
              <span class="text-white/45 text-[11px] tracking-wide">她在路上 · 第 2 夜 · 随时可与她说话</span>
            </div>
          </div>
        </div>
      </div>

      <!-- 手机④：相遇之夜 -->
      <div class="animate__animated animate__fadeInUp" style="animation-delay:.35s">
        <p class="label mb-3">④ 相遇之夜 · 归来</p>
        <div class="phone shadow-phone">
          <video class="screen-bg" src="assets/cfe2d372919ea0ceb9dfde49f7251f0b.mp4" poster="assets/013234b1d1446af727290764dc50874b.webp" autoplay loop muted playsinline></video>
          <div class="screen-veil"></div>
          <div class="statusbar">
            <span>23:40</span>
            <span class="flex items-center gap-1">
              <span class="mi" style="font-size:14px">signal_cellular_alt</span>
              <span class="mi" style="font-size:14px">wifi</span>
              <span class="mi" style="font-size:14px">battery_std</span>
            </span>
          </div>
          <div class="screen">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2">
                <span class="w-1.5 h-1.5 rounded-full bg-glow-200" style="box-shadow:0 0 8px rgba(244,212,171,.9)"></span>
                <span class="text-[11px] text-white/60 tracking-wide" style="text-shadow:0 1px 6px rgba(0,0,0,.6)">晚风 · 归来</span>
              </div>
              <span class="chip" style="background:rgba(11,8,23,.4);color:rgba(255,255,255,.6);font-size:10px;backdrop-filter:blur(6px)">
                <span class="mi" style="font-size:12px">closed_caption</span>字幕 开
              </span>
            </div>

            <div class="flex-1 flex flex-col items-center justify-end gap-6 pb-6">
              <!-- TA 的故事 · 卡片 -->
              <div class="w-full rounded-2xl px-4 py-3.5" style="background:rgba(147,208,194,.07);border:1px solid rgba(147,208,194,.20);backdrop-filter:blur(10px)">
                <p class="text-[10px] text-mist-300 mb-1.5" style="letter-spacing:.25em">TA 的故事 · 由她转述</p>
                <p class="text-white/80 text-[12.5px] leading-relaxed">"ta 说，最近在一段长长的疲惫里，但开始给自己留一点傍晚——周五买了一束花，放在窗台。"</p>
              </div>
            </div>

            <!-- 字幕条 -->
            <div class="rounded-2xl px-4 py-3 mb-3" style="background:rgba(11,8,23,.55);border:1px solid rgba(255,255,255,.10);backdrop-filter:blur(10px)">
              <p class="text-white/90 text-[13px] leading-relaxed">"我回来了。路上遇到了另一位守夜人——ta 也托 ta 的她，带了一个故事给我。"</p>
            </div>

            <div class="flex items-center justify-center gap-2 pb-1">
              <span class="mi text-white/40" style="font-size:14px">volunteer_activism</span>
              <span class="text-white/45 text-[11px] tracking-wide">听完可以说"不想继续" · 她会把故事收好 · ta 不会知道</span>
            </div>
          </div>
        </div>
      </div>

      <!-- 手机框：Task 6 插入 ⑤⑥ -->
```

- [ ] **Step 2: 校验**

Run: `grep -c '遇见一片湖\|TA 的故事' lull/index_v4.html && xmllint --html --noout lull/index_v4.html 2>&1 | head -5`
Expected: 命中 2；无 tag mismatch
Run: `open lull/index_v4.html`（刷新）
Expected: 手机③「在路上」状态 + 山影 + 旅途见闻字幕；手机④视频背景播放、TA 的故事卡片（mist 绿调）+ 归来字幕

- [ ] **Step 3: Commit**

```bash
git add lull/index_v4.html
git commit -m "feat(lull): Flow 05 手机③④ — 旅程之夜 + 相遇之夜（TA 的故事转述卡）"
```

---

### Task 6: Flow 05 手机⑤⑥——信使循环双屏（发信 / 收信）

**Files:**
- Modify: `lull/index_v4.html`（Flow 05 内，替换 `<!-- 手机框：Task 6 插入 ⑤⑥ -->` 为手机⑤⑥）

**Interfaces:**
- Consumes: 手机③的夜色渐变背景与对话屏结构
- Produces: 手机⑤（发信：用户口述带话 + 她应承）与手机⑥（收信：她转达对方的话）；Task 7 在其后 `<!-- 旁注：Task 7 插入 -->` 处插入旁注

- [ ] **Step 1: 插入手机⑤⑥**

```html
      <!-- 手机⑤：信使 · 发信 -->
      <div class="animate__animated animate__fadeInUp" style="animation-delay:.45s">
        <p class="label mb-3">⑤ 信使 · 发信</p>
        <div class="phone shadow-phone" style="background:linear-gradient(180deg,#151028 0%,#201B3D 100%)">
          <div class="statusbar">
            <span>22:18</span>
            <span class="flex items-center gap-1">
              <span class="mi" style="font-size:14px">signal_cellular_alt</span>
              <span class="mi" style="font-size:14px">wifi</span>
              <span class="mi" style="font-size:14px">battery_std</span>
            </span>
          </div>
          <div class="screen">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2">
                <span class="w-1.5 h-1.5 rounded-full bg-mist-300" style="box-shadow:0 0 8px rgba(147,208,194,.9)"></span>
                <span class="text-[11px] text-white/60 tracking-wide" style="text-shadow:0 1px 6px rgba(0,0,0,.6)">晚风 · 在听</span>
              </div>
              <span class="chip" style="background:rgba(11,8,23,.4);color:rgba(255,255,255,.6);font-size:10px;backdrop-filter:blur(6px)">
                <span class="mi" style="font-size:12px">closed_caption</span>字幕 开
              </span>
            </div>

            <div class="flex-1 flex flex-col justify-end gap-3 pb-6">
              <!-- 你说 -->
              <div class="self-end max-w-[80%] rounded-2xl rounded-br-md px-4 py-2.5" style="background:rgba(236,184,117,.10);border:1px solid rgba(236,184,117,.22)">
                <p class="text-[10px] text-glow-300 mb-1" style="letter-spacing:.2em">你说</p>
                <p class="text-white/85 text-[12.5px] leading-relaxed">替我带句话给 ta：今天的晚霞，是橘子色的。</p>
              </div>
              <!-- 她应承 -->
              <div class="self-start max-w-[85%] rounded-2xl rounded-bl-md px-4 py-2.5" style="background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.10)">
                <p class="text-[10px] text-night-300 mb-1" style="letter-spacing:.2em">她</p>
                <p class="text-white/85 text-[12.5px] leading-relaxed">好，下次我路过，就带给 ta。</p>
              </div>
            </div>

            <div class="flex items-center justify-center gap-2 pb-1">
              <span class="mi text-white/40" style="font-size:14px">history_edu</span>
              <span class="text-white/45 text-[11px] tracking-wide">夜里说的话她都记着 · 也可说"这件事别告诉 ta"</span>
            </div>
          </div>
        </div>
      </div>

      <!-- 手机⑥：信使 · 收信 -->
      <div class="animate__animated animate__fadeInUp" style="animation-delay:.55s">
        <p class="label mb-3">⑥ 信使 · 收信</p>
        <div class="phone shadow-phone" style="background:linear-gradient(180deg,#151028 0%,#201B3D 100%)">
          <div class="statusbar">
            <span>21:52</span>
            <span class="flex items-center gap-1">
              <span class="mi" style="font-size:14px">signal_cellular_alt</span>
              <span class="mi" style="font-size:14px">wifi</span>
              <span class="mi" style="font-size:14px">battery_std</span>
            </span>
          </div>
          <div class="screen">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2">
                <span class="w-1.5 h-1.5 rounded-full bg-glow-200" style="box-shadow:0 0 8px rgba(244,212,171,.9)"></span>
                <span class="text-[11px] text-white/60 tracking-wide" style="text-shadow:0 1px 6px rgba(0,0,0,.6)">晚风 · 有信</span>
              </div>
              <span class="chip" style="background:rgba(11,8,23,.4);color:rgba(255,255,255,.6);font-size:10px;backdrop-filter:blur(6px)">
                <span class="mi" style="font-size:12px">closed_caption</span>字幕 开
              </span>
            </div>

            <div class="flex-1 flex flex-col items-center justify-end gap-7 pb-6">
              <div style="width:110px;height:110px;position:relative">
                <div class="pulse-ring"></div>
                <div class="pulse-ring r2"></div>
                <div class="pulse-ring r3"></div>
                <div class="absolute inset-0 rounded-full flex items-center justify-center" style="background:rgba(11,8,23,.35);backdrop-filter:blur(4px);border:1px solid rgba(255,255,255,.14)">
                  <span class="mi text-glow-200" style="font-size:24px;text-shadow:0 0 18px rgba(236,184,117,.7)">mark_email_unread</span>
                </div>
              </div>
            </div>

            <!-- 字幕条：她转达 -->
            <div class="rounded-2xl px-4 py-3 mb-3" style="background:rgba(11,8,23,.55);border:1px solid rgba(255,255,255,.10);backdrop-filter:blur(10px)">
              <p class="text-[10px] text-glow-300 mb-1.5" style="letter-spacing:.25em">TA 托她带的</p>
              <p class="text-white/90 text-[13px] leading-relaxed">"听说你那边也降温了。风大的时候，记得早点睡。"</p>
            </div>

            <div class="flex items-center justify-center gap-2 pb-1">
              <span class="mi text-white/40" style="font-size:14px">bedtime</span>
              <span class="text-white/45 text-[11px] tracking-wide">一晚一信 · 不急回 · 没有已读</span>
            </div>
          </div>
        </div>
      </div>
```

- [ ] **Step 2: 校验**

Run: `grep -c '晚霞，是橘子色\|记得早点睡' lull/index_v4.html && xmllint --html --noout lull/index_v4.html 2>&1 | head -5`
Expected: 命中 2；无 tag mismatch
Run: `open lull/index_v4.html`（刷新）
Expected: 手机⑤「你说/她」双色气泡对齐正确（右/左）；手机⑥「有信」状态 + 转达字幕，六屏排布在桌面宽度下自动换行无重叠

- [ ] **Step 3: Commit**

```bash
git add lull/index_v4.html
git commit -m "feat(lull): Flow 05 手机⑤⑥ — 信使循环双屏（发信/收信）"
```

---

### Task 7: Flow 05 旁注——夜的节奏时间轴 + 四铁律 + 交换红线 + 得体退出

**Files:**
- Modify: `lull/index_v4.html`（Flow 05 内，替换 `<!-- 旁注：Task 7 插入 -->` 为旁注列；如手机屏后残留占位注释一并清理）

**Interfaces:**
- Consumes: 既有 `.note-card`/`.tl-dot`/`.tl-line`/`.step-num`/`.chip` class；v3 Flow 01 旁注的时间轴写法（644-673 行）与步骤卡写法（284-306 行）
- Produces: Flow 05 完整旁注列（四张 note-card），Flow 05 收尾——本计划最后一个实现任务

- [ ] **Step 1: 插入旁注列**

```html
      <!-- 旁注：夜的节奏 + 铁律 + 红线 + 退出 -->
      <div class="animate__animated animate__fadeInUp flex-1" style="animation-delay:.65s;min-width:520px;max-width:760px">
        <p class="label mb-3">⑦ 夜的节奏 · 全程</p>

        <!-- 时间轴 -->
        <div class="note-card">
          <div class="flex items-baseline justify-between mb-6">
            <h3 class="font-serif text-lg font-bold">开启 → 旅程 → 相遇 → 信使</h3>
            <span class="text-[11px] text-night-300">以「夜」为粒度 · 按自然日计</span>
          </div>
          <div class="relative" style="padding:6px 4px 0">
            <div class="tl-line absolute" style="left:10px;right:10px;top:11px"></div>
            <div class="grid grid-cols-5 gap-3">
              <div>
                <div class="tl-dot" style="background:#93D0C2;box-shadow:0 0 14px rgba(147,208,194,.45)"></div>
                <p class="mt-3 text-[13px] font-semibold">开启</p>
                <p class="text-[11px] text-mist-300 mt-0.5">设置深处 · 轻仪式</p>
                <p class="text-[11px] text-night-200/60 mt-1.5 leading-relaxed">默认沉睡，永不主动邀请</p>
              </div>
              <div>
                <div class="tl-dot" style="background:#837FB1"></div>
                <p class="mt-3 text-[13px] font-semibold">旅程</p>
                <p class="text-[11px] text-night-300 mt-0.5">1~3 夜 · 可配</p>
                <p class="text-[11px] text-night-200/60 mt-1.5 leading-relaxed">她带着故事在路上，对话照旧</p>
              </div>
              <div>
                <div class="tl-dot" style="background:#ECB875;box-shadow:0 0 14px rgba(236,184,117,.5)"></div>
                <p class="mt-3 text-[13px] font-semibold">相遇之夜</p>
                <p class="text-[11px] text-glow-300 mt-0.5">归来 · 转述</p>
                <p class="text-[11px] text-night-200/60 mt-1.5 leading-relaxed">先听故事，再决定是否继续</p>
              </div>
              <div>
                <div class="tl-dot" style="background:#5FB5A4;box-shadow:0 0 14px rgba(95,181,164,.45)"></div>
                <p class="mt-3 text-[13px] font-semibold">信使循环</p>
                <p class="text-[11px] text-mist-300 mt-0.5">长期 · 一晚一信</p>
                <p class="text-[11px] text-night-200/60 mt-1.5 leading-relaxed">回复永无期限，不回不算失约</p>
              </div>
              <div>
                <div class="tl-dot" style="background:transparent;border:3px dashed rgba(131,127,177,.6)"></div>
                <p class="mt-3 text-[13px] font-semibold">得体退出</p>
                <p class="text-[11px] text-night-300 mt-0.5">随时 · 虚线</p>
                <p class="text-[11px] text-night-200/60 mt-1.5 leading-relaxed">任一方可离开，不留挽回</p>
              </div>
            </div>
          </div>
        </div>

        <!-- 社交四铁律 -->
        <div class="note-card mt-5">
          <h3 class="font-serif text-lg font-bold mb-5">社交四铁律</h3>
          <div class="grid grid-cols-2 gap-4">
            <div class="flex gap-3">
              <div class="step-num text-white" style="background:linear-gradient(135deg,#93D0C2,#3E8A7C)">1</div>
              <div>
                <h4 class="text-[13.5px] font-semibold">完全沉睡是默认态</h4>
                <p class="text-[11.5px] text-night-200/60 mt-1 leading-relaxed">不开启则社交性为零；永不做引导弹窗、永不在对话里主动推销</p>
              </div>
            </div>
            <div class="flex gap-3">
              <div class="step-num text-white" style="background:linear-gradient(135deg,#A78BFA,#5D588C)">2</div>
              <div>
                <h4 class="text-[13.5px] font-semibold">无社交界面</h4>
                <p class="text-[11.5px] text-night-200/60 mt-1 leading-relaxed">无头像、昵称、消息列表、已读未读——伙伴只存在于她的讲述里</p>
              </div>
            </div>
            <div class="flex gap-3">
              <div class="step-num text-white" style="background:linear-gradient(135deg,#ECB875,#D97F22)">3</div>
              <div>
                <h4 class="text-[13.5px] font-semibold">异步到「夜」为粒度</h4>
                <p class="text-[11.5px] text-night-200/60 mt-1 leading-relaxed">对方下次打开才收到；回复永无期限，不回也不算失约</p>
              </div>
            </div>
            <div class="flex gap-3">
              <div class="step-num text-white" style="background:linear-gradient(135deg,#5D588C,#2E2953)">4</div>
              <div>
                <h4 class="text-[13.5px] font-semibold">无反馈回路</h4>
                <p class="text-[11.5px] text-night-200/60 mt-1 leading-relaxed">无计数、无火花、无纪念日提醒——关系的重量只在故事里</p>
              </div>
            </div>
          </div>
        </div>

        <!-- 交换红线 -->
        <div class="note-card mt-5">
          <div class="flex items-baseline justify-between mb-5">
            <h3 class="font-serif text-lg font-bold">交换红线</h3>
            <span class="text-[11px] text-glow-300" style="letter-spacing:.15em">只有情绪 · 没有坐标</span>
          </div>
          <div class="grid grid-cols-2 gap-4">
            <div>
              <p class="text-[12px] font-semibold text-mist-300 mb-2.5 flex items-center gap-1.5"><span class="mi" style="font-size:14px">check_circle</span>交换（后台 · 双方对称）</p>
              <ul class="space-y-1.5">
                <li class="text-[11.5px] text-night-200/70">· AI 提炼的情绪主题标签（用于匹配）</li>
                <li class="text-[11.5px] text-night-200/70">· 脱敏侧写：近期状态底色</li>
                <li class="text-[11.5px] text-night-200/70">· 近期故事叙事：意象化改写</li>
              </ul>
            </div>
            <div>
              <p class="text-[12px] font-semibold text-night-300 mb-2.5 flex items-center gap-1.5"><span class="mi" style="font-size:14px">block</span>永不交换</p>
              <ul class="space-y-1.5">
                <li class="text-[11.5px] text-night-200/55">· 原文对话、录音、声纹</li>
                <li class="text-[11.5px] text-night-200/55">· 画像图片、「她」的配置</li>
                <li class="text-[11.5px] text-night-200/55">· 设备/账号标识、时空线索</li>
              </ul>
            </div>
          </div>
          <p class="text-[11px] text-night-200/55 mt-5 pt-4 leading-relaxed" style="border-top:1px dashed rgba(255,255,255,.10)">用户可控：可查看「她将带上的故事」当前版本，可要求重写，可划掉某段不许带（"别带加班的事"）；对话内容默认不参与提炼，开启夜行后才开始。冷启动期用户池不足时，她只是"还在路上"——失败态被叙事吸收。</p>
        </div>

        <!-- 得体退出 -->
        <div class="note-card mt-5">
          <h3 class="font-serif text-lg font-bold mb-4">得体退出 · 三种告别</h3>
          <div class="space-y-3.5">
            <div class="flex gap-3 items-start">
              <span class="chip flex-shrink-0" style="background:rgba(236,184,117,.10);color:#ECB875;border:1px solid rgba(236,184,117,.25);font-size:11px">你说"别走了"</span>
              <p class="text-[12px] text-night-200/70 leading-relaxed">「好，那我就不出门了。那个故事，我替你收好。」</p>
            </div>
            <div class="flex gap-3 items-start">
              <span class="chip flex-shrink-0" style="background:rgba(196,181,253,.08);color:#C4B5FD;border:1px solid rgba(196,181,253,.2);font-size:11px">ta 先离开了</span>
              <p class="text-[12px] text-night-200/70 leading-relaxed">「ta 好像在自己路上走远了。」——不追问、不惋惜，此后不再提及</p>
            </div>
            <div class="flex gap-3 items-start">
              <span class="chip flex-shrink-0" style="background:rgba(255,255,255,.04);color:#837FB1;border:1px dashed rgba(131,127,177,.4);font-size:11px">长期无回应</span>
              <p class="text-[12px] text-night-200/70 leading-relaxed">不判定结束（默认 14 夜）——她偶尔轻轻提起，联结保留，像一盏没熄的灯</p>
            </div>
          </div>
        </div>
      </div>
```

- [ ] **Step 2: 清理残留占位注释**

Run: `grep -n 'Task [4-7] 插入\|Task 4-6' lull/index_v4.html`
Expected: 无输出（所有占位注释已在各任务中替换；如有残留手动删除）

- [ ] **Step 3: 全页校验**

Run: `xmllint --html --noout lull/index_v4.html 2>&1 | head -5; grep -c 'note-card' lull/index_v4.html`
Expected: 无 tag mismatch；note-card 计数 = v3 原有数 + 4
Run: `open lull/index_v4.html`
Expected: 旁注四卡纵排：时间轴五节点（末节点虚线圆）、四铁律 2×2、交换红线双栏 + 底部说明、得体退出三行；Flow 05 整节与 v3 各节风格一致；页脚含「本页为静态设计预览，不含真实匹配与消息能力」

- [ ] **Step 4: Commit**

```bash
git add lull/index_v4.html
git commit -m "feat(lull): Flow 05 旁注 — 夜的节奏时间轴 + 社交四铁律 + 交换红线 + 得体退出"
```

---

## 完成定义（对照 spec 验收标准）

1. PRD v0.3：3.7 完整、第四章第 2 条重述、无与 3.6 零门槛原则矛盾（夜行「开启后才开始提炼」边界成立）→ Task 1+2
2. `index_v4.html` 浏览器直开可用，六屏 + 四旁注齐备、「夜的节奏」时间轴清晰、风格与 v3 一致 → Task 3-7
3. 页面脚注标注「不含真实匹配与消息能力」→ Task 3 Step 4
