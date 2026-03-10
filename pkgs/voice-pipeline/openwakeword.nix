{ lib
, python3Packages
, fetchPypi
, fetchurl
}:

let
  # Pre-fetch the required models so openWakeWord doesn't try to download at runtime
  embeddingModel = fetchurl {
    url = "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/embedding_model.onnx";
    sha256 = "sha256-cNFkKQwdCV0dTuFJvF4AVDJQpzFrWfMdBWz/e9MHXB8=";
  };
  melspectrogramModel = fetchurl {
    url = "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/melspectrogram.onnx";
    sha256 = "sha256-uisOD4t7h1NposicsTNg/1O6xDbyiVzO2fR5+mXrF28=";
  };
  sileroVadModel = fetchurl {
    url = "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/silero_vad.onnx";
    sha256 = "sha256-o16/Uv085fFGmyo2FY26dhvEe5c+ozgrMYbKFbH1ryg=";
  };
  heyJarvisModel = fetchurl {
    url = "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/hey_jarvis_v0.1.onnx";
    sha256 = "sha256-lKE8/mAHWxMvakcufkYugSPucIYbw/tYQ0pzcS7g0ss=";
  };
in
python3Packages.buildPythonPackage rec {
  pname = "openwakeword";
  version = "0.6.0";
  format = "wheel";

  src = fetchPypi {
    inherit pname version format;
    dist = "py3";
    python = "py3";
    sha256 = "sha256-b0I6Tjrp3Q480StQ/4q/aWefaHtKs0nXyCwCHA4qvJ0=";
  };

  propagatedBuildInputs = with python3Packages; [
    onnxruntime
    tqdm
    scipy
    scikit-learn
    requests
    numpy
  ];

  # Inject pre-fetched models into the package
  postInstall = ''
    modelsDir="$out/${python3Packages.python.sitePackages}/openwakeword/resources/models"
    mkdir -p "$modelsDir"
    cp ${embeddingModel} "$modelsDir/embedding_model.onnx"
    cp ${melspectrogramModel} "$modelsDir/melspectrogram.onnx"
    cp ${sileroVadModel} "$modelsDir/silero_vad.onnx"
    cp ${heyJarvisModel} "$modelsDir/hey_jarvis_v0.1.onnx"
  '';

  pythonImportsCheck = [ "openwakeword" ];

  meta = {
    description = "Open-source audio wake word detection framework";
    homepage = "https://github.com/dscripka/openWakeWord";
    license = lib.licenses.asl20;
  };
}
