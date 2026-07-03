# js-hermes-agent

[Hermes Agent](https://github.com/NousResearch/hermes-agent)(Nous Research)를 Docker로 실행하기 위한 프로젝트입니다. **Ubuntu 24.04 베이스에 공식 인스톨러(git 방식)로 설치**한 커스텀 이미지를 빌드해 Docker Hub(`genichin/js-hermes-agent`)에 배포합니다.

공식 `nousresearch/hermes-agent` 이미지 대신 직접 빌드하는 이유: 공식 이미지는 코드 트리가 root 소유 불변(`.install_method=docker`)이라 **컨테이너 안에서 `hermes update`가 차단**됩니다. 이 이미지는 hermes 유저 소유 `/opt/apps/hermes-agent`에 git-clone 설치(`.install_method=git`)하므로 **`hermes update`가 동작**합니다. 단, 컨테이너를 재생성하면 코드는 이미지 빌드 시점으로 돌아갑니다 (update는 재빌드 없이 최신 유지하는 용도).

## 구성

- `Dockerfile` — Ubuntu 24.04 + s6-overlay + 공식 인스톨러 설치. 추가 도구(jq, gh, openssh-server, node 22 등) 포함.
- `docker/` — sshd 설정, s6 서비스 정의(`sshd`, `user-services`, `dashboard`), 엔트리포인트(`main-wrapper.sh`), 부트스트랩(`cont-init.d/`).
- `docker-compose.yml` — 게이트웨이 + 대시보드 + sshd 상시 실행용.
- `Makefile` — 빌드/푸시/실행 명령 모음.

공식 이미지와 호환 유지: hermes 유저(uid 10000), `HERMES_HOME=/opt/data` 볼륨, CMD 라우팅(무인자 → CLI, `gateway run` → 게이트웨이) 동일 — **기존 `~/.hermes` 볼륨 그대로 사용 가능**.

## 빌드 & Docker Hub 푸시

```sh
docker login                 # Docker Hub 로그인 (최초 1회)

make build                   # 로컬 아키텍처용 빌드
make push                    # 빌드 + 푸시
make release                 # multi-arch(amd64+arm64) 빌드 + 푸시 (권장)
```

태그 지정: `make release TAG=v0.1.0`
Hermes 브랜치 지정: `make release HERMES_BRANCH=<브랜치>` (기본 main)

> `make release`는 buildx를 사용합니다. 최초 1회 `docker buildx create --use`가 필요할 수 있습니다.

## 사용법

### 1. 최초 설정 (1회)

```sh
make setup
```

셋업 위저드가 API 키 등을 물어보고 `~/.hermes/.env`에 저장합니다. 모든 상태(설정, 세션, 스킬, 메모리)는 호스트의 `~/.hermes/`에 저장되므로 이미지를 업그레이드해도 유지됩니다.

### 2. 게이트웨이 모드 (Telegram/Discord/Slack 등 상시 실행)

```sh
make gateway    # docker compose up -d
make logs       # 로그 확인
make stop       # 중지
```

- 포트 8642: OpenAI 호환 API / 헬스 엔드포인트
- 포트 9119: 웹 대시보드 (`HERMES_DASHBOARD=1`)
- 대시보드는 non-loopback 바인드 시 인증이 필수입니다. 간단하게는 `HERMES_DASHBOARD_BASIC_AUTH_USERNAME` / `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD` 환경변수를 compose에 추가하세요.

### 3. 대화형 CLI

```sh
make run
```

### 4. SSH 접속 (`HERMES_SSHD=1`)

컨테이너에 sshd 가 s6 supervised 서비스로 들어 있습니다. compose 기본값으로 켜져 있고 호스트 포트 2222 에 매핑됩니다.

```sh
# SSH 키가 없다면 먼저 생성 (~/.ssh/id_ed25519 + id_ed25519.pub 생성됨)
# 저장 위치는 Enter(기본값), 패스프레이즈는 선택(없으면 Enter 두 번)
ssh-keygen -t ed25519 -C "your-email@example.com"

# 공개키 등록 (호스트에서; ~/.hermes 가 /opt/data 로 마운트됨)
mkdir -p ~/.hermes/.ssh
cat ~/.ssh/id_ed25519.pub >> ~/.hermes/.ssh/authorized_keys

make gateway
ssh -p 2222 hermes@localhost
```

> 개인키(`id_ed25519`)는 절대 서버/저장소에 복사하지 마세요. 등록하는 것은 공개키(`.pub`)뿐입니다.

- **공개키 인증만** 허용 (비밀번호/루트 로그인 불가), 접속 유저는 `hermes`.
- 공개키는 `~/.hermes/.ssh/authorized_keys` 또는 `HERMES_SSHD_AUTHORIZED_KEYS` 환경변수로 주입 (환경변수 사용 시 파일을 **덮어씀**).
- 호스트 키는 `/opt/data/.ssh-host`(= `~/.hermes/.ssh-host`)에 영속화되어 컨테이너를 재생성해도 host key 경고가 없습니다.
- `HERMES_SSHD` 미설정 시 sshd 는 기동하지 않습니다 (dashboard 와 같은 게이팅 패턴).
- 컨테이너 내부 포트는 `HERMES_SSHD_PORT`(기본 22)로 변경 가능.

### 5. 사용자 서비스 자동 실행 (`HERMES_USER_SERVICES=1`)

볼륨의 `workspace/services/<이름>/run` 실행파일을 컨테이너 기동 시 자동 실행하고 s6 가 감독(크래시 시 자동 재시작)합니다. **서비스 추가/제거에 이미지 재빌드가 필요 없습니다.**

```sh
# 호스트에서 (또는 SSH 로 접속해 /opt/data/workspace/services 에):
mkdir -p ~/.hermes/workspace/services/myapp
cat > ~/.hermes/workspace/services/myapp/run <<'EOF'
#!/bin/sh
exec node /opt/data/workspace/myapp/server.js
EOF
chmod +x ~/.hermes/workspace/services/myapp/run
```

- `run` 은 **foreground 로 실행**되어야 합니다 (데몬화/백그라운드 금지 — s6 가 감독).
- 서비스는 hermes 유저로 실행됩니다.
- 새 서비스 디렉터리는 30초마다 자동 감지됩니다. 즉시 반영하려면 컨테이너 재시작.
- 서비스 제어 (컨테이너 안에서, PATH 에 `/command` 추가):
  `s6-svstat /opt/data/workspace/services/myapp` (상태),
  `s6-svc -t <dir>` (재시작), `s6-svc -d <dir>` (중지).
- 로그는 `docker logs` 로 통합 출력됩니다.

## compose.yaml 예제 (리포 클론 없이 이미지만 사용)

Docker Hub 이미지(`genichin/js-hermes-agent`)만 받아서 쓰는 경우의 독립형 `compose.yaml` 예제입니다:

```yaml
services:
  hermes:
    image: genichin/js-hermes-agent:20260704   # 또는 :latest
    container_name: hermes
    restart: unless-stopped
    command: gateway run
    ports:
      - "8642:8642"   # gateway API (OpenAI 호환)
      - "9119:9119"   # 웹 대시보드
      - "2222:22"     # SSH (hermes 유저, 공개키 인증만)
    volumes:
      - ~/.hermes:/opt/data        # 모든 상태(설정/세션/키)가 여기 저장됨
    environment:
      - HERMES_DASHBOARD=1
      # 대시보드는 non-loopback 바인드 시 인증 필수:
      - HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin
      - HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=change-me
      - HERMES_SSHD=1
      # SSH 공개키 주입 (또는 ~/.hermes/.ssh/authorized_keys 에 직접 추가):
      # - HERMES_SSHD_AUTHORIZED_KEYS=ssh-ed25519 AAAA... user@host
      # 사용자 서비스 자동 실행 (~/.hermes/workspace/services/<이름>/run):
      - HERMES_USER_SERVICES=1
      # API 키는 최초 1회 setup 위저드로 저장하거나 직접 전달:
      # - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      # - OPENAI_API_KEY=${OPENAI_API_KEY}
    shm_size: "1g"    # Playwright/브라우저 도구용
    deploy:
      resources:
        limits:
          memory: 4G
          cpus: "2.0"
```

```sh
# 최초 1회: API 키 설정
docker run -it --rm -v ~/.hermes:/opt/data genichin/js-hermes-agent:20260704 setup

# 기동
docker compose up -d
ssh -p 2222 hermes@<서버주소>
```

## 업그레이드

두 가지 방법이 있습니다:

**1. 컨테이너 안에서 즉시 업데이트** (재빌드 불필요, 컨테이너 재생성 시까지 유지):

```sh
docker exec -u hermes <컨테이너> hermes update
# 또는 SSH 접속 후: hermes update
```

**2. 이미지 재빌드** (영구 반영):

```sh
make release TAG=$(date +%Y%m%d)                # 재빌드 + 푸시 (인스톨러가 최신 main 을 clone)
docker compose pull && docker compose up -d     # 배포 서버에서 갱신
```

`~/.hermes` 데이터는 유지되며, 새 버전이 config 스키마 마이그레이션을 자동 수행합니다.

## 참고

- 공식 Docker 가이드: https://hermes-agent.nousresearch.com/docs/user-guide/docker
- 게이트웨이 컨테이너 2개를 같은 `~/.hermes`에 동시에 붙이지 마세요 (데이터 손상 위험).
- 브라우저 도구 사용 시 `shm_size: 1g` 필요 (compose에 반영됨).
