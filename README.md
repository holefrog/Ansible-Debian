# X230 Web3 Kiosk — 部署手册
> Debian 13 (Trixie) + Cage (Wayland Kiosk) + Brave Browser  
> 版本：v4 | 用途：Polymarket 交易终端 | 硬件：ThinkPad X230 / 16GB RAM

---

## 概览

```
空白硬盘
  └─► 第一阶段：手动安装 Debian 13（本文档指导）
        └─► 第二阶段：主力机执行 Ansible Playbook（自动完成所有配置）
              └─► 完成：开机自动进入 Brave 全屏 Kiosk
```

### 设计理念：极简与安全 (Minimal Attack Surface)

作为一个专用的 Web3 交易终端，系统的**安全性和可靠性**是最高优先级。因此，本项目的 Ansible Playbook 在设计上采用了非常规的极简策略：
- **拒绝安装 Ansible 依赖（如 `python3-apt` 甚至完整的 Python 环境）**。标准的 Ansible 模块（如 `apt`、`get_url`）要求目标机具备相对庞大的 Python 运行时和管理库。
- **全局使用 `raw` 模块**。通过 `raw` 模块直接通过 SSH 下发底层的 Shell 指令，确保系统只安装运行 Wayland (Cage) 和 Brave 浏览器所需的**绝对最少依赖**。从根本上减小系统体积，降低多余软件包带来的潜在安全漏洞和维护风险。

目录结构：

```
Ansible-Debian/
├── README.md
├── inventory.ini
├── group_vars/
│   └── all.yml
├── templates/
│   └── wifi.nmconnection.j2        # NetworkManager Wi-Fi 配置模板
├── site.yml                        # 主 playbook
├── key/                            # SSH 密钥（不提交 git）
│   ├── debian                      # 私钥
│   └── debian.pub                  # 公钥
├── files/
│   ├── systemd/
│   │   ├── autologin.conf          # TTY1 自动登录
│   │   └── cage-kiosk.service      # Kiosk 用户服务
│   ├── brave/
│   │   ├── brave-kiosk.sh          # Brave 启动脚本
│   │   └── initial_preferences     # Brave 初始配置（禁用 Web3 钱包）
│   ├── nftables/
│   │   └── nftables.conf           # 防火墙规则
│   └── networkmanager/
│       └── 99-autoconnect.conf     # NM 自动重连策略
└── post_update_check.sh            # Brave 更新后手动验证脚本
```

> `key/` 目录包含私钥，不应提交 git。如果项目有 `.gitignore`，添加 `key/` 到其中。

---

## 第一阶段：制作安装 U 盘并安装系统

### 1.1 下载 ISO

**当前版本：Debian 13.5（2026-05-16 发布）**

```bash
# 下载 netinst ISO（约 650MB）
curl -LO https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.5.0-amd64-netinst.iso

# 下载校验文件
curl -LO https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/SHA512SUMS

# 验证（输出中应包含 OK）
sha512sum --ignore-missing -c SHA512SUMS
```

如果官方源下载慢，可替换为就近镜像：
`https://mirror.csclub.uwaterloo.ca/debian-cd/current/amd64/iso-cd/`

---

### 1.2 写入 U 盘

准备：U 盘容量 ≥ 2GB，写入后数据全部清除。

```bash
# 找到 U 盘设备号（注意区分，写错会覆盖其他磁盘）
lsblk

# 写入（替换 sdX 为实际设备，例如 sdb，不加分区号）
sudo dd if=debian-13.5.0-amd64-netinst.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

---

### 1.3 BIOS 设置（X230 专项）

开机按 `F1` 进入 BIOS：

| 选项 | 设置 |
|------|------|
| Security → Secure Boot | Disabled |
| Startup → Boot Mode | Legacy Support |
| Startup → Boot Order | USB HDD 排第一 |

保存退出（F10）。

---

### 1.4 Debian 安装流程

插入 U 盘，开机进入安装界面。按以下选择，其余全部回车默认：

| 步骤 | 选择 |
|------|------|
| 安装类型 | Install（不选 Graphical install） |
| Language | English |
| Location | Canada |
| Locale | en_US.UTF-8 |
| Keyboard | American English |
| Hostname | ThinkPad-X230 |
| Domain | 留空，直接回车 |
| Root password | 设置强密码并记录 |
| 普通用户名 | kiosk |
| 普通用户密码 | 设置并记录 |
| 时区 | Pacific |

安装过程中会提示配置网络，选择 Wi-Fi 接口，输入 SSID 和密码完成连接。

**磁盘分区：**
- Guided - use entire disk
- 选择唯一磁盘（通常 `/dev/sda`）
- All files in one partition
- 确认写入：Yes

**软件选择界面（tasksel）：**

基础系统安装完毕后自动弹出，用空格键取消所有勾选，只保留：
- `[*] standard system utilities`
- `[*] SSH server`

> `SSH server` 必须勾选，后续 Ansible 通过 SSH 接管依赖它。

**安装 GRUB：**

安装程序列出可用磁盘，X230 只有一块时直接选择它（通常显示为 `/dev/sda`）。

完成后拔出 U 盘，重启。

---

### 1.5 首次启动

系统重启后出现命令行登录提示，用 `root` 登录。

**确认网络已连接：**

安装过程中 Wi-Fi 已配置，重启后应自动恢复：

```bash
ip -br addr
```

如果没有显示 IP，重启一次通常可以恢复：

```bash
reboot
```

**安装 sudo 并将 kiosk 加入 sudo 组：**

```bash
apt-get install -y sudo
usermod -aG sudo kiosk
```

**记录 MAC 地址，在路由器绑定静态 IP：**

```bash
ip link
# 找到 Wi-Fi 接口下 link/ether 后面的值，例如：
# link/ether aa:bb:cc:dd:ee:ff
```

登录路由器管理界面，找到 DHCP 静态绑定（Static DHCP / Address Reservation），
将上述 MAC 地址绑定到 `192.168.50.230`，保存后重启 X230：

```bash
reboot
```

重启后确认 IP 已变为 `192.168.50.230`：

```bash
ip -br addr
```

确认后即可从主力机 SSH 接入。

---

## 第二阶段：主力机执行 Ansible Playbook

### 2.1 主力机环境准备

```bash
# 安装 Ansible（如果尚未安装）
pip install ansible
# 或
sudo apt install ansible
```

### 2.2 配置 SSH 免密登录

以下命令在主力机的 `Ansible-Debian/` 目录下执行：

```bash
cd Ansible-Debian/

# 创建 key/ 子目录并生成密钥对
mkdir -p key
ssh-keygen -t ed25519 -f key/debian -N ""

# 推送公钥到 X230（会提示输入 kiosk 用户密码）
ssh-copy-id -i key/debian.pub kiosk@192.168.50.230
```

### 2.3 配置 kiosk 免密 sudo（playbook 执行期间需要）

SSH 进入 X230，以 root 执行（会提示输入 root 密码）：

```bash
ssh -i key/debian kiosk@192.168.50.230
su -
echo "kiosk ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/kiosk-nopasswd
chmod 440 /etc/sudoers.d/kiosk-nopasswd
exit
exit
```

> 部署完成后可删除此文件（`rm /etc/sudoers.d/kiosk-nopasswd`）以恢复正常权限。

### 2.4 执行 Playbook

```bash
cd Ansible-Debian/

# 先测试连通性
ansible -i inventory.ini all -m raw -a "echo ok" --become --private-key=key/debian

# 执行完整部署
ansible-playbook -i inventory.ini site.yml --become --private-key=key/debian
```

执行时间约 10-20 分钟（取决于网速）。

### 2.5 部署完成与启动

Playbook 前面步骤全部成功后，会自动重启 X230。重启完成后，`cage-kiosk.service` 会自动启动，X230 的屏幕应会进入 Brave 全屏 Kiosk。

同时，GRUB 会被配置为开机不等待菜单，重启后直接进入默认 Debian 系统。

因此，**不需要手动执行 reboot**。

> Kiosk 界面中，直接按下 MetaMask 的默认唤醒快捷键：`Alt + Shift + M`。用来设置 MetaMask，设置钱包定时退出
> 如果你在 MetaMask 中导入了钱包，请务必在 MetaMask 设置里启用：
> “关闭浏览器时锁定”（Lock on browser close）

**避免开机后不登录钱包，直接显示持仓**
 Alt+F4：手动让 Brave 结束，触发退出清理。


**如果没有正常进入：**

按 `Ctrl+Alt+F3` 切换到 TTY3，用 `kiosk` 用户登录：

```bash
systemctl status cage-kiosk.service
journalctl -u cage-kiosk.service -n 50
```

---

## 日常维护

### Wi-Fi 断线重连

NetworkManager 已配置无限自动重连，正常情况下无需干预。
如需手动操作，切换到 TTY（Ctrl+Alt+F3），用 kiosk 登录：

```bash
nmcli device wifi list
nmcli connection up "你的SSID"
```

### SSID 变化后重新部署

如果家里或现场 Wi-Fi 的 SSID / 密码变化，先把 X230 接上有线网络，确保主力机仍能通过 `inventory.ini` 里的地址 SSH 到 X230。

在主力机的 `Ansible-Debian/` 目录中修改 `group_vars/all.yml`：

```yaml
wifi_ssid: "新的SSID"
wifi_password: "新的WiFi密码"
# wifi_interface: "wlp3s0"  # 选填；默认就是 wlp3s0
```

然后重新执行网络部署：

```bash
ansible-playbook -i inventory.ini site.yml --become --private-key=key/debian --tags network
```

如果当前 playbook 没有使用 tag，也可以直接重新执行完整部署：

```bash
ansible-playbook -i inventory.ini site.yml --become --private-key=key/debian
```

部署时会先检查 X230 当前连接的 Wi-Fi SSID：只有当前 SSID 和 `group_vars/all.yml` 里的 `wifi_ssid` 不一致时，才会重新写入 Wi-Fi profile、重载 NetworkManager 并尝试连接新的 SSID。如果已经连在同一个 SSID 上，网络配置不会被重新设置。

确认方式：

```bash
ssh -i key/debian kiosk@192.168.50.230
nmcli connection show
nmcli device status
```

如果部署时出现 `No suitable device found`，通常表示当前无线网卡不可用、被禁用，或旧配置曾绑定了错误接口名。只要 playbook 继续完成，新的 Wi-Fi 配置已经写入；重启或无线设备恢复后 NetworkManager 会自动重连。需要手动排查时：

```bash
nmcli radio wifi
nmcli device status
nmcli connection up "新的SSID"
```

### 更新 Brave

```bash
sudo apt update && sudo apt upgrade -y brave-browser
```

**⚠️ 每次 Brave 大版本更新后，必须运行检查脚本：**

```bash
bash ~/post_update_check.sh
```

### 系统更新

```bash
sudo apt update && sudo apt upgrade -y
sudo reboot
```

---

## 第二阶段遗留项

### A. nftables 出站白名单

当前出站全放行。使用 Polymarket 1-2 周后，执行以下命令收集出站域名：

```bash
sudo apt install -y tcpdump
sudo tcpdump -i <Wi-Fi接口名> -n port 53 2>/dev/null | grep -oP 'A\? \K[^\s]+' | sort -u
```

收集到列表后，补充 `files/nftables/nftables.conf` 中的出站规则，重新执行 playbook。

### B. Ledger 硬件钱包

确认 Ledger 型号后，添加对应 udev 规则。官方规则文件：
`https://raw.githubusercontent.com/LedgerHQ/udev-rules/master/20-hw1.rules`

---

## 故障速查

| 现象 | 检查点 |
|------|--------|
| 重启后停在命令行登录 | `cat /etc/systemd/system/getty@tty1.service.d/autologin.conf` |
| Brave 不全屏 | `journalctl -u cage-kiosk.service` |
| Wi-Fi 断线不重连 | `nmcli connection show` 确认 autoconnect=yes |
| Polymarket 页面卡加载 | Brave Shields 图标 → 降低该域名拦截级别 |
| MetaMask 无法唤醒 | Settings → Web3 → Default wallet → 确认为 None |

### 修改主机名后 Brave 无法启动（无限重启死循环）

**问题原因：**  
当您更改了主机名（从 Home-X230 改为 ThinkPad-X230）后，Brave 浏览器在配置目录下的 `SingletonLock` 锁文件依然记录着旧的主机名。由于主机名不匹配，Brave 误以为该用户的数据配置文件正被另一台计算机（通过网络共享等方式）使用，为了防止数据损坏从而拒绝启动并直接退出。Brave 的反复崩溃导致 `cage-kiosk.service` 不断尝试重启，由于重启过快，cage 无法正常获取 DRM 显示权限，最终陷入了死循环。

**我是如何修复的：**

1. 通过 SSH 登录到目标主机。
2. 找到了 kiosk 用户的 Brave 锁文件：`/home/kiosk/.config/BraveSoftware/Brave-Browser/SingletonLock` 并将其删除。
3. 检查 `/home/kiosk/.local` 目录及子目录的所有者是否变成了 `root:root`。如果是，请执行 `chown -R kiosk:kiosk /home/kiosk/.local` 恢复正确权限。
4. 重启了目标主机以清理残留的 session 状态和显示占用。
5. 目前检查后台进程（`ps aux | grep brave`），浏览器进程和 Wayland 显示服务均已稳定运行，屏幕应该已经恢复正常了。
