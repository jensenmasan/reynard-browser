/*
 * 马老师沉浸式翻译 — background page
 *
 * 负责三件事：
 *  1. 工具栏按钮 / 右键菜单 触发当前页面的翻译开关
 *  2. 用扩展权限发起请求（不受页面 CORS 限制）
 *  3. 把免费接口与自有 OpenAI 兼容接口统一成 translateBatch()
 */

const MENU_ID = 'malaoshi-translate-page';
const DEFAULT_SETTINGS = {
  engine: 'google',
  targetLang: 'zh-CN',
  baseUrl: '',
  apiKey: '',
  model: '',
  displayMode: 'bilingual',
};

// ---------------------------------------------------------------- 入口绑定

function ensureMenu() {
  browser.menus.create(
    {
      id: MENU_ID,
      title: '沉浸式翻译此页',
      contexts: ['page', 'selection'],
    },
    () => void browser.runtime.lastError
  );
}

browser.runtime.onInstalled.addListener(ensureMenu);
browser.runtime.onStartup && browser.runtime.onStartup.addListener(ensureMenu);
ensureMenu();

function sendToggle(tab) {
  if (!tab || tab.id === undefined || tab.id === null) {
    return;
  }
  browser.tabs.sendMessage(tab.id, { type: 'mlt-toggle' }).catch(() => {
    // 页面可能还没注入内容脚本（例如 about: 页面），忽略即可。
  });
}

browser.menus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === MENU_ID) {
    sendToggle(tab);
  }
});

browser.browserAction.onClicked.addListener((tab) => {
  sendToggle(tab);
});

// ---------------------------------------------------------------- 设置读写

async function loadSettings() {
  const stored = await browser.storage.local.get('mlt.settings');
  return Object.assign({}, DEFAULT_SETTINGS, stored['mlt.settings'] || {});
}

// ---------------------------------------------------------------- 翻译引擎

function splitSegments(payload) {
  // Google 的 gtx 接口把长句切成多段返回，这里拼回整段。
  if (!Array.isArray(payload) || !Array.isArray(payload[0])) {
    return '';
  }
  return payload[0]
    .map((segment) => (Array.isArray(segment) ? segment[0] || '' : ''))
    .join('');
}

async function googleTranslateOne(text, settings) {
  const url =
    'https://translate.googleapis.com/translate_a/single' +
    '?client=gtx&dt=t&sl=auto&tl=' +
    encodeURIComponent(settings.targetLang) +
    '&q=' +
    encodeURIComponent(text);
  const response = await fetch(url, { credentials: 'omit', cache: 'no-store' });
  if (!response.ok) {
    throw new Error('翻译接口返回 HTTP ' + response.status);
  }
  const payload = await response.json();
  return splitSegments(payload);
}

async function googleTranslate(texts, settings) {
  const results = new Array(texts.length).fill('');
  const concurrency = 4;
  let cursor = 0;

  async function worker() {
    while (cursor < texts.length) {
      const index = cursor++;
      try {
        results[index] = await googleTranslateOne(texts[index], settings);
      } catch (error) {
        results[index] = '';
      }
    }
  }

  await Promise.all(Array.from({ length: Math.min(concurrency, texts.length) }, worker));
  return results;
}

function extractJsonArray(raw) {
  const text = String(raw || '').trim();
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const candidate = fenced ? fenced[1] : text;
  const start = candidate.indexOf('[');
  const end = candidate.lastIndexOf(']');
  if (start === -1 || end === -1 || end <= start) {
    throw new Error('自定义接口没有返回 JSON 数组');
  }
  return JSON.parse(candidate.slice(start, end + 1));
}

async function openAITranslate(texts, settings) {
  if (!settings.baseUrl || !settings.apiKey || !settings.model) {
    throw new Error('请先在设置里填写接口地址、密钥与模型');
  }

  const systemPrompt =
    '你是一名专业翻译。把用户给出的每一段编号文本翻译成' +
    settings.targetLang +
    '。要求：逐段对应，不合并、不拆分、不添加解释；保留原有标点与专有名词；' +
    '只输出一个 JSON 字符串数组，长度与段数一致，顺序一致。';
  const userPrompt = texts.map((text, index) => `[${index + 1}] ${text}`).join('\n');

  const response = await fetch(
    settings.baseUrl.replace(/\/+$/, '') + '/chat/completions',
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + settings.apiKey,
      },
      body: JSON.stringify({
        model: settings.model,
        temperature: 0.2,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userPrompt },
        ],
      }),
    }
  );

  if (!response.ok) {
    const detail = await response.text().catch(() => '');
    throw new Error('自定义接口返回 HTTP ' + response.status + ' ' + detail.slice(0, 120));
  }

  const payload = await response.json();
  const content =
    payload && payload.choices && payload.choices[0] && payload.choices[0].message
      ? payload.choices[0].message.content
      : '';
  const parsed = extractJsonArray(content);
  return texts.map((_, index) => (typeof parsed[index] === 'string' ? parsed[index] : ''));
}

async function translateBatch(texts, settings) {
  if (!Array.isArray(texts) || texts.length === 0) {
    return [];
  }

  if (settings.engine === 'openai') {
    return openAITranslate(texts, settings);
  }

  return googleTranslate(texts, settings);
}

browser.runtime.onMessage.addListener((message, sender) => {
  if (!message || message.type !== 'mlt-translate') {
    return undefined;
  }

  return (async () => {
    const settings = await loadSettings();
    try {
      const translations = await translateBatch(message.texts || [], settings);
      return { ok: true, translations };
    } catch (error) {
      return { ok: false, error: String(error && error.message ? error.message : error) };
    }
  })();
});
