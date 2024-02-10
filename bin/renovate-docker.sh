#!/usr/bin/env bash

# Avoids fatal: detected dubious ownership in repository at '/app'
git config --global --add safe.directory /app

shift
echo "renovate ${@}"
renovate "${@}"