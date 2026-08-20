FROM node:24-alpine
RUN apk add --no-cache ffmpeg
WORKDIR /app
COPY package.json ./
RUN npm install
COPY tsconfig.json ./
COPY drizzle.config.ts ./
COPY drizzle ./drizzle
COPY src ./src
EXPOSE 3000
CMD ["npm", "run", "start:container"]
