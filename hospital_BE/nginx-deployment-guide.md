# Nginx Deployment Guide with HTTPS and Custom Domain

This guide provides step-by-step instructions for deploying the application using Docker Compose, Nginx Proxy Manager (NPM), and configuring HTTPS with Let's Encrypt.

---

## 1. Install Docker and Docker Compose

Ensure that Docker and Docker Compose are installed on your server.

---

## 2. Docker Compose Configuration

Create a `docker-compose.yml` file:

```yaml
version: '3.8'
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '80:80'
      - '443:443'  
      - '81:81'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    environment:
      - TZ=Asia/Ho_Chi_Minh
    networks:
      - npm_network

  frontend-server:
    image: 'nginx:alpine'
    restart: unless-stopped
    volumes:
      - /var/www/hospital-react-app:/usr/share/nginx/html:ro
      - /var/www/nginx-config/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    networks:
      - npm_network

networks:
  npm_network:
    driver: bridge
```

---

## 3. Nginx Configuration for Frontend

1. Create the configuration directory and file:
```bash
sudo mkdir -p /var/www/nginx-config
sudo nano /var/www/nginx-config/nginx.conf
```

2. Add the following content to `nginx.conf`:
```nginx
server {
    listen 80 default_server;
    server_name _;
    
    root /usr/share/nginx/html;
    index index.html;

    # Disable content size matching and buffering
    proxy_buffering off;
    proxy_buffer_size 128k;
    proxy_buffers 4 256k;
    proxy_busy_buffers_size 256k;

    # Increase timeouts
    proxy_connect_timeout 600;
    proxy_send_timeout 600;
    proxy_read_timeout 600;
    send_timeout 600;

    location / {
        try_files $uri $uri/ /index.html;
        
        # Disable caching for HTML files
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header Pragma "no-cache";
        add_header Expires "0";
        
        # Fix content matching issues
        proxy_max_temp_file_size 0;
        proxy_buffering off;
    }

    # Static files handling
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, no-transform";
        access_log off;
        
        # Disable content size matching for static files
        proxy_buffering off;
    }

    # Enable gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 10240;
    gzip_proxied expired no-cache no-store private auth;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml;
    gzip_disable "MSIE [1-6]\.";

    # Increase client body size if needed
    client_max_body_size 20M;
}
```

3. Set permissions:
```bash
sudo chmod 644 /var/www/nginx-config/nginx.conf
```

---

## 4. Nginx Proxy Manager Configuration

1. Access Nginx Proxy Manager:
   - URL: `http://your-server-ip:81`
   - Default login:
     - Email: `admin@example.com`
     - Password: `changeme`

2. Configure the Frontend (`demoproject.software`):
   - Add new Proxy Host
   - Domain Names: `demoproject.software`
   - Scheme: `http`
   - Forward Hostname/IP: `frontend-server`
   - Forward Port: `80`
   - SSL Tab:
     - Request new SSL Certificate
     - Force SSL
     - HTTP/2 Support
     - Agree to Let's Encrypt Terms

3. Configure the Backend API (`api.demoproject.software`):
   - Add new Proxy Host
   - Domain Names: `api.demoproject.software`
   - Scheme: `http`
   - Forward Hostname/IP: `your-server-ip`
   - Forward Port: `8080` (or your backend port)
   - SSL Tab:
     - Request new SSL Certificate
     - Force SSL
     - HTTP/2 Support
   - Advanced Tab:
     - Websockets Support
     - Block Common Exploits
     - Custom headers:
       ```
       Access-Control-Allow-Origin: https://demoproject.software
       Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS
       Access-Control-Allow-Headers: Content-Type, Authorization
       Access-Control-Allow-Credentials: true
       ```

---

## 5. Deploy Frontend

1. Build the React app:
```bash
npm run build
```

2. Copy the build files:
```bash
sudo mkdir -p /var/www/hospital-react-app
sudo cp -r build/* /var/www/hospital-react-app/
```

3. Set permissions:
```bash
sudo chown -R www-data:www-data /var/www/hospital-react-app
sudo chmod -R 755 /var/www/hospital-react-app
```

---

## 6. Start Services

```bash
docker-compose up -d
```

---

## 7. DNS Verification

Ensure your DNS records are configured correctly:
- `A` record for `demoproject.software` pointing to your server IP.
- `A` record for `api.demoproject.software` pointing to your server IP.

---

## 8. Verify Deployment

1. Frontend: `https://demoproject.software`
2. Backend API: `https://api.demoproject.software`
3. Swagger UI: `https://api.demoproject.software/swagger`

---

## Troubleshooting

1. **If `index.html` content matching fails:**
   - Verify that `nginx.conf` is configured correctly.
   - Restart the frontend container:
     ```bash
     docker-compose restart frontend-server
     ```

2. **If SSL is not working:**
   - Check the Nginx Proxy Manager logs.
   - Ensure ports `80` and `443` are open in your server's firewall.
   - Verify that your DNS records have fully propagated.
