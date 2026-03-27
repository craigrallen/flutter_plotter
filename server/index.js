const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const Database = require('better-sqlite3');
const { WebSocketServer } = require('ws');
const http = require('http');

const app = express();

// CORS — allow all origins (public API, no sensitive data without auth token)
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

app.use(express.json());

const PORT = process.env.PORT || 8080;
const JWT_SECRET = process.env.JWT_SECRET || 'floatilla-dev-secret-change-in-prod';

// ── Database ──────────────────────────────────────────────────────────────────

const db = new Database(process.env.DB_PATH || '/data/floatilla.db');

db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL COLLATE NOCASE,
    email TEXT UNIQUE,
    vessel_name TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    reset_token TEXT,
    reset_token_expires INTEGER,
    lat REAL,
    lng REAL,
    sog REAL DEFAULT 0,
    cog REAL DEFAULT 0,
    last_seen INTEGER,
    created_at INTEGER DEFAULT (unixepoch())
  );
  CREATE TABLE IF NOT EXISTS friendships (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    friend_id INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at INTEGER DEFAULT (unixepoch()),
    UNIQUE(user_id, friend_id)
  );
  CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    text TEXT NOT NULL,
    lat REAL,
    lng REAL,
    created_at INTEGER DEFAULT (unixepoch())
  );
  CREATE TABLE IF NOT EXISTS waypoints (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sender_id INTEGER NOT NULL,
    recipient_id INTEGER NOT NULL,
    name TEXT,
    lat REAL NOT NULL,
    lng REAL NOT NULL,
    note TEXT,
    created_at INTEGER DEFAULT (unixepoch())
  );
`);

// ── Auth middleware ───────────────────────────────────────────────────────────

function authMiddleware(req, res, next) {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'No token' });
  }
  try {
    const payload = jwt.verify(header.slice(7), JWT_SECRET);
    req.userId = payload.userId;
    next();
  } catch {
    res.status(401).json({ error: 'Invalid token' });
  }
}

function makeToken(userId) {
  return jwt.sign({ userId }, JWT_SECRET, { expiresIn: '30d' });
}

// ── Auth routes ───────────────────────────────────────────────────────────────

app.post('/auth/register', async (req, res) => {
  const { username, vesselName, password } = req.body;
  if (!username || !vesselName || !password) {
    return res.status(400).json({ error: 'Missing fields' });
  }
  if (username.length < 3) {
    return res.status(400).json({ error: 'Username too short' });
  }
  if (password.length < 6) {
    return res.status(400).json({ error: 'Password too short' });
  }
  try {
    const hash = await bcrypt.hash(password, 10);
    const stmt = db.prepare(
      'INSERT INTO users (username, vessel_name, password_hash) VALUES (?, ?, ?)'
    );
    const result = stmt.run(username, vesselName, hash);
    const token = makeToken(result.lastInsertRowid);
    res.status(201).json({ token, userId: result.lastInsertRowid, username, vesselName });
  } catch (err) {
    if (err.message.includes('UNIQUE')) {
      res.status(409).json({ error: 'Username already taken' });
    } else {
      console.error('Register error:', err);
      res.status(500).json({ error: 'Server error' });
    }
  }
});

app.post('/auth/login', async (req, res) => {
  const { username, password } = req.body;
  if (!username || !password) {
    return res.status(400).json({ error: 'Missing fields' });
  }
  const user = db.prepare('SELECT * FROM users WHERE username = ?').get(username);
  if (!user) {
    return res.status(401).json({ error: 'Invalid username or password' });
  }
  const ok = await bcrypt.compare(password, user.password_hash);
  if (!ok) {
    return res.status(401).json({ error: 'Invalid username or password' });
  }
  const token = makeToken(user.id);
  res.json({ token, userId: user.id, username: user.username, vesselName: user.vessel_name });
});

// Forgot password — fire and forget (don't leak user existence via timing/response)
app.post('/auth/forgot-password', async (req, res) => {
  const { identifier } = req.body; // username or email
  if (!identifier) {
    return res.status(400).json({ error: 'Missing identifier' });
  }
  // Always respond 200 regardless of whether user exists
  res.json({ message: 'If that account exists, a reset link has been sent' });

  // Background: generate token and log it (email sending would go here)
  try {
    const user = db.prepare(
      'SELECT * FROM users WHERE username = ? OR email = ?'
    ).get(identifier, identifier);
    if (user) {
      const token = require('crypto').randomBytes(32).toString('hex');
      const expires = Date.now() + 3600 * 1000; // 1 hour
      db.prepare(
        'UPDATE users SET reset_token = ?, reset_token_expires = ? WHERE id = ?'
      ).run(token, expires, user.id);
      // TODO: send email with reset link
      console.log(`[ForgotPassword] Reset token for ${user.username}: ${token}`);
    }
  } catch (err) {
    console.error('Forgot password error:', err);
  }
});

// Reset password with token
app.post('/auth/reset-password', async (req, res) => {
  const { token, newPassword } = req.body;
  if (!token || !newPassword) {
    return res.status(400).json({ error: 'Missing fields' });
  }
  if (newPassword.length < 6) {
    return res.status(400).json({ error: 'Password too short' });
  }
  const user = db.prepare(
    'SELECT * FROM users WHERE reset_token = ? AND reset_token_expires > ?'
  ).get(token, Date.now());
  if (!user) {
    return res.status(400).json({ error: 'Invalid or expired reset token' });
  }
  const hash = await bcrypt.hash(newPassword, 10);
  db.prepare(
    'UPDATE users SET password_hash = ?, reset_token = NULL, reset_token_expires = NULL WHERE id = ?'
  ).run(hash, user.id);
  res.json({ message: 'Password reset successfully' });
});

// ── User / location ───────────────────────────────────────────────────────────

app.get('/users/me', authMiddleware, (req, res) => {
  const user = db.prepare('SELECT id, username, vessel_name, lat, lng, sog, cog FROM users WHERE id = ?').get(req.userId);
  if (!user) return res.status(404).json({ error: 'Not found' });
  res.json(user);
});

app.post('/users/location', authMiddleware, (req, res) => {
  const { lat, lng, sog, cog } = req.body;
  db.prepare('UPDATE users SET lat = ?, lng = ?, sog = ?, cog = ?, last_seen = ? WHERE id = ?')
    .run(lat, lng, sog ?? 0, cog ?? 0, Date.now(), req.userId);

  // Broadcast to friends
  const friends = db.prepare(`
    SELECT u.id FROM users u
    JOIN friendships f ON (f.friend_id = u.id AND f.user_id = ?) OR (f.user_id = u.id AND f.friend_id = ?)
    WHERE f.status = 'accepted'
  `).all(req.userId, req.userId);

  const user = db.prepare('SELECT id, username, vessel_name, lat, lng, sog, cog FROM users WHERE id = ?').get(req.userId);
  const payload = JSON.stringify({ type: 'friend_update', data: user });
  friends.forEach(f => {
    const conn = wsClients.get(f.id);
    if (conn && conn.readyState === 1) conn.send(payload);
  });

  res.json({ ok: true });
});

// ── Friends ───────────────────────────────────────────────────────────────────

app.get('/friends', authMiddleware, (req, res) => {
  const friends = db.prepare(`
    SELECT u.id, u.username, u.vessel_name, u.lat, u.lng, u.sog, u.cog, u.last_seen, f.status
    FROM users u
    JOIN friendships f ON (f.friend_id = u.id AND f.user_id = ?) OR (f.user_id = u.id AND f.friend_id = ?)
    WHERE f.status = 'accepted'
  `).all(req.userId, req.userId);
  res.json(friends);
});

app.get('/friends/requests', authMiddleware, (req, res) => {
  const requests = db.prepare(`
    SELECT u.id, u.username, u.vessel_name, f.id as friendship_id
    FROM users u
    JOIN friendships f ON f.user_id = u.id
    WHERE f.friend_id = ? AND f.status = 'pending'
  `).all(req.userId);
  res.json(requests);
});

app.post('/friends/add', authMiddleware, (req, res) => {
  const { username } = req.body;
  const target = db.prepare('SELECT id FROM users WHERE username = ?').get(username);
  if (!target) return res.status(404).json({ error: 'User not found' });
  if (target.id === req.userId) return res.status(400).json({ error: 'Cannot add yourself' });
  try {
    db.prepare('INSERT INTO friendships (user_id, friend_id, status) VALUES (?, ?, ?)').run(req.userId, target.id, 'pending');
    res.json({ ok: true });
  } catch (err) {
    if (err.message.includes('UNIQUE')) {
      res.status(409).json({ error: 'Request already sent' });
    } else {
      res.status(500).json({ error: 'Server error' });
    }
  }
});

app.post('/friends/accept', authMiddleware, (req, res) => {
  const { friendshipId } = req.body;
  const f = db.prepare('SELECT * FROM friendships WHERE id = ? AND friend_id = ?').get(friendshipId, req.userId);
  if (!f) return res.status(404).json({ error: 'Request not found' });
  db.prepare('UPDATE friendships SET status = ? WHERE id = ?').run('accepted', friendshipId);
  // Also create reverse friendship for easy lookup
  try {
    db.prepare('INSERT INTO friendships (user_id, friend_id, status) VALUES (?, ?, ?)').run(req.userId, f.user_id, 'accepted');
  } catch {}
  res.json({ ok: true });
});

app.post('/friends/remove', authMiddleware, (req, res) => {
  const { friendId } = req.body;
  db.prepare('DELETE FROM friendships WHERE (user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)')
    .run(req.userId, friendId, friendId, req.userId);
  res.json({ ok: true });
});

// ── Messages ──────────────────────────────────────────────────────────────────

app.get('/messages', authMiddleware, (req, res) => {
  const page = parseInt(req.query.page) || 1;
  const limit = 50;
  const offset = (page - 1) * limit;
  const msgs = db.prepare(`
    SELECT m.id, m.text, m.lat, m.lng, m.created_at, u.username, u.vessel_name
    FROM messages m
    JOIN users u ON u.id = m.user_id
    ORDER BY m.created_at DESC LIMIT ? OFFSET ?
  `).all(limit, offset);
  res.json(msgs);
});

app.post('/messages', authMiddleware, (req, res) => {
  const { text, lat, lng } = req.body;
  if (!text || text.trim().length === 0) {
    return res.status(400).json({ error: 'Message text required' });
  }
  const result = db.prepare('INSERT INTO messages (user_id, text, lat, lng) VALUES (?, ?, ?, ?)')
    .run(req.userId, text.trim(), lat ?? null, lng ?? null);
  const msg = db.prepare(`
    SELECT m.id, m.text, m.lat, m.lng, m.created_at, u.username, u.vessel_name
    FROM messages m JOIN users u ON u.id = m.user_id WHERE m.id = ?
  `).get(result.lastInsertRowid);

  // Broadcast to all connected clients
  const payload = JSON.stringify({ type: 'message', data: msg });
  wsClients.forEach((ws) => {
    if (ws.readyState === 1) ws.send(payload);
  });

  res.status(201).json(msg);
});

// ── Waypoints ─────────────────────────────────────────────────────────────────

app.post('/waypoints/share', authMiddleware, (req, res) => {
  const { recipientUsername, name, lat, lng, note } = req.body;
  const recipient = db.prepare('SELECT id FROM users WHERE username = ?').get(recipientUsername);
  if (!recipient) return res.status(404).json({ error: 'User not found' });

  const result = db.prepare('INSERT INTO waypoints (sender_id, recipient_id, name, lat, lng, note) VALUES (?, ?, ?, ?, ?, ?)')
    .run(req.userId, recipient.id, name ?? '', lat, lng, note ?? '');
  const wp = db.prepare('SELECT * FROM waypoints WHERE id = ?').get(result.lastInsertRowid);

  // Notify recipient
  const conn = wsClients.get(recipient.id);
  if (conn && conn.readyState === 1) {
    conn.send(JSON.stringify({ type: 'waypoint_shared', data: wp }));
  }

  res.status(201).json(wp);
});

// ── Man Overboard ─────────────────────────────────────────────────────────────

app.post('/mob', authMiddleware, (req, res) => {
  const { lat, lng } = req.body;
  const user = db.prepare('SELECT username, vessel_name FROM users WHERE id = ?').get(req.userId);
  const alert = {
    userId: req.userId,
    username: user.username,
    vesselName: user.vessel_name,
    lat,
    lng,
    timestamp: Date.now(),
  };
  const payload = JSON.stringify({ type: 'mob', data: alert });
  wsClients.forEach((ws) => {
    if (ws.readyState === 1) ws.send(payload);
  });
  res.json({ ok: true, alert });
});

// ── WebSocket ─────────────────────────────────────────────────────────────────

const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });
const wsClients = new Map(); // userId → WebSocket

wss.on('connection', (ws, req) => {
  const url = new URL(req.url, 'http://localhost');
  const token = url.searchParams.get('token');
  let userId;
  try {
    const payload = jwt.verify(token, JWT_SECRET);
    userId = payload.userId;
  } catch {
    ws.close(4001, 'Invalid token');
    return;
  }

  wsClients.set(userId, ws);
  console.log(`WS connected: user ${userId} (${wsClients.size} total)`);

  ws.on('close', () => {
    wsClients.delete(userId);
    console.log(`WS disconnected: user ${userId} (${wsClients.size} total)`);
  });

  ws.on('error', (err) => {
    console.error(`WS error for user ${userId}:`, err.message);
  });

  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString());
      if (msg.type === 'ping') ws.send(JSON.stringify({ type: 'pong' }));
    } catch {}
  });

  // Send ping periodically to keep connection alive
  const keepAlive = setInterval(() => {
    if (ws.readyState === 1) ws.send(JSON.stringify({ type: 'ping' }));
    else clearInterval(keepAlive);
  }, 30000);
});

// ── Start ─────────────────────────────────────────────────────────────────────

server.listen(PORT, () => {
  console.log(`Fleet Social relay server running on port ${PORT}`);
});
