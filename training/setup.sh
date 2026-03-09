#!/usr/bin/env bash
# Setup script for openWakeWord training environment.
# Run inside the training devShell: nix develop .#training
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Setting up openWakeWord training environment ==="

# 1. Clone openWakeWord and piper-sample-generator
if [ ! -d "openwakeword" ]; then
  echo "Cloning openWakeWord..."
  git clone https://github.com/dscripka/openWakeWord openwakeword
else
  echo "openWakeWord already cloned"
fi

if [ ! -d "piper-sample-generator" ]; then
  echo "Cloning piper-sample-generator..."
  git clone https://github.com/rhasspy/piper-sample-generator
else
  echo "piper-sample-generator already cloned"
fi

# 2. Download Piper TTS model
PIPER_MODEL="piper-sample-generator/models/en_US-libritts_r-medium.pt"
if [ ! -f "$PIPER_MODEL" ]; then
  echo "Downloading Piper TTS model..."
  mkdir -p piper-sample-generator/models
  wget -O "$PIPER_MODEL" \
    'https://github.com/rhasspy/piper-sample-generator/releases/download/v2.0.0/en_US-libritts_r-medium.pt'
else
  echo "Piper TTS model already downloaded"
fi

# 3. Install pip-only dependencies (not in nixpkgs)
echo "Installing pip dependencies..."
pip install --quiet \
  "datasets>=2.14,<4" \
  audiomentations==0.33.0 \
  acoustics==0.2.6 \
  pronouncing==0.2.0 \
  deep-phonemizer==0.0.19

# Install openWakeWord in editable mode
pip install --quiet --no-deps -e ./openwakeword

# 4. Download openWakeWord embedding models
MODELS_DIR="openwakeword/openwakeword/resources/models"
mkdir -p "$MODELS_DIR"
for f in embedding_model.onnx embedding_model.tflite melspectrogram.onnx melspectrogram.tflite; do
  if [ ! -f "$MODELS_DIR/$f" ]; then
    echo "Downloading $f..."
    wget -q -O "$MODELS_DIR/$f" \
      "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/$f"
  fi
done

# 5. Download training data
mkdir -p data
echo ""
echo "=== Downloading training datasets ==="
echo "This downloads ~3GB of data (room impulse responses, background audio, features)."
echo ""

# Room impulse responses
if [ ! -d "data/mit_rirs" ]; then
  echo "Downloading MIT room impulse responses..."
  python3 -c "
import os, scipy.io.wavfile, numpy as np, datasets
from tqdm import tqdm
os.makedirs('data/mit_rirs', exist_ok=True)
ds = datasets.load_dataset('davidscripka/MIT_environmental_impulse_responses', split='train', streaming=True)
for row in tqdm(ds, desc='RIRs'):
    name = row['audio']['path'].split('/')[-1]
    scipy.io.wavfile.write(os.path.join('data/mit_rirs', name), 16000, (row['audio']['array']*32767).astype(np.int16))
"
else
  echo "MIT RIRs already downloaded"
fi

# Background audio (AudioSet sample)
if [ ! -d "data/audioset_16k" ]; then
  echo "Downloading AudioSet background audio sample..."
  mkdir -p data/audioset data/audioset_16k
  if wget --timeout=30 --tries=3 -O data/audioset/bal_train09.tar \
    "https://huggingface.co/datasets/agkphysics/AudioSet/resolve/main/data/bal_train09.tar" 2>&1; then
    cd data/audioset && tar -xf bal_train09.tar && cd ../..
    python3 -c "
import os, scipy.io.wavfile, numpy as np, datasets
from pathlib import Path
from tqdm import tqdm
os.makedirs('data/audioset_16k', exist_ok=True)
ds = datasets.Dataset.from_dict({'audio': [str(i) for i in Path('data/audioset/audio').glob('**/*.flac')]})
ds = ds.cast_column('audio', datasets.Audio(sampling_rate=16000))
for row in tqdm(ds, desc='AudioSet'):
    name = row['audio']['path'].split('/')[-1].replace('.flac', '.wav')
    scipy.io.wavfile.write(os.path.join('data/audioset_16k', name), 16000, (row['audio']['array']*32767).astype(np.int16))
"
  else
    echo "WARNING: AudioSet download failed — skipping. FMA background audio will be used instead."
    rmdir data/audioset_16k 2>/dev/null || true
  fi
else
  echo "AudioSet already downloaded"
fi

# FMA background music
if [ ! -d "data/fma" ]; then
  echo "Downloading FMA background music (1 hour)..."
  python3 -c "
import os, scipy.io.wavfile, numpy as np, datasets
from tqdm import tqdm
os.makedirs('data/fma', exist_ok=True)
ds = datasets.load_dataset('rudraml/fma', name='small', split='train', streaming=True, trust_remote_code=True)
ds = iter(ds.cast_column('audio', datasets.Audio(sampling_rate=16000)))
n_hours = 3
for i in tqdm(range(n_hours*3600//30), desc='FMA'):
    row = next(ds)
    name = row['audio']['path'].split('/')[-1].replace('.mp3', '.wav')
    scipy.io.wavfile.write(os.path.join('data/fma', name), 16000, (row['audio']['array']*32767).astype(np.int16))
"
else
  echo "FMA already downloaded"
fi

# Pre-computed features
if [ ! -f "data/openwakeword_features_ACAV100M_2000_hrs_16bit.npy" ]; then
  echo "Downloading ACAV100M features (~2GB)..."
  wget --timeout=60 --tries=3 -O data/openwakeword_features_ACAV100M_2000_hrs_16bit.npy \
    "https://huggingface.co/datasets/davidscripka/openwakeword_features/resolve/main/openwakeword_features_ACAV100M_2000_hrs_16bit.npy"
else
  echo "ACAV100M features already downloaded"
fi

if [ ! -f "data/validation_set_features.npy" ]; then
  echo "Downloading validation features..."
  wget --timeout=60 --tries=3 -O data/validation_set_features.npy \
    "https://huggingface.co/datasets/davidscripka/openwakeword_features/resolve/main/validation_set_features.npy"
else
  echo "Validation features already downloaded"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "To train the 'hey claw' model, run:"
echo "  cd training"
echo "  python openwakeword/openwakeword/train.py --training_config hey_claw.yml --generate_clips"
echo "  python openwakeword/openwakeword/train.py --training_config hey_claw.yml --augment_clips"
echo "  python openwakeword/openwakeword/train.py --training_config hey_claw.yml --train_model"
echo ""
echo "Or run all steps at once:"
echo "  ./train.sh"
