{
  buildLuarocksPackage,
  fetchzip,
  complete ? false,
  # There is a lua.sqlite (written in lua) and a nixpkgs.sqlite (written in C).
  # To distinguish then, I name nixpkgs.sqlite as nixpkgs_sqlite.
  nixpkgs_sqlite,
  nixpkgs_glibc ? null,
}: buildLuarocksPackage {
  pname = if complete then "lsqlite3complete" else "lsqlite3";
  version = "0.9.6-1";
  src = fetchzip {
    url = "https://github.com/cyril0124/lsqlite-src/raw/a90275237a4b242adbaa2946901682edf79a4b86/lsqlite3_v096.zip";
    sha256 = "060qmdngzmigk4zsjq573a59j7idajlzrj43xj9g7xyp1ps39bij";
  };
  propagatedBuildInputs = [
    nixpkgs_sqlite.dev
  ];
  buildInputs = if complete then [nixpkgs_glibc] else [];
}

