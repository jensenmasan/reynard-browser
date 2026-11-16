/*
 * 马老师沉浸式翻译 — content script
 *
 * 把页面按「块级元素」切开，逐块请求翻译，然后在原文下方插入译文，
 * 形成双语对照。翻译请求统一交给 background 页面发出（不受页面 CORS 限制）。
 */

(() => {
  if (window.__malaoshiTranslateLoaded) {
    return;
  }
  window.__malaoshiTranslateLoaded = true;

  const DEFAULT_SETTINGS = {
    engine: 'google',
    targetLang: 'zh-CN',
    baseUrl: '',
    apiKey: '',
    model: '',
    displayMode: 'bilingual',
  };

  const LIMITS = {
    maxBlocks: 320,
    batchSize: 6,
    maxCharsPerBlock: 2000,
  };

  const SKIP_SELECTOR = [
    'script',
    'style',
    'noscript',
    'pre',
    'code',
    'kbd',
    'samp',
    'textarea',
    'input',
    'select',
    'option',
    'svg',
    'canvas',
    'iframe',
    'video',
    'audio',
    'template',
    '[contenteditable="true"]',
    '[aria-hidden="true"]',
    '.mlt-trans-block',
  ].join(',');

  const CANDIDATE_SELECTOR =
    'p,li,h1,h2,h3,h4,h5,h6,blockquote,dd,dt,figcaption,td,th,div,article,section,summary';

  const APPEND_INSIDE_TAGS = new Set([
    'LI',
    'TD',
    'TH',
    'DT',
    'DD',
    'FIGCAPTION',
    'BLOCKQUOTE',
    'SUMMARY',
  ]);

  const PAGE_STYLE_ID = 'malaoshi-translate-style';

  let settings = Object.assign({}, DEFAULT_SETTINGS);
  let isActive = false;
  let isTranslating = false;
  let records = [];
  let ui = null;
  let statusTimer = 0;

  // ------------------------------------------------------------- 存储

  async function loadSettings() {
    try {
      const stored = await browser.storage.local.get('mlt.settings');
      settings = Object.assign({}, DEFAULT_SETTINGS, stored['mlt.settings'] || {});
    } catch (error) {
      settings = Object.assign({}, DEFAULT_SETTINGS);
    }
  }

  async function saveSettings(next) {
    settings = Object.assign({}, settings, next);
    try {
      await browser.storage.local.set({ 'mlt.settings': settings });
    } catch (error) {
      // 存储失败不影响本次翻译
    }
  }

  // ------------------------------------------------------------- DOM 采集

  function isHidden(element) {
    if (!element.isConnected) {
      return true;
    }
    const style = window.getComputedStyle(element);
    if (!style || style.display === 'none' || style.visibility === 'hidden') {
      return true;
    }
    if (Number(style.opacity) === 0) {
      return true;
    }
    const rect = element.getBoundingClientRect();
    return rect.width === 0 && rect.height === 0;
  }

  function hasBlockLevelChild(element) {
    for (const child of element.children) {
      if (child.classList && child.classList.contains('mlt-trans-block')) {
        continue;
      }
      const display = window.getComputedStyle(child).display;
      if (!display) {
        continue;
      }
      if (display.startsWith('inline') || display === 'contents' || display === 'none') {
        continue;
      }
      return true;
    }
    return false;
  }

  function isTranslatableBlock(element) {
    if (element.closest(SKIP_SELECTOR)) {
      return false;
    }
    if (element.hasAttribute('data-mlt-translated')) {
      return false;
    }
    if (isHidden(element)) {
      return false;
    }
    if (hasBlockLevelChild(element)) {
      return false;
    }
    const text = (element.innerText || '').replace(/[ \t\u00a0]+/g, ' ').trim();
    if (text.length < 2 || text.length > LIMITS.maxCharsPerBlock) {
      return false;
    }
    // 只有符号或数字的块不值得翻译
    if (!/[A-Za-z\u00c0-\u024f\u0400-\u04ff\u0600-\u06ff\u3040-\u30ff\uac00-\ud7af]/.test(text)) {
      return false;
    }
    return true;
  }

  function collectBlocks() {
    if (!document.body) {
      return [];
    }

    const blocks = [];
    const candidates = document.body.querySelectorAll(CANDIDATE_SELECTOR);
    for (const element of candidates) {
      if (blocks.length >= LIMITS.maxBlocks) {
        break;
      }
      if (!isTranslatableBlock(element)) {
        continue;
      }
      // 跳过已经被外层块覆盖的重复文本
      if (blocks.some((kept) => kept.contains(element))) {
        continue;
      }
      blocks.push(element);
    }
    return blocks;
  }

  function blockText(element) {
    return (element.innerText || '')
      .replace(/[ \t\u00a0]+/g, ' ')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  // ------------------------------------------------------------- 渲染

  function ensurePageStyle() {
    if (document.getElementById(PAGE_STYLE_ID)) {
      return;
    }
    const style = document.createElement('style');
    style.id = PAGE_STYLE_ID;
    style.textContent = [
      '.mlt-trans-block{display:block;margin:4px 0 10px;line-height:1.65;font-size:0.98em;',
      'color:inherit;opacity:0.92;white-space:pre-wrap;word-break:break-word;}',
      '.mlt-trans-block.mlt-pending{opacity:0.45;}',
      '.mlt-source-children-hidden > *:not(.mlt-trans-block){display:none !important;}',
    ].join('');
    (document.head || document.documentElement).appendChild(style);
  }

  function createTranslationNode(text) {
    const node = document.createElement('div');
    node.className = 'mlt-trans-block';
    node.setAttribute('dir', 'auto');
    node.textContent = text;
    return node;
  }

  function renderTranslation(element, text) {
    const appendInside = APPEND_INSIDE_TAGS.has(element.tagName);
    const node = createTranslationNode(text);
    element.setAttribute('data-mlt-translated', '1');

    if (appendInside) {
      element.appendChild(node);
    } else {
      element.insertAdjacentElement('afterend', node);
    }

    const record = {
      source: element,
      node,
      appendInside,
      hiddenByMode: false,
    };
    records.push(record);
    return record;
  }

  function applyDisplayMode(mode) {
    for (const record of records) {
      const onlyTranslation = mode === 'translation';
      if (record.appendInside) {
        record.source.classList.toggle('mlt-source-children-hidden', onlyTranslation);
      } else if (onlyTranslation) {
        if (record.source.style.display !== 'none') {
          record.source.dataset.mltPreviousDisplay = record.source.style.display;
          record.source.style.display = 'none';
          record.hiddenByMode = true;
        }
      } else if (record.hiddenByMode) {
        record.source.style.display = record.source.dataset.mltPreviousDisplay || '';
        delete record.source.dataset.mltPreviousDisplay;
        record.hiddenByMode = false;
      }
      record.node.style.display = mode === 'original' ? 'none' : 'block';
    }
  }

  function clearTranslations() {
    for (const record of records) {
      if (record.appendInside) {
        record.source.classList.remove('mlt-source-children-hidden');
      } else if (record.hiddenByMode) {
        record.source.style.display = record.source.dataset.mltPreviousDisplay || '';
        delete record.source.dataset.mltPreviousDisplay;
      }
      record.source.removeAttribute('data-mlt-translated');
      record.node.remove();
    }
    records = [];
    document.querySelectorAll('.mlt-trans-block').forEach((node) => node.remove());
    document.querySelectorAll('[data-mlt-translated]').forEach((element) => {
      element.removeAttribute('data-mlt-translated');
    });
  }

  // ------------------------------------------------------------- 翻译流程

  async function requestTranslation(texts) {
    if (!texts.length) {
      return [];
    }
    try {
      const response = await browser.runtime.sendMessage({
        type: 'mlt-translate',
        texts,
      });
      if (!response || !response.ok) {
        throw new Error((response && response.error) || '翻译服务没有响应');
      }
      return response.translations || [];
    } catch (error) {
      throw new Error(
        String(error && error.message ? error.message : error) || '翻译请求失败'
      );
    }
  }

  async function translateBlocks(blocks) {
    for (let start = 0; start < blocks.length; start += LIMITS.batchSize) {
      const batch = blocks.slice(start, start + LIMITS.batchSize);
      const texts = batch.map(blockText);
      const placeholders = batch.map((element) =>
        renderTranslation(element, '翻译中…')
      );
      placeholders.forEach((record) => record.node.classList.add('mlt-pending'));

      let translations = [];
      try {
        translations = await requestTranslation(texts);
      } catch (error) {
        placeholders.forEach((record) => {
          record.node.classList.remove('mlt-pending');
          record.node.textContent = '翻译失败：' + error.message;
        });
        setStatus(error.message, true);
        return;
      }

      placeholders.forEach((record, index) => {
        record.node.classList.remove('mlt-pending');
        const value = (translations[index] || '').trim();
        record.node.textContent = value || '（没有返回译文）';
      });

      setStatus('已翻译 ' + Math.min(start + batch.length, blocks.length) + ' 段');
    }

    if (settings.displayMode === 'translation') {
      applyDisplayMode('translation');
    }
  }

  async function startTranslation() {
    if (isTranslating) {
      return;
    }

    const blocks = collectBlocks();
    if (!blocks.length) {
      setStatus('这个页面没有找到可翻译的内容', true);
      return;
    }

    ensurePageStyle();
    isTranslating = true;
    isActive = true;
    setStatus('正在翻译…');

    try {
      await translateBlocks(blocks);
      setStatus('翻译完成 · 共 ' + blocks.length + ' 段');
    } finally {
      isTranslating = false;
      syncUI();
    }
  }

  function restorePage() {
    clearTranslations();
    isActive = false;
    syncUI();
  }

  function toggleTranslation() {
    if (isActive) {
      restorePage();
    } else {
      startTranslation();
    }
  }

  // ------------------------------------------------------------- 悬浮 UI

  function createUI() {
    const host = document.createElement('div');
    host.id = 'malaoshi-translate-host';
    host.style.cssText = [
      'position:fixed',
      'right:14px',
      'bottom:96px',
      'z-index:2147483000',
      'width:0',
      'height:0',
      'overflow:visible',
    ].join(';');

    const shadow = host.attachShadow({ mode: 'open' });
    shadow.innerHTML = `
      <style>
        :host { all: initial; }
        * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
        .ball, .bar, .panel {
          font-family: -apple-system, "PingFang SC", "Helvetica Neue", sans-serif;
        }
        .ball {
          position: fixed; right: 14px; bottom: 96px;
          width: 40px; height: 40px; border-radius: 50%;
          display: flex; align-items: center; justify-content: center;
          color: #fff; font-size: 17px; font-weight: 700;
          background: linear-gradient(135deg, #5B7CFA, #8B5CF6);
          box-shadow: 0 6px 18px rgba(76, 81, 191, 0.38);
          cursor: pointer; user-select: none;
        }
        .ball:active { transform: scale(0.94); }
        .bar {
          position: fixed; right: 14px; bottom: 96px;
          display: none; align-items: center; gap: 4px;
          padding: 6px 8px; border-radius: 20px;
          background: rgba(28, 28, 32, 0.92);
          box-shadow: 0 8px 24px rgba(0, 0, 0, 0.28);
          backdrop-filter: blur(12px);
          color: #fff;
        }
        .bar.visible { display: flex; }
        .bar button {
          appearance: none; border: 0; background: transparent;
          color: rgba(255,255,255,0.72); font-size: 12px; font-weight: 600;
          padding: 6px 8px; border-radius: 14px; cursor: pointer;
        }
        .bar button.on { background: rgba(255,255,255,0.16); color: #fff; }
        .bar .icon { width: 26px; height: 26px; display: flex; align-items: center; justify-content: center; }
        .status {
          position: fixed; right: 14px; bottom: 146px;
          max-width: 60vw; padding: 6px 10px; border-radius: 12px;
          background: rgba(28,28,32,0.92); color: #fff;
          font-size: 12px; line-height: 1.4; display: none;
        }
        .status.visible { display: block; }
        .status.error { background: rgba(150, 30, 30, 0.94); }
        .panel {
          position: fixed; right: 14px; bottom: 146px; width: 280px;
          display: none; flex-direction: column; gap: 8px;
          padding: 14px; border-radius: 16px;
          background: rgba(28,28,32,0.96); color: #fff; font-size: 12px;
          box-shadow: 0 12px 32px rgba(0,0,0,0.35);
        }
        .panel.visible { display: flex; }
        .panel h3 { margin: 0 0 2px; font-size: 13px; font-weight: 700; }
        .panel label { display: flex; flex-direction: column; gap: 4px; color: rgba(255,255,255,0.72); }
        .panel input, .panel select {
          appearance: none; width: 100%; padding: 7px 9px; border-radius: 9px;
          border: 1px solid rgba(255,255,255,0.16); background: rgba(255,255,255,0.08);
          color: #fff; font-size: 12px;
        }
        .panel .row { display: flex; gap: 6px; }
        .panel .row button {
          flex: 1; padding: 8px 10px; border-radius: 10px; border: 0;
          background: rgba(255,255,255,0.14); color: #fff; font-size: 12px; font-weight: 600;
        }
        .panel .row button.primary { background: linear-gradient(135deg, #5B7CFA, #8B5CF6); }
      </style>
      <div class="ball" part="ball">译</div>
      <div class="bar">
        <button data-mode="bilingual">双语</button>
        <button data-mode="translation">仅译文</button>
        <button data-mode="original">原文</button>
        <button class="icon" data-action="settings" title="设置">⚙</button>
        <button class="icon" data-action="close" title="关闭">×</button>
      </div>
      <div class="status"></div>
      <div class="panel">
        <h3>沉浸式翻译设置</h3>
        <label>翻译服务
          <select data-field="engine">
            <option value="google">免费接口（无需密钥）</option>
            <option value="openai">自定义 OpenAI 兼容接口</option>
          </select>
        </label>
        <label>目标语言
          <input data-field="targetLang" type="text" placeholder="zh-CN" />
        </label>
        <label>接口地址（Base URL）
          <input data-field="baseUrl" type="url" placeholder="https://api.deepseek.com/v1" />
        </label>
        <label>API Key
          <input data-field="apiKey" type="password" placeholder="sk-..." />
        </label>
        <label>模型
          <input data-field="model" type="text" placeholder="deepseek-chat" />
        </label>
        <div class="row">
          <button data-action="cancel">取消</button>
          <button data-action="save" class="primary">保存</button>
        </div>
      </div>
    `;

    (document.body || document.documentElement).appendChild(host);

    const ball = shadow.querySelector('.ball');
    const bar = shadow.querySelector('.bar');
    const status = shadow.querySelector('.status');
    const panel = shadow.querySelector('.panel');

    ball.addEventListener('click', () => {
      if (!isActive) {
        startTranslation();
      }
      setUIExpanded(true);
    });

    bar.addEventListener('click', (event) => {
      const target = event.target.closest('button');
      if (!target) {
        return;
      }

      const mode = target.dataset.mode;
      if (mode) {
        settings.displayMode = mode;
        saveSettings({ displayMode: mode });
        applyDisplayMode(mode);
        syncUI();
        return;
      }

      const action = target.dataset.action;
      if (action === 'close') {
        setUIExpanded(false);
      } else if (action === 'settings') {
        openSettings();
      }
    });

    panel.addEventListener('click', (event) => {
      const target = event.target.closest('button');
      if (!target) {
        return;
      }
      if (target.dataset.action === 'cancel') {
        panel.classList.remove('visible');
      } else if (target.dataset.action === 'save') {
        const read = (field) => {
          const input = panel.querySelector('[data-field="' + field + '"]');
          return input ? input.value.trim() : '';
        };
        settings.engine = read('engine') || 'google';
        settings.targetLang = read('targetLang') || 'zh-CN';
        settings.baseUrl = read('baseUrl');
        settings.apiKey = read('apiKey');
        settings.model = read('model');
        saveSettings({
          engine: settings.engine,
          targetLang: settings.targetLang,
          baseUrl: settings.baseUrl,
          apiKey: settings.apiKey,
          model: settings.model,
        });
        panel.classList.remove('visible');
        setStatus('设置已保存');
      }
    });

    return { host, ball, bar, status, panel };
  }

  function ensureUI() {
    if (!ui) {
      ui = createUI();
    }
    return ui;
  }

  function setUIExpanded(expanded) {
    const current = ensureUI();
    current.ball.style.display = expanded ? 'none' : 'flex';
    current.bar.classList.toggle('visible', expanded);
    if (!expanded) {
      current.status.classList.remove('visible');
    }
  }

  function setStatus(text, isError = false) {
    const current = ensureUI();
    current.status.textContent = text;
    current.status.classList.toggle('error', !!isError);
    current.status.classList.add('visible');
    window.clearTimeout(statusTimer);
    statusTimer = window.setTimeout(() => {
      current.status.classList.remove('visible');
    }, isError ? 6000 : 3200);
  }

  function openSettings() {
    const current = ensureUI();
    const set = (field, value) => {
      const input = current.panel.querySelector('[data-field="' + field + '"]');
      if (input) {
        input.value = value || '';
      }
    };
    set('engine', settings.engine);
    set('targetLang', settings.targetLang);
    set('baseUrl', settings.baseUrl);
    set('apiKey', settings.apiKey);
    set('model', settings.model);
    current.panel.classList.add('visible');
  }

  function syncUI() {
    const current = ensureUI();
    current.bar.querySelectorAll('button[data-mode]').forEach((button) => {
      button.classList.toggle('on', button.dataset.mode === settings.displayMode);
    });
    current.ball.style.display = isActive ? 'none' : 'flex';
    if (isActive) {
      current.bar.classList.add('visible');
    }
  }

  // ------------------------------------------------------------- 消息与生命周期

  browser.runtime.onMessage.addListener((message) => {
    if (!message || message.type !== 'mlt-toggle') {
      return undefined;
    }
    toggleTranslation();
    return undefined;
  });

  (async () => {
    await loadSettings();
    if (!document.body) {
      return;
    }
    ensureUI();
    syncUI();
  })();
})();
