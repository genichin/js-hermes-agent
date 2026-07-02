# js-hermes-agent

[Hermes Agent](https://github.com/NousResearch/hermes-agent)(Nous Research)를 Docker로 실행하기 위한 프로젝트입니다. 공식 이미지 `nousresearch/hermes-agent`를 베이스로 커스텀 이미지를 빌드해 Docker Hub(`genichin/js-hermes-agent`)에 배포합니다.

## 구성

- `Dockerfile` — 공식 이미지 기반 파생 이미지. 추가 도구(jq, curl, gh, openssh-server 등)를 설치. 필요한 패키지는 여기에 추가.
- `docker/` — sshd 설정(`sshd_config`)과 s6 서비스 정의(`s6-rc.d/sshd/`).
- `docker-compose.yml` — 게이트웨이 + 대시보드 + sshd 상시 실행용.
- `Makefile` — 빌드/푸시/실행 명령 모음.

## 빌드 & Docker Hub 푸시

```sh
docker login                 # Docker Hub 로그인 (최초 1회)

make build                   # 로컬 아키텍처용 빌드
make push                    # 빌드 + 푸시
make release                 # multi-arch(amd64+arm64) 빌드 + 푸시 (권장)
```

태그 지정: `make release TAG=v0.1.0`
베이스 이미지 버전 고정: `make release BASE_TAG=<태그>`

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
# 공개키 등록 (호스트에서; ~/.hermes 가 /opt/data 로 마운트됨)
mkdir -p ~/.hermes/.ssh
cat ~/.ssh/id_ed25519.pub >> ~/.hermes/.ssh/authorized_keys

make gateway
ssh -p 2222 hermes@localhost
```

- **공개키 인증만** 허용 (비밀번호/루트 로그인 불가), 접속 유저는 `hermes`.
- 공개키는 `~/.hermes/.ssh/authorized_keys` 또는 `HERMES_SSHD_AUTHORIZED_KEYS` 환경변수로 주입 (환경변수 사용 시 파일을 **덮어씀**).
- 호스트 키는 `/opt/data/.ssh-host`(= `~/.hermes/.ssh-host`)에 영속화되어 컨테이너를 재생성해도 host key 경고가 없습니다.
- `HERMES_SSHD` 미설정 시 sshd 는 기동하지 않습니다 (dashboard 와 같은 게이팅 패턴).
- 컨테이너 내부 포트는 `HERMES_SSHD_PORT`(기본 22)로 변경 가능.

## 업그레이드

```sh
docker pull nousresearch/hermes-agent:latest   # 베이스 갱신
make release                                    # 재빌드 + 푸시
docker compose pull && docker compose up -d     # 배포 서버에서 갱신
```

`~/.hermes` 데이터는 유지되며, 새 이미지가 config 스키마 마이그레이션을 자동 수행합니다.

## 참고

- 공식 Docker 가이드: https://hermes-agent.nousresearch.com/docs/user-guide/docker
- 게이트웨이 컨테이너 2개를 같은 `~/.hermes`에 동시에 붙이지 마세요 (데이터 손상 위험).
- 브라우저 도구 사용 시 `shm_size: 1g` 필요 (compose에 반영됨).
