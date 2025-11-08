package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/jhump/protoreflect/desc/protoparse"
	"github.com/jhump/protoreflect/dynamic"
	"github.com/jhump/protoreflect/dynamic/grpcdynamic"
	"github.com/joho/godotenv"
	"google.golang.org/grpc"
)

type healthResponse struct {
	OK bool `json:"ok"`
}

type recItem struct {
	ID    string  `json:"id"`
	Score float64 `json:"score"`
}

type recResponse struct {
	ProductID       string    `json:"productId,omitempty"`
	UserID          string    `json:"userId,omitempty"`
	Strategy        string    `json:"strategy"`
	Recommendations []recItem `json:"recommendations"`
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func mustAtoi(s string, def int) int {
	if s == "" {
		return def
	}
	if n, err := strconv.Atoi(s); err == nil {
		return n
	}
	return def
}

func recommendationsHandler(w http.ResponseWriter, r *http.Request) {
	strategy := strings.ToLower(getenv("REC_STRATEGY", "popular"))
	if qStrategy := r.URL.Query().Get("strategy"); qStrategy != "" {
		strategy = strings.ToLower(qStrategy)
	}

	limit := mustAtoi(r.URL.Query().Get("limit"), mustAtoi(getenv("REC_LIMIT", "5"), 5))
	if limit < 1 {
		limit = 1
	}
	if limit > 50 {
		limit = 50
	}

	productID := r.URL.Query().Get("productId")
	userID := r.URL.Query().Get("userId")

	recs := make([]recItem, 0, limit)

	// If a Catalog gRPC address is configured, try using it to fetch products
	// Fallback to deterministic local generation if unavailable.
	grpcAddr := os.Getenv("CATALOG_GRPC_ADDR") // e.g., "catalog-service:50051" or "127.0.0.1:50051"
	if grpcAddr != "" {
		fetched, err := fetchRecommendationsViaGRPC(grpcAddr, strategy, productID, limit)
		if err == nil && len(fetched) > 0 {
			recs = fetched
		} else if err != nil {
			log.Printf("[recommendation] gRPC fetch error (fallback to local): %v", err)
		}
	}

	if len(recs) == 0 {
		switch strategy {
		case "related":
			seed := int64(42)
			if productID != "" {
				for _, b := range []byte(productID) {
					seed += int64(b)
				}
			}
			rng := rand.New(rand.NewSource(seed))
			for i := 0; i < limit; i++ {
				recs = append(recs, recItem{
					ID:    fmt.Sprintf("p%04d", rng.Intn(9999)),
					Score: 0.6 + rng.Float64()*0.4,
				})
			}
		default:
			daySeed := time.Now().UTC().Format("2006-01-02")
			var seed int64 = 0
			for _, b := range []byte(daySeed) {
				seed += int64(b)
			}
			rng := rand.New(rand.NewSource(seed))
			for i := 0; i < limit; i++ {
				recs = append(recs, recItem{
					ID:    fmt.Sprintf("pop%03d", rng.Intn(1000)),
					Score: 0.5 + rng.Float64()*0.5,
				})
			}
			strategy = "popular"
		}
	}

	resp := recResponse{
		ProductID:       productID,
		UserID:          userID,
		Strategy:        strategy,
		Recommendations: recs,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func fetchRecommendationsViaGRPC(addr, strategy, productID string, limit int) ([]recItem, error) {
	conn, err := grpc.Dial(addr, grpc.WithInsecure())
	if err != nil {
		return nil, fmt.Errorf("dial: %w", err)
	}
	defer conn.Close()

	// Parse proto at runtime
	parser := protoparse.Parser{
		ImportPaths: []string{"./proto"},
	}
	fds, err := parser.ParseFiles("catalog.proto")
	if err != nil || len(fds) == 0 {
		return nil, fmt.Errorf("parse proto: %w", err)
	}
	fd := fds[0]
	svc := fd.FindService("catalog.v1.CatalogService")
	if svc == nil {
		return nil, fmt.Errorf("service not found in proto")
	}
	stub := grpcdynamic.NewStub(conn)

	// Helper to call ListProducts(tag)
	callList := func(tag string) ([]map[string]interface{}, error) {
		m := dynamic.NewMessage(svc.FindMethodByName("ListProducts").GetInputType())
		if tag != "" {
			_ = m.TrySetFieldByName("tag", tag)
		}
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		resp, err := stub.InvokeRpc(ctx, svc.FindMethodByName("ListProducts"), m)
		if err != nil {
			return nil, err
		}
		// Extract items list from dynamic message
		dm, ok := resp.(*dynamic.Message)
		if !ok {
			return nil, fmt.Errorf("unexpected response type from ListProducts")
		}
		itemsVal, _ := dm.TryGetFieldByName("items")
		items, _ := itemsVal.([]interface{})
		out := make([]map[string]interface{}, 0, len(items))
		for _, it := range items {
			if dm, ok := it.(*dynamic.Message); ok {
				js, _ := dm.MarshalJSON()
				var tmp map[string]interface{}
				_ = json.Unmarshal(js, &tmp)
				out = append(out, tmp)
			}
		}
		return out, nil
	}

	var list []map[string]interface{}
	switch strategy {
	case "related":
		// get product to infer a tag
		if productID != "" {
			m := dynamic.NewMessage(svc.FindMethodByName("GetProduct").GetInputType())
			_ = m.TrySetFieldByName("id", productID)
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()
			resp, err := stub.InvokeRpc(ctx, svc.FindMethodByName("GetProduct"), m)
			if err == nil {
				pdm, ok := resp.(*dynamic.Message)
				if !ok {
					break
				}
				js, _ := pdm.MarshalJSON()
				var prod struct {
					Tags []string `json:"tags"`
				}
				_ = json.Unmarshal(js, &prod)
				tag := ""
				if len(prod.Tags) > 0 {
					tag = prod.Tags[0]
				}
				list, _ = callList(tag)
			}
		}
	default:
		list, _ = callList("")
	}

	// Select up to limit items and score
	recs := make([]recItem, 0, limit)
	for i := 0; i < len(list) && len(recs) < limit; i++ {
		id := fmt.Sprintf("%v", list[i]["id"])
		recs = append(recs, recItem{ID: id, Score: 0.75})
	}
	return recs, nil
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(healthResponse{OK: true})
}

func main() {
	// Load .env if present (no error if missing)
	_ = godotenv.Load()

	host := getenv("HOST", "127.0.0.1")
	port := getenv("PORT", "8080")
	dbURL := os.Getenv("DATABASE_URL")

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", healthHandler)
	mux.HandleFunc("/recommendations", recommendationsHandler)

	srv := &http.Server{
		Addr:              host + ":" + port,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("recommendation-service listening on %s:%s", host, port)
	if dbURL != "" {
		log.Printf("recommendation-service DATABASE_URL configured")
	} else {
		log.Printf("recommendation-service DATABASE_URL not set (running without DB)")
	}
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("server error: %v", err)
	}
}
