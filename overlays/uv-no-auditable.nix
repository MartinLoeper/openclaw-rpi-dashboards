final: prev: {
  uv = prev.uv.overrideAttrs (old: {
    nativeBuildInputs = builtins.filter
      (dep: !(dep ? pname && dep.pname == "cargo-auditable-cargo-wrapper"))
      (old.nativeBuildInputs or []);
  });
}
