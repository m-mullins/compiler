FROM alpine:latest
RUN apk upgrade --update-cache --available && \
    apk add ghc curl musl-dev zlib-dev ncurses-dev ncurses-static
RUN curl -sSL https://get.haskellstack.org/ | sh
WORKDIR /app
RUN echo -e "#!/usr/bin/env sh\nexec stack --resolver lts-12.14 --system-ghc --allow-different-user \$*" >/usr/bin/stackp && chmod +x /usr/bin/stackp
CMD stackp build --flag elm:static; cp -p `stackp path --local-install-root`/bin/elm ./;
