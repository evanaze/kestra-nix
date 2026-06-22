{
  stdenvNoCC,
  lib,
  fetchurl,
  makeWrapper,
  javaPackages,
}:

let
  version = "1.3.22";
  jre = javaPackages.compiler.temurin-bin.jre-25;
in
stdenvNoCC.mkDerivation {
  pname = "kestra";
  inherit version;

  src = fetchurl {
    url = "https://github.com/kestra-io/kestra/releases/download/v${version}/kestra-${version}";
    hash = "sha256-sEqtCn4mnP2frV8RskiSZLT9U9IP5bEl2t/rzXtrM80=";
  };

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/java $out/bin
    cp $src $out/share/java/kestra.jar

    makeWrapper ${jre}/bin/java $out/bin/kestra \
      --add-flags "-jar" \
      --add-flags "$out/share/java/kestra.jar"

    runHook postInstall
  '';

  meta = {
    description = "Kestra workflow orchestrator standalone server distribution";
    homepage = "https://github.com/kestra-io/kestra";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "kestra";
  };
}
