# Build the static bundle, then serve it with nginx.
# The API base URL is baked in at build time (Vite inlines VITE_* variables):
# empty in Azure (same origin), the dev-router for docker-compose by default.
FROM node:26-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
ARG VITE_API_URL=http://localhost:5104
ENV VITE_API_URL=$VITE_API_URL
RUN npm run build

FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
