FROM docker.io/library/alpine:edge
ARG VERSION
RUN apk add --no-cache aws-cli=${VERSION}

ENTRYPOINT [ "/usr/bin/aws" ]
