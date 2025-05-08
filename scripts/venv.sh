#!/bin/bash
set -e

VENV_DIR="venv"

echo "[SCRIPT] Creating virtual environment..."
python3 -m venv $VENV_DIR

echo "[SCRIPT] Activating virtual environment..."
source $VENV_DIR/bin/activate

echo "[SCRIPT] Python version:"
python --version

echo "[SCRIPT] Venv directory structure:"
ls -l $VENV_DIR
