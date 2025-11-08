package main

import (
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/joho/godotenv"
	amqp "github.com/rabbitmq/amqp091-go"
)

type PaymentRequest struct {
	OrderID     string  `json:"order_id"`
	UserID      string  `json:"user_id"`
	TotalAmount float64 `json:"total_amount"`
}

type PaymentEvent struct {
	OrderID string `json:"order_id"`
	Status  string `json:"status"`
}

func envBool(key string, def bool) bool {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	switch v {
	case "1", "true", "TRUE", "True", "yes", "on", "ON":
		return true
	}
	return false
}

func publishPayment(status string, event PaymentEvent) error {
	if !envBool("PAYMENT_PUBLISH_ENABLED", false) {
		log.Printf("[payment-service] publishing disabled; skipping publish for order %s", event.OrderID)
		return nil
	}
	url := os.Getenv("PAYMENT_RABBIT_URL")
	if url == "" {
		url = "amqp://guest:guest@localhost:5672/"
	}
	conn, err := amqp.Dial(url)
	if err != nil {
		return fmt.Errorf("connect RabbitMQ: %w", err)
	}
	defer conn.Close()
	ch, err := conn.Channel()
	if err != nil {
		return fmt.Errorf("open channel: %w", err)
	}
	defer ch.Close()
	// Use topic exchange 'orders' and routing keys 'orders.payment_succeeded|failed'
	if err := ch.ExchangeDeclare("orders", "topic", true, false, false, false, nil); err != nil {
		return fmt.Errorf("declare exchange: %w", err)
	}
	routingKey := status
	switch status {
	case "payment.succeeded":
		routingKey = "orders.payment_succeeded"
	case "payment.failed":
		routingKey = "orders.payment_failed"
	default:
		// allow passing full routing key already
		if status != "orders.payment_succeeded" && status != "orders.payment_failed" {
			routingKey = "orders." + status
		}
	}
	body, _ := json.Marshal(event)
	if err := ch.Publish("orders", routingKey, false, false, amqp.Publishing{
		ContentType: "application/json",
		Body:        body,
	}); err != nil {
		return fmt.Errorf("publish: %w", err)
	}
	return nil
}

func simulatePayment(total float64) string {
	// 20% failure by default; configurable via PAYMENT_FAIL_PROB (0-100)
	failProb := 20
	if s := os.Getenv("PAYMENT_FAIL_PROB"); s != "" {
		if v, err := strconv.Atoi(s); err == nil && v >= 0 && v <= 100 {
			failProb = v
		}
	}
	if rand.Intn(100) < failProb {
		return "payment.failed"
	}
	return "payment.succeeded"
}

func main() {
	// Load .env if present
	_ = godotenv.Load()
	rand.Seed(time.Now().UnixNano())
	if db := os.Getenv("DATABASE_URL"); db != "" {
		log.Printf("payment-service DATABASE_URL configured")
	} else {
		log.Printf("payment-service DATABASE_URL not set (running without DB)")
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"ok":true}`))
	})

	mux.HandleFunc("/payments", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		var req PaymentRequest
		dec := json.NewDecoder(r.Body)
		if err := dec.Decode(&req); err != nil {
			http.Error(w, "invalid JSON", http.StatusBadRequest)
			return
		}
		if req.OrderID == "" || req.UserID == "" || req.TotalAmount <= 0 {
			http.Error(w, "order_id, user_id and positive total_amount required", http.StatusBadRequest)
			return
		}

		// Simulate processing delay
		time.Sleep(500 * time.Millisecond)
		status := simulatePayment(req.TotalAmount)
		evt := PaymentEvent{OrderID: req.OrderID, Status: status}
		if err := publishPayment(status, evt); err != nil {
			if envBool("PAYMENT_PUBLISH_STRICT", false) {
				http.Error(w, "publish failed: "+err.Error(), http.StatusBadGateway)
				return
			}
			log.Printf("[payment-service] publish failed (ignored): %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(evt)
	})

	host := os.Getenv("HOST")
	if host == "" {
		host = "127.0.0.1"
	}
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	addr := host + ":" + port
	log.Printf("payment-service listening on http://%s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("server error: %v", err)
	}
}
