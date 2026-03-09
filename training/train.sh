#!/usr/bin/env bash
# Train the "hey claw" wake word model end-to-end.
# Run inside the training devShell after setup.sh has completed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

CONFIG="hey_claw.yml"
TRAIN="openwakeword/openwakeword/train.py"

if [ ! -f "$TRAIN" ]; then
  echo "Error: openWakeWord not found. Run ./setup.sh first."
  exit 1
fi

echo "=== Step 1/3: Generating synthetic clips ==="
python3 "$TRAIN" --training_config "$CONFIG" --generate_clips

echo ""
echo "=== Step 2/3: Augmenting clips ==="
python3 "$TRAIN" --training_config "$CONFIG" --augment_clips

echo ""
echo "=== Step 3/3: Training model ==="
python3 "$TRAIN" --training_config "$CONFIG" --train_model

echo ""
echo "=== Training complete ==="
echo "Model saved to: output/hey_claw/hey_claw.onnx"
echo ""
echo "To test with your microphone:"
echo "  python openwakeword/examples/detect_from_microphone.py --model_path output/hey_claw/hey_claw.onnx"
echo ""
echo "To deploy to the Pi, copy the .onnx file and set:"
echo "  services.clawpi.voice.wakewordModel = ./training/output/hey_claw/hey_claw.onnx;"
