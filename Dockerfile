FROM wordpress:6.4-php8.2-apache

# Copy only wp-content if customized (themes, plugins, uploads)
COPY wp-content /var/www/html/wp-content

# Set proper ownership
RUN chown -R www-data:www-data /var/www/html

EXPOSE 80
