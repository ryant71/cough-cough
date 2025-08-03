PARAMS_FILE := cloudformation/parameters/ec2-parameters.json
BUCKET := $(shell jq -r '.[] | select(.ParameterKey == "BucketName") | .ParameterValue' $(PARAMS_FILE))
S3_PATH := s3://$(BUCKET)/Downloads/
LOCAL_PATH := /media/ryan/MyBookWD/S3/

.PHONY: s3-sync s3-ls s3-clean help

.DEFAULT_GOAL := help

help:
	@echo ""
	@printf "$(YELLOW)Available Make targets:$(RESET)\n"
	@awk 'BEGIN {FS = ":.*?#"} /^[a-zA-Z0-9_.-]+:.*?#/ {printf "  \033[1;32m%-35s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)


s3-sync: # Sync to download directory
	@echo "Syncing from $(S3_PATH) to $(LOCAL_PATH)..."
	aws s3 sync $(S3_PATH) $(LOCAL_PATH)

s3-ls: # List S3 download contents
	@echo "Listing bucket: $(S3_PATH)"
	aws s3 ls $(S3_PATH)

s3-clean: # Remove files from S3 downloads directory
	@echo "Deleting contents of $(S3_PATH)..."
	aws s3 rm $(S3_PATH) --recursive

local-ls: # List contens of local download directory
	@echo "List contents of $(LOCAL_PATH)..."
	eza --tree -a -L 3  $(LOCAL_PATH)
