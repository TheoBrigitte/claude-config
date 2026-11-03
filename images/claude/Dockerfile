FROM node:22-bookworm-slim

ARG CLAUDE_CODE_VERSION=2.1.317

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates procps \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
 && npm cache clean --force

ENV DISABLE_AUTOUPDATER=1

USER node
WORKDIR /home/node
