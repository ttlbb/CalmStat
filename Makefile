CC := xcrun clang
BUILD_DIR := .build
APP_DIR := dist/CalmStat.app
CONTENTS_DIR := $(APP_DIR)/Contents
BINARY := $(BUILD_DIR)/CalmStat
TEST_BINARY := $(BUILD_DIR)/formatter-tests
APP_ICON := support/CalmStat.icns
CFLAGS := -fobjc-arc -fmodules -fmodules-cache-path=$(BUILD_DIR)/ModuleCache -Wall -Wextra -Werror -mmacosx-version-min=13.0
FRAMEWORKS := -framework Cocoa -framework ServiceManagement

SOURCES := \
	Sources/CalmStat/main.m \
	Sources/CalmStat/CSFormatter.m \
	Sources/CalmStat/CSSystemMonitor.m \
	Sources/CalmStat/CSNetworkFloatingPanel.m \
	Sources/CalmStat/CSMenuBarController.m

.PHONY: all app test clean

all: app

$(BINARY): $(SOURCES)
	mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) -I Sources/CalmStat $(SOURCES) $(FRAMEWORKS) -o $(BINARY)

app: $(BINARY) support/Info.plist $(APP_ICON)
	rm -rf $(APP_DIR)
	mkdir -p $(CONTENTS_DIR)/MacOS $(CONTENTS_DIR)/Resources
	cp $(BINARY) $(CONTENTS_DIR)/MacOS/CalmStat
	cp support/Info.plist $(CONTENTS_DIR)/Info.plist
	cp $(APP_ICON) $(CONTENTS_DIR)/Resources/AppIcon.icns
	codesign --force --sign - $(APP_DIR)
	@echo "已生成：$(APP_DIR)"

$(TEST_BINARY): Tests/formatter_tests.m Sources/CalmStat/CSFormatter.m Sources/CalmStat/CSSystemMonitor.m
	mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) -I Sources/CalmStat $^ -framework Foundation -o $(TEST_BINARY)

test: $(TEST_BINARY)
	$(TEST_BINARY)

clean:
	rm -rf $(BUILD_DIR) $(APP_DIR)
