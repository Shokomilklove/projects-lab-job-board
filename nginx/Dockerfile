FROM nginx:1.27-alpine@sha256:65645c7bb6a0661892a8b03b89d0743208a18dd2f3f17a54ef4b76fb8e2f2a10

LABEL maintainer="DevSecOps Lab"
LABEL service="nginx-proxy"

RUN apk update && apk upgrade --no-cache

COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -q --spider http://localhost:80/api/jobs/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
