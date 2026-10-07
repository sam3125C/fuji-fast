# fuji-fast

富士照片处理的小工具集。

## tag

同步照片配套文件的 Finder 标签。目前支持把同名 RAF 文件的标签标记为与 JPG 一致。

### 用法

```
tag <动作> <目录>
```

- 动作：目前仅支持 `jpg2raf`
- 目录：处理范围，例如 `./` 表示只处理当前文件夹（不递归子目录）

### 示例

```
tag jpg2raf ./
tag jpg2raf ~/Pictures/101_FUJI
```

### 行为说明

- 大小写不敏感（`.jpg/.JPG`、`.raf/.RAF` 均可识别）
- JPG 无标签时，会同步清除同名 RAF 的标签
- 找不到同名 RAF 时跳过
- 仅支持 macOS，依赖系统自带的 `xattr`

### 安装

```
ln -s "$(pwd)/tag" /usr/local/bin/tag
```

安装后在任意目录执行 `tag jpg2raf ./` 即可。
