#!/bin/sh
# Replace placeholders in index.html with actual env vars at container start
sed -i "s|__KEYCLOAK_URL__|${KEYCLOAK_URL:-http://keycloak:8080}|g" /usr/share/nginx/html/index.html
sed -i "s|__KEYCLOAK_REALM__|${KEYCLOAK_REALM:-devportal}|g" /usr/share/nginx/html/index.html
sed -i "s|__KEYCLOAK_CLIENT_ID__|${KEYCLOAK_CLIENT_ID:-devportal-app}|g" /usr/share/nginx/html/index.html
exec "$@"
