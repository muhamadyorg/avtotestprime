#!/bin/bash
set -e

DOMAIN="avtotestprime.uz"
PROJECT_DIR="/www/wwwroot/avtotestprime.uz"
DB_NAME="avtotestprime"
DB_USER="avtotestprime"
DB_PASS=$(openssl rand -base64 32)
SECRET_KEY=$(openssl rand -base64 50)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  AvtotestPrime - aaPanel VPS Deploy Script${NC}"
echo -e "${GREEN}  Domen: ${DOMAIN}${NC}"
echo -e "${GREEN}  Joylashuv: ${PROJECT_DIR}${NC}"
echo -e "${GREEN}================================================${NC}"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Xatolik: Bu skriptni root sifatida ishga tushiring!${NC}"
    echo "Foydalanish: bash deploy.sh"
    exit 1
fi

echo -e "${YELLOW}[1/8] Kerakli paketlarni o'rnatish...${NC}"
apt update -y
apt install -y python3 python3-pip python3-venv python3-dev libpq-dev git curl

if ! command -v psql &> /dev/null; then
    echo -e "${YELLOW}PostgreSQL o'rnatilmoqda...${NC}"
    apt install -y postgresql postgresql-contrib
    systemctl enable postgresql
    systemctl start postgresql
fi

echo -e "${YELLOW}[2/8] PostgreSQL bazasini sozlash...${NC}"
systemctl start postgresql 2>/dev/null || true
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"
echo -e "${GREEN}Baza tayyor!${NC}"

echo -e "${YELLOW}[3/8] Python virtual muhitini sozlash...${NC}"
cd "$PROJECT_DIR"
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
echo -e "${GREEN}Python paketlari o'rnatildi!${NC}"

echo -e "${YELLOW}[4/8] .env faylini yaratish...${NC}"
if [ -f "${PROJECT_DIR}/.env" ]; then
    echo -e "${YELLOW}Mavjud .env topildi, zaxira nusxasi yaratilmoqda...${NC}"
    cp "${PROJECT_DIR}/.env" "${PROJECT_DIR}/.env.backup.$(date +%Y%m%d_%H%M%S)"
fi
cat > "${PROJECT_DIR}/.env" <<EOF
SECRET_KEY=${SECRET_KEY}
DEBUG=False
ALLOWED_HOSTS=${DOMAIN},www.${DOMAIN},localhost,127.0.0.1
PGDATABASE=${DB_NAME}
PGUSER=${DB_USER}
PGPASSWORD=${DB_PASS}
PGHOST=localhost
PGPORT=5432
EOF
echo -e "${GREEN}.env fayli yaratildi!${NC}"

echo -e "${YELLOW}[5/8] Django migratsiya va sozlash...${NC}"
set -a
source "${PROJECT_DIR}/.env"
set +a

python manage.py migrate
python manage.py collectstatic --noinput

python manage.py shell -c "
from django.contrib.auth.models import User
if not User.objects.filter(username='admin').exists():
    User.objects.create_superuser('admin', '', 'admin')
    print('Admin foydalanuvchi yaratildi: admin/admin')
else:
    print('Admin foydalanuvchi allaqachon mavjud')
"

mkdir -p media/questions
echo -e "${GREEN}Migratsiya va static fayllar tayyor!${NC}"

echo -e "${YELLOW}[6/8] Gunicorn systemd xizmatini sozlash...${NC}"
cat > /etc/systemd/system/avtotestprime.service <<EOF
[Unit]
Description=AvtotestPrime Gunicorn Daemon
After=network.target postgresql.service

[Service]
User=www
Group=www
WorkingDirectory=${PROJECT_DIR}
EnvironmentFile=${PROJECT_DIR}/.env
ExecStart=${PROJECT_DIR}/venv/bin/gunicorn avtotestprime.wsgi:application --bind 127.0.0.1:8000 --workers 3 --timeout 120
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

chown -R www:www "$PROJECT_DIR"

systemctl daemon-reload
systemctl enable avtotestprime
systemctl restart avtotestprime

sleep 2
if systemctl is-active --quiet avtotestprime; then
    echo -e "${GREEN}Gunicorn muvaffaqiyatli ishga tushdi!${NC}"
else
    echo -e "${RED}Gunicorn xatolik bilan ishga tushmadi. Logni tekshiring:${NC}"
    journalctl -u avtotestprime --no-pager -n 20
fi

echo -e "${YELLOW}[7/8] aaPanel Nginx konfiguratsiyasini yaratish...${NC}"

NGINX_CONF="/www/server/panel/vhost/nginx/${DOMAIN}.conf"

if [ -f "$NGINX_CONF" ]; then
    cp "$NGINX_CONF" "${NGINX_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}Mavjud nginx config zaxiralandi!${NC}"
fi

cat > "$NGINX_CONF" <<'NGINXEOF'
server {
    listen 80;
    server_name avtotestprime.uz www.avtotestprime.uz;

    client_max_body_size 20M;
    access_log /www/wwwlogs/avtotestprime.uz.log;
    error_log /www/wwwlogs/avtotestprime.uz.error.log;

    location /static/ {
        alias /www/wwwroot/avtotestprime.uz/staticfiles/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    location /media/ {
        alias /www/wwwroot/avtotestprime.uz/media/;
        expires 7d;
    }

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 120;
        proxy_connect_timeout 120;
    }
}
NGINXEOF

/www/server/nginx/sbin/nginx -t && /www/server/nginx/sbin/nginx -s reload
echo -e "${GREEN}Nginx konfiguratsiya tayyor va qayta yuklandi!${NC}"

echo -e "${YELLOW}[8/8] SSL sertifikatini tekshirish...${NC}"
echo -e "${YELLOW}SSL ni aaPanel dan o'rnating:${NC}"
echo -e "  1. aaPanel > Website > ${DOMAIN} > SSL"
echo -e "  2. Let's Encrypt tanlang"
echo -e "  3. Force HTTPS ni yoqing"

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  Deploy muvaffaqiyatli yakunlandi!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "Sayt:      ${GREEN}http://${DOMAIN}${NC}"
echo -e "Admin:     ${GREEN}admin / admin${NC}"
echo ""
echo -e "${YELLOW}Muhim: aaPanel dan SSL o'rnatishni unutmang!${NC}"
echo ""
echo -e "Ma'lumotlar bazasi:"
echo -e "  Baza nomi:      ${DB_NAME}"
echo -e "  Foydalanuvchi:   ${DB_USER}"
echo -e "  Parol:           ${DB_PASS}"
echo ""
echo -e "Foydali buyruqlar:"
echo -e "  ${GREEN}systemctl restart avtotestprime${NC}  - Serverni qayta ishga tushirish"
echo -e "  ${GREEN}systemctl status avtotestprime${NC}   - Server holatini ko'rish"
echo -e "  ${GREEN}journalctl -u avtotestprime -f${NC}   - Loglarni ko'rish"
echo -e "  ${GREEN}cd ${PROJECT_DIR} && source venv/bin/activate${NC} - Virtual muhitga kirish"
echo ""
echo -e ".env fayli: ${PROJECT_DIR}/.env"
echo -e "${YELLOW}Bu ma'lumotlarni xavfsiz joyga saqlang!${NC}"
