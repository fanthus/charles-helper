# charles-helper

从 Charles Proxy `.chls` 会话文件中解析 `multipart/form-data` 里 `Content-Type: application/x-gzip` 字段的原始压缩数据，并可选解压为明文。

## macOS 小工具（CharlesParse）

原生 SwiftUI 窗口应用，拖入或打开 `.chls` 即可查看 gzip 解压结果与表单字段，支持复制与导出。

### 依赖

- **Python 3**：系统需已安装 `python3`（推荐 `brew install python`）
- 可选：环境变量 `CHARLES_PARSE_PYTHON` 指向自定义解释器路径

### 构建与运行

```bash
open CharlesParse/CharlesParse.xcodeproj
```

在 Xcode 中选择 **CharlesParse** scheme，按 `Cmd+R` 运行。

命令行构建：

```bash
cd CharlesParse
xcodebuild -scheme CharlesParse -configuration Debug build
```

构建时会将仓库根目录的 `chls_gzip.py` 同步到 App 资源目录。

### 使用

1. 启动 **CHLS 解析**（CharlesParse）
2. 拖入 `.chls` 文件，或点击「打开…」
3. 在「解压文本」「表单字段」间切换查看
4. 底部可：复制文本、复制字段 JSON、导出 gzip 文件

## 命令行

```bash
# 解压后的 URL 编码日志体（默认）
python3 chls_gzip.py /path/to/session.chls

# JSON 输出（供 App 或脚本调用）
python3 chls_gzip.py test.chls --json

# 仅 gzip 压缩字节
python3 chls_gzip.py test.chls --output gzip -o payload.gz

# 解压后原始字节
python3 chls_gzip.py test.chls --output raw -o payload.bin

# 解析为表单字段 JSON
python3 chls_gzip.py test.chls --output fields
```

## Python API

```python
from chls_gzip import extract_from_chls

parts = extract_from_chls("/path/to/session.chls")
part = parts[0]
print(part.gzip_raw)       # multipart 内 gzip 字节
print(part.decompressed)   # gunzip 后
print(part.form_fields)    # 若为 x-www-form-urlencoded
```
