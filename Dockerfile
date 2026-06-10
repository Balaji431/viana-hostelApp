FROM php:8.2-apache

# Install MySQL extensions
RUN docker-php-ext-install mysqli pdo pdo_mysql

# Enable Apache rewrite
RUN a2enmod rewrite

# Fix Apache FQDN warning
RUN echo "ServerName 15.206.172.50" >> /etc/apache2/apache2.conf

RUN echo "<Directory /var/www/html>\nOptions Indexes FollowSymLinks\nAllowOverride All\nRequire all granted\nEnableSendfile Off\n</Directory>" > /etc/apache2/conf-available/custom.conf && a2enconf custom

WORKDIR /var/www/html

# Copy frontend (compiled Flutter web)
COPY build/web/ /var/www/html/

# Copy backend (PHP API)
COPY hostel_backend/ /var/www/html/api/
