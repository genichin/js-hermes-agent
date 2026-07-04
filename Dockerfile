# js-hermes-agent — Ubuntu 기반, 공식 인스톨러(git 방식) 설치
#
# 공식 nousresearch/hermes-agent 이미지는 /opt/hermes 를 root 소유 불변
# 트리로 두고 .install_method=docker 스탬프를 박아 `hermes update` 를
# 차단한다. 이 이미지는 공식 curl 인스톨러로 hermes 유저 소유
# /opt/apps/hermes-agent 에 git-clone 설치(.install_method=git)하므로
# 컨테이너 안에서 `hermes update` 가 동작한다.
#
# 주의: 컨테이너를 재생성하면 코드가 이미지 빌드 시점으로 돌아간다.
# update 는 "재빌드 없이 최신 유지" 용도이고, 영구 반영은 이미지 재빌드.
ARG UBUNTU_TAG=24.04
FROM ubuntu:${UBUNTU_TAG}
ARG TARGETARCH
ARG S6_OVERLAY_VERSION=3.2.3.0
ARG HERMES_BRANCH=main
ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="js-hermes-agent" \
      org.opencontainers.image.description="Hermes Agent on Ubuntu (installer-based; hermes update works)" \
      org.opencontainers.image.authors="Justin <genichin@gmail.com>" \
      org.opencontainers.image.base.name="docker.io/library/ubuntu"

# ── 시스템 패키지 ────────────────────────────────────────────────────────────
# build-essential/python3-dev/libffi-dev 는 설치·update 시 wheel 빌드용.
# node/uv/git 이 시스템(또는 볼륨)에 있어야 hermes update 가 자급자족한다.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl git jq xz-utils procps \
       openssh-server openssh-client \
       build-essential python3-dev libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# gh (GitHub CLI): 공식 apt 저장소
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 (nodesource) — 인스톨러가 시스템 node(>=22.12)를 감지하면
# 볼륨 안($HERMES_HOME/node)에 자체 node 를 설치하지 않는다.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# s6-overlay (공식 이미지와 같은 supervision 스택)
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) S6_ARCH=x86_64 ;; \
      arm64) S6_ARCH=aarch64 ;; \
      *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/s6-noarch.tar.xz "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz"; \
    curl -fsSL -o /tmp/s6-arch.tar.xz "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz"; \
    tar -C / -Jxpf /tmp/s6-noarch.tar.xz; \
    tar -C / -Jxpf /tmp/s6-arch.tar.xz; \
    rm -f /tmp/s6-*.tar.xz

# ── hermes 유저 (공식 이미지와 동일: uid 10000, HOME=/opt/data) ─────────────
# 비밀번호 '*' = 잠금 아님·비밀번호 로그인 불가 (SSH 공개키 인증용)
RUN useradd -u 10000 -U -m -d /opt/data -s /bin/bash hermes \
    && usermod -p '*' hermes \
    && mkdir -p /opt/apps \
    && chown hermes:hermes /opt/apps

# ── Hermes Agent 설치 (공식 인스톨러, git 방식) ─────────────────────────────
# --dir 을 볼륨 밖 /opt/apps/hermes-agent 로 명시해야 한다: 비루트 기본 경로는
# $HERMES_HOME/hermes-agent 인데 그곳은 런타임에 볼륨으로 가려진다.
# 인스톨러가 $HERMES_HOME/bin/uv 를 설치하지만 이것도 볼륨에 가려진다 —
# 런타임의 hermes_cli/managed_uv.py 가 없으면 자동 재설치하므로 문제 없음
# (오히려 볼륨에 영속됨).
# UV_PYTHON_INSTALL_DIR 를 볼륨 밖으로 고정하는 것이 필수: 기본값은
# ~/.local/share/uv/python(= /opt/data 볼륨 안)이라 venv 의 python 심볼릭
# 링크가 bind mount 시 끊겨 "unable to exec hermes" 로 기동 불능이 된다.
# 런타임 ENV 로도 유지해 hermes update 의 파이썬 해석도 같은 위치를 쓰게 한다.
ENV HERMES_HOME=/opt/data \
    PLAYWRIGHT_BROWSERS_PATH=/opt/apps/hermes-agent/.playwright \
    UV_PYTHON_INSTALL_DIR=/opt/apps/uv/python \
    UV_PYTHON_BIN_DIR=/opt/apps/uv/bin
USER hermes
RUN curl -fsSL https://hermes-agent.nousresearch.com/install.sh \
    | bash -s -- --dir /opt/apps/hermes-agent --branch "${HERMES_BRANCH}" \
        --skip-setup --non-interactive --skip-browser \
    && test -x /opt/apps/hermes-agent/venv/bin/hermes \
    && test "$(cat /opt/apps/hermes-agent/.install_method)" = git

# 브라우저: 인스톨러와 동일하게 저장소의 npx playwright 사용.
# 시스템 라이브러리는 root 로, chromium 바이너리는 hermes 소유
# PLAYWRIGHT_BROWSERS_PATH(이미지 안)에 설치
USER root
RUN cd /opt/apps/hermes-agent && npx playwright install-deps chromium \
    && rm -rf /var/lib/apt/lists/*
USER hermes
RUN cd /opt/apps/hermes-agent && npx playwright install chromium
USER root

# ── 런타임 ENV + SSH 세션 전파 ──────────────────────────────────────────────
# /opt/data/bin, /opt/data/.local/bin 은 런타임에 볼륨에서 생기는 도구(uv 등)용.
ENV PATH=/opt/apps/hermes-agent/venv/bin:/opt/data/bin:/opt/data/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HERMES_WRITE_SAFE_ROOT=/opt/data
# sshd(UsePAM yes) 세션은 Docker ENV 를 상속받지 않으므로 pam_env 가 읽는
# /etc/environment 에 덤프 (대화형/비대화형 모두 적용)
RUN env | grep -E '^(PATH|HERMES_|PLAYWRIGHT_|UV_)' > /etc/environment

# ── s6 서비스: sshd, user-services, dashboard + 엔트리포인트 ────────────────
COPY docker/sshd_config /etc/ssh/sshd_config.hermes
COPY docker/s6-rc.d/ /etc/s6-overlay/s6-rc.d/
COPY docker/cont-init.d/ /etc/cont-init.d/
COPY docker/main-wrapper.sh /opt/container/main-wrapper.sh
RUN chmod +x /etc/s6-overlay/s6-rc.d/*/run /etc/s6-overlay/s6-rc.d/*/finish \
       /etc/cont-init.d/* /opt/container/main-wrapper.sh \
    && mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/sshd \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/user-services \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/dashboard

EXPOSE 22 8642 9119

# CMD 라우팅은 공식 이미지와 동일: 인자 없음 → hermes CLI,
# 실행파일 → 그대로 실행, 그 외 → hermes <args> (예: gateway run)
ENTRYPOINT ["/init", "/opt/container/main-wrapper.sh"]
CMD []
