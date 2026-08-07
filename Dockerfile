FROM hub.rat.dev/library/swift:5.9-jammy

RUN apt-get update \
    && apt-get install -y --no-install-recommends git curl unzip shellcheck \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
CMD ["bash"]
