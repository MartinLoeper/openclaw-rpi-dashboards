{ lib
, python3Packages
, fetchPypi
, fetchurl
}:

let
  # Pre-fetch the required models so openWakeWord doesn't try to download at runtime
  embeddingModel = fetchurl {
    url = "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/embedding_model.tflite";
    sha256 = "sha256-wK6iHrhKTOkKCMhw2kG3pxc7RSaeajIHxx1nxA86Wdg=";
  };
  melspectrogramModel = fetchurl {
    url = "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/melspectrogram.tflite";
    sha256 = "sha256-lvoK3MtujPlcsURlQJoaKJjuSpaoW7ntPH6w5ovxY+g=";
  };
  sileroVadModel = fetchurl {
    url = "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/silero_vad.onnx";
    sha256 = "sha256-o16/Uv085fFGmyo2FY26dhvEe5c+ozgrMYbKFbH1ryg=";
  };
  heyJarvisModel = fetchurl {
    url = "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/hey_jarvis_v0.1.tflite";
    sha256 = "sha256-FL/3eGBJheG1wZ8Pe75HemnPKB2Ns0sjKzuXJBH3EOI=";
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
    ai-edge-litert
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
    cp ${embeddingModel} "$modelsDir/embedding_model.tflite"
    cp ${melspectrogramModel} "$modelsDir/melspectrogram.tflite"
    cp ${sileroVadModel} "$modelsDir/silero_vad.onnx"
    cp ${heyJarvisModel} "$modelsDir/hey_jarvis_v0.1.tflite"
  '';

  pythonImportsCheck = [ "openwakeword" ];

  meta = {
    description = "Open-source audio wake word detection framework";
    homepage = "https://github.com/dscripka/openWakeWord";
    license = lib.licenses.asl20;
  };
}
