const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { Pool } = require('pg');
const { WebSocketServer } = require('ws');
const http = require('http');
const crypto = require('crypto');

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

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DATABASE_URL?.includes('railway.internal')
    ? false  // internal Railway network — no SSL needed
    : { rejectUnauthorized: false },
});

async function initDb() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      username TEXT UNIQUE NOT NULL,
      email TEXT UNIQUE,
      vessel_name TEXT NOT NULL,
      password_hash TEXT NOT NULL,
      reset_token TEXT,
      reset_token_expires BIGINT,
      lat DOUBLE PRECISION,
      lng DOUBLE PRECISION,
      sog DOUBLE PRECISION DEFAULT 0,
      cog DOUBLE PRECISION DEFAULT 0,
      last_seen BIGINT,
      created_at BIGINT DEFAULT EXTRACT(EPOCH FROM NOW())::BIGINT,
      banned BOOLEAN DEFAULT false
    );
    CREATE TABLE IF NOT EXISTS friendships (
      id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      friend_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at BIGINT DEFAULT EXTRACT(EPOCH FROM NOW())::BIGINT,
      UNIQUE(user_id, friend_id)
    );
    CREATE TABLE IF NOT EXISTS messages (
      id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      text TEXT NOT NULL,
      lat DOUBLE PRECISION,
      lng DOUBLE PRECISION,
      created_at BIGINT DEFAULT EXTRACT(EPOCH FROM NOW())::BIGINT
    );
    CREATE TABLE IF NOT EXISTS waypoints (
      id SERIAL PRIMARY KEY,
      sender_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      recipient_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      name TEXT,
      lat DOUBLE PRECISION NOT NULL,
      lng DOUBLE PRECISION NOT NULL,
      note TEXT,
      created_at BIGINT DEFAULT EXTRACT(EPOCH FROM NOW())::BIGINT
    );
  `);
  // Add banned column if it doesn't exist (migration for existing deployments)
  await pool.query(`
    ALTER TABLE users ADD COLUMN IF NOT EXISTS banned BOOLEAN DEFAULT false
  `).catch(() => {});
  console.log('Database schema ready');
}

// ── Auth middleware ───────────────────────────────────────────────────────────

function authMiddleware(req, res, next) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
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
  if (!username || !vesselName || !password)
    return res.status(400).json({ error: 'Missing fields' });
  if (username.length < 3)
    return res.status(400).json({ error: 'Username too short' });
  if (password.length < 6)
    return res.status(400).json({ error: 'Password too short' });
  try {
    const hash = await bcrypt.hash(password, 10);
    const result = await pool.query(
      'INSERT INTO users (username, vessel_name, password_hash) VALUES ($1, $2, $3) RETURNING id',
      [username, vesselName, hash]
    );
    const userId = result.rows[0].id;
    res.status(201).json({ token: makeToken(userId), userId, username, vesselName });
  } catch (err) {
    if (err.code === '23505') {
      res.status(409).json({ error: 'Username already taken' });
    } else {
      console.error('Register error:', err);
      res.status(500).json({ error: 'Server error' });
    }
  }
});

app.post('/auth/login', async (req, res) => {
  const { username, password } = req.body;
  if (!username || !password)
    return res.status(400).json({ error: 'Missing fields' });
  const result = await pool.query('SELECT * FROM users WHERE LOWER(username) = LOWER($1)', [username]);
  const user = result.rows[0];
  if (!user) return res.status(401).json({ error: 'Invalid username or password' });
  const ok = await bcrypt.compare(password, user.password_hash);
  if (!ok) return res.status(401).json({ error: 'Invalid username or password' });
  res.json({ token: makeToken(user.id), userId: user.id, username: user.username, vesselName: user.vessel_name });
});

app.post('/auth/forgot-password', async (req, res) => {
  const { identifier } = req.body;
  if (!identifier) return res.status(400).json({ error: 'Missing identifier' });
  res.json({ message: 'If that account exists, a reset link has been sent' });
  try {
    const result = await pool.query(
      'SELECT * FROM users WHERE LOWER(username) = LOWER($1) OR LOWER(email) = LOWER($1)',
      [identifier]
    );
    const user = result.rows[0];
    if (user) {
      const token = crypto.randomBytes(32).toString('hex');
      const expires = Date.now() + 3600 * 1000;
      await pool.query(
        'UPDATE users SET reset_token = $1, reset_token_expires = $2 WHERE id = $3',
        [token, expires, user.id]
      );
      console.log(`[ForgotPassword] Reset token for ${user.username}: ${token}`);
    }
  } catch (err) {
    console.error('Forgot password error:', err);
  }
});

app.post('/auth/reset-password', async (req, res) => {
  const { token, newPassword } = req.body;
  if (!token || !newPassword) return res.status(400).json({ error: 'Missing fields' });
  if (newPassword.length < 6) return res.status(400).json({ error: 'Password too short' });
  const result = await pool.query(
    'SELECT * FROM users WHERE reset_token = $1 AND reset_token_expires > $2',
    [token, Date.now()]
  );
  const user = result.rows[0];
  if (!user) return res.status(400).json({ error: 'Invalid or expired reset token' });
  const hash = await bcrypt.hash(newPassword, 10);
  await pool.query(
    'UPDATE users SET password_hash = $1, reset_token = NULL, reset_token_expires = NULL WHERE id = $2',
    [hash, user.id]
  );
  res.json({ message: 'Password reset successfully' });
});

// ── User / location ───────────────────────────────────────────────────────────

app.get('/users/me', authMiddleware, async (req, res) => {
  const result = await pool.query(
    'SELECT id, username, vessel_name, lat, lng, sog, cog FROM users WHERE id = $1',
    [req.userId]
  );
  const user = result.rows[0];
  if (!user) return res.status(404).json({ error: 'Not found' });
  res.json(user);
});

app.post('/users/location', authMiddleware, async (req, res) => {
  const { lat, lng, sog, cog } = req.body;
  await pool.query(
    'UPDATE users SET lat = $1, lng = $2, sog = $3, cog = $4, last_seen = $5 WHERE id = $6',
    [lat, lng, sog ?? 0, cog ?? 0, Date.now(), req.userId]
  );
  const userRes = await pool.query(
    'SELECT id, username, vessel_name, lat, lng, sog, cog FROM users WHERE id = $1',
    [req.userId]
  );
  const user = userRes.rows[0];
  const friendsRes = await pool.query(`
    SELECT u.id FROM users u
    JOIN friendships f ON (f.friend_id = u.id AND f.user_id = $1) OR (f.user_id = u.id AND f.friend_id = $1)
    WHERE f.status = 'accepted'
  `, [req.userId]);
  const payload = JSON.stringify({ type: 'friend_update', data: user });
  friendsRes.rows.forEach(f => {
    const conn = wsClients.get(f.id);
    if (conn?.readyState === 1) conn.send(payload);
  });
  res.json({ ok: true });
});

// ── Friends ───────────────────────────────────────────────────────────────────

app.get('/friends', authMiddleware, async (req, res) => {
  const result = await pool.query(`
    SELECT u.id, u.username, u.vessel_name, u.lat, u.lng, u.sog, u.cog, u.last_seen, f.status
    FROM users u
    JOIN friendships f ON (f.friend_id = u.id AND f.user_id = $1) OR (f.user_id = u.id AND f.friend_id = $1)
    WHERE f.status = 'accepted'
  `, [req.userId]);
  res.json(result.rows);
});

app.get('/friends/requests', authMiddleware, async (req, res) => {
  const result = await pool.query(`
    SELECT u.id, u.username, u.vessel_name, f.id as friendship_id
    FROM users u
    JOIN friendships f ON f.user_id = u.id
    WHERE f.friend_id = $1 AND f.status = 'pending'
  `, [req.userId]);
  res.json(result.rows);
});

app.post('/friends/add', authMiddleware, async (req, res) => {
  const { username } = req.body;
  const targetRes = await pool.query('SELECT id FROM users WHERE LOWER(username) = LOWER($1)', [username]);
  const target = targetRes.rows[0];
  if (!target) return res.status(404).json({ error: 'User not found' });
  if (target.id === req.userId) return res.status(400).json({ error: 'Cannot add yourself' });
  try {
    await pool.query(
      'INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, $3)',
      [req.userId, target.id, 'pending']
    );
    res.json({ ok: true });
  } catch (err) {
    if (err.code === '23505') {
      res.status(409).json({ error: 'Request already sent' });
    } else {
      res.status(500).json({ error: 'Server error' });
    }
  }
});

app.post('/friends/accept', authMiddleware, async (req, res) => {
  const { friendshipId } = req.body;
  const fRes = await pool.query(
    'SELECT * FROM friendships WHERE id = $1 AND friend_id = $2',
    [friendshipId, req.userId]
  );
  const f = fRes.rows[0];
  if (!f) return res.status(404).json({ error: 'Request not found' });
  await pool.query('UPDATE friendships SET status = $1 WHERE id = $2', ['accepted', friendshipId]);
  try {
    await pool.query(
      'INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, $3)',
      [req.userId, f.user_id, 'accepted']
    );
  } catch {}
  res.json({ ok: true });
});

app.post('/friends/remove', authMiddleware, async (req, res) => {
  const { friendId } = req.body;
  await pool.query(
    'DELETE FROM friendships WHERE (user_id = $1 AND friend_id = $2) OR (user_id = $2 AND friend_id = $1)',
    [req.userId, friendId]
  );
  res.json({ ok: true });
});

// ── Messages ──────────────────────────────────────────────────────────────────

app.get('/messages', authMiddleware, async (req, res) => {
  const page = parseInt(req.query.page) || 1;
  const limit = 50;
  const offset = (page - 1) * limit;
  const result = await pool.query(`
    SELECT m.id, m.text, m.lat, m.lng, m.created_at, u.username, u.vessel_name
    FROM messages m
    JOIN users u ON u.id = m.user_id
    ORDER BY m.created_at DESC LIMIT $1 OFFSET $2
  `, [limit, offset]);
  res.json(result.rows);
});

app.post('/messages', authMiddleware, async (req, res) => {
  const { text, lat, lng } = req.body;
  if (!text?.trim()) return res.status(400).json({ error: 'Message text required' });
  const insertRes = await pool.query(
    'INSERT INTO messages (user_id, text, lat, lng) VALUES ($1, $2, $3, $4) RETURNING id',
    [req.userId, text.trim(), lat ?? null, lng ?? null]
  );
  const msgRes = await pool.query(`
    SELECT m.id, m.text, m.lat, m.lng, m.created_at, u.username, u.vessel_name
    FROM messages m JOIN users u ON u.id = m.user_id WHERE m.id = $1
  `, [insertRes.rows[0].id]);
  const msg = msgRes.rows[0];
  const payload = JSON.stringify({ type: 'message', data: msg });
  wsClients.forEach(ws => { if (ws.readyState === 1) ws.send(payload); });
  res.status(201).json(msg);
});

// ── Waypoints ─────────────────────────────────────────────────────────────────

app.post('/waypoints/share', authMiddleware, async (req, res) => {
  const { recipientUsername, name, lat, lng, note } = req.body;
  const recipRes = await pool.query(
    'SELECT id FROM users WHERE LOWER(username) = LOWER($1)', [recipientUsername]
  );
  const recipient = recipRes.rows[0];
  if (!recipient) return res.status(404).json({ error: 'User not found' });
  const result = await pool.query(
    'INSERT INTO waypoints (sender_id, recipient_id, name, lat, lng, note) VALUES ($1, $2, $3, $4, $5, $6) RETURNING *',
    [req.userId, recipient.id, name ?? '', lat, lng, note ?? '']
  );
  const wp = result.rows[0];
  const conn = wsClients.get(recipient.id);
  if (conn?.readyState === 1) conn.send(JSON.stringify({ type: 'waypoint_shared', data: wp }));
  res.status(201).json(wp);
});

// ── Man Overboard ─────────────────────────────────────────────────────────────

app.post('/mob', authMiddleware, async (req, res) => {
  const { lat, lng } = req.body;
  const userRes = await pool.query('SELECT username, vessel_name FROM users WHERE id = $1', [req.userId]);
  const user = userRes.rows[0];
  const alert = { userId: req.userId, username: user.username, vesselName: user.vessel_name, lat, lng, timestamp: Date.now() };
  const payload = JSON.stringify({ type: 'mob', data: alert });
  wsClients.forEach(ws => { if (ws.readyState === 1) ws.send(payload); });
  res.json({ ok: true, alert });
});

// ── WebSocket ─────────────────────────────────────────────────────────────────

const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });
const wsClients = new Map();

wss.on('connection', (ws, req) => {
  const url = new URL(req.url, 'http://localhost');
  const token = url.searchParams.get('token');
  let userId;
  try {
    userId = jwt.verify(token, JWT_SECRET).userId;
  } catch {
    ws.close(4001, 'Invalid token');
    return;
  }
  wsClients.set(userId, ws);
  console.log(`WS connected: user ${userId} (${wsClients.size} total)`);
  ws.on('close', () => { wsClients.delete(userId); });
  ws.on('error', err => console.error(`WS error for user ${userId}:`, err.message));
  ws.on('message', data => {
    try {
      const msg = JSON.parse(data.toString());
      if (msg.type === 'ping') ws.send(JSON.stringify({ type: 'pong' }));
    } catch {}
  });
  const keepAlive = setInterval(() => {
    if (ws.readyState === 1) ws.send(JSON.stringify({ type: 'ping' }));
    else clearInterval(keepAlive);
  }, 30000);
});

// ── Start ─────────────────────────────────────────────────────────────────────

initDb().then(() => {
  server.listen(PORT, () => {
    console.log(`Fleet Social relay server running on port ${PORT}`);
  });
}).catch(err => {
  console.error('Failed to init database:', err);
  process.exit(1);
});

// ── Admin API ─────────────────────────────────────────────────────────────────

function adminAuth(req, res, next) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) return res.status(401).json({ error: 'No token' });
  try {
    const payload = jwt.verify(header.slice(7), JWT_SECRET);
    if (!payload.admin) return res.status(403).json({ error: 'Forbidden' });
    next();
  } catch {
    res.status(401).json({ error: 'Invalid token' });
  }
}

app.post('/admin/login', async (req, res) => {
  const { username, password } = req.body;
  if (username !== process.env.ADMIN_USERNAME || password !== process.env.ADMIN_PASSWORD) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }
  const token = jwt.sign({ admin: true, username }, JWT_SECRET, { expiresIn: '8h' });
  res.json({ token });
});

app.get('/admin/stats', adminAuth, async (req, res) => {
  const [users, messages, friendships] = await Promise.all([
    pool.query('SELECT COUNT(*) FROM users'),
    pool.query('SELECT COUNT(*) FROM messages'),
    pool.query("SELECT COUNT(*) FROM friendships WHERE status = 'accepted'"),
  ]);
  const onlineRes = await pool.query(
    'SELECT COUNT(*) FROM users WHERE last_seen > $1',
    [Date.now() - 5 * 60 * 1000]
  );
  const newTodayRes = await pool.query(
    'SELECT COUNT(*) FROM users WHERE created_at > $1',
    [Math.floor(Date.now() / 1000) - 86400]
  );
  res.json({
    totalUsers: parseInt(users.rows[0].count),
    totalMessages: parseInt(messages.rows[0].count),
    totalFriendships: parseInt(friendships.rows[0].count),
    onlineNow: parseInt(onlineRes.rows[0].count),
    newUsersToday: parseInt(newTodayRes.rows[0].count),
    wsConnections: wsClients.size,
  });
});

app.get('/admin/users', adminAuth, async (req, res) => {
  const page = parseInt(req.query.page) || 1;
  const limit = 50;
  const offset = (page - 1) * limit;
  const search = req.query.search || '';
  const result = await pool.query(`
    SELECT id, username, vessel_name, email, lat, lng, last_seen, created_at,
           (SELECT COUNT(*) FROM friendships WHERE (user_id = u.id OR friend_id = u.id) AND status = 'accepted') as friend_count,
           (SELECT COUNT(*) FROM messages WHERE user_id = u.id) as message_count,
           banned
    FROM users u
    WHERE $1 = '' OR LOWER(username) LIKE LOWER($1) OR LOWER(vessel_name) LIKE LOWER($1)
    ORDER BY created_at DESC LIMIT $2 OFFSET $3
  `, [search ? `%${search}%` : '', limit, offset]);
  const countRes = await pool.query(
    `SELECT COUNT(*) FROM users WHERE $1 = '' OR LOWER(username) LIKE LOWER($1) OR LOWER(vessel_name) LIKE LOWER($1)`,
    [search ? `%${search}%` : '']
  );
  res.json({ users: result.rows, total: parseInt(countRes.rows[0].count), page, limit });
});

app.get('/admin/messages', adminAuth, async (req, res) => {
  const page = parseInt(req.query.page) || 1;
  const limit = 50;
  const offset = (page - 1) * limit;
  const result = await pool.query(`
    SELECT m.id, m.text, m.lat, m.lng, m.created_at, u.username, u.vessel_name
    FROM messages m JOIN users u ON u.id = m.user_id
    ORDER BY m.created_at DESC LIMIT $1 OFFSET $2
  `, [limit, offset]);
  const countRes = await pool.query('SELECT COUNT(*) FROM messages');
  res.json({ messages: result.rows, total: parseInt(countRes.rows[0].count), page, limit });
});

app.delete('/admin/messages/:id', adminAuth, async (req, res) => {
  await pool.query('DELETE FROM messages WHERE id = $1', [req.params.id]);
  res.json({ ok: true });
});

app.post('/admin/users/:id/ban', adminAuth, async (req, res) => {
  await pool.query('UPDATE users SET banned = true WHERE id = $1', [req.params.id]);
  // Close WS if connected
  const conn = wsClients.get(parseInt(req.params.id));
  if (conn) { conn.close(4003, 'Banned'); wsClients.delete(parseInt(req.params.id)); }
  res.json({ ok: true });
});

app.post('/admin/users/:id/unban', adminAuth, async (req, res) => {
  await pool.query('UPDATE users SET banned = false WHERE id = $1', [req.params.id]);
  res.json({ ok: true });
});

app.delete('/admin/users/:id', adminAuth, async (req, res) => {
  await pool.query('DELETE FROM users WHERE id = $1', [req.params.id]);
  res.json({ ok: true });
});

app.get('/admin/activity', adminAuth, async (req, res) => {
  // Messages per day for last 14 days
  const result = await pool.query(`
    SELECT DATE(TO_TIMESTAMP(created_at)) as day, COUNT(*) as count
    FROM messages
    WHERE created_at > $1
    GROUP BY day ORDER BY day
  `, [Math.floor(Date.now() / 1000) - 14 * 86400]);
  // New users per day for last 14 days
  const usersResult = await pool.query(`
    SELECT DATE(TO_TIMESTAMP(created_at)) as day, COUNT(*) as count
    FROM users
    WHERE created_at > $1
    GROUP BY day ORDER BY day
  `, [Math.floor(Date.now() / 1000) - 14 * 86400]);
  res.json({ messages: result.rows, newUsers: usersResult.rows });
});
