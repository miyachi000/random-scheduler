FROM alpine:3.12.0

USER root

RUN echo 'alias ll="ls -al"' >> /etc/profile.d/ashrc.sh && \
    apk --no-cache add curl jq && \
    apk --no-cache add vim

COPY ./random-scheduler.sh /

CMD ["/bin/sh", "/random-scheduler.sh"]
