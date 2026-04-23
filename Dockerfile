FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    python3 \
    nodejs \
    npm \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Anvil (Foundry)
RUN curl -L https://foundry.paradigm.xyz | bash
RUN $HOME/.foundry/bin/foundryup

# Add Foundry to PATH
ENV PATH="$PATH:/root/.foundry/bin"

# Create app directory
WORKDIR /app

# Copy entrypoint
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Expose ports
EXPOSE 8545 3000

# Set environment variables
ENV PORT=8545
ENV EXPLORER_PORT=3000
ENV JSONBIN_BIN_ID="6936f28bae596e708f8bafc0"
ENV JSONBIN_API_KEY='$2a$10$aAW84k1Q4lfQR8ELHBneT.01Go2JevCCoay/TR4AATTeNpTd7ou9K'
ENV FORK_URL="https://eth-mainnet.g.alchemy.com/v2/QFjExKnnaI2I4qTV7EFM7WwB0gl08X0n"
ENV CHAIN_ID="1"
ENV PUBLIC_URL="https://anvil-render-q5wl.onrender.com"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8545 || exit 1

# Run
CMD ["/app/entrypoint.sh"]
