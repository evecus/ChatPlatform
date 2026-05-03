# Chat Platform

私人多人聊天平台，支持文字 + 文件传输，邀请码注册，管理员后台。

## 项目结构

```
chat-platform/
├── server/          # Go 后端
├── flutter_app/     # Flutter Android App
├── chat.service     # systemd 服务文件
└── docker-compose.yml
```

---

## 一、编译（GitHub Actions 自动完成）

### 1. Fork / 上传代码到 GitHub

### 2. 修改服务器地址

服务器地址在 App 内运行时填写，无需修改代码。

### 3. 生成 Android 签名 keystore

在本地任意机器执行（需要 JDK）：

```bash
keytool -genkey -v \
  -keystore release.jks \
  -alias chat \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000
```

按提示填写信息，记住：
- keystore 密码（storePassword）
- key 密码（keyPassword）
- alias 名称（这里填的是 `chat`）

### 4. 配置 GitHub Secrets

进入仓库 → Settings → Secrets and variables → Actions → New repository secret

| Secret 名称 | 内容 |
|------------|------|
| `KEY_STORE_BASE64` | `base64 -w0 release.jks` 的输出 |
| `KEY_STORE_PASSWORD` | keystore 密码 |
| `KEY_ALIAS` | `chat` |
| `KEY_PASSWORD` | key 密码 |

生成 base64：
```bash
# Linux/macOS
base64 -w0 release.jks

# Windows (PowerShell)
[Convert]::ToBase64String([IO.File]::ReadAllBytes("release.jks"))
```

### 5. 触发编译

打一个 tag 即可自动编译并发布到 Release：

```bash
git tag v1.0.0
git push origin v1.0.0
```

或者在 Actions 页面手动点 `Run workflow`。

编译完成后在 Releases 页面下载：
- `chat-server`：Linux 服务器二进制
- `app-arm64-v8a-release.apk`：主流 Android 设备（推荐）
- `app-armeabi-v7a-release.apk`：旧设备
- `app-x86_64-release.apk`：模拟器

---

## 二、VPS 部署（裸机）

### 1. 准备目录

```bash
mkdir -p /opt/chat/data/uploads
```

### 2. 上传文件

```bash
scp chat-server user@your-vps:/opt/chat/
```

### 3. 创建 .env 文件

```bash
cat > /opt/chat/.env << 'EOF'
PORT=8080
JWT_SECRET=换成一个随机长字符串
DB_PATH=./data/chat.db
UPLOAD_DIR=./data/uploads
MAX_FILE_SIZE_MB=10
HISTORY_LIMIT=50
EOF

chmod 600 /opt/chat/.env
```

生成随机 JWT_SECRET：
```bash
openssl rand -hex 32
```

### 4. 添加执行权限

```bash
chmod +x /opt/chat/chat-server
```

### 5. 配置 systemd 服务

```bash
cp chat.service /etc/systemd/system/chat.service

# 如果 VPS 没有 www-data 用户，改成 root 或你的用户
# 编辑 /etc/systemd/system/chat.service 中的 User=

systemctl daemon-reload
systemctl enable chat
systemctl start chat
systemctl status chat
```

### 6. 查看日志

```bash
journalctl -u chat -f
```

启动时会输出类似：
```
=== BOOTSTRAP INVITE CODE: a1b2c3d4e5f6 (use this to register the first admin) ===
```

**复制这个码**，用它注册第一个账号（自动成为管理员）。

### 7. 反向代理（你自己配）

服务运行在 `http://127.0.0.1:8080`，支持标准 HTTP + WebSocket。

Nginx 示例片段（你已有的配置里加）：
```nginx
location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

---

## 三、Docker 部署（后续）

```bash
# 复制环境变量
cp server/.env.example .env
# 编辑 .env 填入 JWT_SECRET 等

docker-compose up -d

# 查看日志（获取初始注册码）
docker-compose logs -f
```

---

## 四、首次使用流程

1. 服务启动 → 日志里看到 Bootstrap 注册码
2. 打开 App → Register → 填用户名、密码、注册码 → 第一个注册的自动成管理员
3. 进入管理员后台 → 生成更多注册码 → 分享给其他人
4. 其他人用注册码注册 → 直接进入聊天室

---

## API 端点速查

```
POST /api/auth/register     注册（需要 invite_code）
POST /api/auth/login        登录
GET  /api/auth/me           当前用户信息
POST /api/files/upload      上传文件（需要 JWT）
GET  /api/files/:id         下载文件（需要 JWT）
GET  /ws?token=<jwt>        WebSocket 连接

GET    /api/admin/users              用户列表
POST   /api/admin/users/:id/ban      封号
POST   /api/admin/users/:id/unban    解封
POST   /api/admin/users/:id/kick     踢出
DELETE /api/admin/users/:id          删除
GET    /api/admin/invite-codes       注册码列表
POST   /api/admin/invite-codes       生成注册码
DELETE /api/admin/invite-codes/:id   删除注册码
GET    /health                       健康检查
```

---

## WebSocket 消息格式

### 服务器 → 客户端

```json
{ "type": "history",      "messages": [...] }
{ "type": "online_users", "users": [{"id":1,"username":"alice"}] }
{ "type": "message",      "message": { "id":1, "username":"alice", "type":"text", "content":"hi", "created_at":"..." } }
{ "type": "user_joined",  "username": "bob" }
{ "type": "user_left",    "username": "bob" }
{ "type": "user_banned",  "username": "bob" }
{ "type": "kicked",       "reason": "removed by admin" }
{ "type": "banned",       "reason": "your account has been banned" }
```

### 客户端 → 服务器

```json
{ "type": "send_message", "content": "hello" }
{ "type": "send_file",    "content": "file_id", "file_name": "doc.pdf", "file_size": 1024 }
```
