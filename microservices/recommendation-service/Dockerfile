FROM golang:1.22-alpine AS build
WORKDIR /app

# Cache modules
COPY go.mod .
RUN --mount=type=cache,target=/go/pkg/mod go mod download

# Copy source and build
COPY . .
RUN --mount=type=cache,target=/go/pkg/mod CGO_ENABLED=0 GOOS=linux go build -o /recommendation-service ./cmd/recommendation-service

FROM alpine:3.20
WORKDIR /app
COPY --from=build /recommendation-service /app/recommendation-service
# Copy runtime proto files for dynamic gRPC client
COPY --from=build /app/proto /app/proto
EXPOSE 8080
ENV HOST=0.0.0.0 PORT=8080
CMD ["/app/recommendation-service"]
