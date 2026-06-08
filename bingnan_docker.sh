#!/bin/bash
#===============================================
# Bingnan Docker 一键安装管理脚本
# 版本: v2.0
# 适用: 飞牛OS / Linux + Docker
# 包含 16 个服务（含 Dockge & Miniflux 替代方案）
#===============================================

set -e

# ========== 颜色定义 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ========== 全局变量 ==========
WORK_DIR=""
MIRROR_URL=""
PROXY_URL=""
NAS_IP=""
SCRIPT_VERSION="v2.0"
COMPOSE_CMD="docker compose"

# ========== 服务列表 ==========
# 格式: 序号:名称:目录名:端口:描述
declare -a SERVICES=(
    "1:Clash:clash:9090:VPN代理"
    "2:Homepage:homepage:3002:导航页"
    "3:MoviePilot:moviepilot:3001:媒体自动化"
    "4:qBittorrent:qbittorrent:8084:下载工具"
    "5:Emby:emby:8096:媒体服务器"
    "6:Transmission:transmission:9091:BT下载"
    "7:Draw.io:drawio:8087:流程图"
    "8:Reader:reader:8089:阅读器"
    "9:ZFile:zfile:8094:网盘挂载"
    "10:Halo:halo:8095:博客系统"
    "11:Memos:memos:8097:备忘录"
    "12:StirlingPDF:stirlingpdf:8098:PDF工具箱"
    "13:n8n:n8n:8101:工作流自动化"
    "15:Dockge:dockge:5001:Docker管理"
    "16:Miniflux:miniflux:8110:RSS阅读器"
)

# ========== 工具函数 ==========
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
hr()    { echo -e "${CYAN}═══════════════════════════════════════════${NC}"; }

get_nas_ip() {
    NAS_IP=$(ip route get 1 | awk '{print $NF;exit}' 2>/dev/null || hostname -I | awk '{print $1}')
}

get_service_name() {
    local idx=$1
    echo "${SERVICES[$idx]}" | cut -d: -f2
}

get_service_dir() {
    local idx=$1
    echo "${SERVICES[$idx]}" | cut -d: -f3
}

get_service_port() {
    local idx=$1
    echo "${SERVICES[$idx]}" | cut -d: -f4
}

get_service_desc() {
    local idx=$1
    echo "${SERVICES[$idx]}" | cut -d: -f5
}

get_container_name() {
    local idx=$1
    local name
    name=$(get_service_name "$idx")
    echo "${name,,}"
}

# ========== 检查 Docker ==========
check_docker() {
    if ! command -v docker &>/dev/null; then
        error "Docker 未安装！请先安装 Docker。"
        exit 1
    fi
    
    if docker compose version &>/dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &>/dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        error "Docker Compose 未安装！"
        exit 1
    fi
    
    get_nas_ip
    info "Docker 环境检查通过"
    info "本机 IP: $NAS_IP"
}

# ========== 配置镜像加速 ==========
select_mirror() {
    hr
    echo -e "${CYAN}请选择 Docker 镜像加速地址：${NC}"
    echo "  1) DockerProxy（推荐）"
    echo "  2) 阿里云（需输入加速地址）"
    echo "  3) 中科大"
    echo "  4) 不配置"
    echo ""
    read -rp "请输入选项 [1-4]: " mirror_choice
    
    case "$mirror_choice" in
        1) MIRROR_URL="https://dockerproxy.com" ;;
        2)
            read -rp "请输入阿里云镜像加速地址: " MIRROR_URL
            ;;
        3) MIRROR_URL="https://docker.mirrors.ustc.edu.cn" ;;
        4) MIRROR_URL="" ;;
        *)
            warn "无效选项，跳过镜像加速配置"
            MIRROR_URL=""
            ;;
    esac
    
    if [ -n "$MIRROR_URL" ]; then
        info "镜像加速地址: $MIRROR_URL"
        mkdir -p /etc/docker
        if [ -f /etc/docker/daemon.json ]; then
            cp /etc/docker/daemon.json /etc/docker/daemon.json.bak
        fi
        cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["$MIRROR_URL"]
}
EOF
        systemctl restart docker 2>/dev/null || service docker restart 2>/dev/null || warn "Docker 重启失败，请手动重启"
        info "镜像加速配置完成"
    fi
}

# ========== 配置工作目录 ==========
configure_workdir() {
    hr
    echo -e "${CYAN}配置 Docker 工作目录${NC}"
    echo "  默认: /vol1/1000/docker（飞牛OS）"
    echo "  其他: /opt/docker /data/docker 等"
    echo ""
    read -rp "请输入工作目录（留空使用默认）: " input_dir
    
    if [ -z "$input_dir" ]; then
        WORK_DIR="/vol1/1000/docker"
    else
        WORK_DIR="$input_dir"
    fi
    
    mkdir -p "$WORK_DIR"
    info "工作目录: $WORK_DIR"
}

# ========== 配置代理 ==========
configure_proxy() {
    hr
    echo -e "${CYAN}是否配置代理服务器？${NC}"
    echo "  1) 配置代理服务器"
    echo "  2) 跳过"
    echo ""
    read -rp "请输入选项 [1-2]: " proxy_choice
    
    if [ "$proxy_choice" = "1" ]; then
        read -rp "请输入 HTTP 代理地址 (如 http://192.168.3.88:7890): " PROXY_URL
        info "代理地址: $PROXY_URL"
        
        mkdir -p /etc/systemd/system/docker.service.d
        cat > /etc/systemd/system/docker.service.d/proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=$PROXY_URL"
Environment="HTTPS_PROXY=$PROXY_URL"
Environment="NO_PROXY=localhost,127.0.0.1,.local"
EOF
        systemctl daemon-reload
        systemctl restart docker
        info "Docker 代理配置完成"
    else
        PROXY_URL=""
        info "跳过代理配置"
    fi
}

# ========== 生成 docker-compose.yml ==========
generate_compose() {
    local idx=$1
    local name
    local dir
    local port
    name=$(get_service_name "$idx")
    dir=$(get_service_dir "$idx")
    port=$(get_service_port "$idx")
    
    local service_dir="$WORK_DIR/$dir"
    mkdir -p "$service_dir"
    local yml_path="$service_dir/docker-compose.yml"
    
    case "$name" in
        "Clash")
            cat > "$yml_path" <<'YAMLEOF'
services:
  clash:
    image: ghcr.io/dreamacro/clash
    container_name: clash
    network_mode: "host"
    volumes:
      - ./config.yaml:/root/.config/clash/config.yaml
      - ./ui:/ui
    restart: unless-stopped
YAMLEOF
            ;;
        "Homepage")
            cat > "$yml_path" <<YAMLEOF
services:
  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    container_name: homepage
    ports:
      - ${port}:3000
    volumes:
      - ./config:/app/config
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - HOMEPAGE_ALLOWED_HOSTS=${NAS_IP}:${port}
    restart: unless-stopped
YAMLEOF
            ;;
        "MoviePilot")
            cat > "$yml_path" <<YAMLEOF
services:
  moviepilot:
    image: jxxghp/moviepilot-v2:latest
    container_name: moviepilot
    ports:
      - ${port}:3000
    volumes:
      - ./config:/config
      - ./data:/data
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - NGINX_PORT=${port}
      - MOVIEPILOT_AUTO_UPDATE=false
    restart: unless-stopped
YAMLEOF
            ;;
        "qBittorrent")
            cat > "$yml_path" <<YAMLEOF
services:
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    ports:
      - ${port}:8080
      - 6881:6881
      - 6881:6881/udp
    volumes:
      - ./config:/config
      - ./downloads:/downloads
    environment:
      - PUID=0
      - PGID=0
      - TZ=Asia/Shanghai
      - WEBUI_PORT=8080
    restart: unless-stopped
YAMLEOF
            ;;
        "Emby")
            cat > "$yml_path" <<YAMLEOF
services:
  emby:
    image: emby/embyserver:latest
    container_name: emby
    ports:
      - ${port}:8096
      - 8920:8920
    volumes:
      - ./config:/config
      - ./media:/media
    environment:
      - TZ=Asia/Shanghai
    restart: unless-stopped
YAMLEOF
            ;;
        "Transmission")
            cat > "$yml_path" <<YAMLEOF
services:
  transmission:
    image: lscr.io/linuxserver/transmission:latest
    container_name: transmission
    ports:
      - ${port}:9091
      - 51413:51413
      - 51413:51413/udp
    volumes:
      - ./config:/config
      - ./downloads:/downloads
      - ./watch:/watch
    environment:
      - PUID=0
      - PGID=0
      - TZ=Asia/Shanghai
    restart: unless-stopped
YAMLEOF
            ;;
        "Draw.io")
            cat > "$yml_path" <<YAMLEOF
services:
  drawio:
    image: jgraph/drawio:latest
    container_name: drawio
    ports:
      - ${port}:8080
    volumes:
      - ./data:/data
    restart: unless-stopped
YAMLEOF
            ;;
        "Reader")
            cat > "$yml_path" <<YAMLEOF
services:
  reader:
    image: hectorqin/reader:latest
    container_name: reader
    ports:
      - ${port}:8080
    volumes:
      - ./data:/data
      - ./logs:/logs
    environment:
      - TZ=Asia/Shanghai
      - READER_APP_SECURE=true
      - READER_APP_SECUREKEY=admin123
    restart: unless-stopped
YAMLEOF
            ;;
        "ZFile")
            cat > "$yml_path" <<YAMLEOF
services:
  zfile:
    image: zfile/zfile:latest
    container_name: zfile
    ports:
      - ${port}:8080
    volumes:
      - ./data:/root/.zfile
      - ./file:/file
    restart: unless-stopped
YAMLEOF
            ;;
        "Halo")
            cat > "$yml_path" <<YAMLEOF
services:
  halo:
    image: halohub/halo:latest
    container_name: halo
    ports:
      - ${port}:8090
    volumes:
      - ./data:/root/.halo2
    environment:
      - TZ=Asia/Shanghai
    restart: unless-stopped
YAMLEOF
            ;;
        "Memos")
            cat > "$yml_path" <<YAMLEOF
services:
  memos:
    image: neosmemo/memos:stable
    container_name: memos
    ports:
      - ${port}:5230
    volumes:
      - ./data:/var/opt/memos
    restart: unless-stopped
YAMLEOF
            ;;
        "StirlingPDF")
            cat > "$yml_path" <<YAMLEOF
services:
  stirlingpdf:
    image: frooodle/s-pdf:latest
    container_name: stirlingpdf
    ports:
      - ${port}:8080
    volumes:
      - ./data:/usr/share/tesseract-ocr/4.00/tessdata
      - ./config:/configs
    environment:
      - TZ=Asia/Shanghai
    restart: unless-stopped
YAMLEOF
            ;;
        "n8n")
            cat > "$yml_path" <<YAMLEOF
services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    ports:
      - ${port}:5678
    volumes:
      - ./data:/home/node/.n8n
    environment:
      - TZ=Asia/Shanghai
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - N8N_HOST=${NAS_IP}:${port}
    restart: unless-stopped
YAMLEOF
            ;;
        "Dockge")
            cat > "$yml_path" <<YAMLEOF
services:
  dockge:
    image: louislam/dockge:latest
    container_name: dockge
    ports:
      - ${port}:5001
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/app/data
      - ${WORK_DIR}:/data/stacks
    environment:
      - DOCKGE_STACKS_DIR=/data/stacks
    restart: unless-stopped
YAMLEOF
            ;;
        "Miniflux")
            cat > "$yml_path" <<YAMLEOF
services:
  miniflux:
    image: miniflux/miniflux:latest
    container_name: miniflux
    ports:
      - ${port}:8080
    volumes:
      - ./data:/var/lib/miniflux
    environment:
      - DATABASE_URL=postgres://miniflux:miniflux@miniflux-db/miniflux?sslmode=disable
      - RUN_MIGRATIONS=1
      - CREATE_ADMIN=1
      - ADMIN_USERNAME=admin
      - ADMIN_PASSWORD=admin123
    depends_on:
      - miniflux-db
    restart: unless-stopped

  miniflux-db:
    image: postgres:15-alpine
    container_name: miniflux-db
    volumes:
      - ./db:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=miniflux
      - POSTGRES_PASSWORD=miniflux
      - POSTGRES_DB=miniflux
    restart: unless-stopped
YAMLEOF
            ;;
    esac
    
    info "配置文件已生成: $yml_path"
}

# ========== 部署单个服务 ==========
deploy_single() {
    local idx=$1
    local name
    local dir
    local port
    local desc
    name=$(get_service_name "$idx")
    dir=$(get_service_dir "$idx")
    port=$(get_service_port "$idx")
    desc=$(get_service_desc "$idx")
    local cname=$(get_container_name "$idx")
    
    hr
    echo -e "${CYAN}正在部署: $name ($desc) -> $port${NC}"
    
    local service_dir="$WORK_DIR/$dir"
    
    # 检查是否已部署
    if docker ps --format '{{.Names}}' | grep -q "^${cname}$" 2>/dev/null; then
        warn "$name 已在运行，跳过"
        return
    fi
    
    # 生成 compose 文件
    generate_compose "$idx"
    
    # 执行部署
    cd "$service_dir" || { error "目录不存在: $service_dir"; return 1; }
    
    echo -e "${YELLOW}拉取镜像中...${NC}"
    $COMPOSE_CMD pull 2>&1 || {
        warn "镜像拉取失败，尝试直接启动（可能缓存镜像）"
    }
    
    echo -e "${YELLOW}启动容器中...${NC}"
    $COMPOSE_CMD up -d 2>&1 || {
        error "$name 部署失败"
        return 1
    }
    
    # 等待检查状态
    sleep 3
    if docker ps --format '{{.Names}}' | grep -q "^${cname}$" 2>/dev/null; then
        info "✅ $name 部署成功 -> http://$NAS_IP:$port"
    else
        warn "$name 可能未完全启动，请检查: cd $service_dir && $COMPOSE_CMD logs"
    fi
}

# ========== 显示服务菜单 ==========
show_service_menu() {
    clear
    hr
    echo -e "${CYAN}              服务部署列表${NC}"
    hr
    echo ""
    
    local total=${#SERVICES[@]}
    printf "  %-3s %-15s %-8s %-18s %s\n" "编号" "服务名" "端口" "状态" "说明"
    printf "  %-3s %-15s %-8s %-18s %s\n" "---" "---------------" "--------" "-----------------" "----------"
    
    for i in $(seq 0 $((total - 1))); do
        local name=$(get_service_name "$i")
        local port=$(get_service_port "$i")
        local desc=$(get_service_desc "$i")
        local cname=$(get_container_name "$i")
        
        if docker ps --format '{{.Names}}' | grep -q "^${cname}$" 2>/dev/null; then
            echo -e "  ${GREEN}$((i+1))${NC}     ${GREEN}$name${NC}        ${port}    ${GREEN}✅ 已运行${NC}    $desc"
        else
            echo -e "  ${YELLOW}$((i+1))${NC}     ${name}        ${port}    🔄 未部署    $desc"
        fi
    done
    
    echo ""
    echo -e "  ${BLUE}[a]${NC} 部署全部"
    echo -e "  ${BLUE}[q]${NC} 返回主菜单"
    echo ""
}

# ========== 部署入口 ==========
deploy_projects() {
    hr
    echo -e "${CYAN}           ⚙️ 环境初始化${NC}"
    echo ""
    
    select_mirror
    configure_workdir
    configure_proxy
    
    while true; do
        show_service_menu
        
        read -rp "请输入要部署的服务编号（多个用空格隔开）: " input
        
        if [ "$input" = "q" ]; then
            return
        fi
        
        if [ "$input" = "a" ]; then
            hr
            echo -e "${CYAN}开始部署全部服务...${NC}"
            for i in $(seq 0 $((${#SERVICES[@]} - 1))); do
                deploy_single "$i"
            done
            break
        fi
        
        # 验证输入
        local valid=1
        for num in $input; do
            if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt "${#SERVICES[@]}" ]; then
                warn "无效编号: $num"
                valid=0
            fi
        done
        
        if [ "$valid" = "1" ]; then
            for num in $input; do
                deploy_single $((num - 1))
            done
            break
        fi
    done
    
    # 输出访问地址表
    hr
    echo -e "${CYAN}          📋 服务访问地址${NC}"
    echo ""
    printf "  %-18s %-30s\n" "服务" "地址"
    printf "  %-18s %-30s\n" "-----------------" "------------------------------"
    
    for i in $(seq 0 $((${#SERVICES[@]} - 1))); do
        local name=$(get_service_name "$i")
        local port=$(get_service_port "$i")
        local cname=$(get_container_name "$i")
        
        if docker ps --format '{{.Names}}' | grep -q "^${cname}$" 2>/dev/null; then
            printf "  %-18s http://%s:%s\n" "$name" "$NAS_IP" "$port"
        fi
    done
    
    echo ""
    info "部署完成！"
    read -rp "按回车键返回主菜单..."
}

# ========== 查看容器信息 ==========
show_container_info() {
    clear
    hr
    echo -e "${CYAN}         📊 容器信息概览${NC}"
    echo ""
    
    echo -e "${GREEN}--- 运行中的容器 ---${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | head -30
    
    echo ""
    echo -e "${GREEN}--- 资源占用 (CPU/内存/网络) ---${NC}"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" 2>/dev/null | head -20
    
    echo ""
    echo -e "${GREEN}--- 工作目录 ---${NC}"
    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        echo "  工作目录: $WORK_DIR"
        echo "  子目录列表:"
        ls -1 "$WORK_DIR" 2>/dev/null | while read d; do
            echo "    └── $d"
        done
    else
        warn "工作目录未配置或不存在"
    fi
    
    echo ""
    read -rp "按回车键返回主菜单..."
}

# ========== 清理 ==========
clean_all() {
    clear
    hr
    echo -e "${RED}⚠️  危险操作警告 ⚠️${NC}"
    echo -e "${YELLOW}此操作将：${NC}"
    echo "  1. 停止并删除所有 Docker 容器"
    echo "  2. 删除所有 Docker 镜像"
    echo ""
    read -rp "确认执行？(yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        info "已取消"
        read -rp "按回车键返回主菜单..."
        return
    fi
    
    echo ""
    echo -e "${YELLOW}是否同时清理配置文件（docker-compose.yml 等）？${NC}"
    read -rp "(yes/no): " clean_config
    
    hr
    echo -e "${CYAN}开始清理...${NC}"
    
    # 停止并删除容器
    local running=$(docker ps -q)
    local all=$(docker ps -aq)
    [ -n "$running" ] && docker stop $running 2>/dev/null || true
    [ -n "$all" ] && docker rm $all 2>/dev/null || true
    info "容器已清理"
    
    # 删除镜像
    local images=$(docker images -q)
    [ -n "$images" ] && docker rmi $images -f 2>/dev/null || true
    info "镜像已清理"
    
    # 清理配置文件
    if [ "$clean_config" = "yes" ] && [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        for i in $(seq 0 $((${#SERVICES[@]} - 1))); do
            local dir=$(get_service_dir "$i")
            local service_dir="$WORK_DIR/$dir"
            if [ -f "$service_dir/docker-compose.yml" ]; then
                rm -rf "$service_dir"
                info "已清理: $service_dir"
            fi
        done
    fi
    
    info "清理完成！"
    read -rp "按回车键返回主菜单..."
}

# ========== 主菜单 ==========
show_menu() {
    clear
    hr
    echo -e "${CYAN}   Bingnan Docker 一键安装管理脚本 ${SCRIPT_VERSION}${NC}"
    hr
    echo ""
    echo -e "  ${GREEN}1.${NC} 一键部署项目"
    echo -e "  ${GREEN}2.${NC} 查看容器初始化信息"
    echo -e "  ${GREEN}3.${NC} 一键删除所有容器和镜像"
    echo -e "  ${GREEN}4.${NC} 退出脚本"
    echo ""
    hr
    echo ""
}

# ========== 主循环 ==========
main() {
    check_docker
    
    while true; do
        show_menu
        read -rp "请输入选项 [1-4]: " choice
        
        case "$choice" in
            1) deploy_projects ;;
            2) show_container_info ;;
            3) clean_all ;;
            4)
                info "感谢使用，再见！"
                exit 0
                ;;
            *)
                warn "无效选项，请重新输入"
                sleep 2
                ;;
        esac
    done
}

# ========== 启动 ==========
main
