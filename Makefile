DC=dmd
DFLAGS=-m64 -I=common -debug -g -inline -O
LD=link.exe
LDFLAGS=/NOLOGO /DEFAULTLIB:"user32.lib" /DEFAULTLIB:"gdi32.lib" /DEFAULTLIB:"winmm.lib" /DEFAULTLIB:"phobos64.lib" /DEBUG legacy_stdio_definitions.lib /LIBPATH:"C:\D\dmd2\windows\lib64"

COMMON_D_SOURCES=$(wildcard common/*.d common/*/*.d common/*/*/*.d common/*/*/*/*.d)
COMMON_D_OBJECTS=$(patsubst common/%.d,build/common/%.obj,$(COMMON_D_SOURCES))
COMMON_D_DEPS=$(patsubst common/%.d,build/common/%.mk,$(COMMON_D_SOURCES))

GAME_D_SOURCES=$(wildcard game/*.d game/*/*.d game/*/*/*.d game/*/*/*/*.d)
GAME_D_OBJECTS=$(patsubst game/%.d,build/game/%.obj,$(GAME_D_SOURCES))
GAME_D_DEPS=$(patsubst game/%.d,build/game/%.mk,$(GAME_D_SOURCES))

PLATFORM_D_SOURCES=$(wildcard platform/*.d platform/*/*.d platform/*/*/*.d platform/*/*/*/*.d)
PLATFORM_D_OBJECTS=$(patsubst platform/%.d,build/platform/%.obj,$(PLATFORM_D_SOURCES))
PLATFORM_D_DEPS=$(patsubst platform/%.d,build/platform/%.mk,$(PLATFORM_D_SOURCES))

.PHONY: all
all: build/hhd.exe build/hhd-game.dll

.PHONY: clean
clean:
	del /Q build

.PHONY: run
run: all
	build/hhd.exe

build/hhd.exe: $(PLATFORM_D_OBJECTS) $(COMMON_D_OBJECTS)
	echo $(PLATFORM_D_SOURCES)
	$(LD) $(LDFLAGS) -out:$@ $^

build/hhd-game.dll: $(GAME_D_OBJECTS) $(COMMON_D_OBJECTS)
	$(LD) $(LDFLAGS) -dll -out:$@ $^

build/common/%.obj: common/%.d
	$(DC) $(DFLAGS) -makedeps=$(patsubst %.obj,%.mk,$@) -c -of$@ $<

build/game/%.obj: game/%.d
	$(DC) $(DFLAGS) -I=game -makedeps=$(patsubst %.obj,%.mk,$@) -c -of$@ $<

build/platform/%.obj: platform/%.d
	$(DC) $(DFLAGS) -I=platform -makedeps=$(patsubst %.obj,%.mk,$@) -c -of$@ $<

-include $(COMMON_D_DEPS)
-include $(GAME_D_DEPS)
-include $(PLATFORM_D_DEPS)
