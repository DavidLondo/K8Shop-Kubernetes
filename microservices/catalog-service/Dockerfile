# syntax=docker/dockerfile:1
FROM node:20-alpine
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci --omit=dev || npm i --omit=dev

COPY . .

ENV HOST=0.0.0.0
ENV PORT=8080
EXPOSE 8080 50051
CMD ["npm","start"]
