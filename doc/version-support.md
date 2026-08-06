# 双版本维护

`aho4cj` 使用同一套源码支持仓颉 1.0.5 LTS 与 1.1.3 STS。`cjpm.toml` 中的
`cjc-version = "1.0.5"` 表示最低支持版本，不限制 1.1.3 使用该模块。

## 分支

| 分支 | 目标工具链 | 用途 |
|---|---|---|
| `main` | 1.0.5 LTS 与 1.1.3 STS | 日常开发与下一版本基线 |
| `aho4cj_lt_1.0.5` | 1.0.5 LTS | 1.0.5 LTS 发布与维护线 |
| `aho4cj_st_1.1.3` | 1.1.3 STS | 1.1.3 STS 发布与维护线 |

功能改动先进入 `main`，并同时通过两个版本的测试。发布时从 `main` 更新对应版本分支；版本分支只接受该工具链所需的
发布调整和缺陷修复。STS 专用改动成熟后应合并回 `main`，避免两条源码线长期分叉。

## 本地验证

两套 SDK 应安装在不同目录，并在独立终端中分别加载各自的 `envsetup.sh`。不要把两套环境同时加入一个终端。

在 1.0.5 LTS 环境中运行：

```bash
cjpm build --target-dir target-1.0.5
cjpm test --target-dir target-1.0.5
```

在 1.1.3 STS 环境中运行：

```bash
cjpm build --target-dir target-1.1.3
cjpm test --target-dir target-1.1.3
```

两个版本必须使用不同的目标目录，避免增量缓存格式不兼容。GitHub Actions 会对 `main` 和两条版本分支执行相同的
双版本测试矩阵。

## 中心仓制品

仓颉 1.0.5 自带的 `cjpm` 不提供 `bundle` 和 `publish` 命令。发布兼容 1.0.5 的制品时，先用 1.0.5 完成构建与测试，
再用 1.1.3 的 `cjpm bundle` 和 `cjpm publish` 制作并上传制品；`cjpm.toml` 继续声明最低版本 1.0.5。

同一模块版本不能重复上传。只有当 STS 分支引入无法在 1.0.5 编译的代码时，才提高模块版本，并在该分支把
`cjc-version` 改为 `1.1.3` 后发布新的 STS 制品。当前 `0.1.0` 使用同一套源码兼容两个工具链，无需重复发布。
