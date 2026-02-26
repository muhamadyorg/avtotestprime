#!/bin/bash
set -e

PROJECT_DIR="/www/wwwroot/avtotestprime.uz"

echo "AvtotestPrime yangilanmoqda..."
cd "$PROJECT_DIR"
git pull origin main || git pull origin master

source venv/bin/activate

pip install -r requirements.txt
python manage.py migrate --noinput
python manage.py collectstatic --noinput

chown -R www:www "$PROJECT_DIR"
systemctl restart avtotestprime

sleep 2
echo "Tayyor! Sayt yangilandi."
echo "Holat: $(systemctl is-active avtotestprime)"
