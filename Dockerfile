FROM alpine:3.22

ARG CLAUDE_VERSION=latest

ENV HOME=/home/agent \
    CLAUDE_CONFIG_DIR=/home/agent/.claude \
    USE_BUILTIN_RIPGREP=0 \
    DISABLE_AUTOUPDATER=1 \
    PATH=/home/agent/.local/bin:$PATH

RUN apk add --no-cache \
      bash \
      ca-certificates \
      curl \
      git \
      openssh-client \
      ripgrep \
      libgcc \
      libstdc++ \
      python3 \
      py3-pip \
      nodejs \
      npm \
    && addgroup -S agent \
    && adduser -S -G agent -s /bin/bash agent \
    && mkdir -p /home/agent/.claude /workspace \
    && chown -R agent:agent /home/agent /workspace

RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_VERSION}"

COPY --chown=agent:agent entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["claude"]
