import dotenv from 'dotenv'
dotenv.config()

import express from 'express'
import amqp from 'amqplib'

const app = express()
app.use(express.json())

const HOST = process.env.HOST || '127.0.0.1'
const PORT = parseInt(process.env.PORT || '8080', 10)

// RabbitMQ settings
const NOTIF_CONSUME_ENABLED = (/^(1|true|yes|on)$/i).test(process.env.NOTIF_CONSUME_ENABLED || '0')
const RABBIT_URL = process.env.NOTIF_RABBIT_URL
	|| (process.env.RABBITMQ_HOST ? `amqp://guest:guest@${process.env.RABBITMQ_HOST}:5672` : undefined)
	|| 'amqp://guest:guest@localhost:5672/'

let amqpConnection = null
let amqpChannel = null

async function simulateSend(type, orderId) {
	await new Promise((res) => setTimeout(res, 1500))
	if (type === 'success') {
		console.log(`📬 [Notification] Email sent for Order ${orderId} (payment successful)`) 
	} else {
		console.log(`⚠️ [Notification] Alert sent for Order ${orderId} (payment failed)`) 
	}
}

async function startConsumer() {
	if (!NOTIF_CONSUME_ENABLED) {
		console.log('[notification-service] consumer disabled (NOTIF_CONSUME_ENABLED=0)')
		return
	}
		try {
			amqpConnection = await amqp.connect(RABBIT_URL)
			amqpChannel = await amqpConnection.createChannel()

			// Topic exchange and a dedicated queue bound to payment events
			const EXCHANGE = process.env.NOTIF_EXCHANGE || 'orders'
			await amqpChannel.assertExchange(EXCHANGE, 'topic', { durable: true })
			const queueName = process.env.NOTIF_QUEUE_NAME || 'notification-service'
			await amqpChannel.assertQueue(queueName, { durable: true })
			await amqpChannel.bindQueue(queueName, EXCHANGE, 'orders.payment_succeeded')
			await amqpChannel.bindQueue(queueName, EXCHANGE, 'orders.payment_failed')

			console.log('📢 Notification service waiting for payment events...')

			amqpChannel.consume(queueName, async (msg) => {
			try {
					const data = JSON.parse(msg.content.toString())
					const rk = msg.fields.routingKey || ''
					if (rk.endsWith('payment_succeeded')) {
						console.log(`✅ Order ${data.order_id}: Payment succeeded. Sending confirmation email...`)
						await simulateSend('success', data.order_id)
					} else if (rk.endsWith('payment_failed')) {
						console.log(`❌ Order ${data.order_id}: Payment failed. Sending failure alert...`)
						await simulateSend('failure', data.order_id)
					} else {
						console.log('Ignoring message with routing key:', rk)
					}
					amqpChannel.ack(msg)
			} catch (e) {
					console.error('Error handling notification message:', e)
					amqpChannel.nack(msg, false, false)
			}
			}, { noAck: false })

		amqpConnection.on('close', () => {
			console.error('[notification-service] AMQP connection closed')
			retryLater()
		})
		amqpConnection.on('error', (err) => {
			console.error('[notification-service] AMQP connection error', err)
		})
	} catch (err) {
		console.error('Error in Notification Service consumer:', err)
		retryLater()
	}
}

function retryLater() {
	if (!NOTIF_CONSUME_ENABLED) return
	setTimeout(() => startConsumer().catch(() => {}), 5000)
}

// HTTP endpoints for local testing
app.get('/healthz', (req, res) => {
	res.json({ ok: true })
})

// Simulate notification without RabbitMQ
app.post('/notify', async (req, res) => {
	const { order_id, status, type } = req.body || {}
	if (!order_id) return res.status(400).json({ error: 'order_id required' })
	const t = type || (status === 'payment.failed' ? 'failure' : 'success')
	await simulateSend(t === 'failure' ? 'failure' : 'success', order_id)
	res.json({ order_id, notified: true, channel: 'http' })
})

const server = app.listen(PORT, HOST, () => {
	console.log(`[notification-service] listening on http://${HOST}:${PORT}`)
	startConsumer().catch(() => {})
})

function gracefulShutdown() {
	console.log('[notification-service] shutting down...')
	server.close(() => process.exit(0))
	if (amqpChannel) amqpChannel.close().catch(() => {})
	if (amqpConnection) amqpConnection.close().catch(() => {})
}

process.on('SIGTERM', gracefulShutdown)
process.on('SIGINT', gracefulShutdown)
