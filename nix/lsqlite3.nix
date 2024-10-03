{ pkgs, lib, luajit, fetchzip }:
let 
  buildLuarocksPackage = luajit.pkgs.buildLuarocksPackage;
in buildLuarocksPackage {
  pname = "lsqlite3";
  version = "0.9.6-1";

  src = fetchzip {
    url = "http://lua.sqlite.org/index.cgi/zip/lsqlite3_v096.zip";
    hash = "sha256-Mq409A3X9/OS7IPI/KlULR6ZihqnYKk/mS/W/2yrGBg=";
  };

  propagatedBuildInputs = with pkgs; [
    sqlite.dev
  ];
}