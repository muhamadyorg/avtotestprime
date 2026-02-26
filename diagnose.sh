#!/bin/bash
echo "========================================"
echo "  AvtotestPrime Diagnostika"
echo "  $(date)"
echo "========================================"
echo ""

echo "--- 1. FAYL TUZILMASI ---"
echo "PROJECT_DIR tarkibi:"
ls -la /www/wwwroot/avtotestprime.uz/
echo ""
echo "manage.py bormi:"
ls -la /www/wwwroot/avtotestprime.uz/manage.py 2>&1
echo ""
echo "settings.py bormi:"
ls -la /www/wwwroot/avtotestprime.uz/avtotestprime/settings.py 2>&1
echo ""

echo "--- 2. .env FAYL ---"
cat /www/wwwroot/avtotestprime.uz/.env 2>&1
echo ""

echo "--- 3. POSTGRESQL ---"
systemctl is-active postgresql
sudo -u postgres psql -tAc "SELECT datname FROM pg_database WHERE datname='avtotestprime';" 2>&1
sudo -u postgres psql -tAc "SELECT rolname FROM pg_roles WHERE rolname='avtotestprime';" 2>&1
echo ""

echo "--- 4. DB ULANISH ---"
DB_PASS=$(grep PGPASSWORD /www/wwwroot/avtotestprime.uz/.env 2>/dev/null | head -1 | cut -d'"' -f2)
PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -U avtotestprime -d avtotestprime -c "SELECT 1 AS db_ok;" 2>&1
echo ""

echo "--- 5. GUNICORN SERVICE ---"
systemctl is-active avtotestprime 2>&1
systemctl is-enabled avtotestprime 2>&1
echo ""
echo "Service fayli:"
cat /etc/systemd/system/avtotestprime.service 2>&1
echo ""
echo "Gunicorn loglar (oxirgi 20 qator):"
journalctl -u avtotestprime --no-pager -n 20 2>&1
echo ""

echo "--- 6. PORT 8000 ---"
echo "8000-portda nima ishlayapti:"
ss -tlnp | grep 8000 2>&1
echo ""
echo "Gunicorn javobi:"
curl -s -o /dev/null -w "HTTP %{http_code}" http://127.0.0.1:8000/ 2>&1
echo ""
echo ""

echo "--- 7. NGINX ---"
echo "Nginx ishlayaptimi:"
if [ -x "/www/server/nginx/sbin/nginx" ]; then
    /www/server/nginx/sbin/nginx -t 2>&1
elif command -v nginx &> /dev/null; then
    nginx -t 2>&1
else
    echo "nginx topilmadi"
fi
echo ""
echo "Nginx config fayli:"
CONF=""
if [ -f "/www/server/panel/vhost/nginx/avtotestprime.uz.conf" ]; then
    CONF="/www/server/panel/vhost/nginx/avtotestprime.uz.conf"
elif [ -f "/etc/nginx/sites-available/avtotestprime.uz" ]; then
    CONF="/etc/nginx/sites-available/avtotestprime.uz"
elif [ -f "/etc/nginx/conf.d/avtotestprime.uz.conf" ]; then
    CONF="/etc/nginx/conf.d/avtotestprime.uz.conf"
fi
if [ -n "$CONF" ]; then
    echo "Joylashuv: $CONF"
    cat "$CONF" 2>&1
else
    echo "Config topilmadi!"
    echo "aaPanel nginx configs:"
    ls /www/server/panel/vhost/nginx/ 2>&1
    echo "sites-available:"
    ls /etc/nginx/sites-available/ 2>&1
    echo "conf.d:"
    ls /etc/nginx/conf.d/ 2>&1
fi
echo ""

echo "--- 8. AAPANEL SAYT SOZLAMALARI ---"
echo "aaPanel vhost papkasi:"
ls -la /www/server/panel/vhost/nginx/ 2>&1
echo ""

echo "--- 9. VENV VA DJANGO ---"
cd /www/wwwroot/avtotestprime.uz
if [ -f "venv/bin/python" ]; then
    echo "Python versiya:"
    venv/bin/python --version 2>&1
    echo ""
    echo "Django tekshiruv:"
    export $(grep -v '^#' .env 2>/dev/null | sed 's/"//g' | xargs) 2>/dev/null
    venv/bin/python manage.py check 2>&1
else
    echo "venv topilmadi!"
fi
echo ""

echo "--- 10. WEB DAN TEKSHIRISH ---"
echo "80-port (Nginx):"
curl -s -o /dev/null -w "HTTP %{http_code}" http://127.0.0.1:80/ 2>&1
echo ""
echo "IP orqali:"
IP=$(hostname -I | awk '{print $1}')
curl -s -o /dev/null -w "HTTP %{http_code}" http://${IP}/ 2>&1
echo ""
echo ""

echo "========================================"
echo "  Diagnostika tugadi"
echo "========================================"
