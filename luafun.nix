{ luajit-pro
, fetchFromGitHub
}:
luajit-pro.pkgs.buildLuaPackage {
  pname = "luafun";
  version = "latest";
  src = fetchFromGitHub {
    owner = "luafun";
    repo = "luafun";
    rev = "cc118e135b8dc3c8b5a2292394b2397506ff0e22";
    hash = "sha256-cbFgZpKqbbSffrKIrDhQ0GJr0dMAZ+K5U2SVEi6GI/E=";
  };

  dontBuild = true;
  installPhase = ''
    destdir=$out/share/lua/${luajit-pro.luaversion}
    mkdir -p $destdir
    cp fun.lua $destdir/
  '';
}

