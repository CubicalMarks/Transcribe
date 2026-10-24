.PHONY: build dmg release run lint test check probe

build:
	bash scripts/build-app.sh

dmg:
	bash scripts/build-dmg.sh

release:
	bash scripts/release.sh $(RELEASE_ARGS)

run: build
	open dist/Transcribe.app

lint:
	bash scripts/lint.sh

test:
	swift test
	python3 scripts/test-release.py

check: lint build test

probe:
	swift run transcribe-probe --help
