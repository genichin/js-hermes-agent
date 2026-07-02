IMAGE    ?= genichin/js-hermes-agent
TAG      ?= latest
BASE_TAG ?= latest
PLATFORMS ?= linux/amd64,linux/arm64

.PHONY: build push release run setup gateway logs stop

# 로컬 아키텍처용 빌드
build:
	docker build --build-arg BASE_TAG=$(BASE_TAG) -t $(IMAGE):$(TAG) .

# 로컬 빌드 결과 푸시 (docker login 필요)
push: build
	docker push $(IMAGE):$(TAG)

# multi-arch(amd64+arm64) 빌드 후 바로 푸시 (buildx 필요, 권장)
release:
	docker buildx build \
		--platform $(PLATFORMS) \
		--build-arg BASE_TAG=$(BASE_TAG) \
		-t $(IMAGE):$(TAG) \
		--push .

# 최초 1회: 셋업 위저드 (API 키 등 ~/.hermes/.env 에 저장)
setup:
	mkdir -p ~/.hermes
	docker run -it --rm -v ~/.hermes:/opt/data $(IMAGE):$(TAG) setup

# 대화형 CLI 채팅
run:
	docker run -it --rm -v ~/.hermes:/opt/data $(IMAGE):$(TAG)

# 게이트웨이 모드 (compose 사용)
gateway:
	docker compose up -d

logs:
	docker compose logs -f

stop:
	docker compose down
