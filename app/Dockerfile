FROM node:20-alpine

WORKDIR /usr/src/app

# Copy package metadata and install production dependencies only
COPY package*.json ./
RUN npm install --omit=dev && npm cache clean --force

# Copy application source
COPY src ./src

# Security rule (AGENTS.md Section 5.1): Run as non-root user
USER node

EXPOSE 3000

# Native container healthcheck hitting shallow liveness endpoint
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

CMD ["node", "src/index.js"]
