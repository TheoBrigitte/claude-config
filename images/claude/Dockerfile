ARG TARGETARCH
ARG CLAUDE_CODE_VERSION=2.1.317

# Checksums from https://downloads.claude.ai/claude-code-releases/<version>/manifest.json
FROM scratch AS claude-amd64
ARG CLAUDE_CODE_VERSION
ADD --chmod=0755 --checksum=sha256:bcc2be9105875dc31a44825ede92e46c4f98225eeb3ad617340daa217100339b \
    https://downloads.claude.ai/claude-code-releases/${CLAUDE_CODE_VERSION}/linux-x64-musl/claude /claude

FROM scratch AS claude-arm64
ARG CLAUDE_CODE_VERSION
ADD --chmod=0755 --checksum=sha256:dc8c59cf937e60e9cc93afe226ef437474ded56ba813743d09106d24a08c83bd \
    https://downloads.claude.ai/claude-code-releases/${CLAUDE_CODE_VERSION}/linux-arm64-musl/claude /claude

FROM claude-${TARGETARCH} AS claude

FROM alpine:3.24

RUN apk add --no-cache bash ca-certificates coreutils diffutils findutils gawk grep gzip jq libgcc libstdc++ procps-ng sed tar which \
 && addgroup -g 1000 node \
 && adduser -D -u 1000 -G node -h /home/node -s /bin/bash node

COPY --from=claude /claude /usr/local/bin/claude
COPY --chmod=0755 start.sh /usr/local/bin/start.sh

ENV DISABLE_AUTOUPDATER=1

USER node
WORKDIR /home/node
CMD ["/usr/local/bin/start.sh"]
