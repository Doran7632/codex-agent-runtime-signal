# codex-agent-runtime-signal Source Upload Pack

这个目录是可上传到 GitHub 仓库的源码副本，可以作为仓库根目录使用。

已包含：

- `Package.swift` / `Package.resolved`
- `Sources/`
- `Tests/`
- `script/` 和 `scripts/`
- `.github/workflows/`
- `.codex/config.toml` 和 `.codex/environments/`
- `docs/`
- `README.md`、`LICENSE`、`NOTICE`、`ASSET_LICENSES.md`、`TRADEMARKS.md`、`CHANGELOG.md`、`VERSION`

已排除：

- `.git/`
- `.build/`
- `.swiftpm/`
- `dist/`
- `DerivedData/`
- `.DS_Store`
- `task_plan.md`、`progress.md`、`findings.md`
- Python cache / Xcode user data

基础检查：

```bash
swift package describe --type json
bash -n script/*.sh scripts/*
```

如果要上传 release 安装包，请使用上一级目录中的 DMG/ZIP 上传包，不要把 `dist/` 放进源码仓库。
