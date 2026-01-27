#!/bin/bash
# X Digest Generator
# Fetches For You timeline, filters for signal, maintains a rolling 7-day digest

set -e

REPO_DIR="/Users/r/x-digest"
cd "$REPO_DIR"

DATE=$(date +"%Y-%m-%d")
DATETIME=$(date +"%A, %d %B %Y")
TIMESTAMP=$(date +"%Y-%m-%d %H:%M")

echo "📰 Fetching For You timeline..."
bird home -n 150 --json > /tmp/timeline.json 2>/dev/null || {
  echo "Failed to fetch timeline"
  exit 1
}

echo "🔍 Filtering and generating HTML..."

DATETIME="$DATETIME" DATE="$DATE" TIMESTAMP="$TIMESTAMP" REPO_DIR="$REPO_DIR" node << 'NODEJS'
const fs = require('fs');
const path = require('path');

const REPO_DIR = process.env.REPO_DIR;
const POSTS_FILE = path.join(REPO_DIR, 'posts.json');
const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;

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

const getMediaType = (tweet) => {
  if (!tweet.media || tweet.media.length === 0) return null;
  const types = tweet.media.map(m => m.type);
  if (types.includes('video')) return 'video';
  if (types.includes('animated_gif')) return 'gif';
  if (types.includes('photo')) return 'image';
  return null;
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
    category: categorize(t.text || ''),
    addedAt: Date.now(),
    addedDate: process.env.TIMESTAMP,
    media: getMediaType(t)
  };
  
  if (t.quotedTweet) {
    base.quotedTweet = {
      author: escapeHtml(t.quotedTweet.author?.name || 'Unknown'),
      handle: escapeHtml(t.quotedTweet.author?.username || 'unknown'),
      text: escapeHtml(t.quotedTweet.text),
      url: `https://x.com/${t.quotedTweet.author?.username}/status/${t.quotedTweet.id}`,
      media: getMediaType(t.quotedTweet)
    };
  }
  
  return base;
};

// Load existing posts
let existingPosts = [];
try {
  if (fs.existsSync(POSTS_FILE)) {
    existingPosts = JSON.parse(fs.readFileSync(POSTS_FILE, 'utf8'));
  }
} catch (e) {
  console.log('No existing posts or error reading:', e.message);
}

// Get existing IDs for deduplication
const existingIds = new Set(existingPosts.map(p => p.id));

// Process new tweets
const raw = fs.readFileSync('/tmp/timeline.json', 'utf8');
const tweets = JSON.parse(raw);

const newPosts = tweets
  .filter(t => {
    if (!t.text) return false;
    if (existingIds.has(t.id)) return false; // Skip duplicates
    if (isLikelyAd(t)) return false;
    const matchesInclude = includePatterns.some(p => p.test(t.text));
    const matchesExclude = excludePatterns.some(p => p.test(t.text));
    return matchesInclude && !matchesExclude;
  })
  .map(formatTweet);

console.log(`Found ${newPosts.length} new posts`);

// Combine: new posts at top, then existing
const now = Date.now();
const allPosts = [...newPosts, ...existingPosts]
  .filter(p => (now - p.addedAt) < SEVEN_DAYS_MS) // Keep only last 7 days
  .slice(0, 200); // Cap total posts

// Save posts
fs.writeFileSync(POSTS_FILE, JSON.stringify(allPosts, null, 2));

const digestData = {
  date: process.env.DATETIME,
  updated: process.env.TIMESTAMP,
  count: allPosts.length,
  newCount: newPosts.length,
  tweets: allPosts
};

// Generate HTML
const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>X Digest</title>
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
      --bookmark: #f59e0b;
      --unread: #3b82f6;
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
    
    #gate { display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 50vh; gap: 1rem; }
    #gate input { background: var(--card-bg); border: 1px solid var(--border); padding: 0.75rem 1rem; border-radius: 8px; color: var(--text); font-size: 1rem; text-align: center; width: 120px; }
    #gate input:focus { outline: none; border-color: var(--accent); }
    #gate .error { color: #ef4444; font-size: 0.85rem; }
    #app { display: none; }
    
    .tabs { display: flex; gap: 0; margin-bottom: 1.5rem; border-bottom: 1px solid var(--border); }
    .tab { padding: 0.75rem 1.5rem; cursor: pointer; color: var(--text-muted); border-bottom: 2px solid transparent; transition: all 0.2s; }
    .tab:hover { color: var(--text); }
    .tab.active { color: var(--accent); border-bottom-color: var(--accent); }
    .tab-count { font-size: 0.75rem; background: var(--border); padding: 0.1rem 0.4rem; border-radius: 4px; margin-left: 0.5rem; }
    .tab-count.unread { background: var(--unread); color: white; }
    
    header { padding: 1.5rem 0 1rem; }
    h1 { font-size: 1.5rem; font-weight: 600; margin-bottom: 0.25rem; }
    .date { color: var(--text-muted); font-size: 0.9rem; }
    .updated { color: var(--text-muted); font-size: 0.8rem; margin-top: 0.25rem; }
    .count { color: var(--accent); font-size: 0.85rem; margin-top: 0.25rem; }
    
    .tweet {
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 1rem;
      margin-bottom: 1rem;
      transition: border-color 0.2s;
      position: relative;
    }
    .tweet:hover { border-color: var(--accent); }
    .tweet.unread { border-left: 3px solid var(--unread); }
    .tweet-header { display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.5rem; flex-wrap: wrap; padding-right: 3rem; }
    .author { font-weight: 600; }
    .handle { color: var(--text-muted); }
    .category {
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
    
    .media-badge {
      font-size: 0.7rem;
      background: #6366f122;
      color: #a5b4fc;
      padding: 0.2rem 0.5rem;
      border-radius: 4px;
    }
    
    .tweet-text { margin-bottom: 0.75rem; white-space: pre-wrap; word-wrap: break-word; }
    .quoted-tweet {
      background: var(--quote-bg);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 0.75rem;
      margin: 0.75rem 0;
      font-size: 0.9rem;
    }
    .quoted-tweet .tweet-header { margin-bottom: 0.25rem; padding-right: 0; }
    .quoted-tweet .tweet-text { margin-bottom: 0.5rem; }
    .tweet-meta { display: flex; gap: 1rem; font-size: 0.85rem; color: var(--text-muted); flex-wrap: wrap; align-items: center; }
    .tweet-link { color: var(--accent); text-decoration: none; }
    .tweet-link:hover { color: var(--accent-hover); text-decoration: underline; }
    .empty { text-align: center; color: var(--text-muted); padding: 3rem; }
    .stats { display: flex; gap: 0.75rem; }
    .added-time { font-size: 0.75rem; color: var(--text-muted); }
    
    .actions {
      position: absolute;
      top: 1rem;
      right: 1rem;
      display: flex;
      gap: 0.5rem;
    }
    .action-btn {
      background: none;
      border: none;
      cursor: pointer;
      font-size: 1.1rem;
      opacity: 0.4;
      transition: opacity 0.2s, transform 0.2s;
      padding: 0.2rem;
    }
    .action-btn:hover { opacity: 0.8; transform: scale(1.1); }
    .action-btn.active { opacity: 1; }
    .action-btn.bookmark.active { color: var(--bookmark); }
    .action-btn.read.active { color: #10b981; }
    
    .bookmark-date { font-size: 0.75rem; color: var(--text-muted); margin-bottom: 0.5rem; }
    
    .mark-all { 
      background: var(--card-bg); 
      border: 1px solid var(--border); 
      color: var(--text-muted); 
      padding: 0.5rem 1rem; 
      border-radius: 6px; 
      cursor: pointer; 
      font-size: 0.85rem;
      margin-bottom: 1rem;
    }
    .mark-all:hover { border-color: var(--accent); color: var(--text); }
  </style>
</head>
<body>
  <div id="gate">
    <h1>🔒</h1>
    <input type="password" id="pw" placeholder="Password" autofocus>
    <div class="error" id="error"></div>
  </div>
  
  <div id="app">
    <header>
      <h1>X Digest</h1>
      <p class="date" id="date"></p>
      <p class="updated" id="updated"></p>
      <p class="count" id="count"></p>
    </header>
    
    <div class="tabs">
      <div class="tab active" data-tab="feed">Feed <span class="tab-count" id="unread-count">0</span></div>
      <div class="tab" data-tab="bookmarks">Bookmarks <span class="tab-count" id="bookmark-count">0</span></div>
    </div>
    
    <main id="feed"></main>
    <main id="bookmarks" style="display: none;"></main>
  </div>
  
  <script>
    const PASSWORD = '!';
    const digestData = ${JSON.stringify(digestData)};
    
    if (sessionStorage.getItem('xdigest_auth') === '1') showApp();
    
    document.getElementById('pw').addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        if (e.target.value === PASSWORD) {
          sessionStorage.setItem('xdigest_auth', '1');
          showApp();
        } else {
          document.getElementById('error').textContent = 'Nope';
          e.target.value = '';
        }
      }
    });
    
    function showApp() {
      document.getElementById('gate').style.display = 'none';
      document.getElementById('app').style.display = 'block';
      renderFeed();
      renderBookmarks();
    }
    
    // Read tracking
    function getReadIds() {
      try { return new Set(JSON.parse(localStorage.getItem('xdigest_read') || '[]')); } 
      catch { return new Set(); }
    }
    function saveReadIds(ids) {
      localStorage.setItem('xdigest_read', JSON.stringify([...ids]));
      updateUnreadCount();
    }
    function isRead(id) { return getReadIds().has(id); }
    function toggleRead(id) {
      const ids = getReadIds();
      if (ids.has(id)) ids.delete(id); else ids.add(id);
      saveReadIds(ids);
      renderFeed();
    }
    function markAllRead() {
      const ids = getReadIds();
      digestData.tweets.forEach(t => ids.add(t.id));
      saveReadIds(ids);
      renderFeed();
    }
    function updateUnreadCount() {
      const readIds = getReadIds();
      const unread = digestData.tweets.filter(t => !readIds.has(t.id)).length;
      const el = document.getElementById('unread-count');
      el.textContent = unread;
      el.className = 'tab-count' + (unread > 0 ? ' unread' : '');
    }
    
    // Bookmarks
    function getBookmarks() {
      try { return JSON.parse(localStorage.getItem('xdigest_bookmarks') || '[]'); } 
      catch { return []; }
    }
    function saveBookmarks(bookmarks) {
      localStorage.setItem('xdigest_bookmarks', JSON.stringify(bookmarks));
      document.getElementById('bookmark-count').textContent = bookmarks.length;
    }
    function isBookmarked(id) { return getBookmarks().some(b => b.id === id); }
    function toggleBookmark(tweet) {
      let bookmarks = getBookmarks();
      const idx = bookmarks.findIndex(b => b.id === tweet.id);
      if (idx >= 0) bookmarks.splice(idx, 1);
      else bookmarks.unshift({ ...tweet, bookmarkedAt: new Date().toISOString() });
      saveBookmarks(bookmarks);
      renderFeed();
      renderBookmarks();
    }
    
    // Tabs
    document.querySelectorAll('.tab').forEach(tab => {
      tab.addEventListener('click', () => {
        document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
        tab.classList.add('active');
        const target = tab.dataset.tab;
        document.getElementById('feed').style.display = target === 'feed' ? 'block' : 'none';
        document.getElementById('bookmarks').style.display = target === 'bookmarks' ? 'block' : 'none';
      });
    });
    
    function getMediaBadge(media) {
      if (!media) return '';
      const icons = { video: '🎬 Video', image: '🖼️ Image', gif: '🎞️ GIF' };
      return '<span class="media-badge">' + (icons[media] || media) + '</span>';
    }
    
    function renderTweet(t, showDate = false, forBookmarks = false) {
      let quotedHtml = '';
      if (t.quotedTweet) {
        quotedHtml = \`
          <div class="quoted-tweet">
            <div class="tweet-header">
              <span class="author">\${t.quotedTweet.author}</span>
              <span class="handle">@\${t.quotedTweet.handle}</span>
              \${getMediaBadge(t.quotedTweet.media)}
            </div>
            <p class="tweet-text">\${t.quotedTweet.text}</p>
            <a href="\${t.quotedTweet.url}" target="_blank" rel="noopener" class="tweet-link">View original →</a>
          </div>\`;
      }
      const bookmarked = isBookmarked(t.id);
      const read = isRead(t.id);
      const dateHtml = showDate && t.addedDate ? '<div class="bookmark-date">From ' + t.addedDate + '</div>' : '';
      const tweetJson = JSON.stringify(t).replace(/'/g, "&apos;").replace(/</g, "&lt;");
      
      return \`
        <article class="tweet \${read ? '' : 'unread'}" data-id="\${t.id}">
          <div class="actions">
            <button class="action-btn read \${read ? 'active' : ''}" onclick="toggleRead('\${t.id}')" title="\${read ? 'Mark unread' : 'Mark read'}">
              \${read ? '✓' : '○'}
            </button>
            <button class="action-btn bookmark \${bookmarked ? 'active' : ''}" onclick='toggleBookmark(\${tweetJson})' title="\${bookmarked ? 'Remove bookmark' : 'Bookmark'}">
              \${bookmarked ? '★' : '☆'}
            </button>
          </div>
          \${dateHtml}
          <div class="tweet-header">
            <span class="author">\${t.author}</span>
            <span class="handle">@\${t.handle}</span>
            <span class="category \${t.category.toLowerCase().replace(' ', '-')}">\${t.category}</span>
            \${getMediaBadge(t.media)}
          </div>
          <p class="tweet-text">\${t.text}</p>
          \${quotedHtml}
          <div class="tweet-meta">
            <span class="stats">❤️ \${t.likes} · 🔁 \${t.retweets}</span>
            <span class="added-time">\${t.addedDate || ''}</span>
            <a href="\${t.url}" target="_blank" rel="noopener" class="tweet-link">View thread →</a>
          </div>
        </article>\`;
    }
    
    function renderFeed() {
      document.getElementById('date').textContent = digestData.date;
      document.getElementById('updated').textContent = 'Updated: ' + digestData.updated;
      document.getElementById('count').textContent = digestData.count + ' posts (rolling 7 days)';
      const container = document.getElementById('feed');
      if (digestData.tweets && digestData.tweets.length > 0) {
        container.innerHTML = '<button class="mark-all" onclick="markAllRead()">Mark all as read</button>' +
          digestData.tweets.map(t => renderTweet(t)).join('');
      } else {
        container.innerHTML = '<p class="empty">No matching posts found.</p>';
      }
      updateUnreadCount();
      document.getElementById('bookmark-count').textContent = getBookmarks().length;
    }
    
    function renderBookmarks() {
      const bookmarks = getBookmarks();
      const container = document.getElementById('bookmarks');
      if (bookmarks.length > 0) {
        container.innerHTML = bookmarks.map(t => renderTweet(t, true, true)).join('');
      } else {
        container.innerHTML = '<p class="empty">No bookmarks yet. Tap ☆ on a post to save it.</p>';
      }
    }
  </script>
</body>
</html>`;

fs.writeFileSync(path.join(REPO_DIR, 'index.html'), html);
NODEJS

echo "📤 Pushing to GitHub..."
git add -A
git commit -m "Update $TIMESTAMP" || echo "No changes"
git push

echo "✅ Done! https://raphdixon.github.io/x-digest/"
