import { cached, fetchJson } from '../cache.js';

// AI 相关新闻：HN Algolia（英文，真 AI 相关，稳定）为主，
// 少数派 RSS 过滤 AI 关键词（中文）作补充。全部失败时优雅降级。
const AI_KW = /AI|人工智能|大模型|LLM|GPT|Claude|Gemini|智能体|算力|芯片|英伟达|Copilot|OpenAI/i;

function parseRssTitles(xml, max) {
  const items = xml.match(/<item>[\s\S]*?<\/item>/g) || [];
  const out = [];
  for (const it of items) {
    const m = it.match(/<title>(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?<\/title>/);
    if (m && m[1].trim()) out.push(m[1].trim());
    if (out.length >= max) break;
  }
  return out;
}

export function getNews() {
  return cached('news', 10 * 60 * 1000, async () => {
    const items = [];
    const errors = [];

    // 1) HN Algolia：AI 相关 stories
    const r = await fetchJson(
      'https://hn.algolia.com/api/v1/search_by_date?query=AI&tags=story&hitsPerPage=6'
    );
    if (r.ok && r.data && Array.isArray(r.data.hits)) {
      for (const h of r.data.hits) {
        if (h.title) items.push({ title: h.title, source: 'HN' });
        if (items.length >= 4) break;
      }
    } else {
      errors.push('hn: ' + (r.error || 'fail'));
    }

    // 2) 少数派 RSS：过滤 AI 关键词（中文补充）
    try {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), 8000);
      const res = await fetch('https://sspai.com/feed', {
        signal: ctrl.signal,
        headers: { 'User-Agent': 'kindle-dash/1.0', Accept: 'application/rss+xml' }
      });
      clearTimeout(timer);
      const xml = await res.text();
      for (const t of parseRssTitles(xml, 12)) {
        if (AI_KW.test(t)) items.push({ title: t, source: '少数派' });
      }
    } catch (e) {
      errors.push('sspai: ' + e.message);
    }

    if (!items.length) {
      return { ok: false, error: errors.join('; ') || 'no news', items: [] };
    }
    return { ok: true, items: items.slice(0, 5), source: 'hn.algolia + sspai' };
  });
}
