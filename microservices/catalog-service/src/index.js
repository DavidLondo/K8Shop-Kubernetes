import dotenv from 'dotenv'
dotenv.config()

import express from 'express'
import cors from 'cors'
import * as grpc from '@grpc/grpc-js'
import * as protoLoader from '@grpc/proto-loader'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import pkg from 'pg'

const { Pool } = pkg

const app = express()
app.use(express.json())
app.use(cors())

const HOST = process.env.HOST || '127.0.0.1'
const PORT = parseInt(process.env.PORT || '8080', 10)
const DATABASE_URL = process.env.DATABASE_URL || ''
const DB_SCHEMA = process.env.DB_SCHEMA || 'catalog'
const GRPC_HOST = process.env.CATALOG_GRPC_HOST || '0.0.0.0'
const GRPC_PORT = parseInt(process.env.CATALOG_GRPC_PORT || '50051', 10)
const VALID_SCHEMA = /^[a-zA-Z0-9_]+$/
if (!VALID_SCHEMA.test(DB_SCHEMA)) {
  throw new Error(`[catalog-service] invalid DB_SCHEMA value: ${DB_SCHEMA}`)
}

class CatalogRepository {
  constructor(poolInstance, schema) {
    this.pool = poolInstance
    this.schema = schema
    this.baseQuery = `
      SELECT p.id::text AS id,
             p.sku,
             p.title,
             p.description,
             p.price::float AS price,
             p.image_url,
             COALESCE(p.tags, ARRAY[]::text[]) AS tags,
             COALESCE(inv.available, 0) AS stock,
             p.created_at,
             p.updated_at
      FROM ${schema}.products p
      LEFT JOIN ${schema}.product_inventory inv ON inv.product_id = p.id
    `
  }

  async listProducts(filters) {
    const clauses = []
    const values = []
    let idx = 1

    if (filters.q) {
      clauses.push(`(LOWER(p.title) LIKE $${idx} OR LOWER(p.sku) LIKE $${idx})`)
      values.push(`%${filters.q.toLowerCase()}%`)
      idx += 1
    }
    if (typeof filters.min === 'number' && !Number.isNaN(filters.min)) {
      clauses.push(`p.price >= $${idx}`)
      values.push(filters.min)
      idx += 1
    }
    if (typeof filters.max === 'number' && !Number.isNaN(filters.max)) {
      clauses.push(`p.price <= $${idx}`)
      values.push(filters.max)
      idx += 1
    }
    if (filters.tag) {
      clauses.push(`EXISTS (SELECT 1 FROM UNNEST(p.tags) t WHERE LOWER(t) = $${idx})`)
      values.push(filters.tag.toLowerCase())
      idx += 1
    }

    const where = clauses.length ? `WHERE ${clauses.join(' AND ')}` : ''
    const query = `${this.baseQuery} ${where} ORDER BY p.title ASC`
    const { rows } = await this.pool.query(query, values)
    return rows.map(mapRow)
  }

  async getProduct(idOrSku) {
    if (!idOrSku) return null
    const query = `${this.baseQuery} WHERE p.id::text = $1 OR LOWER(p.sku) = LOWER($1) LIMIT 1`
    const { rows } = await this.pool.query(query, [idOrSku])
    if (!rows.length) return null
    return mapRow(rows[0])
  }

  async ping() {
    await this.pool.query('SELECT 1')
  }

  async ensureSchema() {
    const client = await this.pool.connect()
    try {
      await client.query(`CREATE SCHEMA IF NOT EXISTS ${this.schema}`)
      await client.query(`
        CREATE TABLE IF NOT EXISTS ${this.schema}.products (
          id uuid PRIMARY KEY,
          sku text NOT NULL UNIQUE,
          title text NOT NULL,
          description text,
          price numeric(10, 2) NOT NULL,
          image_url text,
          tags text[] NOT NULL DEFAULT ARRAY[]::text[],
          created_at timestamptz NOT NULL DEFAULT now(),
          updated_at timestamptz NOT NULL DEFAULT now()
        )
      `)
      await client.query(`
        CREATE TABLE IF NOT EXISTS ${this.schema}.product_inventory (
          product_id uuid PRIMARY KEY REFERENCES ${this.schema}.products(id) ON DELETE CASCADE,
          available integer NOT NULL DEFAULT 0,
          updated_at timestamptz NOT NULL DEFAULT now()
        )
      `)
    } finally {
      client.release()
    }
  }
}

const DB_DISABLE_SSL = /^true$/i.test(process.env.PG_DISABLE_SSL || '')

let pool = null
let repository = null

if (!DATABASE_URL) {
  console.warn('[catalog-service] DATABASE_URL not set, service will fail on queries')
} else {
  pool = createPool(DATABASE_URL, {
    disableSsl: DB_DISABLE_SSL,
    poolMax: parseInt(process.env.PG_POOL_MAX || '10', 10),
  })
}

if (pool) {
  pool.on('error', (err) => {
    console.error('[catalog-service] unexpected database error', err)
  })
  pool.on('connect', (client) => {
    client.query(`SET search_path TO ${DB_SCHEMA}, public`).catch((err) => {
      console.error('[catalog-service] failed to set search_path', err)
    })
  })
  repository = new CatalogRepository(pool, DB_SCHEMA)
  initializeRepository(repository).catch((err) => {
    console.error('[catalog-service] failed to initialize database schema', err)
  })
}

function parseFilters(source) {
  const filters = {}

  if (source.q !== undefined && source.q !== null) {
    const value = String(source.q).trim()
    if (value) filters.q = value
  }

  if (source.tag !== undefined && source.tag !== null) {
    const value = String(source.tag).trim()
    if (value) filters.tag = value
  }

  if (source.min !== undefined && source.min !== null && source.min !== '') {
    const num = Number(source.min)
    if (!Number.isNaN(num)) filters.min = num
  }

  if (source.max !== undefined && source.max !== null && source.max !== '') {
    const num = Number(source.max)
    if (!Number.isNaN(num)) filters.max = num
  }

  return filters
}

function mapRow(row) {
  let updatedAt
  if (row.updated_at instanceof Date) {
    updatedAt = row.updated_at.toISOString()
  } else if (row.updated_at) {
    updatedAt = row.updated_at
  }

  return {
    id: row.id,
    sku: row.sku,
    title: row.title,
    description: row.description,
    price: Number(row.price),
    imageUrl: row.image_url || undefined,
    tags: Array.isArray(row.tags) ? row.tags : [],
    stock: row.stock !== null && row.stock !== undefined ? Number(row.stock) : undefined,
    updatedAt,
  }
}

function serializeProduct(product) {
  return {
    id: product.id,
    sku: product.sku,
    title: product.title,
    price: product.price,
    tags: product.tags || [],
  }
}

function createPool(url, options = {}) {
  const { disableSsl = false, poolMax = 10 } = options
  let connectionString = url
  let sslConfig = false
  let shouldUseSsl = !disableSsl && !/localhost|127\.0\.0\.1/.test(url)

  if (shouldUseSsl) {
    try {
      const parsed = new URL(url)
      const sslModeRaw = parsed.searchParams.get('sslmode')
      if (sslModeRaw) {
        const sslMode = sslModeRaw.toLowerCase()
        if (sslMode === 'disable') {
          shouldUseSsl = false
        }
        parsed.searchParams.delete('sslmode')
      }
      connectionString = parsed.toString()
    } catch (err) {
      console.warn('[catalog-service] failed to parse DATABASE_URL, falling back to raw string', err)
    }
  }

  if (shouldUseSsl) {
    sslConfig = { rejectUnauthorized: false }
  }

  const poolOptions = {
    connectionString,
    max: Number.isFinite(poolMax) && poolMax > 0 ? poolMax : 10,
  }

  poolOptions.ssl = sslConfig

  return new Pool(poolOptions)
}

async function initializeRepository(repo) {
  await repo.ensureSchema()
  console.log('[catalog-service] database schema verified')
}

app.get('/healthz', async (_req, res) => {
  if (!repository) {
    return res.status(500).json({ ok: false, db: 'unconfigured' })
  }
  try {
    await repository.ping()
    res.json({ ok: true, db: 'ok' })
  } catch (err) {
    console.error('[catalog-service] DB health check failed', err)
    res.status(503).json({ ok: false, db: 'error', message: err.message })
  }
})

app.get('/catalog', async (req, res) => {
  if (!repository) {
    return res.status(500).json({ error: 'database not configured' })
  }
  const filters = parseFilters(req.query)
  try {
    const items = await repository.listProducts(filters)
    res.json({ items, count: items.length })
  } catch (err) {
    console.error('[catalog-service] listProducts failed', err)
    res.status(500).json({ error: 'failed to fetch catalog' })
  }
})

app.get('/catalog/:id', async (req, res) => {
  if (!repository) {
    return res.status(500).json({ error: 'database not configured' })
  }
  try {
    const item = await repository.getProduct(req.params.id)
    if (!item) {
      return res.status(404).json({ error: 'not found' })
    }
    res.json(item)
  } catch (err) {
    console.error('[catalog-service] getProduct failed', err)
    res.status(500).json({ error: 'failed to fetch product' })
  }
})

const server = app.listen(PORT, HOST, () => {
  console.log(`[catalog-service] listening on http://${HOST}:${PORT}`)
  if (DATABASE_URL) {
    console.log('[catalog-service] database connection configured')
  }
})

async function shutdown() {
  console.log('[catalog-service] shutting down...')
  server.close(async () => {
    try {
      if (pool) {
        await pool.end()
        console.log('[catalog-service] database pool closed')
      }
    } finally {
      process.exit(0)
    }
  })
}
process.on('SIGTERM', shutdown)
process.on('SIGINT', shutdown)

// ----- gRPC server -----
const __dirname = path.dirname(fileURLToPath(import.meta.url))
const PROTO_PATH = path.resolve(__dirname, '..', 'proto', 'catalog.proto')
const pkgDef = protoLoader.loadSync(PROTO_PATH, { keepCase: true, longs: String, enums: String, arrays: true })
const proto = grpc.loadPackageDefinition(pkgDef)

function startGrpcServer() {
  const svc = proto['catalog']['v1']['CatalogService']
  const impl = {
    GetProduct: async (call, callback) => {
      if (!repository) {
        return callback({ code: grpc.status.UNAVAILABLE, message: 'database not configured' })
      }
      try {
        const id = String(call.request.id || '')
        const item = await repository.getProduct(id)
        if (!item) {
          return callback({ code: grpc.status.NOT_FOUND, message: 'not found' })
        }
        callback(null, serializeProduct(item))
      } catch (err) {
        console.error('[catalog-service] gRPC GetProduct error', err)
        callback({ code: grpc.status.INTERNAL, message: 'failed to fetch product' })
      }
    },
    ListProducts: async (call, callback) => {
      if (!repository) {
        return callback({ code: grpc.status.UNAVAILABLE, message: 'database not configured' })
      }
      try {
        const filters = parseFilters(call.request || {})
        const items = await repository.listProducts(filters)
        callback(null, { items: items.map(serializeProduct) })
      } catch (err) {
        console.error('[catalog-service] gRPC ListProducts error', err)
        callback({ code: grpc.status.INTERNAL, message: 'failed to list products' })
      }
    },
  }
  const server = new grpc.Server()
  server.addService(svc.service, impl)
  const addr = `${GRPC_HOST}:${GRPC_PORT}`
  server.bindAsync(addr, grpc.ServerCredentials.createInsecure(), (err) => {
    if (err) {
      console.error('[catalog-service] gRPC bind error:', err)
      return
    }
    server.start()
    console.log(`[catalog-service] gRPC listening on ${addr}`)
  })
}

startGrpcServer()
