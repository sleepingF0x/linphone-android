# Linphone APK 新手机安装注意事项

本文记录把当前定制版 Linphone APK 安装到一台新 Android 手机时需要检查的事项。

## 1. 安装 APK

先安装当前工程编译出的 debug APK：

```bash
adb install -r app/build/outputs/apk/debug/linphone-android-debug-.apk
```

如果已经安装过旧版本，`-r` 会保留应用数据并覆盖安装。

当前 APK 已包含这些定制行为：

- 来电时主动拉起接听界面。
- 不自动接听。
- 接听界面只显示主叫 username，例如 `1000`，不显示完整 `sip:1000@192.168.1.9`。
- 接听后音频会路由到扬声器。

## 2. 配置 SIP 账号

如果继续使用当前 FreeSWITCH 测试环境：

- 用户名：`1001`
- 密码：`1234`
- 域名/服务器：`192.168.1.9`
- 传输：`TCP`
- Outbound proxy：`sip:192.168.1.9:5060;transport=tcp`

注意：如果旧手机也在线并使用 `1001`，新手机继续使用同一个账号可能导致注册互相覆盖。多台手机同时测试时，建议给新手机分配新账号，例如 `1002`。

## 3. 网络要求

新手机必须能访问 FreeSWITCH 所在机器：

- SIP：`192.168.1.9:5060/tcp`
- RTP：当前 Docker 测试环境开放了 `16000-16020/udp`

最简单的方式是让手机和 Mac/FreeSWITCH 在同一个局域网。

如果服务器 IP 变化，需要同步修改 Linphone 账号配置和 FreeSWITCH 配置。

## 4. Android 权限

至少确认这些权限已允许：

- 麦克风
- 通知
- 电话/通话相关权限
- 联系人，可选，用于联系人名称匹配
- 相机，可选，仅视频通话需要

Android 13 及以上必须允许通知，否则来电通知和前台服务可能异常。

Android 14 及以上还需要允许 full-screen intent，否则来电页面可能无法全屏弹出。

## 5. 后台保活

为了挂断后仍能在后台接收 SIP 来电，需要开启 Linphone 的 keep-alive 前台服务：

```ini
[app]
keep_service_alive=1
auto_start=1
```

系统设置里也要确认：

- 允许通知。
- 允许自启动。
- 允许后台运行。
- 电池策略设为无限制，或忽略电池优化。

注意：不同厂商的后台策略差异很大。即使 APK 内启用了 keep-alive，如果系统禁止后台运行，仍可能收不到来电或无法弹出接听界面。

## 6. 厂商私有权限

这部分不通用。

小米/MIUI、华为/荣耀、OPPO/Realme/OnePlus、vivo/iQOO 等系统都有自己的后台限制。常见需要手动确认的开关包括：

- 自启动
- 后台运行
- 后台弹出界面
- 悬浮窗或显示在其他应用上层
- 电池无限制
- 通知允许

本项目提供了一个 best-effort ADB 脚本：

```bash
scripts/setup-linphone-device.sh
```

脚本会尝试：

- 授予标准运行时权限。
- 设置标准 appops。
- 打开电池优化豁免页面。
- 如果检测到小米/MIUI，设置本次测试验证过的私有 appops：`10008`、`10021` 为 `allow`。
- 打开 MIUI 应用权限页面，方便人工确认。

重要：这个脚本不能保证所有 Android 手机都完全自动配置成功。它是 best-effort 工具，跑完后仍建议人工检查厂商后台权限。

如果连接多台设备，可以指定 adb：

```bash
ADB="adb -s <device_serial>" scripts/setup-linphone-device.sh
```

如果包名变了，可以指定包名：

```bash
PACKAGE="your.package.name" scripts/setup-linphone-device.sh
```

## 7. MIUI 特别说明

这次测试机是 Xiaomi MIX 2 / MIUI 12 / Android 9。现象是：

- SIP 来电正常。
- Linphone 已经执行 `Starting Call activity`。
- 但 MIUI 日志出现 `MIUILOG- Permission Denied Activity`。
- 结果是手机响铃，但接听界面没有被拉到前台。

在这台测试机上，通过下面两个 appops 放行后，接听界面可以稳定弹出：

```bash
adb shell cmd appops set org.linphone 10008 allow
adb shell cmd appops set org.linphone 10021 allow
```

这两个编号是 MIUI 私有 appops，不是标准 Android API。不同 MIUI 版本可能不一样。

## 8. 验证流程

安装和配置完成后，建议按下面顺序验证：

1. 打开 Linphone，确认 SIP 账号已注册。
2. 把 Linphone 退到后台。
3. 用 FreeSWITCH 拨入：

```bash
docker exec linphone-freeswitch-test fs_cli -x 'bgapi originate {absolute_codec_string=PCMU,originate_timeout=45,ignore_early_media=true,origination_caller_id_name=Voice_Test_PCMU,origination_caller_id_number=1000}user/1001@192.168.1.9 &playback(/tmp/linphone-audio/voice_test.wav)'
```

4. 期望结果：

- 接听界面自动拉到前台。
- 不自动接听。
- 接听界面显示主叫 `1000`。
- 手动接听后播放录音。
- 音频正常。

可以用下面命令检查当前前台 Activity：

```bash
adb shell dumpsys window windows | rg -n "mCurrentFocus|mFocusedApp" -C 1
```

正常应看到：

```text
org.linphone/org.linphone.ui.call.CallActivity
```

可以用下面命令检查 FreeSWITCH 通道：

```bash
docker exec linphone-freeswitch-test fs_cli -x 'show channels'
```

测试结束后挂断所有通话：

```bash
docker exec linphone-freeswitch-test fs_cli -x 'hupall NORMAL_CLEARING'
```

## 9. 常见问题

### 来电响铃，但接听页面不弹出

优先检查：

- 通知权限是否允许。
- 后台弹出界面是否允许。
- 自启动和后台运行是否允许。
- MIUI 是否出现 `MIUILOG- Permission Denied Activity`。

可查看日志：

```bash
adb logcat -d -v time | rg -i "Starting Call activity|Permission Denied Activity|MIUILOG|Displayed org.linphone"
```

### 手机收不到来电

优先检查：

- SIP 账号是否注册。
- 手机和 FreeSWITCH 网络是否互通。
- 后台保活服务是否运行。
- 系统是否限制后台网络或电池。

查看注册：

```bash
docker exec linphone-freeswitch-test fs_cli -x 'sofia status profile internal reg'
```

### 接听界面显示完整 SIP 地址

当前定制版已改为显示 username。若仍显示完整地址，确认安装的是最新 APK，并重新安装：

```bash
adb install -r app/build/outputs/apk/debug/linphone-android-debug-.apk
```
