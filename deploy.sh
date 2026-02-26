#!/bin/bash
set -e

DOMAIN="avtotestprime.uz"
PROJECT_DIR="/www/wwwroot/avtotestprime.uz"
DB_NAME="avtotestprime"
DB_USER="avtotestprime"
DB_PASS=$(openssl rand -hex 24)
SECRET_KEY=$(openssl rand -hex 32)

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
echo -e "${GREEN}Paketlar tayyor!${NC}"

echo -e "${YELLOW}[2/8] PostgreSQL bazasini sozlash...${NC}"
systemctl start postgresql 2>/dev/null || true

sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1 && \
    sudo -u postgres psql -c "ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASS}';" || \
    sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"

sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"
sudo -u postgres psql -d "${DB_NAME}" -c "GRANT ALL ON SCHEMA public TO ${DB_USER};" 2>/dev/null || true
echo -e "${GREEN}Baza tayyor!${NC}"

echo -e "${YELLOW}[3/8] Python virtual muhitini sozlash...${NC}"
cd "$PROJECT_DIR"

if [ ! -f "manage.py" ]; then
    echo -e "${RED}Xatolik: manage.py topilmadi! Fayllarni tekshiring.${NC}"
    exit 1
fi

if [ ! -f "avtotestprime/settings.py" ]; then
    echo -e "${RED}Xatolik: avtotestprime/settings.py topilmadi!${NC}"
    exit 1
fi

if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
echo -e "${GREEN}Python paketlari o'rnatildi!${NC}"

echo -e "${YELLOW}[4/8] .env faylini yaratish...${NC}"
echo "SECRET_KEY=\"${SECRET_KEY}\"" > "${PROJECT_DIR}/.env"
echo "DEBUG=\"False\"" >> "${PROJECT_DIR}/.env"
echo "ALLOWED_HOSTS=\"${DOMAIN},www.${DOMAIN},localhost,127.0.0.1\"" >> "${PROJECT_DIR}/.env"
echo "PGDATABASE=\"${DB_NAME}\"" >> "${PROJECT_DIR}/.env"
echo "PGUSER=\"${DB_USER}\"" >> "${PROJECT_DIR}/.env"
echo "PGPASSWORD=\"${DB_PASS}\"" >> "${PROJECT_DIR}/.env"
echo "PGHOST=\"localhost\"" >> "${PROJECT_DIR}/.env"
echo "PGPORT=\"5432\"" >> "${PROJECT_DIR}/.env"
echo -e "${GREEN}.env fayli yaratildi!${NC}"

echo -e "${YELLOW}[5/8] Django migratsiya va sozlash...${NC}"
export SECRET_KEY="${SECRET_KEY}"
export DEBUG="False"
export ALLOWED_HOSTS="${DOMAIN},www.${DOMAIN},localhost,127.0.0.1"
export PGDATABASE="${DB_NAME}"
export PGUSER="${DB_USER}"
export PGPASSWORD="${DB_PASS}"
export PGHOST="localhost"
export PGPORT="5432"

python manage.py migrate --noinput
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
cat > /etc/systemd/system/avtotestprime.service <<SERVICEEOF
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
SERVICEEOF

chown -R www:www "$PROJECT_DIR"

systemctl daemon-reload
systemctl enable avtotestprime
systemctl restart avtotestprime

sleep 2
if systemctl is-active --quiet avtotestprime; then
    echo -e "${GREEN}Gunicorn muvaffaqiyatli ishga tushdi!${NC}"
else
    echo -e "${RED}Gunicorn xatolik. Loglar:${NC}"
    journalctl -u avtotestprime --no-pager -n 20
fi

echo -e "${YELLOW}[7/8] aaPanel Nginx konfiguratsiyasini yaratish...${NC}"

NGINX_CONF="/www/server/panel/vhost/nginx/${DOMAIN}.conf"

if [ -f "$NGINX_CONF" ]; then
    cp "$NGINX_CONF" "${NGINX_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
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
echo -e "${GREEN}Nginx tayyor!${NC}"

echo -e "${YELLOW}[8/8] Yakuniy tekshirish...${NC}"
sleep 1
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/ 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}Sayt ishlayapti! (HTTP ${HTTP_CODE})${NC}"
else
    echo -e "${YELLOW}Sayt hali yuklanmoqda yoki xatolik bor (HTTP ${HTTP_CODE})${NC}"
    echo -e "Tekshirish: journalctl -u avtotestprime -f"
fi

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  Deploy muvaffaqiyatli yakunlandi!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "Sayt:      ${GREEN}http://${DOMAIN}${NC}"
echo -e "Admin:     ${GREEN}admin / admin${NC}"
echo ""
echo -e "${YELLOW}SSL ni aaPanel dan o'rnating:${NC}"
echo -e "  aaPanel > Website > ${DOMAIN} > SSL > Let's Encrypt"
echo ""
echo -e "Ma'lumotlar bazasi:"
echo -e "  Baza:   ${DB_NAME}"
echo -e "  User:   ${DB_USER}"
echo -e "  Parol:  ${DB_PASS}"
echo ""
echo -e "Buyruqlar:"
echo -e "  ${GREEN}systemctl restart avtotestprime${NC}  - qayta ishga tushirish"
echo -e "  ${GREEN}systemctl status avtotestprime${NC}   - holatni ko'rish"
echo -e "  ${GREEN}journalctl -u avtotestprime -f${NC}   - loglarni ko'rish"
echo ""
echo -e "${YELLOW}Bu ma'lumotlarni xavfsiz joyga saqlang!${NC}"
