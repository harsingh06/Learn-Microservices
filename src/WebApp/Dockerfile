# Build the static bundle, then serve it with nginx.
# Vite bakes VITE_* variables in at build time, so API URLs are build args.
FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
ARG VITE_CANDIDATE_API=http://localhost:5101
ARG VITE_JOB_API=http://localhost:5102
ARG VITE_APPLICATION_API=http://localhost:5103
ENV VITE_CANDIDATE_API=$VITE_CANDIDATE_API \
    VITE_JOB_API=$VITE_JOB_API \
    VITE_APPLICATION_API=$VITE_APPLICATION_API
RUN npm run build

FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
