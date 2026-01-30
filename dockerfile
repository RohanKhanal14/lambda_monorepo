FROM public.ecr.aws/sam/build-python3.11:latest-x86_64

# Install curl + tar (needed to fetch docker cli)
RUN yum -y install curl tar gzip && yum clean all

# Install Docker CLI (static) - no daemon, just the client binary
ARG DOCKER_CLI_VERSION=26.1.4
RUN curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_CLI_VERSION}.tgz" \
    -o /tmp/docker.tgz && \
    tar -xzf /tmp/docker.tgz -C /tmp && \
    mv /tmp/docker/docker /usr/local/bin/docker && \
    chmod +x /usr/local/bin/docker && \
    rm -rf /tmp/docker /tmp/docker.tgz

# Install SAM CLI + cfn-lint once, baked into the image
RUN pip3 install --no-cache-dir --upgrade pip && \
    pip3 install --no-cache-dir aws-sam-cli cfn-lint

# Sanity checks (now docker exists)
RUN python3 --version && \
    pip3 --version && \
    sam --version && \
    cfn-lint --version && \
    aws --version && \
    docker --version
