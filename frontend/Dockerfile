FROM nginx:1.29-alpine

# Valores por defecto. Se sobrescriben desde docker-compose.yml o desde el
# ConfigMap de Kubernetes.
ENV BACKEND_URL=http://backend:8000 \
    APP_ENV=development \
    NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1

# La imagen oficial procesa las plantillas de /etc/nginx/templates al arrancar
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY public/ /usr/share/nginx/html/

EXPOSE 80
