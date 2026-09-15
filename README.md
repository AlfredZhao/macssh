# macssh 使用手册

`macssh` 是一个面向 macOS Terminal 的轻量 SSH 主机管理工具。它使用 macOS 自带的 OpenSSH，不保存密码和私钥内容。

## 1. 安装

在项目目录执行：

```bash
chmod +x macssh install.sh
./install.sh
```

默认安装到 `/usr/local/bin/macssh`。如果没有写入权限，可以安装到当前用户目录：

```bash
mkdir -p "$HOME/.local/bin"
PREFIX="$HOME/.local" ./install.sh
```

验证安装：

```bash
macssh --version
```

## 2. 添加主机

交互式添加：

```bash
macssh add
```

按照提示输入主机名称、地址、用户、端口和私钥路径。私钥路径可以留空。

也可以通过一条命令添加：

```bash
macssh add prod \
  --host 10.0.0.8 \
  --user ubuntu \
  --port 22 \
  --key ~/.ssh/prod.pem \
  --tags production
```

通过跳板机连接：

```bash
macssh add internal-db \
  --host 10.0.2.15 \
  --user oracle \
  --key ~/.ssh/db.pem \
  --jump bastion
```

其中 `bastion` 应当是已经配置好的主机名称。

## 3. 查看和连接

```bash
macssh list            # 查看所有主机
macssh connect prod    # 连接指定主机
macssh                 # 从编号菜单选择主机
macssh test prod       # 测试 Key 登录
```

## 4. 修改和删除

```bash
macssh edit prod       # 修改，直接回车保留原值
macssh remove prod     # 删除，执行前要求确认
```

## 5. 使用原生 SSH 工具

`macssh` 生成标准 OpenSSH 配置，因此也可以直接使用：

```bash
ssh prod
scp local.txt prod:/tmp/
sftp prod
```

## 6. 配置文件

主机配置保存在：

```text
~/.ssh/config.d/macssh.conf
```

首次运行时，程序会在 `~/.ssh/config` 中加入：

```sshconfig
Include ~/.ssh/config.d/*.conf
```

```bash
macssh path            # 查看配置文件路径
macssh config          # 编辑原始 SSH 配置
```

## 7. 命令速查

```text
macssh                  选择并连接主机
macssh add [名称]       添加主机
macssh list             查看主机
macssh connect [名称]   连接主机
macssh test <名称>      测试 Key 登录
macssh edit <名称>      修改主机
macssh remove <名称>    删除主机
macssh config           编辑原始 SSH 配置
macssh path             显示配置文件路径
macssh help             显示命令帮助
```

程序不会保存密码，也不会复制或修改私钥。带口令的私钥仍由 macOS Keychain 和 `ssh-agent` 管理。
