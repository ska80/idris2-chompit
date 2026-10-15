PACK   ?= pack
PYTHON ?= python3
CG     ?= chez
ARGS   ?=

SDL_ROOT := $(abspath ../idris2-sdl3)

ROOT := $(SDL_ROOT)

PACK_CHEZ = $(PACK) --no-prompt --cg=chez

.NOTPARALLEL:
.DEFAULT_GOAL := all

ifneq ($(CG),chez)
$(error Only the Chez backend is supported)
endif

SDL_PACKAGES := $(if $(filter-out clean assets,$(or $(MAKECMDGOALS),all)),sdl3 sdl3-mixer)

include $(SDL_ROOT)/cbits/runtime.mk

.PHONY: all deps assets run test smoke clean
all: deps
	$(PACK_CHEZ) build chompit.ipkg

deps:
	$(MAKE) -C "$(SDL_ROOT)" PACK="$(PACK)" CG="$(CG)" core mixer

# Regenerate tracked sounds only when explicitly requested.
assets:
	$(PYTHON) tools/generate_audio.py

run: all
	./build/exec/chompit $(ARGS)

test: all
	$(PACK_CHEZ) build chompit-test.ipkg
	./build/test/exec/chompit-test
	$(PYTHON) tools/test_audio.py
	$(MAKE) smoke

smoke: all
	SDL_VIDEODRIVER=dummy SDL_RENDER_DRIVER=software SDL_AUDIO_DRIVER=dummy ./build/exec/chompit --smoke
	SDL_VIDEODRIVER=dummy SDL_RENDER_DRIVER=software ./build/exec/chompit --smoke --silent

clean:
	$(PACK) --no-prompt clean chompit.ipkg
	$(PACK) --no-prompt clean chompit-test.ipkg
