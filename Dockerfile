FROM imba3r/alpine
MAINTAINER imba3r

# Update packages and install software
RUN set -x \
    && apk add --no-cache openvpn

COPY openvpn/ /etc/openvpn/

CMD /etc/openvpn/start.sh
