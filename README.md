# Newifi 3 D2 — 广东电信 IPTV 内网融合固件

基于 **ImmortalWrt `openwrt-24.10`**（`ramips/mt7621` / `d-team_newifi-d2`），面向
**主路由拨号上网 + Newifi D2 拨号 IPTV 做旁路由** 的场景，内置：

| 能力 | 实现 |
|---|---|
| 直播组播转单播 | **rtp2httpd**（5140，FCC 快切 + 内置网页播放器） |
| 时移 / 回看 | 取 `TimeShiftURL` + `playseek` 占位符，与直播**合并成同一条** `catchup-source` |
| 鉴权 | `gdiptv-update` 重放 `ValidAuthenticationHWCTC.jsp`，自动拿 Cookie 拉频道列表 |
| 频道列表 | 套用 `channels.m3u` 模板（199 频道）决定**分组与排序**，直播+回看合一输出 |
| 节目单 | litiande03/epg 每日输出 `pl.xml.gz`，自动解压缓存到 `/iptv/epg.xml` |
| 抓包 | `gdiptv-sniff` 一条命令抓机顶盒鉴权包并自动写配置 |
| 联动 | 生成后自动把列表地址写入 `rtp2httpd.external_m3u`，回看由它转 HTTP |

---

## 一、网络拓扑（默认预置）

```
                      ┌──────────┐
   宽带 PPPoE 拨号 ────┤  主路由   ├──── LAN 192.168.1.0/24 ──┐
                      └──────────┘                           │
   ┌──────────┐                                              │
   │  光猫     │  ITV 口 ────────────────┐                    │
   └──────────┘                          │                    │
                                         ▼                    ▼
                                 ┌────────────────────────────────┐
                                 │   Newifi 3 D2（本固件）          │
                                 │   LAN4  = IPTV (PPPoE)          │
                                 │   WAN   = DHCP 上联主路由        │
                                 │   LAN1-3 + WiFi = 192.168.2.1/24│
                                 └────────────────────────────────┘
                                         │
                                   电视机 / 机顶盒 / 酷9
```

- **WAN 口** 接主路由 LAN → DHCP 拿到 192.168.1.x，负责上网（节目单、酷9、其他 App）
- **LAN4** 接光猫 ITV 口 → PPPoE 拨 IPTV 专网
- **LAN1-3 + WiFi** 是 `192.168.2.0/24`，电视/机顶盒接这里

> 如果你的 IPTV 是**单线复用**（只有一根线入户 + VLAN），把 `/etc/config/network`
> 里 `iptv` 的 `option device` 从 `lan4` 改成 `wan.45`（45 换成实际 VLAN ID），
> 并把 WAN 口接那根线即可，其余不用动。

---

## 二、编译固件

### GitHub Actions（推荐）

1. 把本目录推到 GitHub（例如 `你的用户名/Newifi-D2-IPTV-OpenWrt`）
2. `Actions` → `Build Newifi D2 IPTV Firmware` → `Run workflow`
3. 约 1.5–3 小时后，在 Release / Artifacts 里下载
   `immortalwrt-*-ramips-mt7621-d-team_newifi-d2-squashfs-sysupgrade.bin`

> **注意**：Windows 上 git 可能丢掉可执行位。首次 push 前执行：
> ```
> git update-index --chmod=+x files/usr/bin/gdiptv-update files/usr/bin/gdiptv-sniff files/etc/hotplug.d/iface/30-gdiptv files/etc/uci-defaults/99-gd-iptv.sh
> ```
> （即使丢了也没关系，`uci-defaults` 首次启动会补 `chmod +x`。）

### 本地编译（Ubuntu/Debian）

```bash
git clone -b openwrt-24.10 https://github.com/immortalwrt/immortalwrt.git
cd immortalwrt
./scripts/feeds update -a && ./scripts/feeds install -a
bash ../scripts/diy-part2.sh      # 加入 rtp2httpd
cp ../configs/newifi-d2-iptv.config .config
cp -r ../files files
make defconfig && make -j$(nproc)
```

---

## 三、刷机

Newifi D2 建议先刷 **Breed**（不死 boot）：

1. 断电 → 按住 Reset（电源口旁边）→ 插电 → 10 秒后松开
2. 电脑设 `192.168.1.x`，浏览器打开 `192.168.1.1` 进 Breed
3. `固件更新` → 勾选 `常规固件` → 闪存布局选 **`公版(0x50000)`**
4. 上传 `*-squashfs-sysupgrade.bin`，自动重启
5. 之后升级直接在 LuCI 里 `系统 → 备份/升级` 刷 sysupgrade 即可

> 首次启动约 1–2 分钟。默认无密码，LuCI 地址 `http://192.168.2.1`。

---

## 四、配置（按顺序做）

### 1. 填 IPTV 拨号账号

编辑 `/etc/config/network`（或 LuCI → 网络 → 接口 → IPTV）：

```
config interface 'iptv'
	option device 'lan4'
	option proto 'pppoe'
	option username '你的IPTV账号@iptv.gd'
	option password '你的密码'
	# 电信若绑定了机顶盒 MAC，取消下行注释并填机顶盒 MAC
	# option macaddr 'AA:BB:CC:DD:EE:FF'
```

保存后 `ifup iptv`，看到 `pppoe-iptv` 拿到 `10.x` 或 `100.x` 地址就说明通了。

> 拿不到账号？进机顶盒设置里看，或打 10000 要；也可以先用 `gdiptv-sniff`
> 抓到 `NetUserID=xxx%40iptv.gd`，`xxx@iptv.gd` 往往就是拨号账号。

### 2. 抓鉴权串

```bash
gdiptv-sniff          # 默认抓 br-lan 180 秒
```

脚本提示后**立刻重启机顶盒**（断电再上电，必须让它在窗口内重新发起鉴权）。
抓到后会自动写入 `gdiptv.main.auth_body`。

失败的话按脚本提示把 `/tmp/iptv-*.pcap` 拷到电脑用 Wireshark 打开：
过滤 `http` → 搜 `ValidAuthenticationHWCTC` → 右键 `HTML Form URL Encoded`
→ `复制 → As UTF-8 Text`，然后：

```bash
uci set gdiptv.main.auth_body='UserID=xxx&Lang=&SupportHD=1&NetUserID=...&userToken=...&VIP='
uci commit gdiptv
```

### 3. 生成列表

```bash
gdiptv-update -f
```

浏览器打开 **`http://192.168.1.2/iptv/`** 看结果：

| 文件 | 用途 |
|---|---|
| `playlist.m3u8` | **主列表**：直播 + 回看合一，已按模板分好组排好序 |
| `iptv.txt` | 酷9 / DIYP 文本源格式 |
| `epg.xml` | xmltv 节目单 |

直播走 rtp2httpd 组播转单播；回看写在每条的 `catchup-source` 里，
播放器按 EPG 选"回看"时会自动拼接时间参数。

### 4. 播放器配置

- **酷9 / DIYP / TVBox**：订阅 `http://192.168.1.2/iptv/iptv.txt`，
  EPG 填 `http://192.168.1.2/iptv/epg.xml`
- **TiviMate / APTV / mytv-android**：订阅 `http://192.168.1.2/iptv/playlist.m3u8`
  （这两个能识别 `catchup-source`，回看直接可用）
- **rtp2httpd 自带播放器**：`http://192.168.1.2:5140/player`
- **rtp2httpd 转好的列表**：`http://192.168.1.2:5140/playlist.m3u`
- **状态面板**：`http://192.168.1.2:5140/status`

> `gdiptv-update` 每次跑完会把 `http://127.0.0.1/iptv/playlist.m3u8`
> 自动写进 `rtp2httpd.external_m3u`。rtp2httpd 会定时拉取它并把里面的
> `rtsp://` 回看源转成 HTTP，所以用它自己的 `/player` 或 `/playlist.m3u`
> 看回看最省事，电视/手机不需要能直连 IPTV 专网。

### 5. 调整分组与排序

分组和频道顺序由模板 **`/etc/gdiptv/channels.m3u`** 决定，直接编辑它即可，
改完跑一次 `gdiptv-update -f` 生效。

```m3u
#EXTINF:-1 tvg-id="广东珠江" tvg-name="广东珠江" group-title="广东",广东珠江
#EXTINF:-1 tvg-id="广东新闻" tvg-name="广东新闻" group-title="广东",广东新闻
```

- **调顺序**：上下移动这几行
- **换分组**：改 `group-title` 的值
- **改 EPG 名**：改 `tvg-id`（播放器靠它匹配节目单）
- **加台**：追加一行就行，名字跟平台返回的对上即可（`gdiptv-update -l` 可查）

模板自带 199 个频道，分组顺序为 **广东 / 央视 / 卫视 / 体育 / 儿童 / 其他**。

几个细节：

- 模板里没收录的新频道**不会丢**，会按内置规则自动归类，排在对应分组末尾
- 同一频道在模板里可以出现多次（分到不同组），例如广东体育同属"广东"和"体育"、
  CCTV-5 同属"央视"和"体育"，这样"体育"组里能直接找到它
- 模板里收录的频道会**豁免**垃圾过滤。电信常把可用的高清源标成
  `CCTV5＋体育高清-测试` 这种名字，不豁免的话会被当成测试流丢掉；
  显示名仍会用模板里你写的干净名字
- 同名多路（高清/超清/4K）自动合并，只留清晰度最高的一路

---

## 五、回看 / 时移

回看地址取自频道列表里的 **`TimeShiftURL`** 属性（不是 `ChannelURL` 里的 rtsp，
那个不能时移），拼上 `playseek` 占位符后写进 `catchup-source`：

```
rtsp://125.88.52.199/PLTV/...smil?accountinfo=...&playseek=${(b)yyyyMMddHHmmss}-${(e)yyyyMMddHHmmss}
```

播放器选"回看"时会把 `${(b)...}` / `${(e)...}` 换成实际的起止时间
（`YYYYMMDDHHMMSS`，北京时间）。

如果你的播放器回看时间点整体差 8 小时，改 `gdiptv.main.catchup_tz_offset`
为 `28800` 或 `-28800` 即可。

不支持 RTSP 的播放器，把 `gdiptv.main.catchup_via_proxy` 设为 `1`，
`catchup-source` 会直接写成 rtp2httpd 的反代地址：

```
http://192.168.1.2:5140/rtsp/125.88.52.199:554/PLTV/....smil?accountinfo=...&playseek=...
```

注意：本固件默认 `catchup_via_proxy=0`（原始 rtsp），因为 rtp2httpd 通过
`external_m3u` 会自动完成这层转换，写两遍反而可能重复包装。

> 时移地址有效期官方标 30 天。`gdiptv-update` 默认 7 天重新鉴权一次，
> cron 里还配了每周一强制刷新，基本不会断。

---

## 六、节目单

默认源 `https://epg.v1.mk/fy.xml`（肥羊 EPG，含央卫 + 广东地方台），
每天 04:10 自动更新，缓存在 `/www/iptv/epg.xml`，**离线也能读**。

换源：

```bash
uci set gdiptv.main.epg_url='https://你的源/epg.xml'
uci commit gdiptv
gdiptv-update -f
```

---

## 七、关键配置说明

### 策略路由（`/etc/hotplug.d/iface/30-gdiptv`）

IPTV 拨号成功后自动下发（网段可在 `/etc/config/gdiptv` 的 `iptv_subnets` 改）：

```
183.59.0.0/16   EPG / RTSP 单播服务器（广东电信）
125.88.0.0/16
59.37.0.0/16
202.105.0.0/16
113.108.0.0/16
10.0.0.0/8      IPTV 内网
224.0.0.0/4     组播
```

同时会：
- 关闭 `rp_filter`（否则组播和非对称回程会被丢）
- 把 `iptv.gd.cn` 的解析交给 IPTV 侧 DNS
- 重启 rtp2httpd 绑定新的 `pppoe-iptv`

### dnsmasq

`rebind_protection` 必须为 `0`——`iptv.gd.cn` 会解析到 `10.x` 私网地址，
开着会被当成 DNS rebinding 直接丢包，鉴权必失败。

### 防火墙

`flow offload` 必须关闭（已预置 `option flow_offloading '0'`），
它会绕过组播/IPTV 的转发路径，导致直播打不开。

---

## 八、排障

| 现象 | 排查 |
|---|---|
| IPTV 拨不上号 | `logread -e pppd`；确认 LAN4 接的是光猫 ITV 口；试填 `macaddr` |
| 拨上了但鉴权失败 | `logread -e gdiptv`；看 `gdiptv-update -f` 输出；确认 `183.59` 路由在不在：`ip route \| grep 183.59` |
| 频道列表 0 条 | `gdiptv-update -f` 后看 `/tmp/gdiptv/list.raw`；可能 auth_body 过期，重新 `gdiptv-sniff` |
| 某些台没出来 | `gdiptv-update -l` 对比平台真实频道名，补进 `/etc/gdiptv/channels.m3u` 模板（名字对不上时会自动归类到末尾，不会丢） |
| 频道顺序不对 | 改 `/etc/gdiptv/channels.m3u` 的行顺序，再 `gdiptv-update -f` |
| 直播能看，回看不行 | 回看源是 `TimeShiftURL`（`125.88.x.x`），确认该网段已走 IPTV 出口；用 rtp2httpd 的 `/player` 看能否回看，排除播放器不支持 rtsp 的问题 |
| 回看时间差 8 小时 | 设 `gdiptv.main.catchup_tz_offset` 为 `28800` 或 `-28800` |
| 播放卡顿 / 花屏 | 把 `/etc/sysctl.d/30-iptv.conf` 里 `force_igmp_version=2` 打开；或调大 `udp_rcvbuf_size` |
| 换台慢 | rtp2httpd 的 FCC 需要本地 FCC 服务器地址，抓包找 `ChannelFCCIP/ChannelFCCPort`，填到 LuCI → 服务 → rtp2httpd |
| 电视能看 IPTV 但上不了网 | 检查 WAN 口是否接主路由 LAN、wan 接口是否 DHCP 拿到地址 |
| 节目单下不动 | EPG 走的是 WAN（外网），不是 IPTV 专网；先确认 `curl -I https://epg.v1.mk/fy.xml` 通 |

常用命令：

```bash
gdiptv-update -f        # 强制重新鉴权 + 重拉列表
gdiptv-update -l        # 列出平台全部频道 ID
gdiptv-sniff            # 抓鉴权包
logread -e gdiptv       # 看更新日志
ip route | grep -E '183.59|224.0'   # 确认策略路由
```

---

## 九、目录结构

```
configs/newifi-d2-iptv.config       # OpenWrt .config
scripts/diy-part1.sh                # 目标探测
scripts/diy-part2.sh                # 注入 rtp2httpd
files/etc/config/network            # WAN=DHCP / LAN4=IPTV PPPoE
files/etc/config/firewall           # iptv 区 + 组播放行 + 关闭 offload
files/etc/config/dhcp               # dnsmasq（关闭 rebind_protection）
files/etc/config/gdiptv             # 鉴权/回看/模板/EPG/网段
files/etc/config/rtp2httpd          # 5140，上游 pppoe-iptv + external_m3u
files/etc/hotplug.d/iface/30-gdiptv # 策略路由 + DNS 分流
files/etc/uci-defaults/99-gd-iptv.sh
files/usr/bin/gdiptv-update         # 鉴权 + 列表(直播+回看) + 节目单
files/usr/bin/gdiptv-sniff          # 抓包取鉴权
files/etc/gdiptv/channels.m3u       # 频道模板：分组 / 排序 / EPG 名（199 条）
files/etc/gdiptv/logo.csv           # 台标映射（可选）
files/etc/crontabs/root             # 每日 04:10 自动更新
```

---

## 十、参考

- 恩山原帖（GD 电信 RTSP 抓取 + 酷9/Redstar）：<https://www.right.com.cn/forum/thread-8413871-1-1.html>
- GD 电信自助鉴权 + 播放列表：<https://mozz.ie/posts/gdct-iptv-auth-and-fetch-playlist/>
- 导出 m3u8：<https://mozz.ie/posts/extracting-iptv-live-streams/>
- rtp2httpd：<https://github.com/stackia/rtp2httpd>（URL 格式 / 时移 / M3U 集成见 <https://rtp2httpd.com>）
- litiande03 EPG：<https://github.com/litiande03/epg>

> 频道列表里的 RTSP 地址带有你机顶盒的鉴权信息，**不要外传**。
