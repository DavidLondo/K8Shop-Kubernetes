# syntax=docker/dockerfile:1
FROM node:20-alpine AS base
WORKDIR /app

# Install only production deps
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev || npm i --omit=dev

# Copy source
COPY . .

ENV HOST=0.0.0.0
ENV PORT=8080
EXPOSE 8080

CMD ["npm","start"]
