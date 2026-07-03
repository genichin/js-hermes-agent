# js-hermes-agent
# 공식 Hermes Agent 이미지 기반 커스텀 이미지.
# 참고: https://hermes-agent.nousresearch.com/docs/user-guide/docker
ARG BASE_TAG=latest
FROM nousresearch/hermes-agent:${BASE_TAG}

LABEL org.opencontainers.image.title="js-hermes-agent" \
      org.opencontainers.image.description="Custom Hermes Agent image (based on nousresearch/hermes-agent)" \
      org.opencontainers.image.authors="Justin <genichin@gmail.com>" \
      org.opencontainers.image.base.name="docker.io/nousresearch/hermes-agent"

# 필요한 apt 패키지를 아래에 추가하세요.
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       jq \
       curl \
       openssh-server \
       ca-certificates \
    # gh (GitHub CLI): Debian 저장소 버전(2.46)이 오래돼 공식 apt 저장소 사용
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/* \
    # hermes 계정 SSH 로그인 준비:
    #  - 잠금 해제('!' → '*'; 비밀번호 로그인은 여전히 불가, 공개키만 허용)
    #  - 대화형 셸을 sh → bash 로 변경
    && usermod -p '*' -s /bin/bash hermes

# SSH 세션은 Docker ENV 를 상속받지 않으므로 (sshd 가 새 환경을 구성),
# 베이스 이미지의 런타임 ENV(PATH, HERMES_HOME 등)를 /etc/environment 에 덤프.
# sshd 는 UsePAM yes → pam_env 가 이 파일을 읽어 대화형/비대화형 세션 모두 적용됨.
# 빌드 시점 env 를 그대로 쓰므로 베이스 이미지의 ENV 변경도 자동 반영.
RUN env | grep -E '^(PATH|HERMES_|PYTHON|PLAYWRIGHT_|npm_config_)' > /etc/environment

# sshd: s6 supervised 서비스로 등록 (HERMES_SSHD=1 일 때만 기동)
COPY docker/sshd_config /etc/ssh/sshd_config.hermes
COPY docker/s6-rc.d/sshd/ /etc/s6-overlay/s6-rc.d/sshd/
# user-services: 볼륨(/opt/data/workspace/services/*/run)의 사용자 서비스를
# s6-svscan 으로 자동 실행·감독 (HERMES_USER_SERVICES=1 일 때만 기동)
COPY docker/s6-rc.d/user-services/ /etc/s6-overlay/s6-rc.d/user-services/
RUN chmod +x /etc/s6-overlay/s6-rc.d/sshd/run /etc/s6-overlay/s6-rc.d/sshd/finish \
       /etc/s6-overlay/s6-rc.d/user-services/run /etc/s6-overlay/s6-rc.d/user-services/finish \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/sshd \
       /etc/s6-overlay/s6-rc.d/user/contents.d/user-services

EXPOSE 22

# 주의: 베이스 이미지는 root 로 /init(s6-overlay)을 실행하고, 각 서비스가
# s6-setuidgid 로 hermes 유저로 강등한다. sshd 도 root 기동이 필요하므로
# USER 를 hermes 로 바꾸지 말 것.
# ENTRYPOINT(/init)와 /opt/data 볼륨 시맨틱, 기본 CMD 는 베이스 그대로 상속:
# 인자 없이 실행하면 hermes CLI, `gateway run`으로 게이트웨이 모드.
