#!/bin/bash
yum -y install gcc zlib zlib-devel pcre-devel openssl openssl-devel
yum -y install gcc-c++ autoconf automake

wget -P /usr/bin http://www.modsecurity.cn/download/modsecurity/modsecurity-v3.0.4.tar.gz
cd /usr/bin; tar -xvzf modsecurity-v3.0.4.tar.gz -C /usr/local/
mv /usr/local/modsecurity-v3.0.4 /usr/local/modsecurity
cd /usr/local/modsecurity; ./configure --prefix=/usr/local/modsecurity
make && make install

wget -P /usr/bin https://documentation-samples.obs.cn-north-4.myhuaweicloud.com/solution-as-code-publicbucket/solution-as-code-moudle/build-a-WAF-based-on-modsecurity/open-source-software/ModSecurity-nginx-master.zip
unzip -o /usr/bin/ModSecurity-nginx-master.zip -d /usr/local/

wget -P /usr/bin https://nginx.org/download/nginx-1.21.1.tar.gz
tar -xvzf /usr/bin/nginx-1.21.1.tar.gz -C /usr/local/
mv /usr/local/nginx-1.21.1/ /usr/local/nginx
mkdir /usr/local/nginx/logs/
cd /usr/local/nginx; ./configure --add-module=/usr/local/ModSecurity-nginx-master --prefix=/usr/local/nginx --with-http_stub_status_module --with-http_ssl_module
make
make install

cpus=$(grep -c processor /proc/cpuinfo)
mkdir -p /usr/local/nginx/ssl
mkdir -p /usr/local/nginx/conf.d
cat>/usr/local/nginx/conf/nginx.conf<<EOF
#user  nobody;
worker_processes $cpus;
events {
    worker_connections 1024;
    multi_accept on;
    use epoll;
}
http {
    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 4096;
    include             /usr/local/nginx/conf/mime.types;
    default_type        application/octet-stream;
    include /usr/local/nginx/conf.d/*.conf;
    upstream webserver {
    }
    server {
        listen 443 ssl;
        server_name  localhost;
        ssl_certificate "/usr/local/nginx/ssl/$2";
        ssl_certificate_key "/usr/local/nginx/ssl/$3";
        ssl_session_cache shared:SSL:1m;
        ssl_session_timeout  10m;
        ssl_ciphers HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;
        location /{
            proxy_pass http://webserver;
            proxy_connect_timeout 5s;
        }
    }
    server {
        listen 80;
        server_name  localhost;
        location /{
            proxy_pass http://webserver;
            proxy_connect_timeout 5s;
        }
    }
}
EOF

RIPListString=$1
RIPList=(${RIPListString//,/ })
for rip in ${RIPList[@]}
do
   sed -i "18 i \        server $rip weight=1 max_fails=1 fail_timeout=10;" /usr/local/nginx/conf/nginx.conf
done

mkdir -p /usr/local/nginx/conf/modsecurity
cp /usr/local/modsecurity/modsecurity.conf-recommended /usr/local/nginx/conf/modsecurity/modsecurity.conf
cp /usr/local/modsecurity/unicode.mapping /usr/local/nginx/conf/modsecurity/unicode.mapping
wget -P /usr/bin http://www.modsecurity.cn/download/corerule/owasp-modsecurity-crs-3.3-dev.zip
unzip -o /usr/bin/owasp-modsecurity-crs-3.3-dev.zip -d /usr/bin
cp /usr/bin/owasp-modsecurity-crs-3.3-dev/crs-setup.conf.example  /usr/local/nginx/conf/modsecurity/crs-setup.conf
cp /usr/bin/owasp-modsecurity-crs-3.3-dev/rules -r  /usr/local/nginx/conf/modsecurity/
mv /usr/local/nginx/conf/modsecurity/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example /usr/local/nginx/conf/modsecurity/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf
mv /usr/local/nginx/conf/modsecurity/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf.example /usr/local/nginx/conf/modsecurity/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf
sed -i "/http /a\\    modsecurity_rules_file /usr/local/nginx/conf/modsecurity/modsecurity.conf;" /usr/local/nginx/conf/nginx.conf
sed -i "/http /a\\    modsecurity on;" /usr/local/nginx/conf/nginx.conf
sed -i "/SecRuleEngine DetectionOnly/a\\Include /usr/local/nginx/conf/modsecurity/rules/*.conf" /usr/local/nginx/conf/modsecurity/modsecurity.conf
sed -i "/SecRuleEngine DetectionOnly/a\\Include /usr/local/nginx/conf/modsecurity/crs-setup.conf" /usr/local/nginx/conf/modsecurity/modsecurity.conf
sed -i "s/SecRuleEngine DetectionOnly/SecRuleEngine On/" /usr/local/nginx/conf/modsecurity/modsecurity.conf
sed -i "60,81d" /usr/local/nginx/conf/modsecurity/rules/REQUEST-910-IP-REPUTATION.conf
cd /usr/local/nginx/sbin; ./nginx