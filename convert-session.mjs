#!/usr/bin/env node
// Quick converter: Claude Code JSONL → Turnshare session JSON
import { readFileSync, writeFileSync } from 'fs';

const inputPath = process.argv[2];
if (!inputPath) { console.error('Usage: node convert-session.mjs <path.jsonl>'); process.exit(1); }

const lines = readFileSync(inputPath, 'utf8').split('\n').filter(Boolean);

const turns = [];
let sessionId, cwd, gitBranch, model;

for (const line of lines) {
  let entry;
  try { entry = JSON.parse(line); } catch { continue; }
  const type = entry.type;

  if (type === 'user') {
    const msg = entry.message;
    if (!msg || typeof msg.content !== 'string') continue;
    const timestamp = entry.timestamp;
    if (!timestamp) continue;

    turns.push({
      role: 'user',
      timestamp,
      content: [{ type: 'text', text: msg.content }]
    });

    if (!sessionId) {
      sessionId = entry.sessionId;
      cwd = entry.cwd;
      gitBranch = entry.gitBranch;
    }
  } else if (type === 'assistant') {
    const msg = entry.message;
    if (!msg?.content || !Array.isArray(msg.content)) continue;
    const timestamp = entry.timestamp;
    if (!timestamp) continue;

    if (!model && msg.model) model = msg.model;

    const blocks = [];
    for (const item of msg.content) {
      if (item.type === 'text' && item.text) {
        blocks.push({ type: 'text', text: item.text });
      } else if (item.type === 'tool_use' && item.name && item.id) {
        blocks.push({
          type: 'tool_use',
          name: item.name,
          id: item.id,
          input: item.input ? JSON.stringify(item.input) : undefined
        });
      }
      // Skip thinking blocks
    }
    if (blocks.length > 0) {
      turns.push({ role: 'assistant', timestamp, content: blocks });
    }
  } else if (type === 'tool_result') {
    const timestamp = entry.timestamp;
    if (!timestamp) continue;
    const toolUseId = entry.toolUseID || 'unknown';
    let output = '';
    if (typeof entry.result === 'string') {
      output = entry.result.slice(0, 5000);
    } else if (entry.result && typeof entry.result === 'object') {
      output = JSON.stringify(entry.result).slice(0, 5000);
    }
    turns.push({
      role: 'tool',
      timestamp,
      content: [{ type: 'tool_result', toolUseId, output }]
    });
  }
}

const projectName = cwd ? cwd.split('/').pop() : undefined;

const session = {
  version: '1',
  metadata: {
    agent: 'claude-code',
    model,
    sessionId: sessionId || inputPath.replace(/.*\//, '').replace('.jsonl', ''),
    projectName,
    projectPath: cwd,
    gitBranch,
    startedAt: turns[0]?.timestamp,
    endedAt: turns[turns.length - 1]?.timestamp
  },
  turns
};

writeFileSync('/dev/stdout', JSON.stringify(session, null, 2));
