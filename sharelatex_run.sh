#!/bin/bash

IP="<MY_IP>"
PORT=8080
EMAIL="<MY_EMALI>"
URL="http://${IP}:${PORT}"
APP_NAME="Sharelatex (Edition)"
APP_PATH="$HOME/sharelatex"
MAIL_FROM_ADDRESS=${EMAIL}
MAIL_REPLY_TO=${EMAIL}
MAIL_TRANSPORT="SMTP"
MAIL_HOST="smtp.server"
MAIL_PORT=25
MAIL_USER=usersmtp
MAIL_PASS=passwordsmtp

mkdir -p ${APP_PATH}/var/

docker run -d --name sharemongo -v ${APP_PATH}/var/mongodb:/data/db mongo:2.6
docker run -d --name shareredis -v ${APP_PATH}/var/redis:/var/lib/redis redis:latest
docker run -d -P -p ${PORT}:80 -v ${APP_PATH}/var/sharelatex:/var/lib/sharelatex \
	-v ${APP_PATH}/var/log/sharelatex:/var/log/sharelatex \
	--env SHARELATEX_MONGO_URL=mongodb://mongo/sharelatex \
	--env SHARELATEX_REDIS_HOST=redis \
	--env SHARELATEX_ADMIN_EMAIL=$EMAIL \
	--env SHARELATEX_SITE_URL=$URL \
	--env SHARELATEX_APP_NAME="$APP_NAME" \
	--link sharemongo:mongo --link shareredis:redis --name sharelatex sharelatex/sharelatex

# Configurar el correu
# S'ha d'editar el fitxer /etc/sharelatex/settings.coffee
docker exec sharelatex awk '/# email:/{n++}{print >"/tmp/settings." n ".coffee" }' /etc/sharelatex/settings.coffee
docker exec sharelatex mv /etc/sharelatex/settings.coffee /etc/sharelatex/settings.coffee.backup
docker exec sharelatex bash -c 'cat /tmp/settings..coffee > /etc/sharelatex/settings.coffee'

cat << EOF | docker exec -i sharelatex bash -c 'cat >> /etc/sharelatex/settings.coffee'
	email:
		fromAddress: "$MAIL_FROM_ADDRESS"
		replyTo: "$MAIL_REPLY_TO"
		transport: "$MAIL_TRANSPORT"
		parameters:
			host: "$MAIL_HOST"
			port: "$MAIL_PORT"
			authMethod: "PLAIN"
			auth: {
				user: "$MAIL_USER",
				pass: "$MAIL_PASS" 
				}
			secure: false 
EOF
docker exec sharelatex bash -c 'cat /tmp/settings.1.coffee >> /etc/sharelatex/settings.coffee'

# Configure max upload
docker exec sharelatex bash -c "sed -i 's/http {/http {\n\tclient_max_body_size 512M;/' /etc/nginx/nginx.conf"
docker exec sharelatex bash -c "service nginx restart"

# Active Admin
docker exec sharelatex /bin/bash -c "cd /var/www/sharelatex/web; grunt create-admin-user --email $EMAIL"

# Install all texlive schemes.
docker exec sharelatex tlmgr update --self
docker exec sharelatex tlmgr install scheme-full
