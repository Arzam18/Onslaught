CXX ?= g++
.DEFAULT_GOAL := release
CXXFLAGS=-Wall -MMD -MP -Wno-switch -Isrc -std=c++17 -DSPSA_TUNE
LDFLAGS=
EVALFILE=nn-abd46cb3aae8e9ac-v2.nnue

# Embed the network when it is present. This also permits source-only builds
# (for example, perft/syntax checks) without silently embedding a missing file.
ifneq ($(wildcard $(EVALFILE)),)
    CXXFLAGS += -DEVALFILE='"$(EVALFILE)"'
else
    $(info NNUE file '$(EVALFILE)' not found; building with runtime NNUE loading/HCE fallback)
endif

UCI_DATE ?=
ifneq ($(strip $(UCI_DATE)),)
    CXXFLAGS += -DUCI_BUILD_DATE='"$(UCI_DATE)"'
endif
CXXFLAGS += $(EXTRA_CXXFLAGS)
LDFLAGS += $(EXTRA_LDFLAGS)

OBJDIR=build
SRC=$(shell find src -name '*.cpp')
C_SRC=$(filter-out %tbchess.c,$(shell find src -name '*.c'))

# ---------------------------------------------------------------------------
# Release builds
#   make releases VERSION=1.0        -> all four variants into $(DISTDIR)/
#   make release-avx2 VERSION=1.0    -> just one variant
# Output: Onslaught-<version>-<windows|ubuntu>-x86-64[-popcnt|-avx2|-avx512]
# ---------------------------------------------------------------------------
VERSION ?= dev
DISTDIR ?= dist
ARCHS   := none popcnt avx2 avx512

ifeq ($(OS),Windows_NT)
    PLATFORM ?= windows
    EXE_EXT  := .exe
else
    PLATFORM ?= ubuntu
    EXE_EXT  :=
endif

ARCH_FLAGS_none   := -march=x86-64
ARCH_FLAGS_popcnt := -march=x86-64 -mpopcnt
ARCH_FLAGS_avx2   := -march=x86-64 -mpopcnt -mavx2 -mbmi
ARCH_FLAGS_avx512 := $(ARCH_FLAGS_avx2) -mavx512f -mavx512bw

ifeq ($(MAKECMDGOALS),)
    MAKECMDGOALS += release
endif

ifneq ($(filter debug,$(MAKECMDGOALS)),)
    CXXFLAGS += -DDEBUG -g
    OBJDIR:=$(OBJDIR)/debug
endif
ifneq ($(filter release,$(MAKECMDGOALS)),)
    CXXFLAGS += -O3
    OBJDIR:=$(OBJDIR)/release
endif
ifneq ($(filter lto,$(MAKECMDGOALS)),)
    CXXFLAGS += -O3 -flto
    LDFLAGS += -flto
ifneq ($(shell uname),Darwin)
    LDFLAGS += -static
endif
    OBJDIR:=$(OBJDIR)/lto
endif
ifneq ($(filter native,$(MAKECMDGOALS)),)
    CXXFLAGS += -O3 -flto -march=native
ifneq ($(shell uname),Darwin)
    CXXFLAGS += -mpopcnt
    LDFLAGS += -static
endif
    LDFLAGS += -flto
    OBJDIR:=$(OBJDIR)/native
endif
ifneq ($(filter pg,$(MAKECMDGOALS)),)
    CXXFLAGS += -pg
    LDFLAGS += -pg
    OBJDIR:=$(OBJDIR)/pg
endif
ifneq ($(filter tune,$(MAKECMDGOALS)),)
    CXXFLAGS += -DTUNING -O3 -flto -march=native
    OBJDIR:=$(OBJDIR)/tune
endif
ifneq ($(filter spsa,$(MAKECMDGOALS)),)
    CXXFLAGS += -DSPSA_TUNE -O3 -flto
    LDFLAGS += -flto
ifneq ($(shell uname),Darwin)
    LDFLAGS += -static
endif
    OBJDIR:=$(OBJDIR)/spsa
endif
ifneq ($(filter perft,$(MAKECMDGOALS)),)
    CXXFLAGS += -O3 -flto -DPERFT
    LDFLAGS += -flto
    OBJDIR:=$(OBJDIR)/perft
endif
# Internal goal used by the release-<arch> targets (one sub-make per variant)
ifneq ($(filter variant,$(MAKECMDGOALS)),)
ifeq ($(filter $(ARCH),$(ARCHS)),)
    $(error ARCH must be one of: $(ARCHS))
endif
    CXXFLAGS += -O3 -flto $(ARCH_FLAGS_$(ARCH))
    LDFLAGS  += -O3 -flto $(ARCH_FLAGS_$(ARCH))
ifneq ($(shell uname),Darwin)
    LDFLAGS  += -static
endif
    OBJDIR:=$(OBJDIR)/release-$(ARCH)
    ARCH_SUFFIX := $(if $(filter none,$(ARCH)),,-$(ARCH))
    EXE := $(DISTDIR)/Onslaught-$(VERSION)-$(PLATFORM)-x86-64$(ARCH_SUFFIX)$(EXE_EXT)
endif

# Android ARM64 release (NEON baseline). DotProd is intentionally not exposed
# as an engine variant: the current NNUE uses int16 weights and squared clipped
# activations, so its hot path has no exact/efficient int8 dot-product kernel.
ANDROID_API ?= 24
ANDROID_NDK_HOME ?= $(ANDROID_NDK_LATEST_HOME)
ANDROID_CXX ?= $(ANDROID_NDK_HOME)/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android$(ANDROID_API)-clang++
ANDROID_EXE ?= $(DISTDIR)/Onslaught-$(VERSION)-android-arm64-neon

android-neon:
	@test -x "$(ANDROID_CXX)" || { echo "Android compiler not found: $(ANDROID_CXX)" >&2; exit 1; }
	@$(MAKE) --no-print-directory release CXX="$(ANDROID_CXX)" UCI_DATE="$(UCI_DATE)" \
		EXTRA_CXXFLAGS="-O3 -flto -march=armv8-a+simd -mtune=cortex-a76" \
		EXTRA_LDFLAGS="-flto -static-libstdc++" EXE="$(ANDROID_EXE)"

OBJ=$(patsubst src/%.cpp,$(OBJDIR)/%.o,$(SRC))
C_OBJ=$(patsubst src/%.c,$(OBJDIR)/%.o,$(C_SRC))
DEPS=$(OBJ:.o=.d) $(C_OBJ:.o=.d)
EXE ?= $(OBJDIR)/Onslaught

release: $(EXE)
debug: $(EXE)
lto: $(EXE)
native: $(EXE)
pg: $(EXE)
tune: $(EXE)
spsa: $(EXE)
perft: $(EXE)
variant: $(EXE)

RELEASE_TARGETS := $(addprefix release-,$(ARCHS))

releases: $(RELEASE_TARGETS)

$(RELEASE_TARGETS): release-%:
	@$(MAKE) --no-print-directory variant ARCH=$* VERSION=$(VERSION) PLATFORM=$(PLATFORM)

$(EXE): $(OBJ) $(C_OBJ)
	@echo "  LINK $@"
	@mkdir -p $(dir $@)
	@$(CXX) $(LDFLAGS) $^ -o $@

$(OBJDIR)/%.o: src/%.cpp src/%.h
	@echo "  CXXC $@"
	@mkdir -p $(dir $@)
	@$(CXX) $(CXXFLAGS) -c $< -o $@

$(OBJDIR)/%.o: src/%.cpp
	@echo "  CXXC $@"
	@mkdir -p $(dir $@)
	@$(CXX) $(CXXFLAGS) -c $< -o $@

$(OBJDIR)/%.o: src/%.c
	@echo "  CXXC $@"
	@mkdir -p $(dir $@)
	@$(CXX) $(CXXFLAGS) -x c++ -c $< -o $@

clean:
	rm -rf $(OBJDIR)

.PHONY: all clean debug release releases variant android-neon $(RELEASE_TARGETS)
-include $(DEPS)