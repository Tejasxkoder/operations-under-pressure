FROM node:20-alpine AS web
WORKDIR /web
COPY frontend/package.json ./
RUN npm install
COPY frontend/ ./
RUN npm run build

FROM node:20-alpine
WORKDIR /app/backend
COPY backend/package.json ./
RUN npm install
COPY backend/ ./
COPY --from=web /web/dist ./public
ENV NODE_ENV=production
EXPOSE 3000
CMD ["sh", "-c", "npx tsx src/migrate.ts && npx tsx src/seed.ts --if-empty && npx tsx src/index.ts"]
