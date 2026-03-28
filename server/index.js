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
  // Cloud sync tables
  await pool.query(`
    CREATE TABLE IF NOT EXISTS cloud_routes (
      user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      data JSONB NOT NULL DEFAULT '[]',
      updated_at BIGINT NOT NULL DEFAULT 0
    )
  `);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS cloud_waypoints (
      user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      data JSONB NOT NULL DEFAULT '[]',
      updated_at BIGINT NOT NULL DEFAULT 0
    )
  `);
  // Migrations for existing deployments
  await pool.query('ALTER TABLE users ADD COLUMN IF NOT EXISTS banned BOOLEAN DEFAULT false').catch(() => {});
  await pool.query('ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token TEXT').catch(() => {});
  await pool.query('ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_platform TEXT').catch(() => {});
  await pool.query('ALTER TABLE users ADD COLUMN IF NOT EXISTS is_pro BOOLEAN DEFAULT false').catch(() => {});
  await pool.query('ALTER TABLE users ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT').catch(() => {});
  await pool.query('ALTER TABLE users ADD COLUMN IF NOT EXISTS feature_flags JSONB DEFAULT \'{}\'').catch(() => {});
  await pool.query(`
    CREATE TABLE IF NOT EXISTS routes (
      id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      waypoints JSONB NOT NULL DEFAULT '[]',
      color TEXT,
      notes TEXT,
      created_at BIGINT DEFAULT EXTRACT(EPOCH FROM NOW())::BIGINT,
      updated_at BIGINT DEFAULT EXTRACT(EPOCH FROM NOW())::BIGINT
    )
  `).catch(() => {});
  await pool.query(`
    CREATE TABLE IF NOT EXISTS saved_waypoints (
      id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      name TEXT NOT NULL DEFAULT 'Waypoint',
      lat DOUBLE PRECISION NOT NULL,
      lng DOUBLE PRECISION NOT NULL,
      symbol TEXT,
      notes TEXT,
      created_at BIGINT DEFAULT EXTRACT(EPOCH FROM NOW())::BIGINT
    )
  `).catch(() => {});
  await pool.query(`
    CREATE TABLE IF NOT EXISTS logbook_entries (
      id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      lat DOUBLE PRECISION NOT NULL,
      lng DOUBLE PRECISION NOT NULL,
      sog DOUBLE PRECISION DEFAULT 0,
      cog DOUBLE PRECISION DEFAULT 0,
      heading DOUBLE PRECISION,
      depth DOUBLE PRECISION,
      wind_speed DOUBLE PRECISION,
      wind_angle DOUBLE PRECISION,
      note TEXT,
      entry_type TEXT DEFAULT 'auto',
      created_at BIGINT DEFAULT EXTRACT(EPOCH FROM NOW())::BIGINT
    )
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

// ── Cloud Sync (routes + waypoints) ──────────────────────────────────────────

// Schema note: cloud_routes and cloud_waypoints store the full payload as JSON
// per user. Each PUT replaces the user's full set (last-write-wins per device).

// Init runs in initDb so tables are guaranteed before routes are hit.
// (Tables added to initDb below.)

// GET /sync/routes — fetch the user's saved cloud routes
app.get('/sync/routes', authMiddleware, async (req, res) => {
  const result = await pool.query(
    'SELECT data, updated_at FROM cloud_routes WHERE user_id = $1',
    [req.userId]
  );
  if (result.rows.length === 0) return res.json({ routes: [], updatedAt: null });
  const row = result.rows[0];
  res.json({ routes: row.data, updatedAt: row.updated_at });
});

// PUT /sync/routes — upload / replace the user's cloud routes
app.put('/sync/routes', authMiddleware, async (req, res) => {
  const { routes } = req.body;
  if (!Array.isArray(routes)) return res.status(400).json({ error: 'routes must be an array' });
  const now = Date.now();
  await pool.query(
    `INSERT INTO cloud_routes (user_id, data, updated_at)
     VALUES ($1, $2, $3)
     ON CONFLICT (user_id) DO UPDATE SET data = $2, updated_at = $3`,
    [req.userId, JSON.stringify(routes), now]
  );
  res.json({ ok: true, updatedAt: now });
});

// GET /sync/waypoints — fetch the user's saved cloud waypoints
app.get('/sync/waypoints', authMiddleware, async (req, res) => {
  const result = await pool.query(
    'SELECT data, updated_at FROM cloud_waypoints WHERE user_id = $1',
    [req.userId]
  );
  if (result.rows.length === 0) return res.json({ waypoints: [], updatedAt: null });
  const row = result.rows[0];
  res.json({ waypoints: row.data, updatedAt: row.updated_at });
});

// PUT /sync/waypoints — upload / replace the user's cloud waypoints
app.put('/sync/waypoints', authMiddleware, async (req, res) => {
  const { waypoints } = req.body;
  if (!Array.isArray(waypoints)) return res.status(400).json({ error: 'waypoints must be an array' });
  const now = Date.now();
  await pool.query(
    `INSERT INTO cloud_waypoints (user_id, data, updated_at)
     VALUES ($1, $2, $3)
     ON CONFLICT (user_id) DO UPDATE SET data = $2, updated_at = $3`,
    [req.userId, JSON.stringify(waypoints), now]
  );
  res.json({ ok: true, updatedAt: now });
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


// ── FCM Push Token registration ────────────────────────────────────────────

app.post('/users/fcm-token', authMiddleware, async (req, res) => {
  const { token, platform } = req.body;
  if (!token) return res.status(400).json({ error: 'Missing token' });
  await pool.query(
    'UPDATE users SET fcm_token = $1, fcm_platform = $2 WHERE id = $3',
    [token, platform || 'android', req.userId]
  ).catch(() => {}); // column may not exist yet, handled in schema init
  res.json({ ok: true });
});

// ── Voyage Logbook ──────────────────────────────────────────────────────────

app.post('/logbook/entry', authMiddleware, async (req, res) => {
  const { lat, lng, sog, cog, heading, depth, windSpeed, windAngle, note, entryType } = req.body;
  if (lat == null || lng == null) return res.status(400).json({ error: 'lat/lng required' });
  const result = await pool.query(
    `INSERT INTO logbook_entries (user_id, lat, lng, sog, cog, heading, depth, wind_speed, wind_angle, note, entry_type, created_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,EXTRACT(EPOCH FROM NOW())::BIGINT) RETURNING id`,
    [req.userId, lat, lng, sog||0, cog||0, heading||null, depth||null, windSpeed||null, windAngle||null, note||null, entryType||'auto']
  );
  res.status(201).json({ id: result.rows[0].id });
});

app.get('/logbook', authMiddleware, async (req, res) => {
  const limit = Math.min(parseInt(req.query.limit)||500, 1000);
  const since = req.query.since ? parseInt(req.query.since) : 0;
  const result = await pool.query(
    `SELECT * FROM logbook_entries WHERE user_id = $1 AND created_at > $2 ORDER BY created_at DESC LIMIT $3`,
    [req.userId, since, limit]
  );
  res.json(result.rows);
});

app.get('/logbook/gpx', authMiddleware, async (req, res) => {
  const since = req.query.since ? parseInt(req.query.since) : Date.now()/1000 - 86400*7;
  const result = await pool.query(
    `SELECT lat, lng, sog, cog, note, created_at FROM logbook_entries
     WHERE user_id = $1 AND created_at > $2 ORDER BY created_at ASC`,
    [req.userId, since]
  );
  const user = await pool.query('SELECT username, vessel_name FROM users WHERE id=$1',[req.userId]);
  const u = user.rows[0];
  const trkpts = result.rows.map(r => {
    const dt = new Date(r.created_at * 1000).toISOString();
    return `    <trkpt lat="${r.lat}" lon="${r.lng}"><time>${dt}</time>${r.sog ? `<speed>${(r.sog*0.514444).toFixed(2)}</speed>` : ''}${r.note ? `<desc>${r.note}</desc>` : ''}</trkpt>`;
  }).join('\n');
  const gpx = `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Floatilla">
  <trk><name>${u?.vessel_name || u?.username || 'My Vessel'} Voyage Log</name>
    <trkseg>\n${trkpts}\n    </trkseg>
  </trk>
</gpx>`;
  res.setHeader('Content-Type', 'application/gpx+xml');
  res.setHeader('Content-Disposition', `attachment; filename="floatilla-log-${Date.now()}.gpx"`);
  res.send(gpx);
});

// ── Anchor drag push alert via server ──────────────────────────────────────
// App posts to this when anchor drags — server can relay to other registered devices

app.post('/alerts/anchor-drag', authMiddleware, async (req, res) => {
  const { lat, lng, radiusM, distanceM } = req.body;
  const user = await pool.query('SELECT username, vessel_name FROM users WHERE id=$1',[req.userId]);
  const u = user.rows[0];
  const alert = {
    type: 'anchor_drag',
    userId: req.userId,
    username: u?.username,
    vesselName: u?.vessel_name,
    lat, lng, radiusM, distanceM,
    timestamp: Date.now(),
  };
  // Broadcast to own WS connection (other devices same user)
  const conn = wsClients.get(req.userId);
  if (conn?.readyState === 1) conn.send(JSON.stringify({ type: 'anchor_drag', data: alert }));
  // Log it
  console.log(`[AnchorDrag] ${u?.username} dragged ${Math.round(distanceM)}m from anchor`);
  res.json({ ok: true });
});

// ── Route / waypoint cloud sync ─────────────────────────────────────────────

app.get('/routes', authMiddleware, async (req, res) => {
  const result = await pool.query(
    'SELECT * FROM routes WHERE user_id = $1 ORDER BY updated_at DESC',
    [req.userId]
  );
  res.json(result.rows);
});

app.post('/routes', authMiddleware, async (req, res) => {
  const { name, waypoints, color, notes } = req.body;
  if (!name || !waypoints) return res.status(400).json({ error: 'name and waypoints required' });
  const result = await pool.query(
    `INSERT INTO routes (user_id, name, waypoints, color, notes, created_at, updated_at)
     VALUES ($1,$2,$3,$4,$5,$6,$6) RETURNING *`,
    [req.userId, name, JSON.stringify(waypoints), color||null, notes||null, Math.floor(Date.now()/1000)]
  );
  res.status(201).json(result.rows[0]);
});

app.put('/routes/:id', authMiddleware, async (req, res) => {
  const { name, waypoints, color, notes } = req.body;
  await pool.query(
    'UPDATE routes SET name=$1, waypoints=$2, color=$3, notes=$4, updated_at=$5 WHERE id=$6 AND user_id=$7',
    [name, JSON.stringify(waypoints), color||null, notes||null, Math.floor(Date.now()/1000), req.params.id, req.userId]
  );
  res.json({ ok: true });
});

app.delete('/routes/:id', authMiddleware, async (req, res) => {
  await pool.query('DELETE FROM routes WHERE id=$1 AND user_id=$2', [req.params.id, req.userId]);
  res.json({ ok: true });
});

app.get('/waypoints', authMiddleware, async (req, res) => {
  const result = await pool.query(
    'SELECT * FROM saved_waypoints WHERE user_id = $1 ORDER BY created_at DESC',
    [req.userId]
  );
  res.json(result.rows);
});

app.post('/waypoints', authMiddleware, async (req, res) => {
  const { name, lat, lng, symbol, notes } = req.body;
  if (!lat || !lng) return res.status(400).json({ error: 'lat/lng required' });
  const result = await pool.query(
    `INSERT INTO saved_waypoints (user_id, name, lat, lng, symbol, notes, created_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
    [req.userId, name||'Waypoint', lat, lng, symbol||null, notes||null, Math.floor(Date.now()/1000)]
  );
  res.status(201).json(result.rows[0]);
});

app.delete('/waypoints/:id', authMiddleware, async (req, res) => {
  await pool.query('DELETE FROM saved_waypoints WHERE id=$1 AND user_id=$2', [req.params.id, req.userId]);
  res.json({ ok: true });
});

// ── Feature Flags ───────────────────────────────────────────────────────────

app.get('/features', authMiddleware, async (req, res) => {
  const result = await pool.query('SELECT is_pro, feature_flags FROM users WHERE id=$1', [req.userId]);
  const user = result.rows[0];
  const flags = user?.feature_flags || {};
  const defaultFlags = {
    pro_features: user?.is_pro || false,
    weather_overlay: true,
    tidal_currents: user?.is_pro || false,
    polar_performance: user?.is_pro || false,
    ais_history: true,
    deviation_table: true,
    race_timer: true,
    dead_reckoning: true,
    celestial_nav: user?.is_pro || false,
    sar_patterns: user?.is_pro || false,
    radar_simulator: user?.is_pro || false,
    nmea_mux: true,
  };
  res.json({ ...defaultFlags, ...flags });
});

// ── Stripe Subscription (stub) ─────────────────────────────────────────────

const stripe = process.env.STRIPE_SECRET_KEY
  ? require('stripe')(process.env.STRIPE_SECRET_KEY)
  : null;

app.post('/subscription/create', authMiddleware, async (req, res) => {
  if (!stripe) return res.status(503).json({ error: 'Stripe not configured' });
  try {
    const user = await pool.query('SELECT email FROM users WHERE id=$1', [req.userId]);
    const email = user.rows[0]?.email;
    if (!email) return res.status(400).json({ error: 'Email required' });
    
    // Create or retrieve customer
    let customer = await pool.query('SELECT stripe_customer_id FROM users WHERE id=$1', [req.userId]);
    let customerId = customer.rows[0]?.stripe_customer_id;
    if (!customerId) {
      const stripeCustomer = await stripe.customers.create({ email });
      customerId = stripeCustomer.id;
      await pool.query('UPDATE users SET stripe_customer_id=$1 WHERE id=$2', [customerId, req.userId]);
    }

    // Create checkout session
    const session = await stripe.checkout.sessions.create({
      customer: customerId,
      payment_method_types: ['card'],
      line_items: [{
        price: process.env.STRIPE_PRICE_ID || 'price_1234',
        quantity: 1,
      }],
      mode: 'subscription',
      success_url: `${req.headers.origin || 'https://floatilla.app'}/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${req.headers.origin || 'https://floatilla.app'}/account`,
    });
    res.json({ url: session.url });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/webhook/stripe', express.raw({ type: 'application/json' }), async (req, res) => {
  if (!stripe) return res.sendStatus(400);
  const sig = req.headers['stripe-signature'];
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!webhookSecret) return res.sendStatus(500);

  try {
    const event = stripe.webhooks.constructEvent(req.body, sig, webhookSecret);
    if (event.type === 'checkout.session.completed' || event.type === 'invoice.payment_succeeded') {
      const customerId = event.data.object.customer;
      await pool.query('UPDATE users SET is_pro=true WHERE stripe_customer_id=$1', [customerId]);
      console.log(`[Stripe] User upgraded to Pro: ${customerId}`);
    } else if (event.type === 'customer.subscription.deleted') {
      const customerId = event.data.object.customer;
      await pool.query('UPDATE users SET is_pro=false WHERE stripe_customer_id=$1', [customerId]);
      console.log(`[Stripe] User downgraded: ${customerId}`);
    }
    res.sendStatus(200);
  } catch (e) {
    console.error('[Stripe webhook error]', e.message);
    res.sendStatus(400);
  }
});

// ── Tidal/Weather Proxies (stub endpoints for future implementation) ───────

app.get('/proxy/tides', async (req, res) => {
  // TODO: proxy to NOAA CO-OPS or similar
  // For now, return empty
  res.json({ stations: [], message: 'Tidal proxy not yet implemented' });
});

app.get('/proxy/weather', async (req, res) => {
  // TODO: proxy to Open-Meteo or ECMWF
  res.json({ forecast: [], message: 'Weather proxy not yet implemented' });
});

// ── Admin: Revenue & Feature Flags ─────────────────────────────────────────

app.get('/admin/revenue', adminMiddleware, async (req, res) => {
  const totalUsers = await pool.query('SELECT COUNT(*) FROM users');
  const proUsers = await pool.query('SELECT COUNT(*) FROM users WHERE is_pro=true');
  const freeUsers = totalUsers.rows[0].count - proUsers.rows[0].count;
  
  const subscribers = await pool.query(
    'SELECT id, username, email, stripe_customer_id, is_pro, created_at FROM users WHERE is_pro=true ORDER BY created_at DESC'
  );

  // Simple MRR calc: assume $9.99/month per pro user
  const mrr = proUsers.rows[0].count * 9.99;

  res.json({
    mrr: mrr.toFixed(2),
    proCount: proUsers.rows[0].count,
    freeCount: freeUsers,
    churnRate: 0, // TODO: calculate from subscription history
    subscribers: subscribers.rows,
  });
});

app.get('/admin/features', adminMiddleware, async (req, res) => {
  const users = await pool.query(
    'SELECT id, username, is_pro, feature_flags FROM users ORDER BY created_at DESC'
  );
  res.json(users.rows);
});

app.put('/admin/users/:id/pro', adminMiddleware, async (req, res) => {
  const { is_pro } = req.body;
  await pool.query('UPDATE users SET is_pro=$1 WHERE id=$2', [is_pro, req.params.id]);
  res.json({ ok: true });
});
