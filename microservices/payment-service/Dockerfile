FROM golang:1.22-alpine AS build
WORKDIR /app

# Cache modules
COPY go.mod .
RUN --mount=type=cache,target=/go/pkg/mod go mod download

# Copy source and build
COPY . .
RUN --mount=type=cache,target=/go/pkg/mod CGO_ENABLED=0 GOOS=linux go build -o /payment-service ./cmd/payment-service

FROM alpine:3.20
WORKDIR /app
COPY --from=build /payment-service /app/payment-service
EXPOSE 8080
ENV HOST=0.0.0.0 PORT=8080
CMD ["/app/payment-service"]
