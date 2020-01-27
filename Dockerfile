FROM php

## Install Base Packages
RUN apt-get update && apt-get -y install 

## Install Perl
RUN apt-get update && apt-get -y install \
    libapache2-mod-perl2 \ 
	libexpat1-dev \
	libswitch-perl \
    perl \
	make \
    curl \
    git \
    gcc \
	apache2
	
RUN cpan install XML::Simple Clone Date::Format Lingua::EN::Gender Lingua::EN::Titlecase Lingua::Conjunction Lingua::EN::Numbers Lingua::EN::Conjugate Template::Plugin::Lingua::EN::Inflect Number::Format Date::Parse Number::Format List::MoreUtils Test::More Lingua::Conjunction Lingua::EN::Conjugate Lingua::EN::Gender Lingua::EN::Numbers Lingua::EN::Titlecase Template::Plugin::Lingua::EN::Inflect Test::Exception Lingua::EN::Inflect::Number Lingua::EN::Inflect Test::Harness Email::Date::Format 
RUN cpan install Games::Dice::Roll20

RUN sed -i 's/AllowOverride None/AllowOverride All/g' /etc/apache2/apache2.conf

RUN a2enmod rewrite perl cgid

EXPOSE 80

RUN rm -rf /var/www/html/*
COPY source /var/www/html/generator/
RUN chmod +x /var/www/html/generator/*generator
RUN chown www-data:www-data /var/www/html/* -R

RUN apt-get remove make curl git gcc -y && apt-get autoremove -y

# forward request and error logs to docker log collector
RUN ln -sf /dev/stdout /var/log/apache2/access.log \
    && ln -sf /dev/stderr /var/log/apache2/error.log

CMD /usr/sbin/apache2ctl -D FOREGROUND