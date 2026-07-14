FROM node:20-alpine AS builder
WORKDIR /app

COPY package*.json ./
COPY prisma/ ./prisma/
RUN npm install
RUN npx prisma generate

COPY src/ ./src/
COPY tsconfig.json ./
RUN npm run build

# ---

FROM node:20-alpine AS production
WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev

# Copy generated Prisma client and compiled output from builder
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder /app/node_modules/@prisma/client ./node_modules/@prisma/client
COPY --from=builder /app/dist ./dist
COPY prisma/ ./prisma/

EXPOSE 3000

# Push schema directly (idempotent, skips broken migration history)
CMD ["sh", "-c", "npx prisma db push --accept-data-loss && node dist/index.js"]
