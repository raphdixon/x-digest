#!/bin/bash
# X Digest Generator
# Fetches For You timeline, filters for signal, generates HTML with quote tweets

set -e

REPO_DIR="/Users/r/x-digest"
cd "$REPO_DIR"

DATE=$(date +"%Y-%m-%d")
DATETIME=$(date +"%A, %d %B %Y")

echo "📰 Fetching For You timeline..."
bird home -n 150 --json > /tmp/timeline.json 2>/dev/null || {
  echo "Failed to fetch timeline"
  exit 1
}

echo "🔍 Filtering and generating HTML..."

DATETIME="$DATETIME" DATE="$DATE" node << 'NODEJS'
const fs = require('fs');

// Topics we want
const includePatterns = [
  /chip|semiconductor|nvidia|amd|intel|tsmc|asml|fab|wafer|silicon/i,
  /\bAI\b|artificial intelligence|machine learning|LLM|GPT|Claude|Gemini|OpenAI|Anthropic|DeepMind|Google AI|Meta AI|xAI|Mistral/i,
  /startup|funding|IPO|acquisition|merger|layoff|valuation|Series [ABC]|venture capital|\bVC\b/i,
  /scoop|rumor|rumour|insider|reportedly|sources say|exclusive:/i,
  /scandal|lawsuit|investigation|\bSEC\b|antitrust|whistleblower|fraud/i,
  /Apple|Google|Microsoft|Amazon|Meta|Tesla|SpaceX/i
];

// Topics we don't want
const excludePatterns = [
  /trump|biden|maga|democrat|republican|election|vote|congress|senate/i,
  /border|immigration|woke|DEI|trans|gender|abortion|gun rights|2nd amendment/i,
  /palestine|israel|gaza|ukraine|russia|war|military|troops/i,
  /\bNFL\b|\bNBA\b|\bNHL\b|football|soccer|cricket|tennis|golf|Olympics/i,
  /meme|viral|funny|lol|lmao|rofl|😂|🤣|ratio|L take|W take/i,
  /giveaway|discount|promo code|limited time|act now|click here/i
];

// Ad detection heuristics
const isLikelyAd = (tweet) => {
  const text = tweet.text?.toLowerCase() || '';
  const lowEngagement = (tweet.likeCount || 0) < 10 && (tweet.retweetCount || 0) < 5;
  const promoLanguage = /\$0|free trial|sign up|limited time|offer|brokerage|invest|trading platform|sponsored/i.test(text);
  const suspiciousRatio = tweet.likeCount < 20 && text.length > 100 && /\.com|\.io|\.ai/i.test(text);
  return (lowEngagement && promoLanguage) || (lowEngagement && suspiciousRatio);
};

const categorize = (text) => {
  const t = text.toLowerCase();
  if (/chip|semiconductor|nvidia|amd|intel|tsmc|asml|fab|wafer|silicon/i.test(t)) return 'Chips';
  if (/scandal|lawsuit|investigation|sec|antitrust|whistleblower|fraud/i.test(t)) return 'Scandal';
  if (/scoop|rumor|rumour|insider|reportedly|sources say|exclusive/i.test(t)) return 'Scuttlebutt';
  if (/startup|funding|ipo|acquisition|merger|layoff|valuation|series [abc]|vc|venture/i.test(t)) return 'Tech Biz';
  if (/\bai\b|artificial intelligence|machine learning|llm|gpt|claude|gemini|openai|anthropic|deepmind/i.test(t)) return 'AI';
  return 'Tech';
};

const escapeHtml = (str) => {
  if (!str) return '';
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
};

const formatTweet = (t) => {
  const base = {
    id: t.id,
    author: escapeHtml(t.author?.name || 'Unknown'),
    handle: escapeHtml(t.author?.username || 'unknown'),
    text: escapeHtml(t.text),
    url: `https://x.com/${t.author?.username}/status/${t.id}`,
    likes: t.likeCount || 0,
    retweets: t.retweetCount || 0,
    category: categorize(t.text || '')
  };
  
  if (t.quotedTweet) {
    base.quotedTweet = {
      author: escapeHtml(t.quotedTweet.author?.name || 'Unknown'),
      handle: escapeHtml(t.quotedTweet.author?.username || 'unknown'),
      text: escapeHtml(t.quotedTweet.text),
      url: `https://x.com/${t.quotedTweet.author?.username}/status/${t.quotedTweet.id}`
    };
  }
  
  return base;
};

const raw = fs.readFileSync('/tmp/timeline.json', 'utf8');
const tweets = JSON.parse(raw);

const filtered = tweets
  .filter(t => {
    if (!t.text) return false;
    if (isLikelyAd(t)) return false;
    const matchesInclude = includePatterns.some(p => p.test(t.text));
    const matchesExclude = excludePatterns.some(p => p.test(t.text));
    return matchesInclude && !matchesExclude;
  })
  .map(formatTweet)
  .slice(0, 30);

const digestData = {
  date: process.env.DATETIME,
  generated: new Date().toISOString(),
  count: filtered.length,
  tweets: filtered
};

console.log(`Found ${filtered.length} relevant tweets`);

// Generate HTML directly
const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>X Digest - ${process.env.DATE}</title>
  <style>
    :root {
      --bg: #0a0a0a;
      --card-bg: #151515;
      --quote-bg: #1a1a1a;
      --border: #2a2a2a;
      --text: #e5e5e5;
      --text-muted: #888;
      --accent: #3b82f6;
      --accent-hover: #60a5fa;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.6;
      padding: 1rem;
      max-width: 700px;
      margin: 0 auto;
    }
    header { padding: 1.5rem 0; border-bottom: 1px solid var(--border); margin-bottom: 1.5rem; }
    h1 { font-size: 1.5rem; font-weight: 600; margin-bottom: 0.25rem; }
    .date { color: var(--text-muted); font-size: 0.9rem; }
    .count { color: var(--accent); font-size: 0.85rem; margin-top: 0.25rem; }
    .tweet {
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 1rem;
      margin-bottom: 1rem;
      transition: border-color 0.2s;
    }
    .tweet:hover { border-color: var(--accent); }
    .tweet-header { display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.5rem; flex-wrap: wrap; }
    .author { font-weight: 600; }
    .handle { color: var(--text-muted); }
    .category {
      margin-left: auto;
      font-size: 0.7rem;
      background: var(--border);
      padding: 0.2rem 0.5rem;
      border-radius: 4px;
      color: var(--text-muted);
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }
    .category.chips { background: #7c3aed22; color: #a78bfa; }
    .category.ai { background: #3b82f622; color: #60a5fa; }
    .category.tech-biz { background: #10b98122; color: #34d399; }
    .category.scuttlebutt { background: #f59e0b22; color: #fbbf24; }
    .category.scandal { background: #ef444422; color: #f87171; }
    .tweet-text { margin-bottom: 0.75rem; white-space: pre-wrap; word-wrap: break-word; }
    .quoted-tweet {
      background: var(--quote-bg);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 0.75rem;
      margin: 0.75rem 0;
      font-size: 0.9rem;
    }
    .quoted-tweet .tweet-header { margin-bottom: 0.25rem; }
    .quoted-tweet .tweet-text { margin-bottom: 0.5rem; }
    .tweet-meta { display: flex; gap: 1rem; font-size: 0.85rem; color: var(--text-muted); flex-wrap: wrap; }
    .tweet-link { color: var(--accent); text-decoration: none; }
    .tweet-link:hover { color: var(--accent-hover); text-decoration: underline; }
    .empty { text-align: center; color: var(--text-muted); padding: 3rem; }
    .stats { display: flex; gap: 0.75rem; }
  </style>
</head>
<body>
  <header>
    <h1>X Digest</h1>
    <p class="date">${digestData.date}</p>
    <p class="count">${digestData.count} posts curated</p>
  </header>
  <main>
    ${digestData.tweets.length > 0 ? digestData.tweets.map(t => {
      let quotedHtml = '';
      if (t.quotedTweet) {
        quotedHtml = `
          <div class="quoted-tweet">
            <div class="tweet-header">
              <span class="author">${t.quotedTweet.author}</span>
              <span class="handle">@${t.quotedTweet.handle}</span>
            </div>
            <p class="tweet-text">${t.quotedTweet.text}</p>
            <a href="${t.quotedTweet.url}" target="_blank" rel="noopener" class="tweet-link">View original →</a>
          </div>`;
      }
      return `
        <article class="tweet">
          <div class="tweet-header">
            <span class="author">${t.author}</span>
            <span class="handle">@${t.handle}</span>
            <span class="category ${t.category.toLowerCase().replace(' ', '-')}">${t.category}</span>
          </div>
          <p class="tweet-text">${t.text}</p>
          ${quotedHtml}
          <div class="tweet-meta">
            <span class="stats">❤️ ${t.likes} · 🔁 ${t.retweets}</span>
            <a href="${t.url}" target="_blank" rel="noopener" class="tweet-link">View thread →</a>
          </div>
        </article>`;
    }).join('') : '<p class="empty">No matching posts found today.</p>'}
  </main>
</body>
</html>`;

fs.writeFileSync('/Users/r/x-digest/index.html', html);
NODEJS

echo "📤 Pushing to GitHub..."
git add -A
git commit -m "Digest for $DATE" || echo "No changes"
git push

echo "✅ Done! https://raphdixon.github.io/x-digest/"
