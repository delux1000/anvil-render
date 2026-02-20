FROM ghcr.io/foundry-rs/foundry:latest

RUN apt-get update && apt-get install -y curl jq && rm -rf /var/lib/apt/lists/*

EXPOSE 8545

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV PORT=8545
ENV STATE_FILE=/tmp/state.json

ENTRYPOINT ["/entrypoint.sh"]
