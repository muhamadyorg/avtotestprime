#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

echo "AvtotestPrime yangilanmoqda..."
cd "$PROJECT_DIR"
git pull origin main || git pull origin master

source venv/bin/activate

pip install -r requirements.txt
python manage.py migrate --noinput
python manage.py collectstatic --noinput

WEB_USER="www"
if ! id -u www > /dev/null 2>&1; then
    if id -u www-data > /dev/null 2>&1; then
        WEB_USER="www-data"
    else
        WEB_USER="root"
    fi
fi

chown -R ${WEB_USER}:${WEB_USER} "$PROJECT_DIR" 2>/dev/null || true
systemctl restart avtotestprime

sleep 2
echo "Tayyor! Sayt yangilandi."
echo "Holat: $(systemctl is-active avtotestprime)"
