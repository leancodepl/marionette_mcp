# syntax=docker/dockerfile:1
FROM dart:stable

# Version of marionette_mcp to install from pub.dev.
# Bump this (or override with --build-arg) to track releases; pinning keeps the
# image reproducible for a given Docker MCP Registry commit.
ARG MARIONETTE_VERSION=0.5.0

RUN dart pub global activate marionette_mcp ${MARIONETTE_VERSION}
ENV PATH="${PATH}:/root/.pub-cache/bin"

LABEL org.opencontainers.image.title="marionette_mcp" \
      org.opencontainers.image.description="MCP server that lets AI agents inspect and interact with running Flutter apps." \
      org.opencontainers.image.source="https://github.com/leancodepl/marionette_mcp" \
      org.opencontainers.image.licenses="Apache-2.0"

# Default stdio transport — the form the Docker MCP gateway launches.
ENTRYPOINT ["marionette_mcp"]
