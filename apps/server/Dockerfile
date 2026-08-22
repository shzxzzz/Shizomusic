FROM node:24-alpine
RUN apk add --no-cache deno ffmpeg python3 py3-pip \
    && pip install --break-system-packages --no-cache-dir "spotdl==4.5.2" "yt-dlp[default]==2026.7.4"
WORKDIR /app
COPY package.json ./
RUN npm install
COPY tsconfig.json ./
COPY drizzle.config.ts ./
COPY drizzle ./drizzle
COPY src ./src
EXPOSE 3000
CMD ["npm", "run", "start:container"]
