#!/bin/bash
# X Digest Generator
# Fetches timeline, filters for signal, generates HTML

set -e

REPO_DIR="/Users/r/x-digest"
cd "$REPO_DIR"

# Topics we want (case-insensitive keywords)
INCLUDE_KEYWORDS="chip|semiconductor|nvidia|amd|intel|tsmc|asml|fab|wafer|AI|artificial intelligence|machine learning|LLM|GPT|Claude|Gemini|OpenAI|Anthropic|DeepMind|Google AI|Meta AI|xAI|Mistral|startup|funding|IPO|acquisition|merger|layoff|valuation|Series A|Series B|VC|venture|tech business|scoop|rumor|rumour|insider|reportedly|sources say|scandal|lawsuit|investigation|SEC|antitrust|whistleblower"

# Topics we don't want
EXCLUDE_KEYWORDS="trump|biden|maga|democrat|republican|election|vote|border|immigration|woke|DEI|trans|gender|abortion|gun|palestine|israel|gaza|ukraine|russia|war|military|sports|NFL|NBA|NBA|football|soccer|cricket|meme|viral|funny|lol|lmao"

DATE=$(date +"%Y-%m-%d")
DATETIME=$(date +"%A, %d %B %Y")

echo "📰 Fetching timeline..."
bird home --following -n 100 --json > /tmp/timeline.json 2>/dev/null || {
  echo "Failed to fetch timeline"
  exit 1
}

echo "🔍 Filtering tweets..."

# Use node for JSON processing (more reliable than jq for complex filtering)
node << 'NODEJS'
const fs = require('fs');

const includePattern = new RegExp(process.env.INCLUDE_KEYWORDS, 'i');
const excludePattern = new RegExp(process.env.EXCLUDE_KEYWORDS, 'i');

const raw = fs.readFileSync('/tmp/timeline.json', 'utf8');
const tweets = JSON.parse(raw);

const categorize = (text) => {
  const t = text.toLowerCase();
  if (/chip|semiconductor|nvidia|amd|intel|tsmc|asml|fab|wafer/i.test(t)) return 'Chips';
  if (/scandal|lawsuit|investigation|sec|antitrust|whistleblower/i.test(t)) return 'Scandal';
  if (/scoop|rumor|rumour|insider|reportedly|sources say/i.test(t)) return 'Scuttlebutt';
  if (/startup|funding|ipo|acquisition|merger|layoff|valuation|series [ab]|vc|venture/i.test(t)) return 'Tech Biz';
  if (/ai|artificial intelligence|machine learning|llm|gpt|claude|gemini|openai|anthropic|deepmind/i.test(t)) return 'AI';
  return 'Tech';
};

const filtered = tweets
  .filter(t => t.text && includePattern.test(t.text) && !excludePattern.test(t.text))
  .map(t => ({
    id: t.id,
    author: t.author?.name || 'Unknown',
    handle: t.author?.handle || 'unknown',
    text: t.text.replace(/</g, '&lt;').replace(/>/g, '&gt;'),
    url: `https://x.com/${t.author?.handle}/status/${t.id}`,
    likes: t.likes || 0,
    retweets: t.retweets || 0,
    category: categorize(t.text)
  }))
  .slice(0, 30); // Cap at 30 tweets

const output = {
  date: process.env.DATETIME,
  generated: new Date().toISOString(),
  count: filtered.length,
  tweets: filtered
};

fs.writeFileSync('/tmp/digest.json', JSON.stringify(output, null, 2));
console.log(`Found ${filtered.length} relevant tweets`);
NODEJS

echo "📝 Generating HTML..."

# Read the digest data
DIGEST_DATA=$(cat /tmp/digest.json)

# Generate the HTML with embedded data
cat > "$REPO_DIR/index.html" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>X Digest - $DATE</title>
  <style>
    :root {
      --bg: #0a0a0a;
      --card-bg: #151515;
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
    
    header {
      padding: 1.5rem 0;
      border-bottom: 1px solid var(--border);
      margin-bottom: 1.5rem;
    }
    
    h1 {
      font-size: 1.5rem;
      font-weight: 600;
      margin-bottom: 0.25rem;
    }
    
    .date {
      color: var(--text-muted);
      font-size: 0.9rem;
    }
    
    .count {
      color: var(--accent);
      font-size: 0.85rem;
      margin-top: 0.25rem;
    }
    
    .tweet {
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 1rem;
      margin-bottom: 1rem;
      transition: border-color 0.2s;
    }
    
    .tweet:hover {
      border-color: var(--accent);
    }
    
    .tweet-header {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      margin-bottom: 0.5rem;
      flex-wrap: wrap;
    }
    
    .author {
      font-weight: 600;
    }
    
    .handle {
      color: var(--text-muted);
    }
    
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
    
    .tweet-text {
      margin-bottom: 0.75rem;
      white-space: pre-wrap;
      word-wrap: break-word;
    }
    
    .tweet-meta {
      display: flex;
      gap: 1rem;
      font-size: 0.85rem;
      color: var(--text-muted);
      flex-wrap: wrap;
    }
    
    .tweet-link {
      color: var(--accent);
      text-decoration: none;
    }
    
    .tweet-link:hover {
      color: var(--accent-hover);
      text-decoration: underline;
    }
    
    .empty {
      text-align: center;
      color: var(--text-muted);
      padding: 3rem;
    }
    
    .stats {
      display: flex;
      gap: 0.75rem;
    }
  </style>
</head>
<body>
  <header>
    <h1>X Digest</h1>
    <p class="date">$DATETIME</p>
    <p class="count" id="count"></p>
  </header>
  
  <main id="tweets"></main>
  
  <script>
    const digestData = $DIGEST_DATA;
    
    if (digestData && digestData.tweets && digestData.tweets.length > 0) {
      document.getElementById('count').textContent = digestData.count + ' posts curated';
      const container = document.getElementById('tweets');
      container.innerHTML = digestData.tweets.map(t => \`
        <article class="tweet">
          <div class="tweet-header">
            <span class="author">\${t.author}</span>
            <span class="handle">@\${t.handle}</span>
            <span class="category \${t.category.toLowerCase().replace(' ', '-')}">\${t.category}</span>
          </div>
          <p class="tweet-text">\${t.text}</p>
          <div class="tweet-meta">
            <span class="stats">❤️ \${t.likes} · 🔁 \${t.retweets}</span>
            <a href="\${t.url}" target="_blank" rel="noopener" class="tweet-link">View thread →</a>
          </div>
        </article>
      \`).join('');
    } else {
      document.getElementById('tweets').innerHTML = '<p class="empty">No matching posts found today.</p>';
      document.getElementById('count').textContent = '0 posts';
    }
  </script>
</body>
</html>
HTMLEOF

echo "📤 Pushing to GitHub..."
cd "$REPO_DIR"
git add -A
git commit -m "Digest for $DATE" || echo "No changes"
git push

echo "✅ Done! https://raphdixon.github.io/x-digest/"
