.PHONY: build run lint test check probe

build:
	bash scripts/build-app.sh

run: build
	open dist/Transcribe.app

lint:
	bash scripts/lint.sh

test:
	swift test

check: lint build test

probe:
	swift run transcribe-probe --help
