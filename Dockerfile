#BUILD STAGE 
FROM node:20 AS builder
WORKDIR /app

# Install dependencies
COPY package.json package-lock.json* ./
RUN npm install

# Copy source code
COPY . .

# Generate Prisma Client
RUN npx prisma generate


# PRODUCTION STAGE
FROM node:20

WORKDIR /app

# Copy package files
COPY package.json package-lock.json* ./

# Install only production dependencies
RUN npm install --omit=dev

# Copy app source (including generated Prisma Client) from builder
COPY --from=builder /app .

# Expose port
EXPOSE 5000

# Copy and set entrypoint
COPY start.sh ./
RUN chmod +x start.sh

CMD ["./start.sh"]
