#!/bin/bash

# 检查realm是否已安装
if [ -f "/root/realm/realm" ]; then
    echo "检测到realm已安装。"
    realm_status="已安装"
    realm_status_color="\033[0;32m" # 绿色
else
    echo "realm未安装。"
    realm_status="未安装"
    realm_status_color="\033[0;31m" # 红色
fi

# 检查realm服务状态
check_realm_service_status() {
    if systemctl is-active --quiet realm; then
        echo -e "\033[0;32m启用\033[0m" # 绿色
    else
        echo -e "\033[0;31m未启用\033[0m" # 红色
    fi
}

# 显示菜单的函数
show_menu() {
    clear
    echo "            欢迎使用realm一键转发脚本"
    echo " ———————————— realm版本v2.7.0 ————————————"
    echo "     修改by：Azimi    修改日期：2024/12/1"
    echo "     修改内容：1.修改查看转发规则内容更加清晰"
    echo "               2.添加/删除规则后自动重启服务"
    echo "               3.更新realm版本至2.7.0"
    echo "     更新脚本请先删除脚本 rm realm.sh"
    echo "     如果启动失败请检查 /root/realm/config.toml下有无多余配置或者卸载后重新配置"
    echo "     debian系统如果命令无法启动请先更新系统/软件包"
    echo "     该脚本只在debian系统下测试，未做其他系统适配，可能无法启动。如若遇到问题，请自行解决"
    echo "     PS:可能没时间做适配，我尽力而为"
    echo "     仓库：https://github.com/qqrrooty/EZrealm"
    echo " "
    echo "——————————————————"
    echo " 1. 安装 realm"
    echo "——————————————————"
    echo " 2. 添加 realm 转发规则"
    echo " 3. 查看 realm 转发规则"
    echo " 4. 删除 realm 转发规则"
    echo "——————————————————"
    echo " 5. 启动 realm 服务"
    echo " 6. 停止 realm 服务"
    echo " 7. 重启 realm 服务"
    echo "——————————————————"
    echo " 8. 卸载 realm"
    echo "——————————————————"
    echo " 9. 定时重启任务"
    echo "——————————————————"
    echo " 0. 退出脚本"
    echo "——————————————————"
    echo " "
    echo -e "realm 状态：${realm_status_color}${realm_status}\033[0m"
    echo -n "realm 转发状态："
    check_realm_service_status
}

# 部署环境的函数
deploy_realm() {
    mkdir -p /root/realm
    cd /root/realm
    wget -O realm.tar.gz https://github.igeek.ing/https://github.com/zhboner/realm/releases/download/v2.7.0/realm-x86_64-unknown-linux-gnu.tar.gz
    tar -xvf realm.tar.gz
    chmod +x realm
    # 创建服务文件
    echo "[Unit]
Description=realm
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
DynamicUser=true
WorkingDirectory=/root/realm
ExecStart=/root/realm/realm -c /root/realm/config.toml

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/realm.service
    systemctl daemon-reload

    # 服务启动后，检查config.toml是否存在，如果不存在则创建
    if [ ! -f /root/realm/config.toml ]; then
        touch /root/realm/config.toml
    fi

# 检查 config.toml 中是否已经包含 [network] 配置块
    network_count=$(grep -c '^\[network\]' /root/realm/config.toml)

    if [ "$network_count" -eq 0 ]; then
    # 如果没有找到 [network]，将其添加到文件顶部
    echo "[network]
no_tcp = false
use_udp = true
" | cat - /root/realm/config.toml > temp && mv temp /root/realm/config.toml
    echo "[network] 配置已添加到 config.toml 文件。"
    
    elif [ "$network_count" -gt 1 ]; then
    # 如果找到多个 [network]，删除多余的配置块，只保留第一个
    sed -i '0,/^\[\[endpoints\]\]/{//!d}' /root/realm/config.toml
    echo "[network]
no_tcp = false
use_udp = true
" | cat - /root/realm/config.toml > temp && mv temp /root/realm/config.toml
    echo "多余的 [network] 配置已删除。"
    else
    echo "[network] 配置已存在，跳过添加。"
    fi

    # 更新realm状态变量
    realm_status="已安装"
    realm_status_color="\033[0;32m" # 绿色
    echo "部署完成。"
}

# 卸载realm
uninstall_realm() {
    systemctl stop realm
    systemctl disable realm
    rm -rf /etc/systemd/system/realm.service
    systemctl daemon-reload
    rm -rf /root/realm
    rm -rf "$(pwd)"/realm.sh
    sed -i '/realm/d' /etc/crontab
    echo "realm已被卸载。"
    # 更新realm状态变量
    realm_status="未安装"
    realm_status_color="\033[0;31m" # 红色
}

# 删除转发规则的函数
delete_forward() {
  echo -e "                   当前 Realm 转发规则                   "
  echo -e "--------------------------------------------------------"
  printf "%-5s| %-15s| %-35s| %-20s\n" "序号" "本地地址:端口 " "    目的地地址:端口 " "备注"
  echo -e "--------------------------------------------------------"
    local IFS=$'\n' # 设置IFS仅以换行符作为分隔符
    # 搜索所有包含 [[endpoints]] 的行，表示转发规则的起始行
    local lines=($(grep -n '^\[\[endpoints\]\]' /root/realm/config.toml))
    
    if [ ${#lines[@]} -eq 0 ]; then
        echo "没有发现任何转发规则。"
        return
    fi

    local index=1
    for line in "${lines[@]}"; do
        local line_number=$(echo $line | cut -d ':' -f 1)
        local remark_line=$((line_number + 1))
        local listen_line=$((line_number + 2))
        local remote_line=$((line_number + 3))

        local remark=$(sed -n "${remark_line}p" /root/realm/config.toml | grep "^# 备注:" | cut -d ':' -f 2)
        local listen_info=$(sed -n "${listen_line}p" /root/realm/config.toml | cut -d '"' -f 2)
        local remote_info=$(sed -n "${remote_line}p" /root/realm/config.toml | cut -d '"' -f 2)

        local listen_ip_port=$listen_info
        local remote_ip_port=$remote_info

    printf "%-4s| %-14s| %-28s| %-20s\n" " $index" "$listen_info" "$remote_info" "$remark"
    echo -e "--------------------------------------------------------"
        let index+=1
    done


    echo "请输入要删除的转发规则序号，直接按回车返回主菜单。"
    read -p "选择: " choice
    if [ -z "$choice" ]; then
        echo "返回主菜单。"
        return
    fi

    if ! [[ $choice =~ ^[0-9]+$ ]]; then
        echo "无效输入，请输入数字。"
        return
    fi

    if [ $choice -lt 1 ] || [ $choice -gt ${#lines[@]} ]; then
        echo "选择超出范围，请输入有效序号。"
        return
  fi

  local chosen_line=${lines[$((choice-1))]}
  local start_line=$(echo $chosen_line | cut -d ':' -f 1)

  # 找到下一个 [[endpoints]] 行，确定删除范围的结束行
  local next_endpoints_line=$(grep -n '^\[\[endpoints\]\]' /root/realm/config.toml | grep -A 1 "^$start_line:" | tail -n 1 | cut -d ':' -f 1)

  if [ -z "$next_endpoints_line" ] || [ "$next_endpoints_line" -le "$start_line" ]; then
    # 如果没有找到下一个 [[endpoints]]，则删除到文件末尾
    end_line=$(wc -l < /root/realm/config.toml)
  else
    # 如果找到了下一个 [[endpoints]]，则删除到它的前一行
    end_line=$((next_endpoints_line - 1))
  fi

  # 使用 sed 删除指定行范围的内容
  sed -i "${start_line},${end_line}d" /root/realm/config.toml

  # 检查并删除可能多余的空行
  sed -i '/^\s*$/d' /root/realm/config.toml

  echo "转发规则及其备注已删除。"

  # 重启服务
  sudo systemctl restart realm.service
}

# 查看转发规则
show_all_conf() {
  echo -e "                   当前 Realm 转发规则                   "
  echo -e "--------------------------------------------------------"
  printf "%-5s| %-15s| %-35s| %-20s\n" "序号" "本地地址:端口 " "    目的地地址:端口 " "备注"
  echo -e "--------------------------------------------------------"
    local IFS=$'\n' # 设置IFS仅以换行符作为分隔符
    # 搜索所有包含 listen 的行，表示转发规则的起始行
    local lines=($(grep -n 'listen =' /root/realm/config.toml))
    
    if [ ${#lines[@]} -eq 0 ]; then
  echo -e "没有发现任何转发规则。"
        return
    fi

    local index=1
    for line in "${lines[@]}"; do
        local line_number=$(echo $line | cut -d ':' -f 1)
        local listen_info=$(sed -n "${line_number}p" /root/realm/config.toml | cut -d '"' -f 2)
        local remote_info=$(sed -n "$((line_number + 1))p" /root/realm/config.toml | cut -d '"' -f 2)
        local remark=$(sed -n "$((line_number-1))p" /root/realm/config.toml | grep "^# 备注:" | cut -d ':' -f 2)
        
        local listen_ip_port=$listen_info
        local remote_ip_port=$remote_info
        
    printf "%-4s| %-14s| %-28s| %-20s\n" " $index" "$listen_info" "$remote_info" "$remark"
    echo -e "--------------------------------------------------------"
        let index+=1
    done
}

# 添加转发规则
add_forward() {
    while true; do
        read -p "请输入本地监听端口: " local_port
        read -p "请输入需要转发的IP: " ip
        read -p "请输入需要转发端口: " port
        read -p "请输入备注(非中文): " remark
        # 追加到config.toml文件
        echo "[[endpoints]]
# 备注: $remark
listen = \"[::]:$local_port\"
remote = \"$ip:$port\"" >> /root/realm/config.toml
        
        read -p "是否继续添加(Y/N)? " answer
        if [[ $answer != "Y" && $answer != "y" ]]; then
            break
        fi
    done
    
    sudo systemctl restart realm.service
}

# 启动服务
start_service() {
    sudo systemctl unmask realm.service
    sudo systemctl daemon-reload
    sudo systemctl restart realm.service
    sudo systemctl enable realm.service
    echo "realm服务已启动并设置为开机自启。"
}

# 停止服务
stop_service() {
    systemctl stop realm
    echo "realm服务已停止。"
}

# 重启服务
restart_service() {
    sudo systemctl stop realm
    sudo systemctl unmask realm.service
    sudo systemctl daemon-reload
    sudo systemctl restart realm.service
    sudo systemctl enable realm.service
    echo "realm服务已重启。"
}

# 定时任务
cron_restart() {
  echo -e "------------------------------------------------------------------"
  echo -e "realm定时重启任务: "
  echo -e "-----------------------------------"
  echo -e "[1] 配置realm定时重启任务"
  echo -e "[2] 删除realm定时重启任务"
  echo -e "-----------------------------------"
  read -p "请选择: " numcron
  if [ "$numcron" == "1" ]; then
    echo -e "------------------------------------------------------------------"
    echo -e "realm定时重启任务类型: "
    echo -e "-----------------------------------"
    echo -e "[1] 每？小时重启"
    echo -e "[2] 每日？点重启"
    echo -e "-----------------------------------"
    read -p "请选择: " numcrontype
    if [ "$numcrontype" == "1" ]; then
      echo -e "-----------------------------------"
      read -p "每？小时重启: " cronhr
      echo "0 */$cronhr * * * root /usr/bin/systemctl restart realm" >>/etc/crontab
      echo -e "定时重启设置成功！"
    elif [ "$numcrontype" == "2" ]; then
      echo -e "-----------------------------------"
      read -p "每日？点重启: " cronhr
      echo "0 $cronhr * * * root /usr/bin/systemctl restart realm" >>/etc/crontab
      echo -e "定时重启设置成功！"
    else
      echo "输入错误，请重试"
      exit
    fi
  elif [ "$numcron" == "2" ]; then
    sed -i "/realm/d" /etc/crontab
    echo -e "定时重启任务删除完成！"
  else
    echo "输入错误，请重试"
    exit
  fi
}

# 主循环
while true; do
    show_menu
    read -p "请选择一个选项[0-9]: " choice
    # 去掉输入中的空格
    choice=$(echo $choice | tr -d '[:space:]')

    # 检查输入是否为数字，并在有效范围内
    if ! [[ "$choice" =~ ^[0-9]$ ]]; then
        echo "无效选项: $choice"
        continue
    fi

    case $choice in
        1)
            deploy_realm
            ;;
        2)
            add_forward
            ;;
        3)
            show_all_conf
            ;;
        4)
            delete_forward
            ;;
        5)
            start_service
            ;;
        6)
            stop_service
            ;;
        7)
            restart_service
            ;;
        8)
            uninstall_realm
            ;;
        9)
            cron_restart
            ;;  
        0)
            echo "退出脚本。"  # 显示退出消息
            exit 0            # 退出脚本
            ;;
        *)
            echo "无效选项: $choice"
            ;;
    esac
    read -p "按任意键继续..." key
done
