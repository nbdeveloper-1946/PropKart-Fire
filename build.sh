#!/bin/bash
echo "Downloading Flutter SDK..."
git clone https://github.com/flutter/flutter.git -b stable --depth 1
export PATH="$PATH:$(pwd)/flutter/bin"
echo "Running flutter doctor..."
flutter doctor
echo "Building Flutter Web release..."
flutter build web --release
