const express = require('express');
const sqlite3 = require('sqlite3').verbose();
const cors = require('cors');
const path = require('path');
const crypto = require('crypto');

const app = express();
const port = process.env.PORT || 3000;

const GOOGLE_PASSWORD_MARKER = 'firebase:google';

app.use(cors());
app.use(express.json({ limit: '50mb' }));

const dbPath = path.join(__dirname, 'vendemas-cloud.db');
const db = new sqlite3.Database(dbPath, (err) => {
    if (err) {
        console.error('Error opening database', err.message);
    } else {
        console.log('Connected to the SQLite database.');
        db.serialize(() => {
            db.run(`CREATE TABLE IF NOT EXISTS users (
                email TEXT PRIMARY KEY,
                password_hash TEXT NOT NULL,
                name TEXT,
                negocio TEXT,
                auth_provider TEXT DEFAULT 'email',
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )`);

            db.run(`ALTER TABLE users ADD COLUMN password_hash TEXT`, () => {});
            db.run(`ALTER TABLE users ADD COLUMN negocio TEXT`, () => {});
            db.run(`ALTER TABLE users ADD COLUMN auth_provider TEXT DEFAULT 'email'`, () => {});
        });
    }
});

function hashPassword(password) {
    const salt = crypto.randomBytes(16).toString('hex');
    const hash = crypto.scryptSync(password, salt, 64).toString('hex');
    return `${salt}:${hash}`;
}

function verifyPassword(password, stored) {
    if (!stored || !stored.includes(':')) return false;
    const [salt, hash] = stored.split(':');
    const test = crypto.scryptSync(password, salt, 64).toString('hex');
    return hash === test;
}

function isValidEmail(email) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function normalizeEmail(email) {
    return email.trim().toLowerCase();
}

/** Registro legacy (email + password en VPS). */
app.post('/api/auth/register', (req, res) => {
    const email = req.body?.email;
    const password = req.body?.password;
    const name = req.body?.name;
    const negocio = req.body?.negocio;

    if (!email || !password || !name || !negocio) {
        return res.status(400).json({ error: 'Faltan campos obligatorios' });
    }

    if (!isValidEmail(email)) {
        return res.status(400).json({ error: 'Correo electrónico inválido' });
    }

    if (password.length < 6) {
        return res.status(400).json({ error: 'La contraseña debe tener al menos 6 caracteres' });
    }

    const passwordHash = hashPassword(password);
    const normalized = normalizeEmail(email);

    db.run(
        `INSERT INTO users (email, password_hash, name, negocio, auth_provider) VALUES (?, ?, ?, ?, 'email')`,
        [normalized, passwordHash, name.trim(), negocio.trim()],
        function (err) {
            if (err) {
                if (err.message.includes('UNIQUE')) {
                    return res.status(409).json({ error: 'Este correo ya está registrado' });
                }
                console.error('Register error:', err);
                return res.status(500).json({ error: 'Error al registrar la cuenta' });
            }

            res.status(201).json({
                message: 'Cuenta creada',
                email: normalized,
                name: name.trim(),
                negocio: negocio.trim(),
            });
        }
    );
});

/** Sincroniza cuenta Firebase → VPS (crear o actualizar). */
app.post('/api/auth/sync', (req, res) => {
    const email = req.body?.email;
    const name = req.body?.name;
    const negocio = req.body?.negocio;
    const authProvider = req.body?.auth_provider || 'email';
    const password = req.body?.password;

    if (!email || !name || !negocio) {
        return res.status(400).json({ error: 'Faltan campos obligatorios' });
    }

    if (!isValidEmail(email)) {
        return res.status(400).json({ error: 'Correo electrónico inválido' });
    }

    const normalized = normalizeEmail(email);
    const provider = authProvider === 'google' ? 'google' : 'email';
    const passwordHash =
        provider === 'google'
            ? GOOGLE_PASSWORD_MARKER
            : password && password.length >= 6
              ? hashPassword(password)
              : GOOGLE_PASSWORD_MARKER;

    db.run(
        `INSERT INTO users (email, password_hash, name, negocio, auth_provider)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(email) DO UPDATE SET
           name = excluded.name,
           negocio = excluded.negocio,
           auth_provider = excluded.auth_provider,
           password_hash = CASE
             WHEN excluded.auth_provider = 'email' AND excluded.password_hash != ? THEN excluded.password_hash
             ELSE users.password_hash
           END`,
        [normalized, passwordHash, name.trim(), negocio.trim(), provider, GOOGLE_PASSWORD_MARKER],
        function (err) {
            if (err) {
                console.error('Sync error:', err);
                return res.status(500).json({ error: 'Error al sincronizar la cuenta' });
            }

            res.status(200).json({
                message: 'Cuenta sincronizada',
                email: normalized,
                name: name.trim(),
                negocio: negocio.trim(),
            });
        }
    );
});

app.post('/api/auth/login', (req, res) => {
    const email = req.body?.email;
    const password = req.body?.password;

    if (!email || !password) {
        return res.status(400).json({ error: 'Correo y contraseña requeridos' });
    }

    db.get(
        `SELECT email, password_hash, name, negocio FROM users WHERE email = ?`,
        [normalizeEmail(email)],
        (err, row) => {
            if (err) {
                console.error('Login error:', err);
                return res.status(500).json({ error: 'Error al iniciar sesión' });
            }

            if (!row || row.password_hash === GOOGLE_PASSWORD_MARKER) {
                return res.status(401).json({ error: 'Usa Firebase o Google para iniciar sesión' });
            }

            if (!verifyPassword(password, row.password_hash)) {
                return res.status(401).json({ error: 'Correo o contraseña incorrectos' });
            }

            res.json({
                email: row.email,
                name: row.name,
                negocio: row.negocio,
            });
        }
    );
});

/** Elimina la cuenta del VPS por correo. */
app.delete('/api/auth/account', (req, res) => {
    const email = req.body?.email;

    if (!email || !isValidEmail(email)) {
        return res.status(400).json({ error: 'Correo inválido' });
    }

    const normalized = normalizeEmail(email);

    db.run(`DELETE FROM users WHERE email = ?`, [normalized], function (err) {
        if (err) {
            console.error('Delete account error:', err);
            return res.status(500).json({ error: 'Error al eliminar la cuenta' });
        }

        if (this.changes === 0) {
            return res.status(404).json({ error: 'Cuenta no encontrada en el servidor' });
        }

        res.json({ message: 'Cuenta eliminada del servidor' });
    });
});

app.listen(port, () => {
    console.log(`Szr Ventas Backend listening on port ${port}`);
});
