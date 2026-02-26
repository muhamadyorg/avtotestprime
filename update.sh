#!/bin/bash
set -e

PROJECT_DIR="/www/wwwroot/avtotestprime.uz"

echo "AvtotestPrime yangilanmoqda..."
cd "$PROJECT_DIR"
git pull origin main || git pull origin master

source venv/bin/activate

set -a
source .env
set +a

pip install -r requirements.txt
python manage.py migrate
python manage.py collectstatic --noinput

chown -R www:www "$PROJECT_DIR"
systemctl restart avtotestprime

echo "Tayyor! Sayt yangilandi."
echo "Holat: $(systemctl is-active avtotestprime)"
