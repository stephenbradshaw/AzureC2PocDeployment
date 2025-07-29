#!/bin/bash
SLIVER_VERSION=v1.5.43

apt update
apt upgrade -y
apt install net-tools -y
apt install apache2 -y
apt install php -y
apt install libapache2-mod-php -y
apt install python-is-python3 -y
mkdir -p /opt/sliver
wget https://github.com/BishopFox/sliver/releases/download/$SLIVER_VERSION/sliver-server_linux -O /opt/sliver/sliver-server_linux_$SLIVER_VERSION
wget https://github.com/BishopFox/sliver/releases/download/$SLIVER_VERSION/sliver-client_linux -O /opt/sliver/sliver-client_linux_$SLIVER_VERSION
chmod +x /opt/sliver/sliver-*
rm -f /opt/sliver/sliver-client
rm -f /opt/sliver/sliver-server
ln -s /opt/sliver/sliver-client_linux_$SLIVER_VERSION /opt/sliver/sliver-client
ln -s /opt/sliver/sliver-server_linux_$SLIVER_VERSION /opt/sliver/sliver-server

echo '127.0.0.1 backend' >> /etc/hosts

cat > /etc/apache2/sites-available/ssl-forward-http.conf <<'endmsg'
<VirtualHost 0.0.0.0:443>

    SSLEngine on

    SSLCertificateFile      /etc/ssl/certs/ssl-cert-snakeoil.pem
    SSLCertificateKeyFile   /etc/ssl/private/ssl-cert-snakeoil.key

    RewriteEngine On

    <Directory /var/www/html>
        Options FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
        FileETag None
    </Directory>

    ProxyPreserveHost On

    ServerName localhost
    DocumentRoot /var/www/html

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log "%h \"%{X-Forwarded-For}i\" \"%{forwarded}i\"  %t \"%r\" %>s %b %{Host}i \"%{Referer}i\" \"%{User-agent}i\" ssl"

    ServerSignature Off

</VirtualHost>
endmsg



cat > /etc/apache2/sites-available/forward-http.conf <<'endmsg'
<VirtualHost 0.0.0.0:80>
    RewriteEngine On

    <Directory /var/www/html>
        Options FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
        FileETag None
    </Directory>

    ProxyPreserveHost On

    ServerName localhost
    DocumentRoot /var/www/html

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log "%h \"%{X-Forwarded-For}i\" \"%{forwarded}i\"  %t \"%r\" %>s %b %{Host}i \"%{Referer}i\" \"%{User-agent}i\""


    ServerSignature Off

</VirtualHost>
endmsg

a2enmod proxy_http proxy rewrite
a2dissite 000-default
a2ensite forward-http

systemctl restart apache2

# create a multiplay user file for local connection
SLIVER_ROOT_DIR=/opt/sliver/ /opt/sliver/sliver-server operator --name admin --lhost 127.0.0.1 --save /opt/sliver/admin_127.0.0.1.cfg


cat > /etc/systemd/system/sliver.service <<'endmsg'
[Unit]
Description=Sliver
After=network.target
StartLimitIntervalSec=0

[Service]
Environment="SLIVER_ROOT_DIR=/opt/sliver"
Type=simple
Restart=on-failure
RestartSec=3
User=root
ExecStart=/opt/sliver/sliver-server daemon

[Install]
WantedBy=multi-user.target
endmsg


systemctl daemon-reload

systemctl start sliver
systemctl status sliver


cat > /var/www/html/index.html <<'endmsg'
<html>
</html>
endmsg




cat > /var/www/html/robots.txt <<'endmsg'
User-agent: *
Disallow: /
endmsg



cat > /var/www/html/.htaccess <<'endmsg'
RewriteEngine on

# rewrite / to index.html
RewriteRule ^$ /index.html [L]

# serve files that exist
RewriteCond /%{REQUEST_FILENAME} -f
RewriteRule .? - [L]

# Respond to known command line/scanner user agents with 404
RewriteCond %{HTTP_USER_AGENT} curl|wget|masscan|python|zgrab|mobile|censys|hello|okhttp|scans|spider|bot [NC]
RewriteRule .* - [R=404]

# Send remaining requests to port 8888 on backend host
RewriteRule ^.*$ http://backend:8888%{REQUEST_URI} [P,NE]
endmsg


MRANDOM=`tr -dc A-Za-z0-9 </dev/urandom | head -c 24; echo`


cat > /var/www/html/$MRANDOM.php <<'endmsg'
<?php
echo "=REQUEST HEADERS=\n\n";
$headers = apache_request_headers();

foreach ($headers as $header => $value) {
	    echo "$header: $value \n";
}

echo "\n\n=APACHE VARIABLES=\n";

echo "HTTP HEADERS\n";
$HTTP_ACCEPT = getenv('HTTP_ACCEPT');
echo "HTTP_ACCEPT : $HTTP_ACCEPT\n";
$HTTP_COOKIE = getenv('HTTP_COOKIE');
echo "HTTP_COOKIE : $HTTP_COOKIE\n";
$HTTP_FORWARDED = getenv('HTTP_FORWARDED');
echo "HTTP_FORWARDED : $HTTP_FORWARDED\n";
$HTTP_X_FORWARDED_FOR = getenv('HTTP_X_FORWARDED_FOR');
echo "HTTP_X_FORWARDED_FOR : $HTTP_X_FORWARDED_FOR\n";
$HTTP_HOST = getenv('HTTP_HOST');
echo "HTTP_HOST : $HTTP_HOST\n";
$HTTP_PROXY_CONNECTION = getenv('HTTP_PROXY_CONNECTION');
echo "HTTP_PROXY_CONNECTION : $HTTP_PROXY_CONNECTION\n";
$HTTP_REFERER = getenv('HTTP_REFERER');
echo "HTTP_REFERER : $HTTP_REFERER\n";
$HTTP_USER_AGENT = getenv('HTTP_USER_AGENT');
echo "HTTP_USER_AGENT : $HTTP_USER_AGENT\n";

echo "\n\n=CONNECTION & REQUEST=\n";
$AUTH_TYPE = getenv('AUTH_TYPE');
echo "AUTH_TYPE : $AUTH_TYPE\n";
$CONN_REMOTE_ADDR = getenv('CONN_REMOTE_ADDR');
echo "CONN_REMOTE_ADDR : $CONN_REMOTE_ADDR\n";
$CONTEXT_PREFIX = getenv('CONTEXT_PREFIX');
echo "CONTEXT_PREFIX : $CONTEXT_PREFIX\n";
$IPV6 = getenv('IPV6');
echo "IPV6 : $IPV6\n";
$PATH_INFO = getenv('PATH_INFO');
echo "PATH_INFO : $PATH_INFO\n";
$QUERY_STRING = getenv('QUERY_STRING');
echo "QUERY_STRING : $QUERY_STRING\n";
$REMOTE_ADDR = getenv('REMOTE_ADDR');
echo "REMOTE_ADDR : $REMOTE_ADDR\n";
$REMOTE_HOST = getenv('REMOTE_HOST');
echo "REMOTE_HOST : $REMOTE_HOST\n";
$REMOTE_IDENT = getenv('REMOTE_IDENT');
echo "REMOTE_IDENT : $REMOTE_IDENT\n";
$REMOTE_PORT = getenv('REMOTE_PORT');
echo "REMOTE_PORT : $REMOTE_PORT\n";
$REMOTE_USER = getenv('REMOTE_USER');
echo "REMOTE_USER : $REMOTE_USER\n";
$REQUEST_METHOD = getenv('REQUEST_METHOD');
echo "REQUEST_METHOD : $REQUEST_METHOD\n";


echo "\n\n=SPECIALS=\n";
$CONN_REMOTE_ADDR = getenv('CONN_REMOTE_ADDR');
echo "CONN_REMOTE_ADDR : $CONN_REMOTE_ADDR\n";
$HTTPS = getenv('HTTPS');
echo "HTTPS : $HTTPS\n";
$IS_SUBREQ = getenv('IS_SUBREQ');
echo "IS_SUBREQ : $IS_SUBREQ\n";
$REMOTE_ADDR = getenv('REMOTE_ADDR');
echo "REMOTE_ADDR : $REMOTE_ADDR\n";
$REQUEST_FILENAME = getenv('REQUEST_FILENAME');
echo "REQUEST_FILENAME : $REQUEST_FILENAME\n";
$REQUEST_SCHEME = getenv('REQUEST_SCHEME');
echo "REQUEST_SCHEME : $REQUEST_SCHEME\n";
$REQUEST_URI = getenv('REQUEST_URI');
echo "REQUEST_URI : $REQUEST_URI\n";
$THE_REQUEST = getenv('THE_REQUEST');
echo "THE_REQUEST : $THE_REQUEST\n";

echo "\n\n=DATA=\n";
try {
echo "Parsed:\n";
print_r($_POST);
echo "\n";
} catch (Exception $e) {

}
try {
echo "Raw (base64 encoded):\n";
echo base64_encode(file_get_contents('php://input'));
} catch (Exception $e) {

}

echo "\n\nLength of input\n";
echo strlen(file_get_contents('php://input'));

echo "\n\nSha of input\n";
echo sha1(file_get_contents('php://input'));

echo "\n\nDone\n\n";

?>
endmsg

mkdir -p /home/ubuntu/.sliver-client/configs
mv /opt/sliver/admin_127.0.0.1.cfg /home/ubuntu/.sliver-client/configs/
chown ubuntu:ubuntu -R /home/ubuntu/.sliver-client
sudo -u ubuntu HOME=/home/ubuntu /bin/bash -c "echo http -l 8888 -p | /opt/sliver/sliver-client"

echo "Test script at $MRANDOM.php"
touch /home/ubuntu/setupdone
