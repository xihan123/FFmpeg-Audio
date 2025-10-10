# 音频精简版 FFmpeg 构建

本仓库提供一套用于构建“仅音频”功能的精简版 FFmpeg 的自动化流程。GitHub Actions 会下载官方源码、根据预设配置裁剪掉所有视频相关的模块，仅保留常见音频编解码、复用及基础滤镜能力，并自动为 Linux、macOS、Windows 生成可用二进制包。

## 特性概览

- ✅ 保留 `ffmpeg`、`ffprobe` 两个命令行工具，方便批量音频转码与探测
- ✅ 启用常见音频编解码（AAC、AC3、FLAC、MP3、Opus、Vorbis、PCM 等）
- ✅ 支持常用音频封装（WAV、MP3、Ogg、Matroska、ADTS 等）
- ✅ 提供基础音频滤镜（重采样、音量、声道映射、速度调整、响度标准化等）
- 🚫 关闭所有视频链路（解码、编码、滤镜、缩放、设备等），缩短构建时间并减小体积

## GitHub Actions 工作流

工作流位于 `.github/workflows/audio-only.yml`，在以下场景触发：

- 推送到 `main` 分支（使用默认版本快速回归）
- 手动 `workflow_dispatch`（可指定任意 FFmpeg 版本）
- 每日定时检查 FFmpeg 官方仓库最新 tag，发现新版本时自动构建并发布
-（可选）通过 `repository_dispatch` 事件外部触发，载荷支持 `version`

主要步骤：

1. `prepare` 任务解析目标 FFmpeg 版本，避免重复构建已发布版本
2. `build` 任务以矩阵方式在 `ubuntu-latest`、`macos-latest`、`windows-latest` 上调用 `scripts/build_ffmpeg_audio.sh`
3. `release` 任务聚合各平台产物并更新/创建同名 Git 标签与 GitHub Release

> **产物命名**：`ffmpeg-audio-only-<版本>-<平台>.tar.gz|zip` 与对应 `.sha256`

构建脚本会依次尝试 `ffmpeg.org`、`download.ffmpeg.org` 与 GitHub 镜像下载源码，并开启 `curl` 自动重试，减少临时网络抖动带来的失败率。

### 手动运行

在 GitHub 仓库界面选择 **Actions → Build FFmpeg Audio Only → Run workflow**，可自定义 FFmpeg 版本号。

## 本地构建（可选）

脚本依据 `uname -s` 自动识别平台并设置打包格式：

- **Linux**：需要 `build-essential`, `pkg-config`, `nasm`, `yasm`, `curl`, `zip`
- **macOS**：推荐使用 Homebrew 安装 `pkg-config`, `nasm`, `yasm`, `gnu-tar`
- **Windows**：建议在 MSYS2 Mingw64 环境运行，确保安装 `base-devel`, `zip`, `curl`, `mingw-w64-x86_64-{gcc,pkg-config,nasm,yasm}`

```bash
bash scripts/build_ffmpeg_audio.sh
```

构建完成后，可在 `artifacts/` 目录找到压缩包及 SHA256 校验文件。

## 配置要点

`build_ffmpeg_audio.sh` 中使用了如下 `./configure` 选项：

- `--disable-everything`：关闭所有解码器/编码器/复用器等，再按需启用音频组件
- `--enable-ffmpeg --enable-ffprobe`：仅保留核心 CLI 工具，仍可使用 `ffmpeg -h`、`ffprobe -h` 获取帮助信息
- `--enable-swresample`：保留音频重采样能力
- `--enable-filter=aformat,anull,aresample,asetpts,atempo,channelmap,channelsplit,loudnorm,pan,volume`
- `--enable-demuxer` / `--enable-muxer`：白名单覆盖常见音频容器（WAV、OGG、Matroska、MP4/M4A、ADTS、AIFF 等）
- `--enable-decoder` / `--enable-encoder`：启用 AAC、AC3、FLAC、PCM 系列等音频编解码器
- 关闭 `avdevice`, `swscale`, `network` 等与视频或网络相关的模块

可根据实际需求调整脚本中的启用/禁用列表，然后重新触发工作流。

### 结果验证

构建完成后，可通过以下命令确认核心功能：

```bash
./ffmpeg -hide_banner -codecs | grep -E "(A\.|DEA)"
./ffmpeg -hide_banner -formats | grep -E "( D | E )"
./ffmpeg -hide_banner -filters | grep audio
```

将一个 WAV 转码为 AAC M4A 并回放，确保读写链路正常：

```bash
./ffmpeg -hide_banner -i sample.wav -c:a aac -b:a 192k output.m4a
./ffprobe -hide_banner output.m4a
```

## 后续改进建议

- 根据业务场景补充更丰富的音频滤镜或外部库支持（如 `libmp3lame`, `libopus` 等）
- 增加 arm64 目标（macOS ARM / Linux ARM）
- 与 Release automation 集成，自动同步到制品仓库或 CDN
