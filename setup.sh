#!/bin/bash

set -e

#echo "🔧 Running system checks..."
#make check

#echo "⚙️ Running full install..."
#make install

echo "🐍 Activating Python virtual environment..."

# shellcheck source=.venv/bin/activate
source .venv/bin/activate

echo "🎉 Setup complete. You're ready to develop!"
