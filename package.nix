{ lib, stdenv, stdenvNoCC, appimageTools, fetchurl, makeWrapper, unzip, asar, channel, release }:

let
  isNightly = channel == "nightly";
  pname = if isNightly then "t3code-nightly" else "t3code";
  executableName = pname;
  wrapperEnvironment = ''
    --set T3CODE_DISABLE_AUTO_UPDATE "true" \
    ${lib.optionalString isNightly ''
      --run 'export T3CODE_HOME="$HOME/.t3-nightly"' \
      --run 'export XDG_CONFIG_HOME="$HOME/.config/t3code-nightly"' \
      --run 'export XDG_DATA_HOME="$HOME/.local/share/t3code-nightly"'
    ''}
  '';
  commonMeta = {
    description = "T3 Code desktop application (${channel} channel)";
    homepage = "https://t3.codes";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/${release.tag}";
    license = lib.licenses.mit;
    mainProgram = executableName;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
  };

  # Asset names are resolved by scripts/update.sh and stored verbatim in
  # versions.json, because T3 Code changes its release asset naming
  # (e.g. v0.1.11 dropped the version from the AppImage names).
  asset = release.assets.${stdenv.hostPlatform.system};
  src = fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/${release.tag}/${asset.name}";
    hash = asset.hash;
  };
  appimageContents = appimageTools.extract {
    inherit pname;
    inherit (release) version;
    inherit src;
  };
  linuxPackage = appimageTools.wrapType2 {
    inherit pname;
    inherit (release) version;
    inherit src;
    nativeBuildInputs = [ makeWrapper ];

    extraInstallCommands = ''
      wrapProgram "$out/bin/${pname}" ${wrapperEnvironment}

      mkdir -p "$out/share/applications"
      desktop_source="$(find ${appimageContents} -name '*.desktop' -print -quit)"

      if [ -n "$desktop_source" ]; then
        desktop_file="$out/share/applications/${pname}.desktop"
        cp "$desktop_source" "$desktop_file"

        substituteInPlace "$desktop_file" \
          --replace-warn "Exec=AppRun" "Exec=${executableName}" \
          --replace-warn "TryExec=AppRun" "TryExec=${executableName}" \

        if ! grep -q '^MimeType=' "$desktop_file"; then
          echo 'MimeType=x-scheme-handler/t3code;' >> "$desktop_file"
        fi  
      fi
    '';

    meta = commonMeta;
  };

  darwinPackage = stdenvNoCC.mkDerivation {
    inherit pname;
    inherit (release) version;

    inherit src;
    nativeBuildInputs = [ makeWrapper unzip ] ++ lib.optionals isNightly [ asar ];
    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/Applications" "$out/bin"
      app="$(find . -maxdepth 1 -name '*.app' -print -quit)"
      test -n "$app"
      cp -R "$app" "$out/Applications/"
      installed_app="$out/Applications/$(basename "$app")"

      ${lib.optionalString isNightly ''
        asar extract "$installed_app/Contents/Resources/app.asar" app-asar
        substituteInPlace app-asar/apps/desktop/dist-electron/main.cjs \
          --replace-fail 'const userDataDirName = isDevelopment ? "t3code-dev" : "t3code";' 'const userDataDirName = isDevelopment ? "t3code-dev" : "t3code-nightly";' \
          --replace-fail 'const legacyUserDataDirName = isDevelopment ? "T3 Code (Dev)" : "T3 Code (Alpha)";' 'const legacyUserDataDirName = isDevelopment ? "T3 Code (Dev)" : "t3code-nightly";'
        rm "$installed_app/Contents/Resources/app.asar"
        asar pack app-asar "$installed_app/Contents/Resources/app.asar"
        rm -rf app-asar
      ''}

      executable="$(find "$installed_app/Contents/MacOS" -type f -perm -0100 -print -quit)"
      test -n "$executable"
      makeWrapper "$executable" "$out/bin/${executableName}" \
        ${wrapperEnvironment}
      runHook postInstall
    '';

    meta = commonMeta;
  };
in
if stdenv.hostPlatform.isLinux then linuxPackage
else if stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64 then darwinPackage
else if stdenv.hostPlatform.isDarwin then
  throw "T3 Code is not packaged for ${stdenv.hostPlatform.system}; only aarch64-darwin is supported"
else throw "T3 Code is not published for ${stdenv.hostPlatform.system}"
