# Makefile for creating release packages

.PHONY: release clean install-files

# Files to include in release
RELEASE_FILES = omada_rotation.sh omada_config.conf.example README.md Setup-Guide.md install-simple.sh install-from-release.sh

# Create release tarball
release: clean
	@echo "Creating release package..."
	@mkdir -p release/omada-rotation
	@cp $(RELEASE_FILES) release/omada-rotation/
	@cd release && tar -czf password-rotator.tar.gz omada-rotation/
	@echo "Release package created: release/password-rotator.tar.gz"
	@echo "Files included:"
	@tar -tzf release/password-rotator.tar.gz

# Create install-ready package (with config renamed)
install-files: clean
	@echo "Creating install-ready package..."
	@mkdir -p release/omada-rotation
	@cp omada_rotation.sh README.md Setup-Guide.md release/omada-rotation/
	@cp omada_config.conf.example release/omada-rotation/omada_config.conf
	@cd release && tar -czf omada-rotation-install.tar.gz omada-rotation/
	@echo "Install package created: release/omada-rotation-install.tar.gz"

# Clean release directory
clean:
	@rm -rf release/
	@echo "Cleaned release directory"

