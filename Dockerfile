ARG ALPINE_VERSION=3.10

FROM alpine:${ALPINE_VERSION} AS updated
WORKDIR /tmp/updated
RUN wget -q https://raw.githubusercontent.com/qdm12/files/master/named.root.updated -O root.hints && \
    wget -q https://raw.githubusercontent.com/qdm12/files/master/root.key.updated -O root.key
WORKDIR /tmp/updated/work
RUN wget -q https://raw.githubusercontent.com/qdm12/files/master/malicious-hostnames.updated -O malicious-hostnames && \
    wget -q https://raw.githubusercontent.com/qdm12/files/master/surveillance-hostnames.updated -O nsa-hostnames && \
    wget -q https://raw.githubusercontent.com/qdm12/files/master/malicious-ips.updated -O malicious-ips && \
    while read hostname; do echo "local-zone: \""$hostname"\" static" >> blocks-malicious.conf; done < malicious-hostnames && \
    while read ip; do echo "private-address: $ip" >> blocks-malicious.conf; done < malicious-ips && \
    tar -cjf /tmp/updated/blocks-malicious.bz2 blocks-malicious.conf && \
    while read hostname; do echo "local-zone: \""$hostname"\" static" >> blocks-nsa.conf; done < nsa-hostnames && \
    tar -cjf /tmp/updated/blocks-nsa.bz2 blocks-nsa.conf && \
    rm -rf /tmp/updated/work/*

FROM alpine:${ALPINE_VERSION}
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION
LABEL \
    org.opencontainers.image.authors="quentin.mcgaw@gmail.com" \
    org.opencontainers.image.created=$BUILD_DATE \
    org.opencontainers.image.version=$VERSION \
    org.opencontainers.image.revision=$VCS_REF \
    org.opencontainers.image.url="https://github.com/qdm12/cloudflare-dns-server" \
    org.opencontainers.image.documentation="https://github.com/qdm12/cloudflare-dns-server/blob/master/README.md" \
    org.opencontainers.image.source="https://github.com/qdm12/cloudflare-dns-server" \
    org.opencontainers.image.title="cloudflare-dns-server" \
    org.opencontainers.image.description="Runs a local DNS server connected to Cloudflare DNS server 1.1.1.1 over TLS (and more)"
EXPOSE 53/udp
ENV VERBOSITY=1 \
    VERBOSITY_DETAILS=0 \
    BLOCK_MALICIOUS=on \
    BLOCK_NSA=off \
    UNBLOCK= \
    LISTENINGPORT=53 \
    PROVIDERS=cloudflare \
    CACHING=on \
    PRIVATE_ADDRESS=127.0.0.1/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.0.0/16,::1/128,fc00::/7,fe80::/10,::ffff:0:0/96
ENTRYPOINT /unbound/entrypoint.sh
HEALTHCHECK --interval=5m --timeout=15s --start-period=5s --retries=1 \
    CMD LISTENINGPORT=${LISTENINGPORT:-53}; dig @127.0.0.1 +short +time=1 duckduckgo.com -p $LISTENINGPORT &> /dev/null; [ $? = 0 ] || exit 1
WORKDIR /unbound
RUN adduser nonrootuser -D -H --uid 1000 && \
    echo "http://dl-cdn.alpinelinux.org/alpine/edge/main" > /etc/apk/repositories && \
    echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories && \
    apk --update --progress -q add ca-certificates bind-tools unbound libcap && \
    mv /usr/sbin/unbound . && \
    chown 1000 unbound && \
    chmod 500 unbound && \
    setcap 'cap_net_bind_service=+ep' unbound && \
    rm -rf /var/cache/apk/* /etc/unbound/* /usr/sbin/unbound-* && \
    mv /etc/ssl/certs/ca-certificates.crt . && \
    chown nonrootuser . ca-certificates.crt && \
    chmod 400 ca-certificates.crt && \
    chmod 700 .
COPY --from=updated --chown=nonrootuser /tmp/updated/root.hints .
COPY --from=updated --chown=nonrootuser /tmp/updated/root.key .
COPY --from=updated --chown=nonrootuser /tmp/updated/blocks-malicious.bz2 .
COPY --from=updated --chown=nonrootuser /tmp/updated/blocks-nsa.bz2 .
COPY --chown=nonrootuser unbound.conf entrypoint.sh ./
RUN chmod 500 entrypoint.sh
USER nonrootuser
